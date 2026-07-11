use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::media::tags::{
    write_metadata, MetadataWrite, RawCover, RawMetadata, MISSING_ALBUM, MISSING_ARTIST,
    MISSING_TITLE,
};
use log::{debug, warn};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

mod editing;
mod models;

pub use models::*;

// group-concat separator for list of artists in sql projections. using ascii unit
// separator so it cannot collide with characters inside an artist name.
const UNIT_SEP: char = '\u{001f}';

pub(crate) const LIKED_SONGS_NAME: &str = "Liked Songs";

pub struct SqliteLibraryStore {
    pub conn: Mutex<Connection>,
    covers_dir: PathBuf,
    playlist_backup_path: PathBuf,
    operation_journal_path: PathBuf,
    /// base directory that every stored path is relativized against. on ios the
    /// app's sandbox container path (and thus the documents dir) carries a uuid
    /// that rotates on every relaunch/reinstall, so absolute paths persisted in
    /// the db go stale. we store paths relative to this base and rebuild the
    /// absolute path on read against the *current* base. paths outside the base
    /// (e.g. a desktop music folder) are stored/returned absolute unchanged.
    ///
    /// note: only in debug IOS builds are the paths randomized, release builds use
    ///     the bundle id which is stable
    base_dir: PathBuf,
}

impl SqliteLibraryStore {
    /// open (or create) the sqlite database at `db_path` and ensure the covers
    /// directory exists. `base_dir` is the directory all stored paths are made
    /// relative to the base directory held by this store.
    pub fn open(
        db_path: &str,
        covers_dir: &str,
        base_dir: &str,
    ) -> Result<SqliteLibraryStore, String> {
        let covers_dir_buf = PathBuf::from(covers_dir);
        fs::create_dir_all(&covers_dir_buf).map_err(|e| format!("create covers dir: {e}"))?;

        if let Some(parent) = Path::new(db_path).parent() {
            if !parent.as_os_str().is_empty() {
                fs::create_dir_all(parent).map_err(|e| format!("create db dir: {e}"))?;
            }
        }

        let conn = Connection::open(db_path).map_err(|e| format!("open db: {e}"))?;
        conn.execute_batch("PRAGMA foreign_keys = ON;")
            .map_err(|e| format!("enable fks: {e}"))?;
        conn.execute_batch(include_str!("schema.sql"))
            .map_err(|e| format!("init schema: {e}"))?;

        ensure_liked_songs_playlist(&conn).map_err(|e| format!("seed liked songs: {e}"))?;
        let playlist_backup_path = Path::new(db_path)
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("playlist_backup.json");
        let operation_journal_path = Path::new(db_path)
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("metadata_operation.json");
        recover_metadata_operation(&conn, &operation_journal_path)?;

        Ok(SqliteLibraryStore {
            conn: Mutex::new(conn),
            covers_dir: covers_dir_buf,
            playlist_backup_path,
            operation_journal_path,
            base_dir: PathBuf::from(base_dir),
        })
    }

    /// convert an absolute path to one relative to `base_dir` for storage. if
    /// `abs` is not under `base_dir` (e.g. a desktop music folder outside the
    /// app sandbox), it is returned absolute unchanged.
    fn to_rel(&self, abs: &Path) -> String {
        relativize(abs, &self.base_dir)
    }

    /// rebuild an absolute path from a stored value. already-absolute stored
    /// values are returned unchanged; relative ones are joined onto the current
    /// `base_dir`.
    fn to_abs(&self, stored: &str) -> String {
        absolutize(stored, &self.base_dir)
    }

    fn abs_song(&self, mut row: SongRow) -> SongRow {
        row.file_path = self.to_abs(&row.file_path);
        row.cover_path = row.cover_path.map(|c| self.to_abs(&c));
        row.song_cover_path = row.song_cover_path.map(|c| self.to_abs(&c));
        row
    }

    fn abs_album(&self, mut row: AlbumRow) -> AlbumRow {
        row.cover_path = row.cover_path.map(|c| self.to_abs(&c));
        row
    }

    fn abs_artist(&self, mut row: ArtistRow) -> ArtistRow {
        row.cover_path = row.cover_path.map(|c| self.to_abs(&c));
        row.custom_cover_path = row.custom_cover_path.map(|c| self.to_abs(&c));
        row
    }

    fn abs_playlist(&self, mut row: PlaylistRow) -> PlaylistRow {
        row.image_path = row.image_path.map(|p| self.to_abs(&p));
        row
    }

    pub fn get_total_songs(&self) -> u32 {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_total_songs: lock poisoned: {e}");
                return 0;
            }
        };
        conn.query_row("SELECT COUNT(*) FROM songs", [], |r| r.get::<_, i64>(0))
            .map(|n| n as u32)
            .unwrap_or(0)
    }

    pub fn get_songs_paginated(&self, offset: u32, limit: u32) -> Vec<SongRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_songs_paginated: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_songs(&conn, SongFilter::Page { offset, limit })
            .unwrap_or_else(|e| {
                warn!("query paginated failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_song(r))
            .collect()
    }

    pub fn get_song_by_id(&self, id: &str) -> Option<SongRow> {
        let conn = self.conn.lock().ok()?;
        query_songs(&conn, SongFilter::ById(id.to_string()))
            .ok()
            .and_then(|mut v| v.pop())
            .map(|r| self.abs_song(r))
    }

    pub fn contains_song_file(&self, file_path: &Path) -> bool {
        let stored = self.to_rel(file_path);
        self.conn
            .lock()
            .ok()
            .and_then(|conn| {
                conn.query_row(
                    "SELECT 1 FROM songs WHERE file_path = ?1",
                    params![stored],
                    |r| r.get::<_, i64>(0),
                )
                .optional()
                .ok()
                .flatten()
            })
            .is_some()
    }

    #[cfg(test)]
    fn insert_song(
        &self,
        file_path: &Path,
        metadata: RawMetadata,
        primary_artist: &str,
        featured_artists: &[String],
        album_artist: &str,
    ) -> Result<(), String> {
        self.insert_song_with_album_artists(
            file_path,
            metadata,
            primary_artist,
            featured_artists,
            &[album_artist.to_string()],
        )
    }

    pub fn insert_song_with_album_artists(
        &self,
        file_path: &Path,
        meta: RawMetadata,
        leading_artist: &str,
        feature_artists: &[String],
        album_artists: &[String],
    ) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        insert_song(
            &conn,
            &self.covers_dir,
            &self.base_dir,
            file_path,
            meta,
            leading_artist,
            feature_artists,
            album_artists,
        )
        .map_err(|e| format!("insert: {e}"))
    }

    pub fn set_scanned_song_cover(&self, file_path: &Path, cover: &RawCover) -> Result<(), String> {
        let stored_file = self.to_rel(file_path);
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let song_id: String = conn
            .query_row(
                "SELECT id FROM songs WHERE file_path = ?1",
                params![stored_file],
                |r| r.get(0),
            )
            .map_err(|e| format!("find scanned song: {e}"))?;
        let ext = guess_cover_ext(&cover.mime_type);
        let dir = self.covers_dir.join("songs");
        fs::create_dir_all(&dir).map_err(|e| format!("create song artwork dir: {e}"))?;
        let destination = dir.join(format!("{song_id}-{}.{}", Uuid::new_v4(), ext));
        fs::write(&destination, &cover.data).map_err(|e| format!("write song artwork: {e}"))?;
        let stored_cover = self.to_rel(&destination);
        conn.execute(
            "UPDATE songs SET cover_path = ?1 WHERE id = ?2",
            params![stored_cover, song_id],
        )
        .map_err(|e| format!("store song artwork: {e}"))?;
        Ok(())
    }

    pub fn get_total_albums(&self) -> u32 {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_total_albums: lock poisoned: {e}");
                return 0;
            }
        };
        conn.query_row("SELECT COUNT(*) FROM albums", [], |r| r.get::<_, i64>(0))
            .map(|n| n as u32)
            .unwrap_or(0)
    }

    pub fn get_albums_paginated(&self, offset: u32, limit: u32) -> Vec<AlbumRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_albums_paginated: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_albums(&conn, offset, limit)
            .unwrap_or_else(|e| {
                warn!("query albums failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_album(r))
            .collect()
    }

    pub fn get_songs_by_album_id(&self, album_id: &str) -> Vec<SongRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_songs_by_album_id: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_songs(&conn, SongFilter::ByAlbumId(album_id.to_string()))
            .unwrap_or_else(|e| {
                warn!("query songs by album failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_song(r))
            .collect()
    }

    pub fn get_total_playlists(&self) -> u32 {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_total_playlists: lock poisoned: {e}");
                return 0;
            }
        };
        conn.query_row("SELECT COUNT(*) FROM playlists", [], |r| r.get::<_, i64>(0))
            .map(|n| n as u32)
            .unwrap_or(0)
    }

    pub fn get_playlists_paginated(&self, offset: u32, limit: u32) -> Vec<PlaylistRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_playlists_paginated: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_playlists(&conn, offset, limit)
            .unwrap_or_else(|e| {
                warn!("query playlists failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_playlist(r))
            .collect()
    }

    pub fn get_songs_in_playlist(&self, playlist_id: &str) -> Vec<SongRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_songs_in_playlist: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_songs(&conn, SongFilter::ByPlaylistId(playlist_id.to_string()))
            .unwrap_or_else(|e| {
                warn!("query songs in playlist failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_song(r))
            .collect()
    }

    pub fn get_liked_song_ids(&self) -> Vec<String> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_liked_song_ids: lock poisoned: {e}");
                return Vec::new();
            }
        };
        let id = match conn
            .query_row(
                "SELECT id FROM playlists WHERE is_system = 1 AND name = ?1",
                params![LIKED_SONGS_NAME],
                |r| r.get::<_, String>(0),
            )
            .optional()
        {
            Ok(Some(id)) => id,
            _ => return Vec::new(),
        };
        let mut stmt = match conn
            .prepare("SELECT song_id FROM playlist_songs WHERE playlist_id = ?1 ORDER BY position")
        {
            Ok(s) => s,
            Err(e) => {
                warn!("prepare liked ids: {e}");
                return Vec::new();
            }
        };
        let rows = match stmt.query_map(params![id], |r| r.get::<_, String>(0)) {
            Ok(r) => r,
            Err(e) => {
                warn!("query liked ids: {e}");
                return Vec::new();
            }
        };
        rows.filter_map(|r| r.ok()).collect()
    }

    pub fn create_playlist(&self, name: &str) -> Result<String, String> {
        let trimmed = name.trim();
        if trimmed.is_empty() {
            return Err("playlist name cannot be empty".into());
        }
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let id = Uuid::new_v4().to_string();
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        conn.execute(
            "INSERT INTO playlists (id, name, is_system, created_at) VALUES (?1, ?2, 0, ?3)",
            params![id, trimmed, now],
        )
        .map_err(|e| format!("insert playlist: {e}"))?;
        if let Err(e) = backup_user_playlists(&conn, &self.playlist_backup_path) {
            warn!("backup playlists after create failed: {e}");
        }
        Ok(id)
    }

    pub fn delete_playlist(&self, id: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let is_system: Option<i64> = conn
            .query_row(
                "SELECT is_system FROM playlists WHERE id = ?1",
                params![id],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| format!("lookup playlist: {e}"))?;
        match is_system {
            None => Err("playlist not found".into()),
            Some(1) => Err("cannot delete a system playlist".into()),
            Some(_) => {
                conn.execute("DELETE FROM playlists WHERE id = ?1", params![id])
                    .map_err(|e| format!("delete: {e}"))?;
                if let Err(e) = backup_user_playlists(&conn, &self.playlist_backup_path) {
                    warn!("backup playlists after delete failed: {e}");
                }
                Ok(())
            }
        }
    }

    pub fn add_song_to_playlist(&self, playlist_id: &str, song_id: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let next_pos: i64 = conn
            .query_row(
                "SELECT COALESCE(MAX(position), 0) + 1 FROM playlist_songs WHERE playlist_id = ?1",
                params![playlist_id],
                |r| r.get(0),
            )
            .map_err(|e| format!("next position: {e}"))?;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);
        conn.execute(
            "INSERT OR IGNORE INTO playlist_songs (playlist_id, song_id, position, added_at) \
             VALUES (?1, ?2, ?3, ?4)",
            params![playlist_id, song_id, next_pos, now],
        )
        .map_err(|e| format!("insert playlist_song: {e}"))?;
        match playlist_is_user(&conn, playlist_id) {
            Ok(true) => {
                if let Err(e) = backup_user_playlists(&conn, &self.playlist_backup_path) {
                    warn!("backup playlists after add song failed: {e}");
                }
            }
            Ok(false) => {}
            Err(e) => warn!("lookup playlist before add-song backup failed: {e}"),
        }
        Ok(())
    }

    pub fn remove_song_from_playlist(
        &self,
        playlist_id: &str,
        song_id: &str,
    ) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        conn.execute(
            "DELETE FROM playlist_songs WHERE playlist_id = ?1 AND song_id = ?2",
            params![playlist_id, song_id],
        )
        .map_err(|e| format!("delete playlist_song: {e}"))?;
        match playlist_is_user(&conn, playlist_id) {
            Ok(true) => {
                if let Err(e) = backup_user_playlists(&conn, &self.playlist_backup_path) {
                    warn!("backup playlists after remove song failed: {e}");
                }
            }
            Ok(false) => {}
            Err(e) => warn!("lookup playlist before remove-song backup failed: {e}"),
        }
        Ok(())
    }

    pub fn update_artist_image(
        &self,
        artist_id: &str,
        artwork: ArtworkUpdate,
    ) -> Result<ArtistRow, String> {
        let new_path = match &artwork {
            ArtworkUpdate::Replace(source) => {
                Some(self.stage_managed_artwork(source, "artists", artist_id)?)
            }
            _ => None,
        };
        let result = (|| {
            let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
            let old: Option<String> = conn
                .query_row(
                    "SELECT custom_cover_path FROM artists WHERE id = ?1",
                    params![artist_id],
                    |r| r.get(0),
                )
                .optional()
                .map_err(|e| format!("lookup artist: {e}"))?
                .ok_or_else(|| "artist not found".to_string())?;
            let value = match &artwork {
                ArtworkUpdate::Keep => old.clone(),
                ArtworkUpdate::Remove => None,
                ArtworkUpdate::Replace(_) => new_path.clone(),
            };
            conn.execute(
                "UPDATE artists SET custom_cover_path = ?1 WHERE id = ?2",
                params![value, artist_id],
            )
            .map_err(|e| format!("update artist image: {e}"))?;
            drop(conn);
            if !matches!(artwork, ArtworkUpdate::Keep) {
                if let Some(old) = old {
                    if Some(old.clone()) != new_path {
                        remove_stored_file(&self.base_dir, &old);
                    }
                }
            }
            self.get_artist_by_id(artist_id)
                .ok_or_else(|| "updated artist not found".into())
        })();
        if result.is_err() {
            if let Some(path) = new_path {
                remove_stored_file(&self.base_dir, &path);
            }
        }
        result
    }

    pub fn update_playlist_metadata(
        &self,
        playlist_id: &str,
        name: &str,
        visual: PlaylistVisualUpdate,
    ) -> Result<PlaylistRow, String> {
        let name = required_text(name, "playlist name")?;
        let new_image = match &visual {
            PlaylistVisualUpdate::Image(source) => {
                Some(self.stage_managed_artwork(source, "playlists", playlist_id)?)
            }
            _ => None,
        };
        let result = (|| {
            let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
            let (is_system, old_icon, old_image): (i64, Option<String>, Option<String>) = conn
                .query_row(
                    "SELECT is_system, icon_key, image_path FROM playlists WHERE id = ?1",
                    params![playlist_id],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )
                .optional()
                .map_err(|e| format!("lookup playlist: {e}"))?
                .ok_or_else(|| "playlist not found".to_string())?;
            if is_system != 0 {
                return Err("system playlists cannot be edited".into());
            }
            let (icon, image) = match &visual {
                PlaylistVisualUpdate::Keep => (old_icon, old_image.clone()),
                PlaylistVisualUpdate::Initials => (None, None),
                PlaylistVisualUpdate::Icon(key) => {
                    if !valid_playlist_icon(key) {
                        return Err("invalid playlist icon".into());
                    }
                    (Some(key.clone()), None)
                }
                PlaylistVisualUpdate::Image(_) => (None, new_image.clone()),
            };
            conn.execute(
                "UPDATE playlists SET name = ?1, icon_key = ?2, image_path = ?3 WHERE id = ?4",
                params![name, icon, image, playlist_id],
            )
            .map_err(|e| format!("update playlist: {e}"))?;
            if let Err(e) = backup_user_playlists(&conn, &self.playlist_backup_path) {
                warn!("backup after playlist update failed: {e}");
            }
            drop(conn);
            if !matches!(visual, PlaylistVisualUpdate::Keep) {
                if let Some(old) = old_image {
                    if Some(old.clone()) != new_image {
                        remove_stored_file(&self.base_dir, &old);
                    }
                }
            }
            self.get_playlists_paginated(0, self.get_total_playlists())
                .into_iter()
                .find(|p| p.id == playlist_id)
                .ok_or_else(|| "updated playlist not found".into())
        })();
        if result.is_err() {
            if let Some(path) = new_image {
                remove_stored_file(&self.base_dir, &path);
            }
        }
        result
    }

    fn stage_managed_artwork(
        &self,
        source: &str,
        category: &str,
        owner_id: &str,
    ) -> Result<String, String> {
        let source = Path::new(source);
        let bytes = fs::read(source).map_err(|e| format!("read artwork: {e}"))?;
        let ext = detect_image_extension(&bytes)
            .ok_or_else(|| "artwork must be a valid JPEG, PNG, or WebP image".to_string())?;
        let dir = self.covers_dir.join(category);
        fs::create_dir_all(&dir).map_err(|e| format!("create artwork dir: {e}"))?;
        let destination = dir.join(format!("{owner_id}-{}.{}", Uuid::new_v4(), ext));
        fs::write(&destination, bytes).map_err(|e| format!("write artwork: {e}"))?;
        Ok(self.to_rel(&destination))
    }

    pub fn restore_user_playlists_from_backup(&self) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        restore_user_playlists_from_backup(&conn, &self.playlist_backup_path)
    }

    pub fn get_liked_songs_playlist_id(&self) -> Option<String> {
        let conn = self.conn.lock().ok()?;
        conn.query_row(
            "SELECT id FROM playlists WHERE is_system = 1 AND name = ?1",
            params![LIKED_SONGS_NAME],
            |r| r.get::<_, String>(0),
        )
        .optional()
        .ok()
        .flatten()
    }

    pub fn search_songs(&self, query: &str, limit: u32) -> Vec<SongRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("search_songs: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_songs(
            &conn,
            SongFilter::Search {
                query: query.to_string(),
                limit,
            },
        )
        .unwrap_or_else(|e| {
            warn!("search songs failed: {e}");
            Vec::new()
        })
        .into_iter()
        .map(|r| self.abs_song(r))
        .collect()
    }

    pub fn search_albums(&self, query: &str, limit: u32) -> Vec<AlbumRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("search_albums: lock poisoned: {e}");
                return Vec::new();
            }
        };
        search_albums(&conn, query, limit)
            .unwrap_or_else(|e| {
                warn!("search albums failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_album(r))
            .collect()
    }

    pub fn get_total_artists(&self) -> u32 {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_total_artists: lock poisoned: {e}");
                return 0;
            }
        };
        conn.query_row("SELECT COUNT(*) FROM artists", [], |r| r.get::<_, i64>(0))
            .map(|n| n as u32)
            .unwrap_or(0)
    }

    pub fn get_artists_paginated(&self, offset: u32, limit: u32) -> Vec<ArtistRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_artists_paginated: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_artists(&conn, ArtistFilter::Page { offset, limit })
            .unwrap_or_else(|e| {
                warn!("query artists failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_artist(r))
            .collect()
    }

    pub fn search_artists(&self, query: &str, limit: u32) -> Vec<ArtistRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("search_artists: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_artists(
            &conn,
            ArtistFilter::Search {
                query: query.to_string(),
                limit,
            },
        )
        .unwrap_or_else(|e| {
            warn!("search artists failed: {e}");
            Vec::new()
        })
        .into_iter()
        .map(|r| self.abs_artist(r))
        .collect()
    }

    pub fn get_artist_by_id(&self, id: &str) -> Option<ArtistRow> {
        let conn = self.conn.lock().ok()?;
        query_artists(&conn, ArtistFilter::ById(id.to_string()))
            .ok()
            .and_then(|mut v| v.pop())
            .map(|r| self.abs_artist(r))
    }

    pub fn get_albums_by_artist_id(&self, artist_id: &str) -> Vec<AlbumRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_albums_by_artist_id: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_albums_by_artist(&conn, artist_id, false)
            .unwrap_or_else(|e| {
                warn!("albums by artist failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_album(r))
            .collect()
    }

    pub fn get_albums_artist_featured_on(&self, artist_id: &str) -> Vec<AlbumRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_albums_artist_featured_on: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_albums_by_artist(&conn, artist_id, true)
            .unwrap_or_else(|e| {
                warn!("albums featured on failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_album(r))
            .collect()
    }

    pub fn get_songs_artist_featured_on(&self, artist_id: &str) -> Vec<SongRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_songs_artist_featured_on: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_songs(&conn, SongFilter::FeaturedByArtistId(artist_id.to_string()))
            .unwrap_or_else(|e| {
                warn!("songs featured on failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_song(r))
            .collect()
    }

    pub fn search_playlists(&self, query: &str, limit: u32) -> Vec<PlaylistRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("search_playlists: lock poisoned: {e}");
                return Vec::new();
            }
        };
        search_playlists(&conn, query, limit)
            .unwrap_or_else(|e| {
                warn!("search playlists failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_playlist(r))
            .collect()
    }

    /// create a new artist row with the same name as the album's current
    /// album-artist and reassign the album (plus its songs' primary artist
    /// entries) to that new row. featured-artist entries on those songs are
    /// intentionally left pointing at the old row.
    pub fn split_album_to_new_artist(&self, album_id: &str) -> Result<String, String> {
        let mut conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let tx = conn.transaction().map_err(|e| format!("tx: {e}"))?;

        let (old_artist_id, name): (String, String) = tx
            .query_row(
                "SELECT a.id, a.name FROM artists a \
                 JOIN albums al ON al.artist_id = a.id \
                 WHERE al.id = ?1",
                params![album_id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .map_err(|e| format!("find album artist: {e}"))?;

        let new_id = Uuid::new_v4().to_string();
        tx.execute(
            "INSERT INTO artists (id, name) VALUES (?1, ?2)",
            params![new_id, name],
        )
        .map_err(|e| format!("insert new artist: {e}"))?;

        tx.execute(
            "UPDATE albums SET artist_id = ?1 WHERE id = ?2",
            params![new_id, album_id],
        )
        .map_err(|e| format!("update album: {e}"))?;
        tx.execute(
            "DELETE FROM album_artists WHERE album_id = ?1",
            params![album_id],
        )
        .map_err(|e| format!("clear album artists: {e}"))?;
        tx.execute(
            "INSERT INTO album_artists (album_id, artist_id, position) VALUES (?1, ?2, 0)",
            params![album_id, new_id],
        )
        .map_err(|e| format!("insert album artist: {e}"))?;
        tx.execute(
            "UPDATE albums SET artist_key = ?1 WHERE id = ?2",
            params![new_id, album_id],
        )
        .map_err(|e| format!("update album key: {e}"))?;

        tx.execute(
            "UPDATE song_artists SET artist_id = ?1 \
             WHERE artist_id = ?2 \
             AND is_featured = 0 \
             AND song_id IN (SELECT id FROM songs WHERE album_id = ?3)",
            params![new_id, old_artist_id, album_id],
        )
        .map_err(|e| format!("update song_artists: {e}"))?;

        tx.commit().map_err(|e| format!("commit: {e}"))?;
        Ok(new_id)
    }

    /// remove a single song. `song_artists`, `playlist_songs`, and
    /// `recently_played` rows cascade; `playback_state.song_id` is nulled by
    /// the fk. if this was the last song in its album, the album row and its
    /// cover file are removed too.
    pub fn delete_song(&self, song_id: &str) -> Result<(), String> {
        let mut conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let tx = conn.transaction().map_err(|e| format!("tx: {e}"))?;
        let album_id: Option<String> = tx
            .query_row(
                "SELECT album_id FROM songs WHERE id = ?1",
                params![song_id],
                |r| r.get::<_, Option<String>>(0),
            )
            .optional()
            .map_err(|e| format!("lookup song: {e}"))?
            .flatten();
        let deleted = tx
            .execute("DELETE FROM songs WHERE id = ?1", params![song_id])
            .map_err(|e| format!("delete song: {e}"))?;
        if deleted == 0 {
            return Err("song not found".into());
        }
        if let Some(aid) = album_id {
            cleanup_orphan_album(&tx, &self.base_dir, &aid)?;
        }
        tx.commit().map_err(|e| format!("commit: {e}"))?;
        Ok(())
    }

    /// remove an entire album and every song it contains. cover file is
    /// unlinked from disk.
    pub fn delete_album(&self, album_id: &str) -> Result<(), String> {
        let mut conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let tx = conn.transaction().map_err(|e| format!("tx: {e}"))?;
        let exists: Option<i64> = tx
            .query_row(
                "SELECT 1 FROM albums WHERE id = ?1",
                params![album_id],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| format!("lookup album: {e}"))?;
        if exists.is_none() {
            return Err("album not found".into());
        }
        tx.execute("DELETE FROM songs WHERE album_id = ?1", params![album_id])
            .map_err(|e| format!("delete album songs: {e}"))?;
        remove_album_row(&tx, &self.base_dir, album_id)?;
        tx.commit().map_err(|e| format!("commit: {e}"))?;
        Ok(())
    }

    /// remove every song whose `file_path` lives under `path`, plus the
    /// `scan_paths` entry itself. returns the number of songs removed.
    pub fn delete_scan_path(&self, path: &str) -> Result<u32, String> {
        let mut conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let tx = conn.transaction().map_err(|e| format!("tx: {e}"))?;
        // `file_path` and `scan_paths.path` are stored relative to `base_dir`;
        // the incoming `path` is the absolute dir from the picker, so match
        // against its relativized form.
        let path = self.to_rel(Path::new(path));
        let path = path.as_str();
        let prefix = format!("{}/%", path.trim_end_matches('/'));
        let affected_albums: Vec<String> = {
            let mut stmt = tx
                .prepare(
                    "SELECT DISTINCT album_id FROM songs \
                     WHERE (file_path LIKE ?1 OR file_path = ?2) AND album_id IS NOT NULL",
                )
                .map_err(|e| format!("prepare album lookup: {e}"))?;
            let rows = stmt
                .query_map(params![prefix, path], |r| r.get::<_, String>(0))
                .map_err(|e| format!("query albums: {e}"))?;
            rows.filter_map(|r| r.ok()).collect()
        };
        let removed = tx
            .execute(
                "DELETE FROM songs WHERE file_path LIKE ?1 OR file_path = ?2",
                params![prefix, path],
            )
            .map_err(|e| format!("delete songs by path: {e}"))?;
        for aid in &affected_albums {
            cleanup_orphan_album(&tx, &self.base_dir, aid)?;
        }
        tx.execute("DELETE FROM scan_paths WHERE path = ?1", params![path])
            .map_err(|e| format!("delete scan path: {e}"))?;
        tx.commit().map_err(|e| format!("commit: {e}"))?;
        Ok(removed as u32)
    }

    pub fn add_scan_path(&self, path: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let now = now_secs();
        let rel = self.to_rel(Path::new(path));
        conn.execute(
            "INSERT OR IGNORE INTO scan_paths (path, added_at) VALUES (?1, ?2)",
            params![rel, now],
        )
        .map_err(|e| format!("insert scan path: {e}"))?;
        Ok(())
    }

    pub fn get_scan_paths(&self) -> Vec<String> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_scan_paths: lock poisoned: {e}");
                return Vec::new();
            }
        };
        let mut stmt = match conn.prepare("SELECT path FROM scan_paths ORDER BY added_at") {
            Ok(s) => s,
            Err(e) => {
                warn!("prepare scan paths: {e}");
                return Vec::new();
            }
        };
        let rows = match stmt.query_map([], |r| r.get::<_, String>(0)) {
            Ok(r) => r,
            Err(e) => {
                warn!("query scan paths: {e}");
                return Vec::new();
            }
        };
        rows.filter_map(|r| r.ok())
            .map(|p| self.to_abs(&p))
            .collect()
    }

    pub fn record_play(&self, song_id: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let now = now_secs();
        conn.execute(
            "INSERT INTO recently_played (song_id, played_at) VALUES (?1, ?2) \
             ON CONFLICT(song_id) DO UPDATE SET played_at = excluded.played_at",
            params![song_id, now],
        )
        .map_err(|e| format!("record play: {e}"))?;
        Ok(())
    }

    pub fn get_recently_played(&self, limit: u32) -> Vec<SongRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_recently_played: lock poisoned: {e}");
                return Vec::new();
            }
        };
        query_songs(&conn, SongFilter::RecentlyPlayed { limit })
            .unwrap_or_else(|e| {
                warn!("query recently played failed: {e}");
                Vec::new()
            })
            .into_iter()
            .map(|r| self.abs_song(r))
            .collect()
    }

    pub fn save_playback_state(
        &self,
        song_id: Option<&str>,
        position_ms: i64,
        loop_one: bool,
    ) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let now = now_secs();
        let loop_flag: i64 = if loop_one { 1 } else { 0 };
        conn.execute(
            "INSERT INTO playback_state (id, song_id, position_ms, loop_one, updated_at) \
             VALUES (1, ?1, ?2, ?3, ?4) \
             ON CONFLICT(id) DO UPDATE SET \
                 song_id = excluded.song_id, \
                 position_ms = excluded.position_ms, \
                 loop_one = excluded.loop_one, \
                 updated_at = excluded.updated_at",
            params![song_id, position_ms, loop_flag, now],
        )
        .map_err(|e| format!("save playback state: {e}"))?;
        Ok(())
    }

    pub fn load_playback_state(&self) -> Option<PlaybackStateRow> {
        let conn = self.conn.lock().ok()?;
        let (song_id, position_ms, loop_flag): (Option<String>, i64, i64) = conn
            .query_row(
                "SELECT song_id, position_ms, loop_one FROM playback_state WHERE id = 1",
                [],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .optional()
            .ok()
            .flatten()?;
        let song_id = song_id?;
        let mut rows = query_songs(&conn, SongFilter::ById(song_id)).ok()?;
        let song = self.abs_song(rows.pop()?);
        Some(PlaybackStateRow {
            song,
            position_ms,
            loop_one: loop_flag != 0,
        })
    }

    pub fn pin_item(&self, item_id: &str, kind: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let now = now_secs();
        let next_pos: i64 = conn
            .query_row(
                "SELECT COALESCE(MAX(position), 0) + 1 FROM pinned_items",
                [],
                |r| r.get(0),
            )
            .map_err(|e| format!("next pin position: {e}"))?;
        conn.execute(
            "INSERT OR REPLACE INTO pinned_items (item_id, kind, position, pinned_at) \
             VALUES (?1, ?2, ?3, ?4)",
            params![item_id, kind, next_pos, now],
        )
        .map_err(|e| format!("pin item: {e}"))?;
        Ok(())
    }

    pub fn unpin_item(&self, item_id: &str, kind: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        conn.execute(
            "DELETE FROM pinned_items WHERE item_id = ?1 AND kind = ?2",
            params![item_id, kind],
        )
        .map_err(|e| format!("unpin item: {e}"))?;
        Ok(())
    }

    pub fn get_pinned_items(&self) -> Vec<PinnedItemRow> {
        let conn = match self.conn.lock() {
            Ok(c) => c,
            Err(e) => {
                warn!("get_pinned_items: lock poisoned: {e}");
                return Vec::new();
            }
        };
        let mut stmt = match conn.prepare(
            "SELECT item_id, kind, position FROM pinned_items ORDER BY position, pinned_at DESC",
        ) {
            Ok(s) => s,
            Err(e) => {
                warn!("prepare pinned items: {e}");
                return Vec::new();
            }
        };
        let rows = match stmt.query_map([], |r| {
            Ok(PinnedItemRow {
                item_id: r.get(0)?,
                kind: r.get(1)?,
                position: r.get(2)?,
            })
        }) {
            Ok(r) => r,
            Err(e) => {
                warn!("query pinned items: {e}");
                return Vec::new();
            }
        };
        rows.filter_map(|r| r.ok()).collect()
    }

    pub fn move_pinned_item(
        &self,
        item_id: &str,
        kind: &str,
        new_index: usize,
    ) -> Result<(), String> {
        let mut conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let tx = conn.transaction().map_err(|e| format!("tx: {e}"))?;

        let mut items: Vec<(String, String, i64)> = {
            let mut stmt = tx
                .prepare("SELECT item_id, kind, position FROM pinned_items ORDER BY position, pinned_at DESC")
                .map_err(|e| format!("prepare: {e}"))?;
            let rows = stmt
                .query_map([], |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, String>(1)?,
                        r.get::<_, i64>(2)?,
                    ))
                })
                .map_err(|e| format!("query: {e}"))?;
            rows.filter_map(|r| r.ok()).collect()
        };

        let current_pos = items
            .iter()
            .position(|(id, k, _)| id == item_id && k == kind)
            .ok_or_else(|| "pinned item not found".to_string())?;
        if new_index >= items.len() {
            return Err("new index out of bounds".to_string());
        }

        let item = items.remove(current_pos);
        items.insert(new_index, item);

        for (i, (id, k, _)) in items.iter().enumerate() {
            tx.execute(
                "UPDATE pinned_items SET position = ?1 WHERE item_id = ?2 AND kind = ?3",
                params![i as i64, id, k],
            )
            .map_err(|e| format!("update position: {e}"))?;
        }

        tx.commit().map_err(|e| format!("commit: {e}"))?;
        Ok(())
    }

    pub fn reset_library(&self) -> Result<(), String> {
        let mut conn = self.conn.lock().map_err(|e| format!("lock: {e}"))?;
        let tx = conn.transaction().map_err(|e| format!("tx: {e}"))?;
        tx.execute("DELETE FROM songs", [])
            .map_err(|e| format!("delete songs: {e}"))?;
        tx.execute("DELETE FROM albums", [])
            .map_err(|e| format!("delete albums: {e}"))?;
        tx.execute("DELETE FROM artists", [])
            .map_err(|e| format!("delete artists: {e}"))?;
        tx.execute("DELETE FROM playlists", [])
            .map_err(|e| format!("delete playlists: {e}"))?;
        tx.execute("DELETE FROM scan_paths", [])
            .map_err(|e| format!("delete scan_paths: {e}"))?;
        tx.execute("DELETE FROM playback_state", [])
            .map_err(|e| format!("delete playback_state: {e}"))?;
        tx.execute("DELETE FROM pinned_items", [])
            .map_err(|e| format!("delete pinned_items: {e}"))?;
        ensure_liked_songs_playlist(&tx).map_err(|e| format!("reseed liked songs: {e}"))?;
        tx.commit().map_err(|e| format!("commit: {e}"))?;
        // preserve user playlist artwork because playlists are restored from
        // their backup after the next scan; clear scanned and artist artwork.
        if let Ok(entries) = fs::read_dir(&self.covers_dir) {
            for entry in entries.flatten() {
                if entry.file_name() == "playlists" {
                    continue;
                }
                let path = entry.path();
                if path.is_dir() {
                    let _ = fs::remove_dir_all(path);
                } else {
                    let _ = fs::remove_file(path);
                }
            }
        }
        Ok(())
    }
}

/// drop an album row if it no longer has any songs. also unlinks the cover
/// file from disk. called inside `delete_song` / `delete_album` /
/// `delete_scan_path` transactions.
fn cleanup_orphan_album(
    tx: &rusqlite::Transaction,
    base_dir: &Path,
    album_id: &str,
) -> Result<(), String> {
    let remaining: i64 = tx
        .query_row(
            "SELECT COUNT(*) FROM songs WHERE album_id = ?1",
            params![album_id],
            |r| r.get(0),
        )
        .map_err(|e| format!("count album songs: {e}"))?;
    if remaining > 0 {
        return Ok(());
    }
    remove_album_row(tx, base_dir, album_id)
}

fn remove_album_row(
    tx: &rusqlite::Transaction,
    base_dir: &Path,
    album_id: &str,
) -> Result<(), String> {
    let cover: Option<String> = tx
        .query_row(
            "SELECT cover_path FROM albums WHERE id = ?1",
            params![album_id],
            |r| r.get::<_, Option<String>>(0),
        )
        .optional()
        .map_err(|e| format!("lookup cover path: {e}"))?
        .flatten();
    tx.execute("DELETE FROM albums WHERE id = ?1", params![album_id])
        .map_err(|e| format!("delete album: {e}"))?;
    if let Some(path) = cover {
        // stored relative; resolve against the current base before unlinking.
        let path = absolutize(&path, base_dir);
        if let Err(e) = fs::remove_file(&path) {
            if e.kind() != std::io::ErrorKind::NotFound {
                warn!("failed to remove cover {path}: {e}");
            }
        }
    }
    Ok(())
}

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

enum SongFilter {
    Page { offset: u32, limit: u32 },
    ById(String),
    ByAlbumId(String),
    ByPlaylistId(String),
    FeaturedByArtistId(String),
    Search { query: String, limit: u32 },
    RecentlyPlayed { limit: u32 },
}

const SONG_QUERY_BASE: &str = "\
    SELECT s.id, s.title, s.track_num, s.disc_num, s.file_path, \
           al.title, COALESCE(s.cover_path, al.cover_path), pa.name, \
           (SELECT GROUP_CONCAT(a.name, ?1) FROM song_artists sa \
            JOIN artists a ON sa.artist_id = a.id \
            WHERE sa.song_id = s.id AND sa.is_featured = 1 \
            ORDER BY sa.position), \
           al.id, \
           (SELECT GROUP_CONCAT(aa_name.name, ?1) FROM album_artists aa \
            JOIN artists aa_name ON aa_name.id = aa.artist_id \
            WHERE aa.album_id = al.id ORDER BY aa.position), \
           s.cover_path \
    FROM songs s \
    LEFT JOIN albums al ON s.album_id = al.id \
    LEFT JOIN song_artists pasa ON pasa.song_id = s.id AND pasa.is_featured = 0 \
    LEFT JOIN artists pa ON pasa.artist_id = pa.id";

fn query_songs(conn: &Connection, filter: SongFilter) -> rusqlite::Result<Vec<SongRow>> {
    match filter {
        SongFilter::Page { offset, limit } => query_song_page(conn, offset, limit),
        SongFilter::ById(id) => query_songs_with_value(conn, " WHERE s.id = ?2", id),
        SongFilter::ByAlbumId(id) => query_songs_with_value(
            conn,
            " WHERE s.album_id = ?2 ORDER BY s.disc_num, s.track_num, s.title",
            id,
        ),
        SongFilter::ByPlaylistId(id) => query_songs_with_value(
            conn,
            " JOIN playlist_songs ps ON ps.song_id = s.id WHERE ps.playlist_id = ?2 ORDER BY ps.position",
            id,
        ),
        SongFilter::FeaturedByArtistId(id) => query_songs_with_value(
            conn,
            " JOIN song_artists fsa ON fsa.song_id = s.id WHERE fsa.artist_id = ?2 AND fsa.is_featured = 1 ORDER BY s.title COLLATE NOCASE",
            id,
        ),
        SongFilter::Search { query, limit } => query_song_search(conn, &query, limit),
        SongFilter::RecentlyPlayed { limit } => query_recent_songs(conn, limit),
    }
}

fn query_song_page(conn: &Connection, offset: u32, limit: u32) -> rusqlite::Result<Vec<SongRow>> {
    let sql = format!(
        "{SONG_QUERY_BASE} ORDER BY s.added_at DESC, s.rowid DESC, s.title COLLATE NOCASE LIMIT ?2 OFFSET ?3"
    );
    let mut statement = conn.prepare(&sql)?;
    let rows = statement.query_map(
        params![UNIT_SEP.to_string(), limit as i64, offset as i64],
        map_song_row,
    )?;
    rows.collect()
}

fn query_songs_with_value(
    conn: &Connection,
    suffix: &str,
    value: String,
) -> rusqlite::Result<Vec<SongRow>> {
    let mut statement = conn.prepare(&format!("{SONG_QUERY_BASE}{suffix}"))?;
    let rows = statement.query_map(params![UNIT_SEP.to_string(), value], map_song_row)?;
    rows.collect()
}

fn query_song_search(conn: &Connection, query: &str, limit: u32) -> rusqlite::Result<Vec<SongRow>> {
    let suffix = " WHERE s.title LIKE ?2 ESCAPE '\\' OR pa.name LIKE ?2 ESCAPE '\\' \
                  OR al.title LIKE ?2 ESCAPE '\\' ORDER BY s.title COLLATE NOCASE LIMIT ?3";
    let sql = format!("{SONG_QUERY_BASE}{suffix}");
    let pattern = format!("%{}%", like_escape(query));
    let mut statement = conn.prepare(&sql)?;
    let rows = statement.query_map(
        params![UNIT_SEP.to_string(), pattern, limit as i64],
        map_song_row,
    )?;
    rows.collect()
}

fn query_recent_songs(conn: &Connection, limit: u32) -> rusqlite::Result<Vec<SongRow>> {
    let suffix = " JOIN recently_played rp ON rp.song_id = s.id \
                  ORDER BY rp.played_at DESC LIMIT ?2";
    let mut statement = conn.prepare(&format!("{SONG_QUERY_BASE}{suffix}"))?;
    let rows = statement.query_map(params![UNIT_SEP.to_string(), limit as i64], map_song_row)?;
    rows.collect()
}

fn query_playlists(
    conn: &Connection,
    offset: u32,
    limit: u32,
) -> rusqlite::Result<Vec<PlaylistRow>> {
    let mut stmt = conn.prepare(
        "SELECT p.id, p.name, p.is_system, \
                (SELECT COUNT(*) FROM playlist_songs ps WHERE ps.playlist_id = p.id) AS song_count, \
                p.icon_key, p.image_path \
         FROM playlists p \
         ORDER BY p.is_system DESC, p.created_at DESC \
         LIMIT ?1 OFFSET ?2",
    )?;
    let rows = stmt.query_map(params![limit as i64, offset as i64], |r| {
        Ok(PlaylistRow {
            id: r.get(0)?,
            name: r.get(1)?,
            is_system: r.get::<_, i64>(2)? != 0,
            song_count: r.get(3)?,
            icon_key: r.get(4)?,
            image_path: r.get(5)?,
        })
    })?;
    rows.collect()
}

fn search_albums(conn: &Connection, query: &str, limit: u32) -> rusqlite::Result<Vec<AlbumRow>> {
    let pattern = format!("%{}%", like_escape(query));
    let mut stmt = conn.prepare(
        "SELECT al.id, al.title, COALESCE(a.name, ?1), al.cover_path, \
                (SELECT COUNT(*) FROM songs s WHERE s.album_id = al.id) AS song_count \
                , (SELECT GROUP_CONCAT(an.name, ?4) FROM album_artists aa \
                   JOIN artists an ON an.id = aa.artist_id \
                   WHERE aa.album_id = al.id ORDER BY aa.position) \
         FROM albums al \
         LEFT JOIN artists a ON al.artist_id = a.id \
         WHERE al.title LIKE ?2 ESCAPE '\\' \
            OR EXISTS (SELECT 1 FROM album_artists saa JOIN artists san ON san.id = saa.artist_id WHERE saa.album_id = al.id AND san.name LIKE ?2 ESCAPE '\\') \
         ORDER BY al.title COLLATE NOCASE \
         LIMIT ?3",
    )?;
    let rows = stmt.query_map(
        params![MISSING_ARTIST, pattern, limit as i64, UNIT_SEP.to_string()],
        |r| {
            Ok(AlbumRow {
                id: r.get(0)?,
                title: r.get(1)?,
                artist: r.get(2)?,
                cover_path: r.get(3)?,
                song_count: r.get(4)?,
                artists: split_names(r.get(5)?),
            })
        },
    )?;
    rows.collect()
}

fn search_playlists(
    conn: &Connection,
    query: &str,
    limit: u32,
) -> rusqlite::Result<Vec<PlaylistRow>> {
    let pattern = format!("%{}%", like_escape(query));
    let mut stmt = conn.prepare(
        "SELECT p.id, p.name, p.is_system, \
                (SELECT COUNT(*) FROM playlist_songs ps WHERE ps.playlist_id = p.id) AS song_count, \
                p.icon_key, p.image_path \
         FROM playlists p \
         WHERE p.name LIKE ?1 ESCAPE '\\' \
         ORDER BY p.is_system DESC, p.name COLLATE NOCASE \
         LIMIT ?2",
    )?;
    let rows = stmt.query_map(params![pattern, limit as i64], |r| {
        Ok(PlaylistRow {
            id: r.get(0)?,
            name: r.get(1)?,
            is_system: r.get::<_, i64>(2)? != 0,
            song_count: r.get(3)?,
            icon_key: r.get(4)?,
            image_path: r.get(5)?,
        })
    })?;
    rows.collect()
}

fn like_escape(q: &str) -> String {
    q.replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

fn backup_user_playlists(conn: &Connection, path: &Path) -> Result<(), String> {
    let mut playlists_stmt = conn
        .prepare(
            "SELECT id, name, icon_key, image_path FROM playlists \
             WHERE is_system = 0 \
             ORDER BY created_at DESC, name COLLATE NOCASE",
        )
        .map_err(|e| format!("prepare playlists backup: {e}"))?;
    let playlists = playlists_stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, Option<String>>(2)?,
                r.get::<_, Option<String>>(3)?,
            ))
        })
        .map_err(|e| format!("query playlists backup: {e}"))?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| format!("collect playlists backup: {e}"))?;

    let mut backup = PlaylistBackup {
        playlists: Vec::new(),
    };
    for (playlist_id, name, icon_key, image_path) in playlists {
        let mut songs_stmt = conn
            .prepare(
                "SELECT s.title, COALESCE(al.title, ?1) \
                 FROM playlist_songs ps \
                 JOIN songs s ON s.id = ps.song_id \
                 LEFT JOIN albums al ON s.album_id = al.id \
                 WHERE ps.playlist_id = ?2 \
                 ORDER BY ps.position",
            )
            .map_err(|e| format!("prepare playlist songs backup: {e}"))?;
        let songs = songs_stmt
            .query_map(params![MISSING_ALBUM, playlist_id], |r| {
                Ok(PlaylistBackupSong {
                    title: r.get(0)?,
                    album: r.get(1)?,
                })
            })
            .map_err(|e| format!("query playlist songs backup: {e}"))?
            .collect::<rusqlite::Result<Vec<_>>>()
            .map_err(|e| format!("collect playlist songs backup: {e}"))?;
        backup.playlists.push(PlaylistBackupPlaylist {
            id: playlist_id,
            name,
            icon_key,
            image_path,
            songs,
        });
    }

    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent).map_err(|e| format!("create backup dir: {e}"))?;
        }
    }
    let json = serde_json::to_string_pretty(&backup).map_err(|e| format!("encode backup: {e}"))?;
    fs::write(path, json).map_err(|e| format!("write backup: {e}"))
}

fn playlist_is_user(conn: &Connection, playlist_id: &str) -> Result<bool, String> {
    conn.query_row(
        "SELECT is_system FROM playlists WHERE id = ?1",
        params![playlist_id],
        |r| r.get::<_, i64>(0),
    )
    .optional()
    .map(|value| value == Some(0))
    .map_err(|e| format!("lookup playlist kind: {e}"))
}

fn restore_user_playlists_from_backup(conn: &Connection, path: &Path) -> Result<(), String> {
    let Some(backup) = read_playlist_backup(path)? else {
        return Ok(());
    };
    let song_index = build_restore_song_index(conn)?;
    let mut totals = (0, 0);
    for playlist in backup.playlists {
        let restored = restore_playlist(conn, playlist, &song_index)?;
        totals.0 += restored.0;
        totals.1 += restored.1;
    }
    debug!(
        "playlist backup restore complete: {} songs restored, {} songs skipped",
        totals.0, totals.1
    );
    Ok(())
}

fn read_playlist_backup(path: &Path) -> Result<Option<PlaylistBackup>, String> {
    if !path.exists() {
        return Ok(None);
    }
    let raw = fs::read_to_string(path).map_err(|error| format!("read backup: {error}"))?;
    let backup = serde_json::from_str::<PlaylistBackup>(&raw)
        .map_err(|error| format!("parse backup: {error}"))?;
    Ok((!backup.playlists.is_empty()).then_some(backup))
}

fn build_restore_song_index(
    conn: &Connection,
) -> Result<std::collections::HashMap<(String, String), String>, String> {
    let mut songs_stmt = conn
        .prepare(
            "SELECT s.id, s.title, COALESCE(al.title, ?1) \
             FROM songs s \
             LEFT JOIN albums al ON s.album_id = al.id \
             ORDER BY s.rowid",
        )
        .map_err(|e| format!("prepare restore song index: {e}"))?;
    let songs = songs_stmt
        .query_map(params![MISSING_ALBUM], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get::<_, String>(2)?,
            ))
        })
        .map_err(|e| format!("query restore song index: {e}"))?
        .collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|e| format!("collect restore song index: {e}"))?;
    let mut song_index = std::collections::HashMap::<(String, String), String>::new();
    for (id, title, album) in songs {
        song_index
            .entry((normalize_match_value(&title), normalize_match_value(&album)))
            .or_insert(id);
    }
    Ok(song_index)
}

fn restore_playlist(
    conn: &Connection,
    playlist: PlaylistBackupPlaylist,
    song_index: &std::collections::HashMap<(String, String), String>,
) -> Result<(usize, usize), String> {
    let name = playlist.name.trim();
    if name.is_empty() || name == LIKED_SONGS_NAME {
        return Ok((0, 0));
    }
    let playlist_id = find_or_create_restored_playlist(conn, &playlist, name)?;
    restore_playlist_songs(conn, &playlist_id, playlist.songs, song_index)
}

fn find_or_create_restored_playlist(
    conn: &Connection,
    playlist: &PlaylistBackupPlaylist,
    name: &str,
) -> Result<String, String> {
    let existing = conn
        .query_row(
            "SELECT id FROM playlists WHERE is_system = 0 AND name = ?1",
            params![name],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| format!("lookup restore playlist: {error}"))?;
    if let Some(id) = existing {
        return Ok(id);
    }
    let id = valid_restored_playlist_id(&playlist.id);
    conn.execute(
        "INSERT INTO playlists (id, name, icon_key, image_path, is_system, created_at) VALUES (?1, ?2, ?3, ?4, 0, ?5)",
        params![id, name, playlist.icon_key, playlist.image_path, now_secs()],
    )
    .map_err(|error| format!("insert restore playlist: {error}"))?;
    Ok(id)
}

fn valid_restored_playlist_id(id: &str) -> String {
    if id.trim().is_empty() {
        Uuid::new_v4().to_string()
    } else {
        id.to_string()
    }
}

fn restore_playlist_songs(
    conn: &Connection,
    playlist_id: &str,
    songs: Vec<PlaylistBackupSong>,
    song_index: &std::collections::HashMap<(String, String), String>,
) -> Result<(usize, usize), String> {
    let mut totals = (0, 0);
    for song in songs {
        let key = (
            normalize_match_value(&song.title),
            normalize_match_value(&song.album),
        );
        let Some(song_id) = song_index.get(&key) else {
            totals.1 += 1;
            continue;
        };
        totals.0 += insert_restored_song(conn, playlist_id, song_id)?;
    }
    Ok(totals)
}

fn insert_restored_song(
    conn: &Connection,
    playlist_id: &str,
    song_id: &str,
) -> Result<usize, String> {
    let next_position = conn
        .query_row(
            "SELECT COALESCE(MAX(position), 0) + 1 FROM playlist_songs WHERE playlist_id = ?1",
            params![playlist_id],
            |row| row.get::<_, i64>(0),
        )
        .map_err(|error| format!("restore next position: {error}"))?;
    conn.execute(
        "INSERT OR IGNORE INTO playlist_songs (playlist_id, song_id, position, added_at) VALUES (?1, ?2, ?3, ?4)",
        params![playlist_id, song_id, next_position, now_secs()],
    )
    .map_err(|error| format!("restore playlist song: {error}"))
}

fn normalize_match_value(value: &str) -> String {
    value
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}

/// make `abs` relative to `base` for storage. stored relative paths always use
/// `/` separators so a library is portable across platforms. if `abs` is not
/// under `base`, it is returned absolute unchanged.
fn relativize(abs: &Path, base: &Path) -> String {
    match abs.strip_prefix(base) {
        Ok(rel) => rel.to_string_lossy().replace('\\', "/"),
        Err(_) => abs.to_string_lossy().to_string(),
    }
}

/// inverse of [`relativize`]. already-absolute stored values pass through; a
/// relative value is joined onto the current `base`.
fn absolutize(stored: &str, base: &Path) -> String {
    let p = Path::new(stored);
    if p.is_absolute() {
        stored.to_string()
    } else {
        base.join(p).to_string_lossy().to_string()
    }
}

fn ensure_liked_songs_playlist(conn: &Connection) -> rusqlite::Result<String> {
    if let Some(id) = conn
        .query_row(
            "SELECT id FROM playlists WHERE is_system = 1 AND name = ?1",
            params![LIKED_SONGS_NAME],
            |r| r.get::<_, String>(0),
        )
        .optional()?
    {
        return Ok(id);
    }
    let id = Uuid::new_v4().to_string();
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    conn.execute(
        "INSERT INTO playlists (id, name, is_system, created_at) VALUES (?1, ?2, 1, ?3)",
        params![id, LIKED_SONGS_NAME, now],
    )?;
    Ok(id)
}

enum ArtistFilter {
    Page { offset: u32, limit: u32 },
    ById(String),
    Search { query: String, limit: u32 },
}

fn query_artists(conn: &Connection, filter: ArtistFilter) -> rusqlite::Result<Vec<ArtistRow>> {
    let base = "\
        SELECT a.id, a.name, \
               COALESCE(a.custom_cover_path, (SELECT al.cover_path FROM albums al \
                JOIN album_artists aa ON aa.album_id = al.id \
                WHERE aa.artist_id = a.id AND al.cover_path IS NOT NULL LIMIT 1)), \
               (SELECT COUNT(*) FROM album_artists WHERE artist_id = a.id) AS album_count, \
               (SELECT COUNT(DISTINCT song_id) FROM song_artists \
                WHERE artist_id = a.id) AS song_count, a.custom_cover_path \
        FROM artists a";

    let map = |row: &rusqlite::Row| -> rusqlite::Result<ArtistRow> {
        Ok(ArtistRow {
            id: row.get(0)?,
            name: row.get(1)?,
            cover_path: row.get(2)?,
            album_count: row.get(3)?,
            song_count: row.get(4)?,
            custom_cover_path: row.get(5)?,
        })
    };

    match filter {
        ArtistFilter::Page { offset, limit } => {
            let sql = format!("{base} ORDER BY a.name COLLATE NOCASE LIMIT ?1 OFFSET ?2");
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![limit as i64, offset as i64], map)?;
            rows.collect()
        }
        ArtistFilter::ById(id) => {
            let sql = format!("{base} WHERE a.id = ?1");
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![id], map)?;
            rows.collect()
        }
        ArtistFilter::Search { query, limit } => {
            let pattern = format!("%{}%", like_escape(&query));
            let sql = format!(
                "{base} WHERE a.name LIKE ?1 ESCAPE '\\' \
                 ORDER BY a.name COLLATE NOCASE LIMIT ?2"
            );
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![pattern, limit as i64], map)?;
            rows.collect()
        }
    }
}

fn query_albums_by_artist(
    conn: &Connection,
    artist_id: &str,
    featured_only: bool,
) -> rusqlite::Result<Vec<AlbumRow>> {
    let sql = if featured_only {
        "SELECT DISTINCT al.id, al.title, COALESCE(a.name, ?1), al.cover_path, \
                (SELECT COUNT(*) FROM songs s2 WHERE s2.album_id = al.id) AS song_count \
                , (SELECT GROUP_CONCAT(an.name, ?3) FROM album_artists aa2 JOIN artists an ON an.id = aa2.artist_id WHERE aa2.album_id = al.id ORDER BY aa2.position) \
         FROM albums al \
         LEFT JOIN artists a ON al.artist_id = a.id \
         JOIN songs s ON s.album_id = al.id \
         JOIN song_artists sa ON sa.song_id = s.id \
         WHERE sa.artist_id = ?2 AND sa.is_featured = 1 \
           AND (al.artist_id IS NULL OR al.artist_id != ?2) \
         ORDER BY al.title COLLATE NOCASE"
    } else {
        "SELECT al.id, al.title, COALESCE(a.name, ?1), al.cover_path, \
                (SELECT COUNT(*) FROM songs s WHERE s.album_id = al.id) AS song_count \
                , (SELECT GROUP_CONCAT(an.name, ?3) FROM album_artists aa2 JOIN artists an ON an.id = aa2.artist_id WHERE aa2.album_id = al.id ORDER BY aa2.position) \
         FROM albums al \
         LEFT JOIN artists a ON al.artist_id = a.id \
         JOIN album_artists own_aa ON own_aa.album_id = al.id \
         WHERE own_aa.artist_id = ?2 \
         ORDER BY al.title COLLATE NOCASE"
    };
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map(
        params![MISSING_ARTIST, artist_id, UNIT_SEP.to_string()],
        |r| {
            Ok(AlbumRow {
                id: r.get(0)?,
                title: r.get(1)?,
                artist: r.get(2)?,
                cover_path: r.get(3)?,
                song_count: r.get(4)?,
                artists: split_names(r.get(5)?),
            })
        },
    )?;
    rows.collect()
}

fn query_albums(conn: &Connection, offset: u32, limit: u32) -> rusqlite::Result<Vec<AlbumRow>> {
    let mut stmt = conn.prepare(
        "SELECT al.id, al.title, COALESCE(a.name, ?1), al.cover_path, \
                (SELECT COUNT(*) FROM songs s WHERE s.album_id = al.id) AS song_count \
                , (SELECT GROUP_CONCAT(an.name, ?4) FROM album_artists aa JOIN artists an ON an.id = aa.artist_id WHERE aa.album_id = al.id ORDER BY aa.position) \
         FROM albums al \
         LEFT JOIN artists a ON al.artist_id = a.id \
         ORDER BY al.title COLLATE NOCASE \
         LIMIT ?2 OFFSET ?3",
    )?;
    let rows = stmt.query_map(
        params![
            MISSING_ARTIST,
            limit as i64,
            offset as i64,
            UNIT_SEP.to_string()
        ],
        |r| {
            Ok(AlbumRow {
                id: r.get(0)?,
                title: r.get(1)?,
                artist: r.get(2)?,
                cover_path: r.get(3)?,
                song_count: r.get(4)?,
                artists: split_names(r.get(5)?),
            })
        },
    )?;
    rows.collect()
}

fn map_song_row(row: &rusqlite::Row) -> rusqlite::Result<SongRow> {
    let features: Option<String> = row.get(8)?;
    let featured_artists = features
        .map(|s| {
            s.split(UNIT_SEP)
                .filter(|p| !p.is_empty())
                .map(|p| p.to_string())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    Ok(SongRow {
        id: row.get(0)?,
        title: row.get(1)?,
        track_num: row.get(2)?,
        disc_num: row.get(3)?,
        file_path: row.get(4)?,
        album: row
            .get::<_, Option<String>>(5)?
            .unwrap_or_else(|| MISSING_ALBUM.to_string()),
        album_id: row.get::<_, Option<String>>(9)?.unwrap_or_default(),
        album_artists: split_names(row.get(10)?),
        cover_path: row.get(6)?,
        song_cover_path: row.get(11)?,
        primary_artist: row
            .get::<_, Option<String>>(7)?
            .unwrap_or_else(|| MISSING_ARTIST.to_string()),
        featured_artists,
    })
}

fn split_names(value: Option<String>) -> Vec<String> {
    value
        .map(|s| {
            s.split(UNIT_SEP)
                .filter(|p| !p.is_empty())
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

#[allow(clippy::too_many_arguments)]
fn insert_song(
    conn: &Connection,
    covers_dir: &Path,
    base_dir: &Path,
    file_path: &Path,
    meta: RawMetadata,
    leading_artist: &str,
    feature_artists: &[String],
    album_artists: &[String],
) -> rusqlite::Result<()> {
    let title = meta.title.unwrap_or_else(|| MISSING_TITLE.to_string());
    let album_name = meta.album.unwrap_or_else(|| MISSING_ALBUM.to_string());
    let track_num = meta.track_num.unwrap_or(1);
    let disc_num = meta.disc_num.unwrap_or(1);
    let file_path_str = relativize(file_path, base_dir);

    let existing: Option<String> = conn
        .query_row(
            "SELECT id FROM songs WHERE file_path = ?1",
            params![file_path_str],
            |r| r.get(0),
        )
        .optional()?;
    if existing.is_some() {
        debug!("skip (already indexed): {file_path_str}");
        return Ok(());
    }

    let leading_artist_id = ensure_artist(conn, leading_artist)?;
    let feature_artist_ids: Vec<String> = feature_artists
        .iter()
        .map(|name| ensure_artist(conn, name))
        .collect::<rusqlite::Result<_>>()?;

    let normalized_album_artists = normalize_names(album_artists.to_vec());
    let normalized_album_artists = if normalized_album_artists.is_empty() {
        vec![leading_artist.to_string()]
    } else {
        normalized_album_artists
    };
    let album_id = ensure_multi_artist_album(conn, &album_name, &normalized_album_artists)?;

    if let Some(cover) = meta.cover {
        write_cover_if_missing(conn, covers_dir, base_dir, &album_id, &cover)?;
    }

    let song_id = Uuid::new_v4().to_string();
    let added_at = now_secs();
    conn.execute(
        "INSERT INTO songs (id, title, track_num, disc_num, album_id, file_path, added_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![
            song_id,
            title,
            track_num,
            disc_num,
            album_id,
            file_path_str,
            added_at
        ],
    )?;
    conn.execute(
        "INSERT INTO song_artists (song_id, artist_id, is_featured, position) \
         VALUES (?1, ?2, 0, 0)",
        params![song_id, leading_artist_id],
    )?;
    for (i, fid) in feature_artist_ids.iter().enumerate() {
        conn.execute(
            "INSERT OR IGNORE INTO song_artists (song_id, artist_id, is_featured, position) \
             VALUES (?1, ?2, 1, ?3)",
            params![song_id, fid, (i as i64) + 1],
        )?;
    }

    Ok(())
}

fn ensure_artist(conn: &Connection, name: &str) -> rusqlite::Result<String> {
    let trimmed = name.trim();
    let lookup = if trimmed.is_empty() {
        MISSING_ARTIST
    } else {
        trimmed
    };
    if let Some(id) = conn
        .query_row(
            "SELECT id FROM artists WHERE name = ?1 LIMIT 1",
            params![lookup],
            |r| r.get::<_, String>(0),
        )
        .optional()?
    {
        return Ok(id);
    }
    let id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO artists (id, name) VALUES (?1, ?2)",
        params![id, lookup],
    )?;
    Ok(id)
}

fn ensure_multi_artist_album(
    conn: &Connection,
    title: &str,
    artist_names: &[String],
) -> rusqlite::Result<String> {
    let artist_ids = artist_names
        .iter()
        .map(|name| ensure_artist(conn, name))
        .collect::<rusqlite::Result<Vec<_>>>()?;
    let mut key_ids = artist_ids.clone();
    key_ids.sort();
    key_ids.dedup();
    let artist_key = key_ids.join("\u{1f}");
    if let Some(id) = conn
        .query_row(
            "SELECT id FROM albums WHERE title = ?1 COLLATE NOCASE AND artist_key = ?2",
            params![title.trim(), artist_key],
            |r| r.get::<_, String>(0),
        )
        .optional()?
    {
        return Ok(id);
    }
    let id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO albums (id, title, artist_id, artist_key, cover_path) VALUES (?1, ?2, ?3, ?4, NULL)",
        params![id, title.trim(), artist_ids[0], artist_key],
    )?;
    for (position, artist_id) in artist_ids.iter().enumerate() {
        conn.execute(
            "INSERT INTO album_artists (album_id, artist_id, position) VALUES (?1, ?2, ?3)",
            params![id, artist_id, position as i64],
        )?;
    }
    Ok(id)
}

fn required_text(value: &str, field: &str) -> Result<String, String> {
    let value = value.split_whitespace().collect::<Vec<_>>().join(" ");
    if value.is_empty() {
        Err(format!("{field} cannot be empty"))
    } else {
        Ok(value)
    }
}

fn normalize_names(values: Vec<String>) -> Vec<String> {
    let mut normalized = Vec::new();
    for value in values {
        let value = value.split_whitespace().collect::<Vec<_>>().join(" ");
        if !value.is_empty()
            && !normalized
                .iter()
                .any(|v: &String| v.eq_ignore_ascii_case(&value))
        {
            normalized.push(value);
        }
    }
    normalized
}

fn valid_playlist_icon(key: &str) -> bool {
    matches!(
        key,
        "music"
            | "queue"
            | "favorite"
            | "star"
            | "car"
            | "fitness"
            | "flight"
            | "celebration"
            | "work"
            | "school"
            | "gaming"
            | "night"
    )
}

fn detect_image_extension(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]) {
        Some("png")
    } else if bytes.starts_with(&[0xff, 0xd8, 0xff]) {
        Some("jpg")
    } else if bytes.len() >= 12 && &bytes[..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some("webp")
    } else {
        None
    }
}

fn remove_stored_file(base_dir: &Path, stored: &str) {
    let path = PathBuf::from(absolutize(stored, base_dir));
    if let Err(e) = fs::remove_file(&path) {
        if e.kind() != std::io::ErrorKind::NotFound {
            warn!("remove managed artwork {:?}: {e}", path);
        }
    }
}

fn album_artist_names(conn: &Connection, album_id: &str) -> rusqlite::Result<Vec<String>> {
    let mut stmt = conn.prepare(
        "SELECT a.name FROM album_artists aa JOIN artists a ON a.id = aa.artist_id WHERE aa.album_id = ?1 ORDER BY aa.position",
    )?;
    let rows = stmt.query_map(params![album_id], |r| r.get::<_, String>(0))?;
    rows.collect()
}

struct PreparedAudioUpdate {
    original: PathBuf,
    staged: PathBuf,
    backup: PathBuf,
}

#[derive(Debug, Serialize, Deserialize)]
struct MetadataOperationJournal {
    id: String,
    files: Vec<MetadataOperationFile>,
}

#[derive(Debug, Serialize, Deserialize)]
struct MetadataOperationFile {
    original: String,
    staged: String,
    backup: String,
}

fn write_metadata_operation_journal(
    path: &Path,
    files: &[PreparedAudioUpdate],
) -> Result<String, String> {
    let id = Uuid::new_v4().to_string();
    let journal = MetadataOperationJournal {
        id: id.clone(),
        files: files
            .iter()
            .map(|file| MetadataOperationFile {
                original: file.original.to_string_lossy().into_owned(),
                staged: file.staged.to_string_lossy().into_owned(),
                backup: file.backup.to_string_lossy().into_owned(),
            })
            .collect(),
    };
    let json =
        serde_json::to_vec_pretty(&journal).map_err(|e| format!("encode metadata journal: {e}"))?;
    fs::write(path, json).map_err(|e| format!("write metadata journal: {e}"))?;
    Ok(id)
}

fn finish_metadata_operation(conn: &Connection, path: &Path, id: &str) {
    let _ = fs::remove_file(path);
    let _ = conn.execute("DELETE FROM metadata_operations WHERE id = ?1", params![id]);
}

fn recover_metadata_operation(conn: &Connection, path: &Path) -> Result<(), String> {
    if !path.exists() {
        return Ok(());
    }
    let raw = fs::read(path).map_err(|e| format!("read metadata recovery journal: {e}"))?;
    let journal: MetadataOperationJournal = serde_json::from_slice(&raw)
        .map_err(|e| format!("parse metadata recovery journal: {e}"))?;
    let committed = conn
        .query_row(
            "SELECT 1 FROM metadata_operations WHERE id = ?1",
            params![journal.id],
            |r| r.get::<_, i64>(0),
        )
        .optional()
        .map_err(|e| format!("check metadata operation: {e}"))?
        .is_some();
    for file in &journal.files {
        let original = Path::new(&file.original);
        let staged = Path::new(&file.staged);
        let backup = Path::new(&file.backup);
        if committed {
            let _ = fs::remove_file(backup);
            let _ = fs::remove_file(staged);
        } else if backup.exists() {
            let _ = fs::remove_file(original);
            fs::rename(backup, original)
                .map_err(|e| format!("restore interrupted metadata edit: {e}"))?;
            let _ = fs::remove_file(staged);
        } else {
            let _ = fs::remove_file(staged);
        }
    }
    finish_metadata_operation(conn, path, &journal.id);
    Ok(())
}

impl Drop for PreparedAudioUpdate {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.staged);
    }
}

impl PreparedAudioUpdate {
    fn activate(&self) -> Result<(), String> {
        fs::rename(&self.original, &self.backup).map_err(|e| format!("backup audio file: {e}"))?;
        if let Err(e) = fs::rename(&self.staged, &self.original) {
            let _ = fs::rename(&self.backup, &self.original);
            return Err(format!("replace audio file: {e}"));
        }
        Ok(())
    }

    fn rollback(&self) {
        let _ = fs::remove_file(&self.original);
        let _ = fs::rename(&self.backup, &self.original);
        let _ = fs::remove_file(&self.staged);
    }

    fn finish(&self) {
        let _ = fs::remove_file(&self.backup);
        let _ = fs::remove_file(&self.staged);
    }
}

#[allow(clippy::too_many_arguments)]
fn prepare_audio_update(
    original: &Path,
    title: &str,
    primary_artist: &str,
    featured_artists: &[String],
    album: &str,
    album_artists: &[String],
    track_num: i64,
    disc_num: i64,
    artwork: Option<&Path>,
) -> Result<PreparedAudioUpdate, String> {
    if !original.is_file() {
        return Err(format!(
            "source audio file is unavailable: {}",
            original.display()
        ));
    }
    let file_name = original
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or_else(|| "invalid audio filename".to_string())?;
    let parent = original
        .parent()
        .ok_or_else(|| "audio file has no parent directory".to_string())?;
    let nonce = Uuid::new_v4();
    let extension = original
        .extension()
        .and_then(|value| value.to_str())
        .ok_or_else(|| "audio file has no extension".to_string())?;
    let staged = parent.join(format!(".{file_name}.clutter-{nonce}.{extension}"));
    let backup = parent.join(format!(".{file_name}.clutter-{nonce}.backup"));
    fs::copy(original, &staged).map_err(|e| format!("stage audio file: {e}"))?;
    let metadata = MetadataWrite {
        title,
        primary_artist,
        featured_artists,
        album,
        album_artists,
        track_num,
        disc_num,
        artwork_path: artwork,
    };
    if let Err(e) = write_metadata(&staged, &metadata) {
        let _ = fs::remove_file(&staged);
        return Err(e);
    }
    // re-probe the staged file before it is allowed to replace the original.
    crate::media::tags::extract_raw_metadata(&staged).map_err(|e| {
        let _ = fs::remove_file(&staged);
        format!("verify staged audio file: {e}")
    })?;
    Ok(PreparedAudioUpdate {
        original: original.to_path_buf(),
        staged,
        backup,
    })
}

fn activate_prepared_batch(files: &[PreparedAudioUpdate]) -> Result<(), String> {
    for (index, file) in files.iter().enumerate() {
        if let Err(error) = file.activate() {
            for active in files[..index].iter().rev() {
                active.rollback();
            }
            return Err(error);
        }
    }
    Ok(())
}

fn rollback_prepared_batch(files: &[PreparedAudioUpdate]) {
    for file in files.iter().rev() {
        file.rollback();
    }
}

fn finish_prepared_batch(files: &[PreparedAudioUpdate]) {
    for file in files {
        file.finish();
    }
}

fn write_cover_if_missing(
    conn: &Connection,
    covers_dir: &Path,
    base_dir: &Path,
    album_id: &str,
    cover: &RawCover,
) -> rusqlite::Result<()> {
    let existing: Option<Option<String>> = conn
        .query_row(
            "SELECT cover_path FROM albums WHERE id = ?1",
            params![album_id],
            |r| r.get::<_, Option<String>>(0),
        )
        .optional()?;
    if let Some(Some(_)) = existing {
        return Ok(());
    }

    let ext = guess_cover_ext(&cover.mime_type);
    let cover_file = covers_dir.join(format!("{album_id}.{ext}"));
    if let Err(e) = fs::write(&cover_file, &cover.data) {
        warn!("failed to write cover {:?}: {}", cover_file, e);
        return Ok(());
    }
    conn.execute(
        "UPDATE albums SET cover_path = ?1 WHERE id = ?2",
        params![relativize(&cover_file, base_dir), album_id],
    )?;
    Ok(())
}

fn guess_cover_ext(mime: &str) -> &'static str {
    match mime.to_ascii_lowercase().as_str() {
        "image/jpeg" | "image/jpg" => "jpg",
        "image/png" => "png",
        "image/webp" => "webp",
        "image/gif" => "gif",
        _ => "bin",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn new_store() -> (SqliteLibraryStore, TempDir) {
        let tmp = TempDir::new().expect("tempdir");
        let db_path = tmp.path().join("library.db");
        let covers_dir = tmp.path().join("covers");
        let store = SqliteLibraryStore::open(
            &db_path.to_string_lossy(),
            &covers_dir.to_string_lossy(),
            &tmp.path().to_string_lossy(),
        )
        .expect("open store");
        (store, tmp)
    }

    #[test]
    fn deezer_feature_splitting_writes_separate_rows() {
        let (store, _tmp) = new_store();

        let meta = RawMetadata {
            title: Some("Go2DaMoon".into()),
            album: Some("Whole Lotta Red".into()),
            leading_artist: Some("Playboi Carti/Kanye West".into()),
            album_artist: Some("Playboi Carti".into()),
            track_num: Some(2),
            disc_num: Some(1),
            cover: None,
        };
        store
            .insert_song(
                Path::new("/tmp/fake-go2damoon.mp3"),
                meta,
                "Playboi Carti",
                &["Kanye West".to_string()],
                "Playboi Carti",
            )
            .expect("insert");

        let conn = store.conn.lock().unwrap();
        let rows: Vec<(String, i64)> = conn
            .prepare(
                "SELECT a.name, sa.is_featured FROM song_artists sa \
                 JOIN artists a ON sa.artist_id = a.id \
                 JOIN songs s ON sa.song_id = s.id \
                 WHERE s.title = 'Go2DaMoon' ORDER BY sa.is_featured, sa.position",
            )
            .unwrap()
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))
            .unwrap()
            .collect::<Result<_, _>>()
            .unwrap();

        assert_eq!(
            rows,
            vec![
                ("Playboi Carti".to_string(), 0),
                ("Kanye West".to_string(), 1),
            ]
        );
    }

    fn insert_basic_song(
        store: &SqliteLibraryStore,
        file_path: &str,
        title: &str,
        album: &str,
        artist: &str,
        features: &[String],
    ) {
        let meta = RawMetadata {
            title: Some(title.into()),
            album: Some(album.into()),
            leading_artist: Some(artist.into()),
            album_artist: Some(artist.into()),
            track_num: Some(1),
            disc_num: Some(1),
            cover: None,
        };
        store
            .insert_song(Path::new(file_path), meta, artist, features, artist)
            .expect("insert");
    }

    fn album_id_for(store: &SqliteLibraryStore, album_title: &str) -> String {
        let conn = store.conn.lock().unwrap();
        conn.query_row(
            "SELECT id FROM albums WHERE title = ?1",
            params![album_title],
            |r| r.get::<_, String>(0),
        )
        .expect("find album")
    }

    #[test]
    fn get_songs_paginated_orders_by_newest_added_first() {
        let (store, _tmp) = new_store();
        insert_basic_song(&store, "/tmp/old.mp3", "Old", "Album", "Artist", &[]);
        insert_basic_song(&store, "/tmp/new.mp3", "New", "Album", "Artist", &[]);
        insert_basic_song(&store, "/tmp/middle.mp3", "Middle", "Album", "Artist", &[]);

        {
            let conn = store.conn.lock().unwrap();
            conn.execute(
                "UPDATE songs SET added_at = CASE title \
                    WHEN 'Old' THEN 10 \
                    WHEN 'Middle' THEN 20 \
                    WHEN 'New' THEN 30 \
                 END",
                [],
            )
            .unwrap();
        }

        let page = store.get_songs_paginated(0, 10);
        let titles: Vec<&str> = page.iter().map(|s| s.title.as_str()).collect();
        assert_eq!(titles, vec!["New", "Middle", "Old"]);
    }

    #[test]
    fn split_album_creates_new_artist_with_same_name() {
        let (store, _tmp) = new_store();
        insert_basic_song(
            &store,
            "/tmp/a.mp3",
            "Track 1",
            "Soundtrack A",
            "John Williams",
            &[],
        );

        let album_id = album_id_for(&store, "Soundtrack A");
        let new_id = store.split_album_to_new_artist(&album_id).expect("split");

        let conn = store.conn.lock().unwrap();
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM artists WHERE name = 'John Williams'",
                [],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(count, 2, "split must leave two rows with the same name");

        let new_row_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM artists WHERE id = ?1 AND name = 'John Williams'",
                params![new_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(new_row_count, 1, "returned new_id must identify a real row");
    }

    #[test]
    fn split_album_reassigns_album_and_primary_song_artists() {
        let (store, _tmp) = new_store();
        insert_basic_song(
            &store,
            "/tmp/1.mp3",
            "Track 1",
            "Album X",
            "Playboi Carti",
            &[],
        );
        insert_basic_song(
            &store,
            "/tmp/2.mp3",
            "Track 2",
            "Album X",
            "Playboi Carti",
            &[],
        );

        let album_id = album_id_for(&store, "Album X");
        let new_id = store.split_album_to_new_artist(&album_id).expect("split");

        let conn = store.conn.lock().unwrap();

        let album_artist: String = conn
            .query_row(
                "SELECT artist_id FROM albums WHERE id = ?1",
                params![album_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(album_artist, new_id);

        let primary_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM song_artists sa \
                 JOIN songs s ON s.id = sa.song_id \
                 WHERE s.album_id = ?1 AND sa.is_featured = 0 AND sa.artist_id = ?2",
                params![album_id, new_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(primary_count, 2, "both songs' primary artist must move");
    }

    #[test]
    fn split_album_does_not_touch_other_albums_or_featured_entries() {
        let (store, _tmp) = new_store();

        // two albums sharing the same (merged) "playboi carti" row.
        insert_basic_song(
            &store,
            "/tmp/a1.mp3",
            "A Track",
            "Album A",
            "Playboi Carti",
            &[],
        );
        insert_basic_song(
            &store,
            "/tmp/b1.mp3",
            "B Track",
            "Album B",
            "Playboi Carti",
            &[],
        );

        // a song on album b where "playboi carti" appears as a feature
        // (primary = kanye west). feature role must not be moved by the split.
        let meta = RawMetadata {
            title: Some("Collab".into()),
            album: Some("Album B".into()),
            leading_artist: Some("Kanye West/Playboi Carti".into()),
            album_artist: Some("Playboi Carti".into()),
            track_num: Some(2),
            disc_num: Some(1),
            cover: None,
        };
        store
            .insert_song(
                Path::new("/tmp/collab.mp3"),
                meta,
                "Kanye West",
                &["Playboi Carti".to_string()],
                "Playboi Carti",
            )
            .expect("insert collab");

        let old_id: String = {
            let conn = store.conn.lock().unwrap();
            conn.query_row(
                "SELECT id FROM artists WHERE name = 'Playboi Carti'",
                [],
                |r| r.get(0),
            )
            .unwrap()
        };

        let album_a_id = album_id_for(&store, "Album A");
        let album_b_id = album_id_for(&store, "Album B");
        store.split_album_to_new_artist(&album_a_id).expect("split");

        let conn = store.conn.lock().unwrap();

        // album b still points to the old artist row.
        let b_artist: String = conn
            .query_row(
                "SELECT artist_id FROM albums WHERE id = ?1",
                params![album_b_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(b_artist, old_id, "other album's artist_id must not change");

        // primary-artist entries for album b songs still point to old_id.
        let b_primary_old: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM song_artists sa \
                 JOIN songs s ON s.id = sa.song_id \
                 WHERE s.album_id = ?1 AND sa.is_featured = 0 AND sa.artist_id = ?2",
                params![album_b_id, old_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(b_primary_old, 1, "Album B primary artist row untouched");

        // featured-role entry for old_id on the collab song still exists.
        let feature_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM song_artists \
                 WHERE artist_id = ?1 AND is_featured = 1",
                params![old_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(
            feature_count, 1,
            "featured-artist link must not be rewritten"
        );
    }

    #[test]
    fn liked_songs_playlist_is_seeded_on_open() {
        let (store, _tmp) = new_store();
        let conn = store.conn.lock().unwrap();
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM playlists WHERE is_system = 1 AND name = ?1",
                params![LIKED_SONGS_NAME],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(count, 1, "liked songs playlist must be seeded on open");
    }

    #[test]
    fn add_and_remove_song_from_playlist_roundtrip() {
        let (store, _tmp) = new_store();
        insert_basic_song(
            &store,
            "/tmp/p1.mp3",
            "Track 1",
            "Some Album",
            "Some Artist",
            &[],
        );
        let song_id: String = {
            let conn = store.conn.lock().unwrap();
            conn.query_row("SELECT id FROM songs LIMIT 1", [], |r| r.get(0))
                .unwrap()
        };
        let pid = store.create_playlist("Favorites").expect("create");
        store.add_song_to_playlist(&pid, &song_id).expect("add");
        assert_eq!(store.get_songs_in_playlist(&pid).len(), 1);

        // idempotent: insert or ignore
        store
            .add_song_to_playlist(&pid, &song_id)
            .expect("add again");
        assert_eq!(store.get_songs_in_playlist(&pid).len(), 1);

        store
            .remove_song_from_playlist(&pid, &song_id)
            .expect("remove");
        assert!(store.get_songs_in_playlist(&pid).is_empty());
    }

    #[test]
    fn playlist_backup_tracks_user_playlist_changes() {
        let (store, _tmp) = new_store();
        insert_basic_song(
            &store,
            "/tmp/backup.mp3",
            "Backup Track",
            "Backup Album",
            "Artist",
            &[],
        );
        let song_id: String = {
            let conn = store.conn.lock().unwrap();
            conn.query_row("SELECT id FROM songs LIMIT 1", [], |r| r.get(0))
                .unwrap()
        };

        let pid = store.create_playlist("Backup List").expect("create");
        store.add_song_to_playlist(&pid, &song_id).expect("add");

        let raw = fs::read_to_string(&store.playlist_backup_path).expect("backup json");
        let backup: PlaylistBackup = serde_json::from_str(&raw).expect("parse backup");
        assert_eq!(backup.playlists.len(), 1);
        assert_eq!(backup.playlists[0].name, "Backup List");
        assert_eq!(backup.playlists[0].songs[0].title, "Backup Track");
        assert_eq!(backup.playlists[0].songs[0].album, "Backup Album");

        store
            .remove_song_from_playlist(&pid, &song_id)
            .expect("remove");
        let raw = fs::read_to_string(&store.playlist_backup_path).expect("backup json");
        let backup: PlaylistBackup = serde_json::from_str(&raw).expect("parse backup");
        assert!(backup.playlists[0].songs.is_empty());

        store.delete_playlist(&pid).expect("delete");
        let raw = fs::read_to_string(&store.playlist_backup_path).expect("backup json");
        let backup: PlaylistBackup = serde_json::from_str(&raw).expect("parse backup");
        assert!(backup.playlists.is_empty());
    }

    #[test]
    fn reset_library_does_not_rewrite_playlist_backup() {
        let (store, _tmp) = new_store();
        insert_basic_song(&store, "/tmp/reset.mp3", "Track", "Album", "Artist", &[]);
        let song_id: String = {
            let conn = store.conn.lock().unwrap();
            conn.query_row("SELECT id FROM songs LIMIT 1", [], |r| r.get(0))
                .unwrap()
        };
        let pid = store.create_playlist("Persist Me").expect("create");
        store.add_song_to_playlist(&pid, &song_id).expect("add");
        let before = fs::read_to_string(&store.playlist_backup_path).expect("backup before");

        store.reset_library().expect("reset");

        let after = fs::read_to_string(&store.playlist_backup_path).expect("backup after");
        assert_eq!(after, before);
    }

    #[test]
    fn liked_songs_changes_do_not_rewrite_playlist_backup() {
        let (store, _tmp) = new_store();
        insert_basic_song(&store, "/tmp/liked.mp3", "Track", "Album", "Artist", &[]);
        let song_id: String = {
            let conn = store.conn.lock().unwrap();
            conn.query_row("SELECT id FROM songs LIMIT 1", [], |r| r.get(0))
                .unwrap()
        };
        let pid = store.create_playlist("Keep Backup").expect("create");
        store.add_song_to_playlist(&pid, &song_id).expect("add");
        let before = fs::read_to_string(&store.playlist_backup_path).expect("backup before");

        let liked_id = store.get_liked_songs_playlist_id().expect("liked playlist");
        store
            .add_song_to_playlist(&liked_id, &song_id)
            .expect("like");
        store
            .remove_song_from_playlist(&liked_id, &song_id)
            .expect("unlike");

        let after = fs::read_to_string(&store.playlist_backup_path).expect("backup after");
        assert_eq!(after, before);
    }

    #[test]
    fn restore_playlist_backup_matches_normalized_title_and_album() {
        let (store, _tmp) = new_store();
        insert_basic_song(
            &store,
            "/tmp/restore.mp3",
            "A Restored Song",
            "The Album",
            "Artist",
            &[],
        );
        let backup = PlaylistBackup {
            playlists: vec![PlaylistBackupPlaylist {
                id: "restored-playlist".to_string(),
                name: "Restored".to_string(),
                icon_key: None,
                image_path: None,
                songs: vec![
                    PlaylistBackupSong {
                        title: "  a   restored SONG ".to_string(),
                        album: " the album ".to_string(),
                    },
                    PlaylistBackupSong {
                        title: "Missing".to_string(),
                        album: "The Album".to_string(),
                    },
                ],
            }],
        };
        fs::write(
            &store.playlist_backup_path,
            serde_json::to_string_pretty(&backup).unwrap(),
        )
        .expect("write backup");

        store
            .restore_user_playlists_from_backup()
            .expect("restore first");
        store
            .restore_user_playlists_from_backup()
            .expect("restore second");

        let playlists = store.get_playlists_paginated(0, 10);
        let restored = playlists
            .iter()
            .find(|p| p.name == "Restored")
            .expect("restored playlist");
        let songs = store.get_songs_in_playlist(&restored.id);
        assert_eq!(songs.len(), 1);
        assert_eq!(songs[0].title, "A Restored Song");
    }

    #[test]
    fn delete_system_playlist_is_refused() {
        let (store, _tmp) = new_store();
        let liked_id = store.get_liked_songs_playlist_id().expect("seeded");
        let err = store.delete_playlist(&liked_id).unwrap_err();
        assert!(
            err.contains("system"),
            "expected refusal referencing system, got: {err}"
        );
        // user-created playlists delete fine
        let pid = store.create_playlist("Temp").expect("create");
        store.delete_playlist(&pid).expect("delete user playlist");
    }

    #[test]
    fn search_songs_matches_title_and_artist() {
        let (store, _tmp) = new_store();
        insert_basic_song(
            &store,
            "/tmp/s1.mp3",
            "Blinding Lights",
            "After Hours",
            "The Weeknd",
            &[],
        );
        insert_basic_song(
            &store,
            "/tmp/s2.mp3",
            "Smells Like Teen Spirit",
            "Nevermind",
            "Nirvana",
            &[],
        );

        let by_title = store.search_songs("blind", 50);
        assert_eq!(by_title.len(), 1);
        assert_eq!(by_title[0].title, "Blinding Lights");

        let by_artist = store.search_songs("nirvana", 50);
        assert_eq!(by_artist.len(), 1);
        assert_eq!(by_artist[0].title, "Smells Like Teen Spirit");

        let by_album = store.search_songs("after hours", 50);
        assert_eq!(by_album.len(), 1);

        let none = store.search_songs("not-a-match", 50);
        assert!(none.is_empty());
    }

    #[test]
    fn search_albums_matches_title_and_artist() {
        let (store, _tmp) = new_store();
        insert_basic_song(&store, "/tmp/a1.mp3", "x", "Starboy", "The Weeknd", &[]);
        insert_basic_song(&store, "/tmp/a2.mp3", "x", "Nevermind", "Nirvana", &[]);

        let by_title = store.search_albums("star", 50);
        assert_eq!(by_title.len(), 1);
        assert_eq!(by_title[0].title, "Starboy");

        let by_artist = store.search_albums("weeknd", 50);
        assert_eq!(by_artist.len(), 1);
        assert_eq!(by_artist[0].title, "Starboy");
    }

    #[test]
    fn search_playlists_matches_name() {
        let (store, _tmp) = new_store();
        store.create_playlist("Road Trip").expect("create 1");
        store.create_playlist("Workout").expect("create 2");

        let by_name = store.search_playlists("road", 50);
        assert_eq!(by_name.len(), 1);
        assert_eq!(by_name[0].name, "Road Trip");

        // system liked songs is found too
        let by_like = store.search_playlists("lik", 50);
        assert!(by_like.iter().any(|p| p.is_system));
    }

    #[test]
    fn playlist_songs_cascade_when_song_is_deleted() {
        let (store, _tmp) = new_store();
        insert_basic_song(&store, "/tmp/c1.mp3", "Track", "Album", "Artist", &[]);
        let song_id: String = {
            let conn = store.conn.lock().unwrap();
            conn.query_row("SELECT id FROM songs LIMIT 1", [], |r| r.get(0))
                .unwrap()
        };
        let pid = store.create_playlist("x").expect("create");
        store.add_song_to_playlist(&pid, &song_id).expect("add");

        {
            let conn = store.conn.lock().unwrap();
            conn.execute("DELETE FROM songs WHERE id = ?1", params![song_id])
                .unwrap();
        }
        assert!(store.get_songs_in_playlist(&pid).is_empty());
    }

    #[test]
    fn song_edit_can_create_multi_artist_album_and_override_cover() {
        let (store, tmp) = new_store();
        insert_basic_song(&store, "/tmp/edit.mp3", "Old", "Old Album", "Artist", &[]);
        let song = store.get_songs_paginated(0, 1).pop().unwrap();
        let image = tmp.path().join("custom.png");
        fs::write(&image, tiny_png()).unwrap();

        let updated = store
            .update_song_metadata(SongMetadataUpdate {
                song_id: song.id,
                title: "New Title".into(),
                primary_artist: "Lead".into(),
                featured_artists: vec!["Feature".into()],
                track_num: 2,
                disc_num: 1,
                album: AlbumSelection::New {
                    title: "Joint Album".into(),
                    artists: vec!["Lead".into(), "Partner".into()],
                },
                cover: ArtworkUpdate::Replace(image.to_string_lossy().into_owned()),
                write_file_tags: false,
            })
            .expect("update song");

        assert_eq!(updated.title, "New Title");
        assert_eq!(updated.album, "Joint Album");
        assert_eq!(updated.album_artists, vec!["Lead", "Partner"]);
        assert!(updated.song_cover_path.is_some());
        assert_eq!(updated.cover_path, updated.song_cover_path);
    }

    #[test]
    fn album_edit_merges_matching_identity_without_losing_songs() {
        let (store, _tmp) = new_store();
        insert_basic_song(
            &store,
            "/tmp/source.mp3",
            "Source",
            "Source Album",
            "Artist",
            &[],
        );
        insert_basic_song(
            &store,
            "/tmp/target.mp3",
            "Target",
            "Target Album",
            "Artist",
            &[],
        );
        let source_id = album_id_for(&store, "Source Album");
        let target_id = album_id_for(&store, "Target Album");

        let result = store
            .update_album_metadata(AlbumMetadataUpdate {
                album_id: source_id.clone(),
                title: "Target Album".into(),
                artists: vec!["Artist".into()],
                cover: ArtworkUpdate::Keep,
                write_file_tags: false,
            })
            .expect("merge album");

        assert_eq!(result.id, target_id);
        assert_eq!(result.song_count, 2);
        assert!(store.get_songs_by_album_id(&source_id).is_empty());
        assert_eq!(store.get_songs_by_album_id(&target_id).len(), 2);
    }

    #[test]
    fn artist_custom_cover_overrides_and_can_restore_album_fallback() {
        let (store, tmp) = new_store();
        insert_basic_song(
            &store,
            "/tmp/artist-cover.mp3",
            "Track",
            "Album",
            "Artist",
            &[],
        );
        let artist = store.get_artists_paginated(0, 1).pop().unwrap();
        let image = tmp.path().join("artist.png");
        fs::write(&image, tiny_png()).unwrap();

        let changed = store
            .update_artist_image(
                &artist.id,
                ArtworkUpdate::Replace(image.to_string_lossy().into_owned()),
            )
            .expect("set artist image");
        assert!(changed.custom_cover_path.is_some());
        assert_eq!(changed.cover_path, changed.custom_cover_path);

        let restored = store
            .update_artist_image(&artist.id, ArtworkUpdate::Remove)
            .expect("remove artist image");
        assert!(restored.custom_cover_path.is_none());
    }

    #[test]
    fn playlist_visual_modes_are_exclusive_and_system_playlist_is_fixed() {
        let (store, tmp) = new_store();
        let id = store.create_playlist("Road Trip").unwrap();
        let image = tmp.path().join("playlist.png");
        fs::write(&image, tiny_png()).unwrap();

        let with_image = store
            .update_playlist_metadata(
                &id,
                "Driving",
                PlaylistVisualUpdate::Image(image.to_string_lossy().into_owned()),
            )
            .unwrap();
        assert!(with_image.image_path.is_some());
        assert!(with_image.icon_key.is_none());

        let with_icon = store
            .update_playlist_metadata(&id, "Driving", PlaylistVisualUpdate::Icon("car".into()))
            .unwrap();
        assert_eq!(with_icon.icon_key.as_deref(), Some("car"));
        assert!(with_icon.image_path.is_none());

        let liked = store.get_liked_songs_playlist_id().unwrap();
        assert!(store
            .update_playlist_metadata(&liked, "Renamed", PlaylistVisualUpdate::Initials)
            .is_err());
    }

    #[test]
    fn interrupted_metadata_operation_restores_original_when_db_did_not_commit() {
        let (store, tmp) = new_store();
        let original = tmp.path().join("track.mp3");
        let staged = tmp.path().join("track.staged.mp3");
        let backup = tmp.path().join("track.backup");
        fs::write(&original, b"new").unwrap();
        fs::write(&staged, b"staged").unwrap();
        fs::write(&backup, b"old").unwrap();
        let journal = MetadataOperationJournal {
            id: "uncommitted".into(),
            files: vec![MetadataOperationFile {
                original: original.to_string_lossy().into_owned(),
                staged: staged.to_string_lossy().into_owned(),
                backup: backup.to_string_lossy().into_owned(),
            }],
        };
        fs::write(
            &store.operation_journal_path,
            serde_json::to_vec(&journal).unwrap(),
        )
        .unwrap();
        let conn = store.conn.lock().unwrap();
        recover_metadata_operation(&conn, &store.operation_journal_path).unwrap();
        assert_eq!(fs::read(&original).unwrap(), b"old");
        assert!(!staged.exists());
        assert!(!backup.exists());
        assert!(!store.operation_journal_path.exists());
    }

    fn tiny_png() -> &'static [u8] {
        // 1x1 transparent png.
        &[
            137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
            8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 8, 215, 99, 96, 0, 0, 0,
            2, 0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
        ]
    }

    #[test]
    fn pin_item_roundtrip() {
        let (store, _tmp) = new_store();
        insert_basic_song(&store, "/tmp/pin.mp3", "Pinned", "Album", "Artist", &[]);
        let song_id: String = {
            let conn = store.conn.lock().unwrap();
            conn.query_row("SELECT id FROM songs LIMIT 1", [], |r| r.get(0))
                .unwrap()
        };

        assert!(store.get_pinned_items().is_empty());

        store.pin_item(&song_id, "song").expect("pin song");
        let pins = store.get_pinned_items();
        assert_eq!(pins.len(), 1);
        assert_eq!(pins[0].item_id, song_id);
        assert_eq!(pins[0].kind, "song");

        // re-pinning the same item updates rather than duplicates.
        store.pin_item(&song_id, "song").expect("re-pin song");
        assert_eq!(store.get_pinned_items().len(), 1);

        store.unpin_item(&song_id, "song").expect("unpin song");
        assert!(store.get_pinned_items().is_empty());
    }

    #[test]
    fn move_pinned_item_reorders() {
        let (store, _tmp) = new_store();
        insert_basic_song(&store, "/tmp/a.mp3", "A", "Album", "Artist", &[]);
        insert_basic_song(&store, "/tmp/b.mp3", "B", "Album", "Artist", &[]);
        insert_basic_song(&store, "/tmp/c.mp3", "C", "Album", "Artist", &[]);

        let conn = store.conn.lock().unwrap();
        let ids: Vec<String> = conn
            .prepare("SELECT id FROM songs ORDER BY title")
            .unwrap()
            .query_map([], |r| r.get::<_, String>(0))
            .unwrap()
            .filter_map(|r| r.ok())
            .collect();
        drop(conn);

        for id in &ids {
            store.pin_item(id, "song").expect("pin");
        }

        // initial order: a, b, c
        assert_eq!(
            store
                .get_pinned_items()
                .iter()
                .map(|p| &p.item_id)
                .collect::<Vec<_>>(),
            vec![&ids[0], &ids[1], &ids[2]]
        );

        // move last to first.
        store.move_pinned_item(&ids[2], "song", 0).expect("move");
        assert_eq!(
            store
                .get_pinned_items()
                .iter()
                .map(|p| &p.item_id)
                .collect::<Vec<_>>(),
            vec![&ids[2], &ids[0], &ids[1]]
        );

        // move first to second.
        store.move_pinned_item(&ids[2], "song", 1).expect("move");
        assert_eq!(
            store
                .get_pinned_items()
                .iter()
                .map(|p| &p.item_id)
                .collect::<Vec<_>>(),
            vec![&ids[0], &ids[2], &ids[1]]
        );
    }
}
