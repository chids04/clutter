use super::*;
use crate::media::tags::extract_raw_metadata;

struct SongEdit {
    song_id: String,
    title: String,
    primary_artist: String,
    featured_artists: Vec<String>,
    track_num: i64,
    disc_num: i64,
    album: AlbumSelection,
    cover: ArtworkUpdate,
    write_file_tags: bool,
    audio: SongAudioUpdate,
}

struct SongSource {
    old_album_id: Option<String>,
    old_cover: Option<String>,
    stored_file_path: String,
    crop: Option<SongCropRow>,
}

struct SongDestination {
    album_id: String,
    album_title: String,
    album_artists: Vec<String>,
    primary_artist_id: String,
    featured_artist_ids: Vec<String>,
    song_cover_path: Option<String>,
    effective_cover_path: Option<String>,
}

struct AlbumEdit {
    album_id: String,
    title: String,
    artist_names: Vec<String>,
    cover: ArtworkUpdate,
    write_file_tags: bool,
}

struct AlbumDestination {
    surviving_id: String,
    source_cover: Option<String>,
    destination_cover: Option<String>,
    final_cover: Option<String>,
    artist_ids: Vec<String>,
    artist_key: String,
    merged: bool,
}

struct ValidatedSongImport {
    source_path: PathBuf,
    title: String,
    primary_artist: String,
    featured_artists: Vec<String>,
    album_title: String,
    album_artists: Vec<String>,
    album_artwork: Option<PathBuf>,
    track_num: i64,
    disc_num: i64,
    cover: ArtworkUpdate,
    crop: Option<ExtractedSongCrop>,
}

struct PreparedSongAudio {
    file: Option<PreparedAudioUpdate>,
    stored_destination: String,
    crop_change: CropChange,
    consumed_temporary: Option<PathBuf>,
    retained_on_failure: Option<PathBuf>,
    retained_on_success: Option<PathBuf>,
}

enum CropChange {
    Keep,
    Upsert(SongCropRow),
    Delete,
}

impl SqliteLibraryStore {
    pub fn import_extracted_song(
        &self,
        update: ExtractedSongImport,
        imports_dir: &Path,
        originals_dir: &Path,
    ) -> Result<SongRow, String> {
        let import = self.validate_song_import(update)?;
        // managed artwork and audio stay staged until sqlite accepts the song
        let artwork = self.stage_import_artwork(&import.cover)?;
        let destination = match prepare_import_audio(&import, imports_dir, artwork.as_deref(), self)
        {
            Ok(path) => path,
            Err(error) => {
                self.remove_managed_path(artwork.as_deref());
                return Err(error);
            }
        };
        let retained = match self.retain_import_original(&import, originals_dir) {
            Ok(path) => path,
            Err(error) => {
                let _ = fs::remove_file(&destination);
                self.remove_managed_path(artwork.as_deref());
                return Err(error);
            }
        };
        let result = self.index_imported_song(
            &import,
            &destination,
            artwork.as_deref(),
            retained.as_deref(),
        );
        if result.is_err() {
            let _ = fs::remove_file(&destination);
            retained.iter().for_each(|path| {
                let _ = fs::remove_file(path);
            });
            self.remove_managed_path(artwork.as_deref());
        } else {
            let _ = fs::remove_file(&import.source_path);
            if let Some(crop) = &import.crop {
                let original = Path::new(&crop.original_source_path);
                if original != import.source_path {
                    let _ = fs::remove_file(original);
                }
            }
        }
        result
    }

    fn validate_song_import(
        &self,
        update: ExtractedSongImport,
    ) -> Result<ValidatedSongImport, String> {
        let title = required_text(&update.title, "song title")?;
        let primary_artist = required_text(&update.primary_artist, "primary artist")?;
        if update.track_num < 1 || update.disc_num < 1 {
            return Err("track and disc numbers must be at least 1".into());
        }
        let featured_artists = normalize_names(update.featured_artists)
            .into_iter()
            .filter(|name| !name.eq_ignore_ascii_case(&primary_artist))
            .collect();
        let (album_title, album_artists, album_artwork) =
            self.import_album_details(update.album, &primary_artist)?;
        let source_path = PathBuf::from(update.source_path);
        extract_raw_metadata(&source_path)
            .map_err(|error| format!("invalid source mp3: {error}"))?;
        Ok(ValidatedSongImport {
            source_path,
            title,
            primary_artist,
            featured_artists,
            album_title,
            album_artists,
            album_artwork: album_artwork.map(|path| PathBuf::from(self.to_abs(&path))),
            track_num: update.track_num,
            disc_num: update.disc_num,
            cover: update.cover,
            crop: update.crop,
        })
    }

    fn import_album_details(
        &self,
        album: AlbumSelection,
        primary_artist: &str,
    ) -> Result<(String, Vec<String>, Option<String>), String> {
        match album {
            AlbumSelection::New { title, artists } => {
                let title = required_text(&title, "album title")?;
                let artists = normalize_names(artists);
                let artists = if artists.is_empty() {
                    vec![primary_artist.to_string()]
                } else {
                    artists
                };
                Ok((title, artists, None))
            }
            AlbumSelection::Existing(album_id) => self.existing_album_details(&album_id),
        }
    }

    fn existing_album_details(
        &self,
        album_id: &str,
    ) -> Result<(String, Vec<String>, Option<String>), String> {
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let (title, artwork) = conn
            .query_row(
                "SELECT title, cover_path FROM albums WHERE id = ?1",
                params![album_id],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, Option<String>>(1)?)),
            )
            .optional()
            .map_err(|error| format!("lookup album: {error}"))?
            .ok_or_else(|| "album not found".to_string())?;
        let artists = album_artist_names(&conn, album_id)
            .map_err(|error| format!("load album artists: {error}"))?;
        Ok((title, artists, artwork))
    }

    fn stage_import_artwork(&self, cover: &ArtworkUpdate) -> Result<Option<String>, String> {
        match cover {
            ArtworkUpdate::Replace(source) => self
                .stage_managed_artwork(source, "songs", &Uuid::new_v4().to_string())
                .map(Some),
            ArtworkUpdate::Keep | ArtworkUpdate::Remove => Ok(None),
        }
    }

    fn index_imported_song(
        &self,
        import: &ValidatedSongImport,
        destination: &Path,
        artwork: Option<&str>,
        retained: Option<&Path>,
    ) -> Result<SongRow, String> {
        let metadata = extract_raw_metadata(destination)
            .map_err(|error| format!("read imported metadata: {error}"))?;
        let mut conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let tx = conn.transaction().map_err(|error| format!("tx: {error}"))?;
        insert_song(
            &tx,
            &self.covers_dir,
            &self.base_dir,
            destination,
            metadata,
            &import.primary_artist,
            &import.featured_artists,
            &import.album_artists,
        )
        .map_err(|error| format!("insert imported song: {error}"))?;
        let stored_path = self.to_rel(destination);
        let song_id: String = tx
            .query_row(
                "SELECT id FROM songs WHERE file_path = ?1",
                params![stored_path],
                |row| row.get(0),
            )
            .map_err(|error| format!("find imported song: {error}"))?;
        if let Some(artwork) = artwork {
            tx.execute(
                "UPDATE songs SET cover_path = ?1 WHERE id = ?2",
                params![artwork, song_id],
            )
            .map_err(|error| format!("store imported artwork: {error}"))?;
        }
        if let (Some(crop), Some(retained)) = (&import.crop, retained) {
            tx.execute(
                "INSERT INTO song_audio_crops (song_id, original_file_path, retained_file_path, start_ms, end_ms) VALUES (?1, ?2, ?3, ?4, ?5)",
                params![
                    song_id,
                    self.to_rel(destination),
                    self.to_rel(retained),
                    crop.start_ms,
                    crop.end_ms
                ],
            )
            .map_err(|error| format!("store imported crop: {error}"))?;
        }
        tx.commit().map_err(|error| format!("commit: {error}"))?;
        drop(conn);
        self.get_song_by_id(&song_id)
            .ok_or_else(|| "imported song not found".into())
    }

    fn retain_import_original(
        &self,
        import: &ValidatedSongImport,
        originals_dir: &Path,
    ) -> Result<Option<PathBuf>, String> {
        let Some(crop) = &import.crop else {
            return Ok(None);
        };
        validate_crop_bounds(crop.start_ms, crop.end_ms)?;
        let original = Path::new(&crop.original_source_path);
        extract_raw_metadata(original)
            .map_err(|error| format!("invalid full-length import: {error}"))?;
        retain_original_file(original, originals_dir, &Uuid::new_v4().to_string()).map(Some)
    }

    pub fn update_song_metadata(
        &self,
        update: SongMetadataUpdate,
        originals_dir: &Path,
    ) -> Result<SongRow, String> {
        let edit = validate_song_edit(update)?;
        let new_cover = self.stage_edit_artwork(&edit.cover, "songs", &edit.song_id)?;
        let result = self.apply_song_edit(&edit, new_cover.as_deref(), originals_dir);
        if result.is_err() {
            self.remove_managed_path(new_cover.as_deref());
        }
        result
    }

    fn apply_song_edit(
        &self,
        edit: &SongEdit,
        new_cover: Option<&str>,
        originals_dir: &Path,
    ) -> Result<SongRow, String> {
        let mut conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let tx = conn.transaction().map_err(|error| format!("tx: {error}"))?;
        let source = load_song_source(&tx, &edit.song_id)?;
        let destination = resolve_song_destination(&tx, edit, &source, new_cover)?;
        let prepared = self.prepare_song_audio(edit, &source, &destination, originals_dir)?;
        let operation = (|| {
            write_song_edit(&tx, edit, &destination, &prepared.stored_destination)?;
            apply_crop_change(&tx, &edit.song_id, &prepared.crop_change)?;
            cleanup_changed_album(&tx, &self.base_dir, &source, &destination)?;
            commit_audio_edit(tx, prepared.file.as_ref(), &self.operation_journal_path)
        })();
        let operation_id = match operation {
            Ok(id) => id,
            Err(error) => {
                remove_optional_file(prepared.retained_on_failure.as_deref());
                return Err(error);
            }
        };
        finish_committed_operation(&conn, &self.operation_journal_path, operation_id);
        drop(conn);
        remove_optional_file(prepared.consumed_temporary.as_deref());
        remove_optional_file(prepared.retained_on_success.as_deref());
        self.cleanup_replaced_cover(&edit.cover, source.old_cover.as_deref(), new_cover);
        self.get_song_by_id(&edit.song_id)
            .ok_or_else(|| "updated song not found".into())
    }

    fn prepare_song_audio(
        &self,
        edit: &SongEdit,
        source: &SongSource,
        destination: &SongDestination,
        originals_dir: &Path,
    ) -> Result<PreparedSongAudio, String> {
        let source_path = PathBuf::from(self.to_abs(&source.stored_file_path));
        let artwork = destination
            .effective_cover_path
            .as_deref()
            .map(|path| PathBuf::from(self.to_abs(path)));
        match &edit.audio {
            SongAudioUpdate::Keep => self.prepare_unchanged_song_audio(
                edit,
                destination,
                &source_path,
                artwork.as_deref(),
            ),
            SongAudioUpdate::ApplyCrop {
                source_path: replacement,
                start_ms,
                end_ms,
            } => self.prepare_song_crop(
                edit,
                source,
                destination,
                &source_path,
                Path::new(replacement),
                (*start_ms, *end_ms),
                artwork.as_deref(),
                originals_dir,
            ),
            SongAudioUpdate::RestoreOriginal => self.prepare_song_restore(
                edit,
                source,
                destination,
                &source_path,
                artwork.as_deref(),
            ),
        }
    }

    fn prepare_unchanged_song_audio(
        &self,
        edit: &SongEdit,
        destination: &SongDestination,
        source_path: &Path,
        artwork: Option<&Path>,
    ) -> Result<PreparedSongAudio, String> {
        let file = if edit.write_file_tags {
            Some(prepare_audio_update(
                source_path,
                &edit.title,
                &edit.primary_artist,
                &edit.featured_artists,
                &destination.album_title,
                &destination.album_artists,
                edit.track_num,
                edit.disc_num,
                artwork,
            )?)
        } else {
            None
        };
        Ok(PreparedSongAudio {
            file,
            stored_destination: self.to_rel(source_path),
            crop_change: CropChange::Keep,
            consumed_temporary: None,
            retained_on_failure: None,
            retained_on_success: None,
        })
    }

    #[allow(clippy::too_many_arguments)]
    fn prepare_song_crop(
        &self,
        edit: &SongEdit,
        source: &SongSource,
        destination: &SongDestination,
        active_path: &Path,
        replacement: &Path,
        bounds: (i64, i64),
        artwork: Option<&Path>,
        originals_dir: &Path,
    ) -> Result<PreparedSongAudio, String> {
        validate_crop_bounds(bounds.0, bounds.1)?;
        extract_raw_metadata(replacement)
            .map_err(|error| format!("invalid cropped mp3: {error}"))?;
        let (crop, retained_on_failure) =
            self.crop_record(source, active_path, bounds, originals_dir)?;
        let active_destination = cropped_destination(active_path)?;
        let file = prepare_audio_replacement(
            active_path,
            &active_destination,
            replacement,
            &edit.title,
            &edit.primary_artist,
            &edit.featured_artists,
            &destination.album_title,
            &destination.album_artists,
            edit.track_num,
            edit.disc_num,
            artwork,
        );
        let file = match file {
            Ok(file) => file,
            Err(error) => {
                remove_optional_file(retained_on_failure.as_deref());
                return Err(error);
            }
        };
        Ok(PreparedSongAudio {
            file: Some(file),
            stored_destination: self.to_rel(&active_destination),
            crop_change: CropChange::Upsert(crop),
            consumed_temporary: Some(replacement.to_path_buf()),
            retained_on_failure,
            retained_on_success: None,
        })
    }

    fn crop_record(
        &self,
        source: &SongSource,
        active_path: &Path,
        bounds: (i64, i64),
        originals_dir: &Path,
    ) -> Result<(SongCropRow, Option<PathBuf>), String> {
        if let Some(existing) = &source.crop {
            let mut crop = existing.clone();
            crop.start_ms = bounds.0;
            crop.end_ms = bounds.1;
            return Ok((crop, None));
        }
        let retained =
            retain_original_file(active_path, originals_dir, &Uuid::new_v4().to_string())?;
        Ok((
            SongCropRow {
                original_file_path: source.stored_file_path.clone(),
                retained_file_path: self.to_rel(&retained),
                start_ms: bounds.0,
                end_ms: bounds.1,
            },
            Some(retained),
        ))
    }

    fn prepare_song_restore(
        &self,
        edit: &SongEdit,
        source: &SongSource,
        destination: &SongDestination,
        active_path: &Path,
        artwork: Option<&Path>,
    ) -> Result<PreparedSongAudio, String> {
        let crop = source
            .crop
            .as_ref()
            .ok_or_else(|| "song has not been cropped".to_string())?;
        let original_destination = PathBuf::from(self.to_abs(&crop.original_file_path));
        if original_destination != active_path && original_destination.exists() {
            return Err(format!(
                "original audio path is occupied: {}",
                original_destination.display()
            ));
        }
        let retained = PathBuf::from(self.to_abs(&crop.retained_file_path));
        let file = prepare_audio_replacement(
            active_path,
            &original_destination,
            &retained,
            &edit.title,
            &edit.primary_artist,
            &edit.featured_artists,
            &destination.album_title,
            &destination.album_artists,
            edit.track_num,
            edit.disc_num,
            artwork,
        )?;
        Ok(PreparedSongAudio {
            file: Some(file),
            stored_destination: crop.original_file_path.clone(),
            crop_change: CropChange::Delete,
            consumed_temporary: None,
            retained_on_failure: None,
            retained_on_success: Some(retained),
        })
    }

    pub fn update_album_metadata(&self, update: AlbumMetadataUpdate) -> Result<AlbumRow, String> {
        let edit = validate_album_edit(update)?;
        let new_cover = self.stage_edit_artwork(&edit.cover, "albums", &edit.album_id)?;
        let result = self.apply_album_edit(&edit, new_cover.as_deref());
        if result.is_err() {
            self.remove_managed_path(new_cover.as_deref());
        }
        result
    }

    fn apply_album_edit(
        &self,
        edit: &AlbumEdit,
        new_cover: Option<&str>,
    ) -> Result<AlbumRow, String> {
        let mut conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let tx = conn.transaction().map_err(|error| format!("tx: {error}"))?;
        let destination = resolve_album_destination(&tx, edit, new_cover)?;
        apply_album_identity(&tx, edit, &destination)?;
        let prepared = self.prepare_album_audio(&tx, edit, &destination)?;
        let operation_id = commit_audio_batch(tx, &prepared, &self.operation_journal_path)?;
        finish_committed_operation(&conn, &self.operation_journal_path, operation_id);
        drop(conn);
        self.cleanup_album_covers(&destination);
        self.find_album(&destination.surviving_id)
    }

    fn prepare_album_audio(
        &self,
        tx: &rusqlite::Transaction<'_>,
        edit: &AlbumEdit,
        destination: &AlbumDestination,
    ) -> Result<Vec<PreparedAudioUpdate>, String> {
        if !edit.write_file_tags {
            return Ok(Vec::new());
        }
        let rows = query_songs(tx, SongFilter::ByAlbumId(destination.surviving_id.clone()))
            .map_err(|error| format!("load album songs: {error}"))?;
        let names = album_artist_names(tx, &destination.surviving_id)
            .map_err(|error| format!("load album artists: {error}"))?;
        rows.into_iter()
            .map(|row| self.prepare_album_song(row, &edit.title, &names))
            .collect()
    }

    fn prepare_album_song(
        &self,
        row: SongRow,
        album_title: &str,
        album_artists: &[String],
    ) -> Result<PreparedAudioUpdate, String> {
        let artwork = row
            .cover_path
            .as_deref()
            .map(|path| PathBuf::from(self.to_abs(path)));
        prepare_audio_update(
            &PathBuf::from(self.to_abs(&row.file_path)),
            &row.title,
            &row.primary_artist,
            &row.featured_artists,
            album_title,
            album_artists,
            row.track_num,
            row.disc_num,
            artwork.as_deref(),
        )
    }

    fn stage_edit_artwork(
        &self,
        artwork: &ArtworkUpdate,
        category: &str,
        owner_id: &str,
    ) -> Result<Option<String>, String> {
        match artwork {
            ArtworkUpdate::Replace(source) => self
                .stage_managed_artwork(source, category, owner_id)
                .map(Some),
            _ => Ok(None),
        }
    }

    fn cleanup_replaced_cover(
        &self,
        artwork: &ArtworkUpdate,
        old_cover: Option<&str>,
        new_cover: Option<&str>,
    ) {
        if matches!(artwork, ArtworkUpdate::Keep) || old_cover == new_cover {
            return;
        }
        self.remove_managed_path(old_cover);
    }

    fn cleanup_album_covers(&self, destination: &AlbumDestination) {
        if destination.source_cover != destination.final_cover {
            self.remove_managed_path(destination.source_cover.as_deref());
        }
        if destination.merged && destination.destination_cover != destination.final_cover {
            self.remove_managed_path(destination.destination_cover.as_deref());
        }
    }

    fn remove_managed_path(&self, path: Option<&str>) {
        if let Some(path) = path {
            remove_stored_file(&self.base_dir, path);
        }
    }

    fn find_album(&self, album_id: &str) -> Result<AlbumRow, String> {
        self.get_albums_paginated(0, self.get_total_albums())
            .into_iter()
            .find(|album| album.id == album_id)
            .ok_or_else(|| "updated album not found".into())
    }
}

fn prepare_import_audio(
    import: &ValidatedSongImport,
    imports_dir: &Path,
    artwork: Option<&str>,
    store: &SqliteLibraryStore,
) -> Result<PathBuf, String> {
    fs::create_dir_all(imports_dir).map_err(|error| format!("create imports dir: {error}"))?;
    let base_name = safe_import_name(&import.title);
    let nonce = Uuid::new_v4();
    let destination = imports_dir.join(format!("{base_name}-{nonce}.mp3"));
    let staged = imports_dir.join(format!(".{base_name}-{nonce}.partial.mp3"));
    fs::copy(&import.source_path, &staged).map_err(|error| format!("stage import: {error}"))?;
    // embed the song override, otherwise carry the selected album artwork
    let artwork = artwork
        .map(|path| PathBuf::from(store.to_abs(path)))
        .or_else(|| import.album_artwork.clone());
    let metadata = MetadataWrite {
        title: &import.title,
        primary_artist: &import.primary_artist,
        featured_artists: &import.featured_artists,
        album: &import.album_title,
        album_artists: &import.album_artists,
        track_num: import.track_num,
        disc_num: import.disc_num,
        artwork_path: artwork.as_deref(),
    };
    if let Err(error) = write_metadata(&staged, &metadata) {
        let _ = fs::remove_file(&staged);
        return Err(error);
    }
    extract_raw_metadata(&staged).map_err(|error| {
        let _ = fs::remove_file(&staged);
        format!("verify imported audio: {error}")
    })?;
    fs::rename(&staged, &destination).map_err(|error| {
        let _ = fs::remove_file(&staged);
        format!("finish imported audio: {error}")
    })?;
    Ok(destination)
}

fn safe_import_name(title: &str) -> String {
    let name = title
        .chars()
        .map(|character| match character {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            other if other.is_control() => '_',
            other => other,
        })
        .take(80)
        .collect::<String>();
    let name = name.trim().trim_matches('.');
    if name.is_empty() {
        "track".to_string()
    } else {
        name.to_string()
    }
}

fn validate_crop_bounds(start_ms: i64, end_ms: i64) -> Result<(), String> {
    if start_ms < 0 || end_ms - start_ms < 100 {
        return Err("crop must be at least 100ms and start at or after zero".into());
    }
    Ok(())
}

fn retain_original_file(source: &Path, directory: &Path, owner: &str) -> Result<PathBuf, String> {
    if !source.is_file() {
        return Err(format!(
            "full-length audio is unavailable: {}",
            source.display()
        ));
    }
    fs::create_dir_all(directory).map_err(|error| format!("create originals dir: {error}"))?;
    let extension = source
        .extension()
        .and_then(|value| value.to_str())
        .ok_or_else(|| "full-length audio has no extension".to_string())?;
    let retained = directory.join(format!("{owner}.{extension}"));
    let staged = directory.join(format!(".{owner}.partial.{extension}"));
    fs::copy(source, &staged).map_err(|error| format!("retain original audio: {error}"))?;
    if let Err(error) = extract_raw_metadata(&staged) {
        let _ = fs::remove_file(&staged);
        return Err(format!("verify retained original: {error}"));
    }
    fs::rename(&staged, &retained).map_err(|error| {
        let _ = fs::remove_file(&staged);
        format!("finish retained original: {error}")
    })?;
    Ok(retained)
}

fn cropped_destination(active: &Path) -> Result<PathBuf, String> {
    let is_mp3 = active
        .extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| value.eq_ignore_ascii_case("mp3"));
    if is_mp3 {
        return Ok(active.to_path_buf());
    }
    let direct = active.with_extension("mp3");
    if !direct.exists() {
        return Ok(direct);
    }
    let stem = active
        .file_stem()
        .and_then(|value| value.to_str())
        .ok_or_else(|| "invalid source audio filename".to_string())?;
    let suffix = &Uuid::new_v4().to_string()[..8];
    Ok(active.with_file_name(format!("{stem}-cropped-{suffix}.mp3")))
}

fn remove_optional_file(path: Option<&Path>) {
    if let Some(path) = path {
        let _ = fs::remove_file(path);
    }
}

fn validate_song_edit(update: SongMetadataUpdate) -> Result<SongEdit, String> {
    let title = required_text(&update.title, "song title")?;
    let primary_artist = required_text(&update.primary_artist, "primary artist")?;
    if update.track_num < 1 || update.disc_num < 1 {
        return Err("track and disc numbers must be at least 1".into());
    }
    let featured_artists = normalize_names(update.featured_artists)
        .into_iter()
        .filter(|name| !name.eq_ignore_ascii_case(&primary_artist))
        .collect();
    Ok(SongEdit {
        song_id: update.song_id,
        title,
        primary_artist,
        featured_artists,
        track_num: update.track_num,
        disc_num: update.disc_num,
        album: update.album,
        cover: update.cover,
        write_file_tags: update.write_file_tags,
        audio: update.audio,
    })
}

fn load_song_source(tx: &rusqlite::Transaction<'_>, song_id: &str) -> Result<SongSource, String> {
    let mut source = tx
        .query_row(
            "SELECT album_id, cover_path, file_path FROM songs WHERE id = ?1",
            params![song_id],
            |row| {
                Ok(SongSource {
                    old_album_id: row.get(0)?,
                    old_cover: row.get(1)?,
                    stored_file_path: row.get(2)?,
                    crop: None,
                })
            },
        )
        .optional()
        .map_err(|error| format!("lookup song: {error}"))?
        .ok_or_else(|| "song not found".to_string())?;
    source.crop = tx
        .query_row(
            "SELECT original_file_path, retained_file_path, start_ms, end_ms FROM song_audio_crops WHERE song_id = ?1",
            params![song_id],
            |row| {
                Ok(SongCropRow {
                    original_file_path: row.get(0)?,
                    retained_file_path: row.get(1)?,
                    start_ms: row.get(2)?,
                    end_ms: row.get(3)?,
                })
            },
        )
        .optional()
        .map_err(|error| format!("load song crop: {error}"))?;
    Ok(source)
}

fn resolve_song_destination(
    tx: &rusqlite::Transaction<'_>,
    edit: &SongEdit,
    source: &SongSource,
    new_cover: Option<&str>,
) -> Result<SongDestination, String> {
    let album_id = resolve_album_selection(tx, &edit.album)?;
    let primary_artist_id = ensure_artist(tx, &edit.primary_artist)
        .map_err(|error| format!("primary artist: {error}"))?;
    let featured_artist_ids = ensure_artists(tx, &edit.featured_artists, "featured artists")?;
    let (album_title, album_cover) = load_album_title_and_cover(tx, &album_id)?;
    let album_artists = album_artist_names(tx, &album_id)
        .map_err(|error| format!("load album artists: {error}"))?;
    let song_cover_path =
        choose_artwork(&edit.cover, source.old_cover.as_deref(), new_cover).map(str::to_string);
    let effective_cover_path = song_cover_path.clone().or(album_cover);
    Ok(SongDestination {
        album_id,
        album_title,
        album_artists,
        primary_artist_id,
        featured_artist_ids,
        song_cover_path,
        effective_cover_path,
    })
}

fn resolve_album_selection(
    tx: &rusqlite::Transaction<'_>,
    selection: &AlbumSelection,
) -> Result<String, String> {
    match selection {
        AlbumSelection::Existing(id) => {
            let exists = tx
                .query_row("SELECT 1 FROM albums WHERE id = ?1", params![id], |row| {
                    row.get::<_, i64>(0)
                })
                .optional()
                .map_err(|error| format!("lookup album: {error}"))?;
            exists
                .map(|_| id.clone())
                .ok_or_else(|| "album not found".into())
        }
        AlbumSelection::New { title, artists } => {
            let title = required_text(title, "album title")?;
            let artists = normalize_names(artists.clone());
            if artists.is_empty() {
                return Err("at least one album artist is required".into());
            }
            ensure_multi_artist_album(tx, &title, &artists)
                .map_err(|error| format!("ensure album: {error}"))
        }
    }
}

fn ensure_artists(
    tx: &rusqlite::Transaction<'_>,
    names: &[String],
    context: &str,
) -> Result<Vec<String>, String> {
    names
        .iter()
        .map(|name| ensure_artist(tx, name))
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|error| format!("{context}: {error}"))
}

fn load_album_title_and_cover(
    tx: &rusqlite::Transaction<'_>,
    album_id: &str,
) -> Result<(String, Option<String>), String> {
    tx.query_row(
        "SELECT title, cover_path FROM albums WHERE id = ?1",
        params![album_id],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .map_err(|error| format!("load destination album: {error}"))
}

fn choose_artwork<'a>(
    artwork: &ArtworkUpdate,
    old_cover: Option<&'a str>,
    new_cover: Option<&'a str>,
) -> Option<&'a str> {
    match artwork {
        ArtworkUpdate::Keep => old_cover,
        ArtworkUpdate::Remove => None,
        ArtworkUpdate::Replace(_) => new_cover,
    }
}

fn write_song_edit(
    tx: &rusqlite::Transaction<'_>,
    edit: &SongEdit,
    destination: &SongDestination,
    stored_file_path: &str,
) -> Result<(), String> {
    tx.execute(
        "UPDATE songs SET title = ?1, track_num = ?2, disc_num = ?3, album_id = ?4, cover_path = ?5, file_path = ?6 WHERE id = ?7",
        params![edit.title, edit.track_num, edit.disc_num, destination.album_id, destination.song_cover_path, stored_file_path, edit.song_id],
    )
    .map_err(|error| format!("update song: {error}"))?;
    replace_song_artists(tx, edit, destination)
}

fn apply_crop_change(
    tx: &rusqlite::Transaction<'_>,
    song_id: &str,
    change: &CropChange,
) -> Result<(), String> {
    match change {
        CropChange::Keep => Ok(()),
        CropChange::Upsert(crop) => tx
            .execute(
                "INSERT INTO song_audio_crops (song_id, original_file_path, retained_file_path, start_ms, end_ms) VALUES (?1, ?2, ?3, ?4, ?5) ON CONFLICT(song_id) DO UPDATE SET start_ms = excluded.start_ms, end_ms = excluded.end_ms",
                params![song_id, crop.original_file_path, crop.retained_file_path, crop.start_ms, crop.end_ms],
            )
            .map(|_| ())
            .map_err(|error| format!("store song crop: {error}")),
        CropChange::Delete => tx
            .execute("DELETE FROM song_audio_crops WHERE song_id = ?1", params![song_id])
            .map(|_| ())
            .map_err(|error| format!("clear song crop: {error}")),
    }
}

fn replace_song_artists(
    tx: &rusqlite::Transaction<'_>,
    edit: &SongEdit,
    destination: &SongDestination,
) -> Result<(), String> {
    tx.execute(
        "DELETE FROM song_artists WHERE song_id = ?1",
        params![edit.song_id],
    )
    .map_err(|error| format!("clear song artists: {error}"))?;
    tx.execute(
        "INSERT INTO song_artists (song_id, artist_id, is_featured, position) VALUES (?1, ?2, 0, 0)",
        params![edit.song_id, destination.primary_artist_id],
    )
    .map_err(|error| format!("insert primary artist: {error}"))?;
    for (position, artist_id) in destination.featured_artist_ids.iter().enumerate() {
        tx.execute(
            "INSERT INTO song_artists (song_id, artist_id, is_featured, position) VALUES (?1, ?2, 1, ?3)",
            params![edit.song_id, artist_id, position as i64 + 1],
        )
        .map_err(|error| format!("insert featured artist: {error}"))?;
    }
    Ok(())
}

fn cleanup_changed_album(
    tx: &rusqlite::Transaction<'_>,
    base_dir: &Path,
    source: &SongSource,
    destination: &SongDestination,
) -> Result<(), String> {
    if let Some(old_id) = source
        .old_album_id
        .as_deref()
        .filter(|old_id| *old_id != destination.album_id)
    {
        cleanup_orphan_album(tx, base_dir, old_id)?;
    }
    Ok(())
}

fn validate_album_edit(update: AlbumMetadataUpdate) -> Result<AlbumEdit, String> {
    let title = required_text(&update.title, "album title")?;
    let artist_names = normalize_names(update.artists);
    if artist_names.is_empty() {
        return Err("at least one album artist is required".into());
    }
    Ok(AlbumEdit {
        album_id: update.album_id,
        title,
        artist_names,
        cover: update.cover,
        write_file_tags: update.write_file_tags,
    })
}

fn resolve_album_destination(
    tx: &rusqlite::Transaction<'_>,
    edit: &AlbumEdit,
    new_cover: Option<&str>,
) -> Result<AlbumDestination, String> {
    let source_cover = load_source_album_cover(tx, &edit.album_id)?;
    let artist_ids = ensure_artists(tx, &edit.artist_names, "album artists")?;
    let artist_key = artist_key(&artist_ids);
    let collision = find_album_collision(tx, edit, &artist_key)?;
    let (surviving_id, destination_cover, merged) = collision
        .map(|(id, cover)| (id, cover, true))
        .unwrap_or_else(|| (edit.album_id.clone(), source_cover.clone(), false));
    let final_cover =
        choose_artwork(&edit.cover, destination_cover.as_deref(), new_cover).map(str::to_string);
    let destination = AlbumDestination {
        surviving_id,
        source_cover,
        destination_cover,
        final_cover,
        artist_ids,
        artist_key,
        merged,
    };
    Ok(destination)
}

fn load_source_album_cover(
    tx: &rusqlite::Transaction<'_>,
    album_id: &str,
) -> Result<Option<String>, String> {
    tx.query_row(
        "SELECT cover_path FROM albums WHERE id = ?1",
        params![album_id],
        |row| row.get(0),
    )
    .optional()
    .map_err(|error| format!("lookup album: {error}"))?
    .ok_or_else(|| "album not found".into())
}

fn artist_key(ids: &[String]) -> String {
    let mut ids = ids.to_vec();
    ids.sort();
    ids.dedup();
    ids.join("\u{1f}")
}

fn find_album_collision(
    tx: &rusqlite::Transaction<'_>,
    edit: &AlbumEdit,
    artist_key: &str,
) -> Result<Option<(String, Option<String>)>, String> {
    tx.query_row(
        "SELECT id, cover_path FROM albums WHERE id != ?1 AND title = ?2 COLLATE NOCASE AND artist_key = ?3",
        params![edit.album_id, edit.title, artist_key],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .optional()
    .map_err(|error| format!("find matching album: {error}"))
}

fn apply_album_identity(
    tx: &rusqlite::Transaction<'_>,
    edit: &AlbumEdit,
    destination: &AlbumDestination,
) -> Result<(), String> {
    if destination.merged {
        merge_album(tx, &edit.album_id, &destination.surviving_id)?;
    } else {
        update_album_identity(tx, edit, destination)?;
    }
    tx.execute(
        "UPDATE albums SET cover_path = ?1 WHERE id = ?2",
        params![destination.final_cover, destination.surviving_id],
    )
    .map_err(|error| format!("update album artwork: {error}"))?;
    Ok(())
}

fn merge_album(
    tx: &rusqlite::Transaction<'_>,
    source_id: &str,
    destination_id: &str,
) -> Result<(), String> {
    tx.execute(
        "UPDATE songs SET album_id = ?1 WHERE album_id = ?2",
        params![destination_id, source_id],
    )
    .map_err(|error| format!("merge album songs: {error}"))?;
    tx.execute(
        "INSERT OR IGNORE INTO pinned_items (item_id, kind, position, pinned_at) SELECT ?1, kind, position, pinned_at FROM pinned_items WHERE item_id = ?2 AND kind = 'album'",
        params![destination_id, source_id],
    )
    .map_err(|error| format!("retarget album pin: {error}"))?;
    tx.execute(
        "DELETE FROM pinned_items WHERE item_id = ?1 AND kind = 'album'",
        params![source_id],
    )
    .map_err(|error| format!("remove source pin: {error}"))?;
    tx.execute("DELETE FROM albums WHERE id = ?1", params![source_id])
        .map_err(|error| format!("delete merged album: {error}"))?;
    Ok(())
}

fn update_album_identity(
    tx: &rusqlite::Transaction<'_>,
    edit: &AlbumEdit,
    destination: &AlbumDestination,
) -> Result<(), String> {
    tx.execute(
        "UPDATE albums SET title = ?1, artist_id = ?2, artist_key = ?3 WHERE id = ?4",
        params![
            edit.title,
            destination.artist_ids[0],
            destination.artist_key,
            destination.surviving_id
        ],
    )
    .map_err(|error| format!("update album: {error}"))?;
    replace_album_artists(tx, &destination.surviving_id, &destination.artist_ids)
}

fn replace_album_artists(
    tx: &rusqlite::Transaction<'_>,
    album_id: &str,
    artist_ids: &[String],
) -> Result<(), String> {
    tx.execute(
        "DELETE FROM album_artists WHERE album_id = ?1",
        params![album_id],
    )
    .map_err(|error| format!("clear album artists: {error}"))?;
    for (position, artist_id) in artist_ids.iter().enumerate() {
        tx.execute(
            "INSERT INTO album_artists (album_id, artist_id, position) VALUES (?1, ?2, ?3)",
            params![album_id, artist_id, position as i64],
        )
        .map_err(|error| format!("insert album artist: {error}"))?;
    }
    Ok(())
}

fn commit_audio_edit(
    tx: rusqlite::Transaction<'_>,
    prepared: Option<&PreparedAudioUpdate>,
    journal_path: &Path,
) -> Result<Option<String>, String> {
    let operation_id = prepared
        .map(|file| record_metadata_operation(&tx, journal_path, std::slice::from_ref(file)))
        .transpose()?;
    if let Some(file) = prepared {
        if let Err(error) = file.activate() {
            let _ = fs::remove_file(journal_path);
            return Err(error);
        }
    }
    if let Err(error) = tx.commit() {
        prepared.iter().for_each(|file| file.rollback());
        let _ = fs::remove_file(journal_path);
        return Err(format!("commit: {error}"));
    }
    prepared.iter().for_each(|file| file.finish());
    Ok(operation_id)
}

fn commit_audio_batch(
    tx: rusqlite::Transaction<'_>,
    prepared: &[PreparedAudioUpdate],
    journal_path: &Path,
) -> Result<Option<String>, String> {
    let operation_id = if prepared.is_empty() {
        None
    } else {
        Some(record_metadata_operation(&tx, journal_path, prepared)?)
    };
    if let Err(error) = activate_prepared_batch(prepared) {
        rollback_prepared_batch(prepared);
        let _ = fs::remove_file(journal_path);
        return Err(error);
    }
    if let Err(error) = tx.commit() {
        rollback_prepared_batch(prepared);
        let _ = fs::remove_file(journal_path);
        return Err(format!("commit: {error}"));
    }
    finish_prepared_batch(prepared);
    Ok(operation_id)
}

fn record_metadata_operation(
    tx: &rusqlite::Transaction<'_>,
    journal_path: &Path,
    prepared: &[PreparedAudioUpdate],
) -> Result<String, String> {
    let id = write_metadata_operation_journal(journal_path, prepared)?;
    tx.execute(
        "INSERT INTO metadata_operations (id, committed_at) VALUES (?1, ?2)",
        params![id, now_secs()],
    )
    .map_err(|error| format!("record metadata operation: {error}"))?;
    Ok(id)
}

fn finish_committed_operation(
    conn: &Connection,
    journal_path: &Path,
    operation_id: Option<String>,
) {
    if let Some(id) = operation_id.as_deref() {
        finish_metadata_operation(conn, journal_path, id);
    }
}
