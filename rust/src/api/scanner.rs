use flutter_rust_bridge::frb;
use log::{info, warn};
use walkdir::WalkDir;

use super::db::{AlbumRow, ArtistRow, PinnedItemRow, PlaybackStateRow, PlaylistRow, SongRow, Store};
use super::metadata::{extract_raw_metadata, parse_artist_string, MISSING_ARTIST};

const SUPPORTED_EXTENSIONS: &[&str] = &["mp3", "flac", "m4a", "mp4", "ogg", "opus", "wav"];

#[derive(Debug, Clone)]
pub struct Config {
    pub is_deezer: bool,
}

/// Flattened, UI-ready view of a song. All names are resolved strings — the
/// frontend never sees IDs for artists/albums.
#[derive(Debug, Clone)]
pub struct SongViewData {
    pub id: String,
    pub title: String,
    pub primary_artist: String,
    pub featured_artists: Vec<String>,
    pub cover_path: Option<String>,
    pub file_path: String,
    pub track_num: i64,
    pub disc_num: i64,
    pub album: String,
}

impl From<SongRow> for SongViewData {
    fn from(row: SongRow) -> Self {
        SongViewData {
            id: row.id,
            title: row.title,
            primary_artist: row.primary_artist,
            featured_artists: row.featured_artists,
            cover_path: row.cover_path,
            file_path: row.file_path,
            track_num: row.track_num,
            disc_num: row.disc_num,
            album: row.album,
        }
    }
}

/// UI-ready album shape. `artist` is the resolved album-artist name.
#[derive(Debug, Clone)]
pub struct AlbumViewData {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub cover_path: Option<String>,
    pub song_count: i64,
}

impl From<AlbumRow> for AlbumViewData {
    fn from(row: AlbumRow) -> Self {
        AlbumViewData {
            id: row.id,
            title: row.title,
            artist: row.artist,
            cover_path: row.cover_path,
            song_count: row.song_count,
        }
    }
}

/// UI-ready playlist shape.
#[derive(Debug, Clone)]
pub struct PlaylistViewData {
    pub id: String,
    pub name: String,
    pub is_system: bool,
    pub song_count: i64,
}

impl From<PlaylistRow> for PlaylistViewData {
    fn from(row: PlaylistRow) -> Self {
        PlaylistViewData {
            id: row.id,
            name: row.name,
            is_system: row.is_system,
            song_count: row.song_count,
        }
    }
}

/// UI-ready artist shape. `cover_path` is a representative album cover for
/// the artist (may be `None` if no albums have covers yet).
#[derive(Debug, Clone)]
pub struct ArtistViewData {
    pub id: String,
    pub name: String,
    pub cover_path: Option<String>,
    pub album_count: i64,
    pub song_count: i64,
}

impl From<ArtistRow> for ArtistViewData {
    fn from(row: ArtistRow) -> Self {
        ArtistViewData {
            id: row.id,
            name: row.name,
            cover_path: row.cover_path,
            album_count: row.album_count,
            song_count: row.song_count,
        }
    }
}

/// UI-ready playback state used to resume the MediaBar on relaunch.
#[derive(Debug, Clone)]
pub struct PlaybackStateData {
    pub song: SongViewData,
    pub position_ms: i64,
    pub loop_one: bool,
}

impl From<PlaybackStateRow> for PlaybackStateData {
    fn from(row: PlaybackStateRow) -> Self {
        PlaybackStateData {
            song: row.song.into(),
            position_ms: row.position_ms,
            loop_one: row.loop_one,
        }
    }
}

/// UI-ready pinned item for the quick-play sidebar.
#[derive(Debug, Clone)]
pub struct PinnedItemData {
    pub item_id: String,
    pub kind: String,
    pub position: i64,
}

impl From<PinnedItemRow> for PinnedItemData {
    fn from(row: PinnedItemRow) -> Self {
        PinnedItemData {
            item_id: row.item_id,
            kind: row.kind,
            position: row.position,
        }
    }
}

#[frb(opaque)]
pub struct CLibrary {
    store: Store,
}

impl CLibrary {
    /// Open (or create) the SQLite database at `db_path` and ensure the covers
    /// directory exists. Must be called once from Dart before any other method.
    pub fn init(
        db_path: String,
        covers_dir: String,
        base_dir: String,
    ) -> Result<CLibrary, String> {
        let store = Store::open(&db_path, &covers_dir, &base_dir)?;
        info!("CLibrary initialised at {db_path} (covers: {covers_dir}, base: {base_dir})");
        Ok(CLibrary { store })
    }

    /// Recursively scan `path` for audio files and write their metadata into
    /// SQLite. Files already present (matched by `file_path`) are skipped.
    pub fn scan_directory(&self, path: String, config: Config) -> Result<(), String> {
        if let Err(e) = self.store.add_scan_path(&path) {
            warn!("failed to persist scan path {path}: {e}");
        }
        let mut processed = 0usize;
        for entry in WalkDir::new(&path)
            .follow_links(true)
            .into_iter()
            .filter_map(|e| e.ok())
        {
            if !entry.file_type().is_file() {
                continue;
            }
            let file_path = entry.path();
            let supported = file_path
                .extension()
                .and_then(|e| e.to_str())
                .map(|e| SUPPORTED_EXTENSIONS.contains(&e.to_ascii_lowercase().as_str()))
                .unwrap_or(false);
            if !supported {
                continue;
            }
            let meta = match extract_raw_metadata(file_path) {
                Ok(m) => m,
                Err(e) => {
                    warn!("failed to read {:?}: {}", file_path, e);
                    continue;
                }
            };

            let (leading_artist, feature_artists) = match meta.leading_artist.as_deref() {
                Some(raw) => parse_artist_string(raw, config.is_deezer),
                None => (MISSING_ARTIST.to_string(), Vec::new()),
            };
            let album_artist = match meta.album_artist.as_deref() {
                Some(raw) => parse_artist_string(raw, config.is_deezer).0,
                None => leading_artist.clone(),
            };

            if let Err(e) = self.store.insert_song(
                file_path,
                meta,
                &leading_artist,
                &feature_artists,
                &album_artist,
            ) {
                warn!("failed to index {:?}: {}", file_path, e);
            } else {
                processed += 1;
            }
        }
        info!("scan complete: {processed} songs indexed from {path}");
        Ok(())
    }

    #[frb(sync)]
    pub fn get_total_songs(&self) -> u32 {
        self.store.get_total_songs()
    }

    pub fn get_songs_paginated(&self, offset: u32, limit: u32) -> Vec<SongViewData> {
        self.store
            .get_songs_paginated(offset, limit)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    pub fn get_song_by_id(&self, id: String) -> Option<SongViewData> {
        self.store.get_song_by_id(&id).map(SongViewData::from)
    }

    #[frb(sync)]
    pub fn get_total_albums(&self) -> u32 {
        self.store.get_total_albums()
    }

    pub fn get_albums_paginated(&self, offset: u32, limit: u32) -> Vec<AlbumViewData> {
        self.store
            .get_albums_paginated(offset, limit)
            .into_iter()
            .map(AlbumViewData::from)
            .collect()
    }

    pub fn get_songs_by_album_id(&self, album_id: String) -> Vec<SongViewData> {
        self.store
            .get_songs_by_album_id(&album_id)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    /// Fork an album onto a freshly-created artist row with the same name.
    /// Returns the new artist's id. Used by the UI to resolve ambiguity when
    /// the scanner merged two distinct same-named artists into one row.
    pub fn split_album_to_new_artist(&self, album_id: String) -> Result<String, String> {
        self.store.split_album_to_new_artist(&album_id)
    }

    #[frb(sync)]
    pub fn get_total_playlists(&self) -> u32 {
        self.store.get_total_playlists()
    }

    pub fn get_playlists_paginated(
        &self,
        offset: u32,
        limit: u32,
    ) -> Vec<PlaylistViewData> {
        self.store
            .get_playlists_paginated(offset, limit)
            .into_iter()
            .map(PlaylistViewData::from)
            .collect()
    }

    pub fn get_songs_in_playlist(&self, playlist_id: String) -> Vec<SongViewData> {
        self.store
            .get_songs_in_playlist(&playlist_id)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    pub fn get_liked_song_ids(&self) -> Vec<String> {
        self.store.get_liked_song_ids()
    }

    pub fn get_liked_songs_playlist_id(&self) -> Option<String> {
        self.store.get_liked_songs_playlist_id()
    }

    pub fn create_playlist(&self, name: String) -> Result<String, String> {
        self.store.create_playlist(&name)
    }

    pub fn delete_playlist(&self, id: String) -> Result<(), String> {
        self.store.delete_playlist(&id)
    }

    pub fn add_song_to_playlist(
        &self,
        playlist_id: String,
        song_id: String,
    ) -> Result<(), String> {
        self.store.add_song_to_playlist(&playlist_id, &song_id)
    }

    pub fn remove_song_from_playlist(
        &self,
        playlist_id: String,
        song_id: String,
    ) -> Result<(), String> {
        self.store.remove_song_from_playlist(&playlist_id, &song_id)
    }

    #[frb(sync)]
    pub fn get_total_artists(&self) -> u32 {
        self.store.get_total_artists()
    }

    pub fn get_artists_paginated(&self, offset: u32, limit: u32) -> Vec<ArtistViewData> {
        self.store
            .get_artists_paginated(offset, limit)
            .into_iter()
            .map(ArtistViewData::from)
            .collect()
    }

    pub fn get_artist_by_id(&self, id: String) -> Option<ArtistViewData> {
        self.store.get_artist_by_id(&id).map(ArtistViewData::from)
    }

    pub fn get_albums_by_artist_id(&self, artist_id: String) -> Vec<AlbumViewData> {
        self.store
            .get_albums_by_artist_id(&artist_id)
            .into_iter()
            .map(AlbumViewData::from)
            .collect()
    }

    pub fn get_albums_artist_featured_on(&self, artist_id: String) -> Vec<AlbumViewData> {
        self.store
            .get_albums_artist_featured_on(&artist_id)
            .into_iter()
            .map(AlbumViewData::from)
            .collect()
    }

    pub fn get_songs_artist_featured_on(&self, artist_id: String) -> Vec<SongViewData> {
        self.store
            .get_songs_artist_featured_on(&artist_id)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    pub fn search_artists(&self, query: String, limit: u32) -> Vec<ArtistViewData> {
        self.store
            .search_artists(&query, limit)
            .into_iter()
            .map(ArtistViewData::from)
            .collect()
    }

    pub fn search_songs(&self, query: String, limit: u32) -> Vec<SongViewData> {
        self.store
            .search_songs(&query, limit)
            .into_iter()
            .map(SongViewData::from)
            .collect()
    }

    pub fn search_albums(&self, query: String, limit: u32) -> Vec<AlbumViewData> {
        self.store
            .search_albums(&query, limit)
            .into_iter()
            .map(AlbumViewData::from)
            .collect()
    }

    pub fn search_playlists(
        &self,
        query: String,
        limit: u32,
    ) -> Vec<PlaylistViewData> {
        self.store
            .search_playlists(&query, limit)
            .into_iter()
            .map(PlaylistViewData::from)
            .collect()
    }

    pub fn delete_song(&self, id: String) -> Result<(), String> {
        self.store.delete_song(&id)
    }

    pub fn delete_album(&self, id: String) -> Result<(), String> {
        self.store.delete_album(&id)
    }

    /// Remove a scan path and every song indexed beneath it. Returns the
    /// number of songs purged so the UI can surface it in a toast.
    pub fn delete_scan_path(&self, path: String) -> Result<u32, String> {
        self.store.delete_scan_path(&path)
    }

    pub fn get_scan_paths(&self) -> Vec<String> {
        self.store.get_scan_paths()
    }

    pub fn record_play(&self, song_id: String) -> Result<(), String> {
        self.store.record_play(&song_id)
    }

    pub fn get_recently_played(&self, limit: u32) -> Vec<SongViewData> {
        self.store
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
        self.store
            .save_playback_state(song_id.as_deref(), position_ms, loop_one)
    }

    pub fn load_playback_state(&self) -> Option<PlaybackStateData> {
        self.store.load_playback_state().map(PlaybackStateData::from)
    }

    pub fn pin_item(&self, item_id: String, kind: String) -> Result<(), String> {
        self.store.pin_item(&item_id, &kind)
    }

    pub fn unpin_item(&self, item_id: String, kind: String) -> Result<(), String> {
        self.store.unpin_item(&item_id, &kind)
    }

    pub fn get_pinned_items(&self) -> Vec<PinnedItemData> {
        self.store
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
        self.store
            .move_pinned_item(&item_id, &kind, new_index as usize)
    }

    pub fn reset_library(&self) -> Result<(), String> {
        self.store.reset_library()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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

    fn new_library() -> (CLibrary, TempDir) {
        let tmp = TempDir::new().expect("tempdir");
        let db_path = tmp.path().join("library.db");
        let covers_dir = tmp.path().join("covers");
        let lib = CLibrary::init(
            db_path.to_string_lossy().to_string(),
            covers_dir.to_string_lossy().to_string(),
            tmp.path().to_string_lossy().to_string(),
        )
        .expect("init library");
        (lib, tmp)
    }

    #[test]
    fn scan_populates_sqlite_and_queries_work() {
        let (lib, _tmp) = new_library();
        lib.scan_directory(
            test_album_dir().to_string_lossy().to_string(),
            Config { is_deezer: true },
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
        lib.scan_directory(scan_path.clone(), Config { is_deezer: true })
            .expect("scan 1");
        lib.scan_directory(scan_path, Config { is_deezer: true })
            .expect("scan 2");
        assert_eq!(lib.get_total_songs(), 24, "rescan must not duplicate songs");
    }

    #[test]
    fn scan_writes_cover_to_disk() {
        let (lib, tmp) = new_library();
        lib.scan_directory(
            test_album_dir().to_string_lossy().to_string(),
            Config { is_deezer: true },
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

    fn seed_scan(lib: &CLibrary) {
        lib.scan_directory(
            test_album_dir().to_string_lossy().to_string(),
            Config { is_deezer: true },
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
        // playback_state.song_id was SET NULL by the FK, so load returns None.
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
        assert!(
            lib.get_songs_by_album_id(album.id).is_empty(),
            "songs gone"
        );
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
            let lib = CLibrary::init(db_path.clone(), covers_dir.clone(), base_dir.clone())
                .expect("init");
            lib.scan_directory(scan_path.clone(), Config { is_deezer: true })
                .expect("scan");
        }
        let lib2 = CLibrary::init(db_path, covers_dir, base_dir).expect("reopen");
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

    /// Reproduces the iOS bug: the app's sandbox container (which holds the
    /// music, covers, and DB) moves to a new path between launches. Stored
    /// paths must resolve against the *current* base, not the stale one.
    #[test]
    fn paths_survive_base_dir_rotation() {
        use std::fs;

        // ----- launch #1: container A is the current base -----
        let container_a = TempDir::new().expect("container a");
        let base_a = container_a.path();
        let music_a = base_a.join("Music");
        fs::create_dir_all(&music_a).expect("music dir");
        // Copy the album into the app's own folder (i.e. under the base), the
        // way music is imported into Clutter on iOS.
        for entry in fs::read_dir(test_album_dir()).expect("read album") {
            let entry = entry.expect("entry");
            if entry.path().extension().and_then(|e| e.to_str()) == Some("mp3") {
                fs::copy(entry.path(), music_a.join(entry.file_name())).expect("copy mp3");
            }
        }

        let db_a = base_a.join("clutter").join("library.db");
        let covers_a = base_a.join("clutter").join("covers");
        {
            let lib = CLibrary::init(
                db_a.to_string_lossy().to_string(),
                covers_a.to_string_lossy().to_string(),
                base_a.to_string_lossy().to_string(),
            )
            .expect("init a");
            lib.scan_directory(
                music_a.to_string_lossy().to_string(),
                Config { is_deezer: true },
            )
            .expect("scan a");
            let songs = lib.get_songs_paginated(0, 100);
            assert!(!songs.is_empty(), "scanned some songs");
            for s in &songs {
                assert!(Path::new(&s.file_path).exists(), "song missing: {}", s.file_path);
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

        // ----- relaunch: container UUID rotated, everything moved to base B -----
        let container_b = TempDir::new().expect("container b");
        let base_b = container_b.path();
        copy_dir_all(base_a, base_b);
        let base_a_str = base_a.to_string_lossy().to_string();
        let base_b_str = base_b.to_string_lossy().to_string();

        let lib2 = CLibrary::init(
            base_b.join("clutter").join("library.db").to_string_lossy().to_string(),
            base_b.join("clutter").join("covers").to_string_lossy().to_string(),
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
        assert!(cover.starts_with(&base_b_str), "cover not rebased onto B: {cover}");
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
        // Records use seconds resolution, so space the plays out.
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
