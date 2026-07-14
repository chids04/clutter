use flutter_rust_bridge::frb;
use log::info;

pub use super::models::*;
use crate::core::LibraryCore;
use crate::storage::sqlite::{
    AlbumMetadataUpdate, AlbumSelection, PlaylistVisualUpdate, SongMetadataUpdate,
};

#[frb(opaque)]
pub struct LibraryApi {
    core: LibraryCore,
}

impl LibraryApi {
    /// open (or create) the sqlite database at `db_path` and ensure the covers
    /// directory exists. must be called once from dart before any other method.
    pub fn init(
        db_path: String,
        covers_dir: String,
        base_dir: String,
    ) -> Result<LibraryApi, String> {
        let core = LibraryCore::open(&db_path, &covers_dir, &base_dir)?;
        info!("library initialised at {db_path} (covers: {covers_dir}, base: {base_dir})");
        Ok(LibraryApi { core })
    }

    /// recursively scan `path` for audio files and write their metadata into
    /// sqlite. files already present (matched by `file_path`) are skipped.
    pub fn scan_directory(&self, path: String, config: ScanConfig) -> Result<(), String> {
        self.core.scan_directory(&path, config.is_deezer)
    }

    pub fn import_extracted_song(
        &self,
        request: ExtractedSongImportRequest,
    ) -> Result<SongViewData, String> {
        self.core
            .import_extracted_song(request.into_internal())
            .map(SongViewData::from)
    }

    #[frb(sync)]
    pub fn get_total_songs(&self) -> u32 {
        self.core.get_total_songs()
    }

    pub fn get_songs_paginated(&self, offset: u32, limit: u32) -> Vec<SongViewData> {
        self.core
            .get_songs_paginated(offset, limit)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    pub fn get_song_by_id(&self, id: String) -> Option<SongViewData> {
        self.core.get_song_by_id(&id).map(SongViewData::from)
    }

    #[frb(sync)]
    pub fn get_total_albums(&self) -> u32 {
        self.core.get_total_albums()
    }

    pub fn get_albums_paginated(&self, offset: u32, limit: u32) -> Vec<AlbumViewData> {
        self.core
            .get_albums_paginated(offset, limit)
            .into_iter()
            .map(AlbumViewData::from)
            .collect()
    }

    pub fn get_songs_by_album_id(&self, album_id: String) -> Vec<SongViewData> {
        self.core
            .get_songs_by_album_id(&album_id)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    /// fork an album onto a freshly-created artist row with the same name.
    /// returns the new artist's id. used by the ui to resolve ambiguity when
    /// the scanner merged two distinct same-named artists into one row.
    pub fn split_album_to_new_artist(&self, album_id: String) -> Result<String, String> {
        self.core.split_album_to_new_artist(&album_id)
    }

    #[frb(sync)]
    pub fn get_total_playlists(&self) -> u32 {
        self.core.get_total_playlists()
    }

    pub fn get_playlists_paginated(&self, offset: u32, limit: u32) -> Vec<PlaylistViewData> {
        self.core
            .get_playlists_paginated(offset, limit)
            .into_iter()
            .map(PlaylistViewData::from)
            .collect()
    }

    pub fn get_songs_in_playlist(&self, playlist_id: String) -> Vec<SongViewData> {
        self.core
            .get_songs_in_playlist(&playlist_id)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    pub fn get_liked_song_ids(&self) -> Vec<String> {
        self.core.get_liked_song_ids()
    }

    pub fn get_liked_songs_playlist_id(&self) -> Option<String> {
        self.core.get_liked_songs_playlist_id()
    }

    pub fn create_playlist(&self, name: String) -> Result<String, String> {
        self.core.create_playlist(&name)
    }

    pub fn delete_playlist(&self, id: String) -> Result<(), String> {
        self.core.delete_playlist(&id)
    }

    pub fn add_song_to_playlist(&self, playlist_id: String, song_id: String) -> Result<(), String> {
        self.core.add_song_to_playlist(&playlist_id, &song_id)
    }

    pub fn remove_song_from_playlist(
        &self,
        playlist_id: String,
        song_id: String,
    ) -> Result<(), String> {
        self.core.remove_song_from_playlist(&playlist_id, &song_id)
    }

    #[frb(sync)]
    pub fn get_total_artists(&self) -> u32 {
        self.core.get_total_artists()
    }

    pub fn get_artists_paginated(&self, offset: u32, limit: u32) -> Vec<ArtistViewData> {
        self.core
            .get_artists_paginated(offset, limit)
            .into_iter()
            .map(ArtistViewData::from)
            .collect()
    }

    pub fn get_artist_by_id(&self, id: String) -> Option<ArtistViewData> {
        self.core.get_artist_by_id(&id).map(ArtistViewData::from)
    }

    pub fn get_albums_by_artist_id(&self, artist_id: String) -> Vec<AlbumViewData> {
        self.core
            .get_albums_by_artist_id(&artist_id)
            .into_iter()
            .map(AlbumViewData::from)
            .collect()
    }

    pub fn get_albums_artist_featured_on(&self, artist_id: String) -> Vec<AlbumViewData> {
        self.core
            .get_albums_artist_featured_on(&artist_id)
            .into_iter()
            .map(AlbumViewData::from)
            .collect()
    }

    pub fn get_songs_artist_featured_on(&self, artist_id: String) -> Vec<SongViewData> {
        self.core
            .get_songs_artist_featured_on(&artist_id)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    pub fn search_artists(&self, query: String, limit: u32) -> Vec<ArtistViewData> {
        self.core
            .search_artists(&query, limit)
            .into_iter()
            .map(ArtistViewData::from)
            .collect()
    }

    pub fn search_songs(&self, query: String, limit: u32) -> Vec<SongViewData> {
        self.core
            .search_songs(&query, limit)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    pub fn search_albums(&self, query: String, limit: u32) -> Vec<AlbumViewData> {
        self.core
            .search_albums(&query, limit)
            .into_iter()
            .map(AlbumViewData::from)
            .collect()
    }

    pub fn search_playlists(&self, query: String, limit: u32) -> Vec<PlaylistViewData> {
        self.core
            .search_playlists(&query, limit)
            .into_iter()
            .map(PlaylistViewData::from)
            .collect()
    }

    pub fn update_song(&self, request: SongEditRequest) -> Result<SongViewData, String> {
        let album = match request.album {
            AlbumChoice::Existing { album_id } => AlbumSelection::Existing(album_id),
            AlbumChoice::New { title, artists } => AlbumSelection::New { title, artists },
        };
        self.core
            .update_song_metadata(SongMetadataUpdate {
                song_id: request.song_id,
                title: request.title,
                primary_artist: request.primary_artist,
                featured_artists: request.featured_artists,
                track_num: request.track_num,
                disc_num: request.disc_num,
                album,
                cover: request.cover.into(),
                write_file_tags: true,
                audio: request.audio.into(),
            })
            .map(SongViewData::from)
    }

    pub fn update_album(&self, request: AlbumEditRequest) -> Result<AlbumViewData, String> {
        self.core
            .update_album_metadata(AlbumMetadataUpdate {
                album_id: request.album_id,
                title: request.title,
                artists: request.artists,
                cover: request.cover.into(),
                write_file_tags: true,
            })
            .map(AlbumViewData::from)
    }

    pub fn update_artist_image(
        &self,
        artist_id: String,
        cover: CoverArtEdit,
    ) -> Result<ArtistViewData, String> {
        self.core
            .update_artist_image(&artist_id, cover.into())
            .map(ArtistViewData::from)
    }

    pub fn update_playlist(
        &self,
        request: PlaylistEditRequest,
    ) -> Result<PlaylistViewData, String> {
        let visual = match request.visual {
            PlaylistVisualEdit::Keep => PlaylistVisualUpdate::Keep,
            PlaylistVisualEdit::Initials => PlaylistVisualUpdate::Initials,
            PlaylistVisualEdit::Icon { key } => PlaylistVisualUpdate::Icon(key),
            PlaylistVisualEdit::Image { source_path } => PlaylistVisualUpdate::Image(source_path),
        };
        self.core
            .update_playlist_metadata(&request.playlist_id, &request.name, visual)
            .map(PlaylistViewData::from)
    }

    pub fn delete_song(&self, id: String) -> Result<(), String> {
        self.core.delete_song(&id)
    }

    pub fn delete_album(&self, id: String) -> Result<(), String> {
        self.core.delete_album(&id)
    }

    /// remove a scan path and every song indexed beneath it. returns the
    /// number of songs purged so the ui can surface it in a toast.
    pub fn delete_scan_path(&self, path: String) -> Result<u32, String> {
        self.core.delete_scan_path(&path)
    }

    pub fn get_scan_paths(&self) -> Vec<String> {
        self.core.get_scan_paths()
    }

    pub fn record_play(&self, song_id: String) -> Result<(), String> {
        self.core.record_play(&song_id)
    }

    pub fn get_recently_played(&self, limit: u32) -> Vec<SongViewData> {
        self.core
            .get_recently_played(limit)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    pub fn save_playback_state(
        &self,
        song_id: Option<String>,
        position_ms: i64,
        loop_one: bool,
    ) -> Result<(), String> {
        self.core
            .save_playback_state(song_id.as_deref(), position_ms, loop_one)
    }

    pub fn load_playback_state(&self) -> Option<PlaybackStateData> {
        self.core.load_playback_state().map(PlaybackStateData::from)
    }

    pub fn pin_item(&self, item_id: String, kind: String) -> Result<(), String> {
        self.core.pin_item(&item_id, &kind)
    }

    pub fn unpin_item(&self, item_id: String, kind: String) -> Result<(), String> {
        self.core.unpin_item(&item_id, &kind)
    }

    pub fn get_pinned_items(&self) -> Vec<PinnedItemData> {
        self.core
            .get_pinned_items()
            .into_iter()
            .map(PinnedItemData::from)
            .collect()
    }

    pub fn move_pinned_item(
        &self,
        item_id: String,
        kind: String,
        new_index: u32,
    ) -> Result<(), String> {
        self.core
            .move_pinned_item(&item_id, &kind, new_index as usize)
    }

    pub fn get_keybindings(&self) -> Result<Vec<KeybindingData>, String> {
        self.core
            .get_keybindings()
            .map(|bindings| bindings.into_iter().map(KeybindingData::from).collect())
    }

    pub fn update_keybinding(&self, binding: KeybindingData) -> Result<KeybindingData, String> {
        self.core
            .update_keybinding(binding.into_row())
            .map(KeybindingData::from)
    }

    pub fn reset_keybindings(&self) -> Result<Vec<KeybindingData>, String> {
        self.core
            .reset_keybindings()
            .map(|bindings| bindings.into_iter().map(KeybindingData::from).collect())
    }

    pub fn reset_library(&self) -> Result<(), String> {
        self.core.reset_library()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::media::tags::extract_raw_metadata;
    use std::path::{Path, PathBuf};
    use tempfile::TempDir;

    fn test_album_dir() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("test")
            .join("Playboi Carti - Whole Lotta Red")
    }

    fn copy_dir_all(src: &Path, dst: &Path) {
        std::fs::create_dir_all(dst).expect("create dst");
        for entry in std::fs::read_dir(src).expect("read src") {
            let entry = entry.expect("entry");
            let to = dst.join(entry.file_name());
            if entry.file_type().expect("file type").is_dir() {
                copy_dir_all(&entry.path(), &to);
            } else {
                std::fs::copy(entry.path(), &to).expect("copy file");
            }
        }
    }

    fn new_library() -> (LibraryApi, TempDir) {
        let tmp = TempDir::new().expect("tempdir");
        let db_path = tmp.path().join("library.db");
        let covers_dir = tmp.path().join("covers");
        let lib = LibraryApi::init(
            db_path.to_string_lossy().to_string(),
            covers_dir.to_string_lossy().to_string(),
            tmp.path().to_string_lossy().to_string(),
        )
        .expect("init library");
        (lib, tmp)
    }

    fn song_edit_request(song: &SongViewData, audio: SongAudioEdit) -> SongEditRequest {
        SongEditRequest {
            song_id: song.id.clone(),
            title: song.title.clone(),
            primary_artist: song.primary_artist.clone(),
            featured_artists: song.featured_artists.clone(),
            track_num: song.track_num,
            disc_num: song.disc_num,
            album: AlbumChoice::Existing {
                album_id: song.album_id.clone(),
            },
            cover: CoverArtEdit::Keep,
            audio,
        }
    }

    fn tiny_wav() -> Vec<u8> {
        let samples = vec![0_u8; 1_600];
        let mut bytes = Vec::with_capacity(44 + samples.len());
        bytes.extend_from_slice(b"RIFF");
        bytes.extend_from_slice(&(36_u32 + samples.len() as u32).to_le_bytes());
        bytes.extend_from_slice(b"WAVEfmt ");
        bytes.extend_from_slice(&16_u32.to_le_bytes());
        bytes.extend_from_slice(&1_u16.to_le_bytes());
        bytes.extend_from_slice(&1_u16.to_le_bytes());
        bytes.extend_from_slice(&8_000_u32.to_le_bytes());
        bytes.extend_from_slice(&16_000_u32.to_le_bytes());
        bytes.extend_from_slice(&2_u16.to_le_bytes());
        bytes.extend_from_slice(&16_u16.to_le_bytes());
        bytes.extend_from_slice(b"data");
        bytes.extend_from_slice(&(samples.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&samples);
        bytes
    }

    #[test]
    fn scan_populates_sqlite_and_queries_work() {
        let (lib, _tmp) = new_library();
        lib.scan_directory(
            test_album_dir().to_string_lossy().to_string(),
            ScanConfig { is_deezer: true },
        )
        .expect("scan");

        assert_eq!(lib.get_total_songs(), 24);

        let page = lib.get_songs_paginated(0, 100);
        assert_eq!(page.len(), 24);

        for song in &page {
            assert!(!song.title.is_empty(), "song title empty: {:?}", song);
            assert!(
                !song.primary_artist.is_empty(),
                "primary artist empty: {:?}",
                song
            );
            assert!(!song.album.is_empty(), "album empty: {:?}", song);
        }

        let carti_tracks = page
            .iter()
            .filter(|s| s.primary_artist == "Playboi Carti")
            .count();
        assert!(
            carti_tracks >= 20,
            "expected most tracks to have Playboi Carti as primary artist, got {carti_tracks}"
        );

        let first = lib
            .get_song_by_id(page[0].id.clone())
            .expect("get_song_by_id");
        assert_eq!(first.id, page[0].id);
        assert_eq!(first.album, page[0].album);
    }

    #[test]
    fn scan_is_idempotent() {
        let (lib, _tmp) = new_library();
        let scan_path = test_album_dir().to_string_lossy().to_string();
        lib.scan_directory(scan_path.clone(), ScanConfig { is_deezer: true })
            .expect("scan 1");
        lib.scan_directory(scan_path, ScanConfig { is_deezer: true })
            .expect("scan 2");
        assert_eq!(lib.get_total_songs(), 24, "rescan must not duplicate songs");
    }

    #[test]
    fn scan_writes_cover_to_disk() {
        let (lib, tmp) = new_library();
        lib.scan_directory(
            test_album_dir().to_string_lossy().to_string(),
            ScanConfig { is_deezer: true },
        )
        .expect("scan");

        let page = lib.get_songs_paginated(0, 1);
        let song = page.first().expect("at least one song");
        let cover = song
            .cover_path
            .as_ref()
            .expect("scanned mp3s embed a front cover");
        let cover_on_disk = Path::new(cover);
        assert!(cover_on_disk.exists(), "cover file not written: {cover}");
        assert!(cover_on_disk.starts_with(tmp.path().join("covers")));
    }

    #[test]
    fn song_edit_rewrites_tags_on_a_temporary_audio_copy() {
        let (lib, tmp) = new_library();
        let source = test_album_dir().join("01 - Rockstar Made.mp3");
        let music_dir = tmp.path().join("editable");
        std::fs::create_dir_all(&music_dir).unwrap();
        let copy = music_dir.join("track.mp3");
        std::fs::copy(source, &copy).unwrap();
        lib.scan_directory(
            music_dir.to_string_lossy().to_string(),
            ScanConfig { is_deezer: true },
        )
        .unwrap();
        let song = lib.get_songs_paginated(0, 1).pop().unwrap();
        let updated = lib
            .update_song(SongEditRequest {
                song_id: song.id.clone(),
                title: "Edited in Clutter".into(),
                primary_artist: song.primary_artist,
                featured_artists: song.featured_artists,
                track_num: song.track_num,
                disc_num: song.disc_num,
                album: AlbumChoice::Existing {
                    album_id: song.album_id,
                },
                cover: CoverArtEdit::Keep,
                audio: SongAudioEdit::Keep,
            })
            .expect("edit song");
        assert_eq!(updated.title, "Edited in Clutter");
        let raw = extract_raw_metadata(&copy).expect("read rewritten tags");
        assert_eq!(raw.title.as_deref(), Some("Edited in Clutter"));
    }

    #[test]
    fn crop_retains_original_and_restore_returns_to_full_source() {
        let (lib, tmp) = new_library();
        let music_dir = tmp.path().join("crop-edit");
        std::fs::create_dir_all(&music_dir).unwrap();
        let original = music_dir.join("track.mp3");
        std::fs::copy(test_album_dir().join("01 - Rockstar Made.mp3"), &original).unwrap();
        lib.scan_directory(
            music_dir.to_string_lossy().into_owned(),
            ScanConfig { is_deezer: true },
        )
        .unwrap();
        let song = lib.get_songs_paginated(0, 1).pop().unwrap();
        let playlist = lib.create_playlist("crop test".into()).unwrap();
        lib.add_song_to_playlist(playlist.clone(), song.id.clone())
            .unwrap();
        let replacement = tmp.path().join("cropped.mp3");
        std::fs::copy(test_album_dir().join("02 - Go2DaMoon.mp3"), &replacement).unwrap();

        let cropped = lib
            .update_song(song_edit_request(
                &song,
                SongAudioEdit::ApplyCrop {
                    source_path: replacement.to_string_lossy().into_owned(),
                    start_ms: 1_000,
                    end_ms: 3_000,
                },
            ))
            .expect("crop song");
        let crop = cropped.crop.as_ref().expect("crop state");
        let retained = PathBuf::from(&crop.original_audio_path);
        assert!(retained.exists());
        assert_eq!((crop.start_ms, crop.end_ms), (1_000, 3_000));
        assert!(
            !replacement.exists(),
            "successful crop consumes its temp file"
        );

        let second_replacement = tmp.path().join("cropped-again.mp3");
        std::fs::copy(
            test_album_dir().join("03 - Stop Breathing.mp3"),
            &second_replacement,
        )
        .unwrap();
        let recropped = lib
            .update_song(song_edit_request(
                &cropped,
                SongAudioEdit::ApplyCrop {
                    source_path: second_replacement.to_string_lossy().into_owned(),
                    start_ms: 500,
                    end_ms: 4_000,
                },
            ))
            .expect("recrop song");
        let recrop = recropped.crop.as_ref().unwrap();
        assert_eq!(recrop.original_audio_path, crop.original_audio_path);
        assert_eq!((recrop.start_ms, recrop.end_ms), (500, 4_000));

        let mut restore = song_edit_request(&recropped, SongAudioEdit::RestoreOriginal);
        restore.title = "Restored with current metadata".into();
        let restored = lib.update_song(restore).expect("restore song");
        assert!(restored.crop.is_none());
        assert_eq!(restored.file_path, original.to_string_lossy());
        assert!(original.exists());
        assert!(!retained.exists(), "restore removes the managed original");
        assert_eq!(lib.get_songs_in_playlist(playlist).len(), 1);
        let tags = extract_raw_metadata(&original).unwrap();
        assert_eq!(
            tags.title.as_deref(),
            Some("Restored with current metadata")
        );
    }

    #[test]
    fn rejected_crop_keeps_song_and_temporary_output() {
        let (lib, tmp) = new_library();
        let music_dir = tmp.path().join("bad-crop");
        std::fs::create_dir_all(&music_dir).unwrap();
        let original = music_dir.join("track.mp3");
        std::fs::copy(test_album_dir().join("01 - Rockstar Made.mp3"), &original).unwrap();
        lib.scan_directory(
            music_dir.to_string_lossy().into_owned(),
            ScanConfig { is_deezer: true },
        )
        .unwrap();
        let song = lib.get_songs_paginated(0, 1).pop().unwrap();
        let replacement = tmp.path().join("retry.mp3");
        std::fs::copy(test_album_dir().join("02 - Go2DaMoon.mp3"), &replacement).unwrap();

        let result = lib.update_song(song_edit_request(
            &song,
            SongAudioEdit::ApplyCrop {
                source_path: replacement.to_string_lossy().into_owned(),
                start_ms: 500,
                end_ms: 550,
            },
        ));

        assert!(result.is_err());
        assert!(replacement.exists());
        let unchanged = lib.get_song_by_id(song.id).unwrap();
        assert!(unchanged.crop.is_none());
        assert_eq!(unchanged.file_path, original.to_string_lossy());
    }

    #[test]
    fn crop_changes_non_mp3_path_and_restore_returns_original_extension() {
        let (lib, tmp) = new_library();
        let music_dir = tmp.path().join("format-crop");
        std::fs::create_dir_all(&music_dir).unwrap();
        let original = music_dir.join("track.wav");
        std::fs::write(&original, tiny_wav()).unwrap();
        lib.scan_directory(
            music_dir.to_string_lossy().into_owned(),
            ScanConfig { is_deezer: true },
        )
        .unwrap();
        let song = lib.get_songs_paginated(0, 1).pop().unwrap();
        let replacement = tmp.path().join("format-crop.mp3");
        std::fs::copy(test_album_dir().join("02 - Go2DaMoon.mp3"), &replacement).unwrap();

        let cropped = lib
            .update_song(song_edit_request(
                &song,
                SongAudioEdit::ApplyCrop {
                    source_path: replacement.to_string_lossy().into_owned(),
                    start_ms: 100,
                    end_ms: 1_000,
                },
            ))
            .expect("crop renamed format");
        assert!(cropped.file_path.ends_with("track.mp3"));
        assert!(!original.exists());

        let restored = lib
            .update_song(song_edit_request(&cropped, SongAudioEdit::RestoreOriginal))
            .expect("restore renamed format");
        assert_eq!(restored.file_path, original.to_string_lossy());
        assert!(original.exists());
    }

    #[test]
    fn extracted_song_import_writes_tags_and_indexes_managed_file() {
        let (lib, tmp) = new_library();
        let source = tmp.path().join("extracted.mp3");
        std::fs::copy(test_album_dir().join("01 - Rockstar Made.mp3"), &source).unwrap();

        let imported = lib
            .import_extracted_song(ExtractedSongImportRequest {
                source_path: source.to_string_lossy().into_owned(),
                title: "Imported Track".into(),
                primary_artist: "Import Artist".into(),
                featured_artists: vec!["Guest".into()],
                track_num: 1,
                disc_num: 1,
                album: AlbumChoice::New {
                    title: "Import Album".into(),
                    artists: vec!["Import Artist".into()],
                },
                cover: CoverArtEdit::Keep,
                crop: None,
            })
            .expect("import song");

        assert_eq!(imported.title, "Imported Track");
        assert_eq!(imported.album, "Import Album");
        assert_eq!(imported.featured_artists, vec!["Guest"]);
        assert!(Path::new(&imported.file_path).exists());
        assert!(imported.file_path.contains("Music/imports"));
        assert!(!source.exists(), "temporary extraction should be removed");
        let tags = extract_raw_metadata(Path::new(&imported.file_path)).unwrap();
        assert_eq!(tags.title.as_deref(), Some("Imported Track"));
    }

    #[test]
    fn cropped_import_retains_full_extraction() {
        let (lib, tmp) = new_library();
        let cropped = tmp.path().join("cropped-import.mp3");
        let original = tmp.path().join("full-import.mp3");
        std::fs::copy(test_album_dir().join("01 - Rockstar Made.mp3"), &cropped).unwrap();
        std::fs::copy(test_album_dir().join("02 - Go2DaMoon.mp3"), &original).unwrap();

        let imported = lib
            .import_extracted_song(ExtractedSongImportRequest {
                source_path: cropped.to_string_lossy().into_owned(),
                title: "Cropped Import".into(),
                primary_artist: "Import Artist".into(),
                featured_artists: vec![],
                track_num: 1,
                disc_num: 1,
                album: AlbumChoice::New {
                    title: "Import Album".into(),
                    artists: vec!["Import Artist".into()],
                },
                cover: CoverArtEdit::Keep,
                crop: Some(ExtractedSongCropRequest {
                    original_source_path: original.to_string_lossy().into_owned(),
                    start_ms: 2_000,
                    end_ms: 5_000,
                }),
            })
            .expect("import cropped song");

        let crop = imported.crop.expect("stored crop");
        let retained = PathBuf::from(&crop.original_audio_path);
        assert!(retained.exists());
        assert_eq!((crop.start_ms, crop.end_ms), (2_000, 5_000));
        assert!(!cropped.exists());
        assert!(!original.exists());
        lib.delete_song(imported.id).unwrap();
        assert!(!retained.exists(), "delete removes the retained original");
    }

    #[test]
    fn rejected_extracted_song_keeps_temporary_file() {
        let (lib, tmp) = new_library();
        let source = tmp.path().join("extracted.mp3");
        std::fs::copy(test_album_dir().join("01 - Rockstar Made.mp3"), &source).unwrap();

        let result = lib.import_extracted_song(ExtractedSongImportRequest {
            source_path: source.to_string_lossy().into_owned(),
            title: "Imported Track".into(),
            primary_artist: "Import Artist".into(),
            featured_artists: vec![],
            track_num: 0,
            disc_num: 1,
            album: AlbumChoice::New {
                title: "Import Album".into(),
                artists: vec!["Import Artist".into()],
            },
            cover: CoverArtEdit::Keep,
            crop: None,
        });

        assert!(result.is_err());
        assert!(source.exists(), "failed import must remain retryable");
        assert_eq!(lib.get_total_songs(), 0);
    }

    #[test]
    fn album_edit_rewrites_every_temporary_source_file() {
        let (lib, tmp) = new_library();
        let music_dir = tmp.path().join("album-edit");
        std::fs::create_dir_all(&music_dir).unwrap();
        for name in ["01 - Rockstar Made.mp3", "02 - Go2DaMoon.mp3"] {
            std::fs::copy(test_album_dir().join(name), music_dir.join(name)).unwrap();
        }
        lib.scan_directory(
            music_dir.to_string_lossy().into_owned(),
            ScanConfig { is_deezer: true },
        )
        .unwrap();
        let album = lib.get_albums_paginated(0, 1).pop().unwrap();
        let updated = lib
            .update_album(AlbumEditRequest {
                album_id: album.id,
                title: "Edited Album".into(),
                artists: vec!["Playboi Carti".into(), "Guest Curator".into()],
                cover: CoverArtEdit::Keep,
            })
            .expect("edit album");
        assert_eq!(updated.artists, vec!["Playboi Carti", "Guest Curator"]);
        for name in ["01 - Rockstar Made.mp3", "02 - Go2DaMoon.mp3"] {
            let raw = extract_raw_metadata(&music_dir.join(name)).unwrap();
            assert_eq!(raw.album.as_deref(), Some("Edited Album"));
            assert_eq!(
                raw.album_artist.as_deref(),
                Some("Playboi Carti / Guest Curator")
            );
        }
    }

    fn seed_scan(lib: &LibraryApi) {
        lib.scan_directory(
            test_album_dir().to_string_lossy().to_string(),
            ScanConfig { is_deezer: true },
        )
        .expect("scan");
    }

    #[test]
    fn delete_song_cascades_to_history_and_playback_state() {
        let (lib, _tmp) = new_library();
        seed_scan(&lib);
        let song = lib.get_songs_paginated(0, 1).pop().expect("a song");
        lib.record_play(song.id.clone()).expect("record play");
        lib.save_playback_state(Some(song.id.clone()), 12_345, false)
            .expect("save state");

        lib.delete_song(song.id.clone()).expect("delete song");

        assert!(lib.get_song_by_id(song.id.clone()).is_none());
        let recents = lib.get_recently_played(10);
        assert!(
            recents.iter().all(|s| s.id != song.id),
            "recently_played should be purged"
        );
        // playback_state.song_id was set null by the fk, so load returns none.
        assert!(lib.load_playback_state().is_none());
    }

    #[test]
    fn delete_album_removes_cover_file() {
        let (lib, _tmp) = new_library();
        seed_scan(&lib);
        let album = lib.get_albums_paginated(0, 1).pop().expect("an album");
        let songs = lib.get_songs_by_album_id(album.id.clone());
        let cover_path = songs
            .iter()
            .find_map(|s| s.cover_path.clone())
            .expect("some song has a cover");
        assert!(Path::new(&cover_path).exists());

        lib.delete_album(album.id.clone()).expect("delete album");

        assert_eq!(lib.get_total_albums(), 0, "album gone");
        assert!(lib.get_songs_by_album_id(album.id).is_empty(), "songs gone");
        assert!(
            !Path::new(&cover_path).exists(),
            "cover file should be unlinked"
        );
    }

    #[test]
    fn delete_scan_path_removes_all_songs_under_it() {
        let (lib, _tmp) = new_library();
        let scan_path = test_album_dir().to_string_lossy().to_string();
        seed_scan(&lib);
        assert_eq!(lib.get_total_songs(), 24);
        assert_eq!(lib.get_scan_paths(), vec![scan_path.clone()]);

        let removed = lib.delete_scan_path(scan_path).expect("delete path");

        assert_eq!(removed, 24);
        assert_eq!(lib.get_total_songs(), 0);
        assert_eq!(lib.get_total_albums(), 0);
        assert!(lib.get_scan_paths().is_empty());
    }

    #[test]
    fn scan_paths_persist_across_reopen() {
        let tmp = TempDir::new().expect("tempdir");
        let base_dir = tmp.path().to_string_lossy().to_string();
        let db_path = tmp.path().join("library.db").to_string_lossy().to_string();
        let covers_dir = tmp.path().join("covers").to_string_lossy().to_string();
        let scan_path = test_album_dir().to_string_lossy().to_string();
        {
            let lib = LibraryApi::init(db_path.clone(), covers_dir.clone(), base_dir.clone())
                .expect("init");
            lib.scan_directory(scan_path.clone(), ScanConfig { is_deezer: true })
                .expect("scan");
        }
        let lib2 = LibraryApi::init(db_path, covers_dir, base_dir).expect("reopen");
        assert_eq!(lib2.get_scan_paths(), vec![scan_path]);
    }

    #[test]
    fn playback_state_roundtrip() {
        let (lib, _tmp) = new_library();
        seed_scan(&lib);
        let song = lib.get_songs_paginated(0, 1).pop().expect("a song");
        lib.save_playback_state(Some(song.id.clone()), 42_000, true)
            .expect("save");
        let loaded = lib.load_playback_state().expect("loaded");
        assert_eq!(loaded.song.id, song.id);
        assert_eq!(loaded.position_ms, 42_000);
        assert!(loaded.loop_one);
    }

    /// reproduces the ios bug: the app's sandbox container (which holds the
    /// music, covers, and db) moves to a new path between launches. stored
    /// paths must resolve against the *current* base, not the stale one.
    #[test]
    fn paths_survive_base_dir_rotation() {
        use std::fs;

        // ----- launch #1: container a is the current base -----
        let container_a = TempDir::new().expect("container a");
        let base_a = container_a.path();
        let music_a = base_a.join("Music");
        fs::create_dir_all(&music_a).expect("music dir");
        // copy the album into the app's own folder (i.e. under the base), the
        // way music is imported into clutter on ios.
        for entry in fs::read_dir(test_album_dir()).expect("read album") {
            let entry = entry.expect("entry");
            if entry.path().extension().and_then(|e| e.to_str()) == Some("mp3") {
                fs::copy(entry.path(), music_a.join(entry.file_name())).expect("copy mp3");
            }
        }

        let db_a = base_a.join("clutter").join("library.db");
        let covers_a = base_a.join("clutter").join("covers");
        {
            let lib = LibraryApi::init(
                db_a.to_string_lossy().to_string(),
                covers_a.to_string_lossy().to_string(),
                base_a.to_string_lossy().to_string(),
            )
            .expect("init a");
            lib.scan_directory(
                music_a.to_string_lossy().to_string(),
                ScanConfig { is_deezer: true },
            )
            .expect("scan a");
            let songs = lib.get_songs_paginated(0, 100);
            assert!(!songs.is_empty(), "scanned some songs");
            for s in &songs {
                assert!(
                    Path::new(&s.file_path).exists(),
                    "song missing: {}",
                    s.file_path
                );
            }
            assert!(
                songs.iter().any(|s| s
                    .cover_path
                    .as_deref()
                    .map(|c| Path::new(c).exists())
                    .unwrap_or(false)),
                "expected at least one cover on disk"
            );
        }

        // ----- relaunch: container uuid rotated, everything moved to base b -----
        let container_b = TempDir::new().expect("container b");
        let base_b = container_b.path();
        copy_dir_all(base_a, base_b);
        let base_a_str = base_a.to_string_lossy().to_string();
        let base_b_str = base_b.to_string_lossy().to_string();

        let lib2 = LibraryApi::init(
            base_b
                .join("clutter")
                .join("library.db")
                .to_string_lossy()
                .to_string(),
            base_b
                .join("clutter")
                .join("covers")
                .to_string_lossy()
                .to_string(),
            base_b_str.clone(),
        )
        .expect("init b");

        let songs = lib2.get_songs_paginated(0, 100);
        assert!(!songs.is_empty(), "songs reload after rotation");
        for s in &songs {
            assert!(
                s.file_path.starts_with(&base_b_str),
                "file_path not rebased onto B: {}",
                s.file_path
            );
            assert!(
                !s.file_path.contains(&base_a_str),
                "file_path still carries stale base A: {}",
                s.file_path
            );
            assert!(
                Path::new(&s.file_path).exists(),
                "song unresolved after rotation: {}",
                s.file_path
            );
        }
        let cover = songs
            .iter()
            .find_map(|s| s.cover_path.clone())
            .expect("a cover path");
        assert!(
            cover.starts_with(&base_b_str),
            "cover not rebased onto B: {cover}"
        );
        assert!(
            Path::new(&cover).exists(),
            "cover unresolved after rotation: {cover}"
        );
    }

    #[test]
    fn recently_played_orders_by_most_recent() {
        let (lib, _tmp) = new_library();
        seed_scan(&lib);
        let page = lib.get_songs_paginated(0, 3);
        // records use seconds resolution, so space the plays out.
        lib.record_play(page[0].id.clone()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        lib.record_play(page[1].id.clone()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        lib.record_play(page[2].id.clone()).unwrap();

        let recents = lib.get_recently_played(10);
        assert_eq!(recents[0].id, page[2].id);
        assert_eq!(recents[1].id, page[1].id);
        assert_eq!(recents[2].id, page[0].id);
    }
}
