use super::*;

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
}

struct SongSource {
    old_album_id: Option<String>,
    old_cover: Option<String>,
    stored_file_path: String,
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

impl SqliteLibraryStore {
    pub fn update_song_metadata(&self, update: SongMetadataUpdate) -> Result<SongRow, String> {
        let edit = validate_song_edit(update)?;
        let new_cover = self.stage_edit_artwork(&edit.cover, "songs", &edit.song_id)?;
        let result = self.apply_song_edit(&edit, new_cover.as_deref());
        if result.is_err() {
            self.remove_managed_path(new_cover.as_deref());
        }
        result
    }

    fn apply_song_edit(&self, edit: &SongEdit, new_cover: Option<&str>) -> Result<SongRow, String> {
        let mut conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let tx = conn.transaction().map_err(|error| format!("tx: {error}"))?;
        let source = load_song_source(&tx, &edit.song_id)?;
        let destination = resolve_song_destination(&tx, edit, &source, new_cover)?;
        let prepared = self.prepare_song_audio(edit, &source, &destination)?;
        write_song_edit(&tx, edit, &destination)?;
        cleanup_changed_album(&tx, &self.base_dir, &source, &destination)?;
        let operation_id = commit_audio_edit(tx, prepared.as_ref(), &self.operation_journal_path)?;
        finish_committed_operation(&conn, &self.operation_journal_path, operation_id);
        drop(conn);
        self.cleanup_replaced_cover(&edit.cover, source.old_cover.as_deref(), new_cover);
        self.get_song_by_id(&edit.song_id)
            .ok_or_else(|| "updated song not found".into())
    }

    fn prepare_song_audio(
        &self,
        edit: &SongEdit,
        source: &SongSource,
        destination: &SongDestination,
    ) -> Result<Option<PreparedAudioUpdate>, String> {
        if !edit.write_file_tags {
            return Ok(None);
        }
        let source_path = PathBuf::from(self.to_abs(&source.stored_file_path));
        let artwork = destination
            .effective_cover_path
            .as_deref()
            .map(|path| PathBuf::from(self.to_abs(path)));
        prepare_audio_update(
            &source_path,
            &edit.title,
            &edit.primary_artist,
            &edit.featured_artists,
            &destination.album_title,
            &destination.album_artists,
            edit.track_num,
            edit.disc_num,
            artwork.as_deref(),
        )
        .map(Some)
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
    })
}

fn load_song_source(tx: &rusqlite::Transaction<'_>, song_id: &str) -> Result<SongSource, String> {
    tx.query_row(
        "SELECT album_id, cover_path, file_path FROM songs WHERE id = ?1",
        params![song_id],
        |row| {
            Ok(SongSource {
                old_album_id: row.get(0)?,
                old_cover: row.get(1)?,
                stored_file_path: row.get(2)?,
            })
        },
    )
    .optional()
    .map_err(|error| format!("lookup song: {error}"))?
    .ok_or_else(|| "song not found".into())
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
) -> Result<(), String> {
    tx.execute(
        "UPDATE songs SET title = ?1, track_num = ?2, disc_num = ?3, album_id = ?4, cover_path = ?5 WHERE id = ?6",
        params![edit.title, edit.track_num, edit.disc_num, destination.album_id, destination.song_cover_path, edit.song_id],
    )
    .map_err(|error| format!("update song: {error}"))?;
    replace_song_artists(tx, edit, destination)
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
