use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use crate::api::metadata::{RawCover, RawMetadata, MISSING_ALBUM, MISSING_ARTIST, MISSING_TITLE};
use flutter_rust_bridge::frb;
use log::{debug, warn};
use rusqlite::{params, Connection, OptionalExtension};
use uuid::Uuid;

// Group-concat separator for features in SQL projections. Using ASCII Unit
// Separator so it cannot collide with characters inside an artist name.
const UNIT_SEP: char = '\u{001f}';

/// Flattened row shape returned by query methods. `scanner.rs` maps this into
/// the public `SongViewData` type.
#[frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SongRow {
    pub id: String,
    pub title: String,
    pub track_num: i64,
    pub disc_num: i64,
    pub file_path: String,
    pub album: String,
    pub cover_path: Option<String>,
    pub primary_artist: String,
    pub featured_artists: Vec<String>,
}

/// Flattened album row. Maps to `AlbumViewData` on the UI side.
#[frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AlbumRow {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub cover_path: Option<String>,
    pub song_count: i64,
}

/// Flattened playlist row. Maps to `PlaylistViewData` on the UI side.
#[frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaylistRow {
    pub id: String,
    pub name: String,
    pub is_system: bool,
    pub song_count: i64,
}

/// Restored playback for the MediaBar on relaunch. `position_ms` is where the
/// user left off; the UI hydrates paused and seeks on first play.
#[frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaybackStateRow {
    pub song: SongRow,
    pub position_ms: i64,
    pub loop_one: bool,
}

/// A pinned item in the quick-play sidebar. `kind` is one of
/// `song`, `album`, or `playlist`.
#[frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PinnedItemRow {
    pub item_id: String,
    pub kind: String,
    pub position: i64,
}

/// Flattened artist row. Maps to `ArtistViewData` on the UI side.
/// `cover_path` is a representative album cover for the artist (first album
/// with non-null `cover_path`), or `None` if the artist has no covers yet.
#[frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtistRow {
    pub id: String,
    pub name: String,
    pub cover_path: Option<String>,
    pub album_count: i64,
    pub song_count: i64,
}

pub(crate) const LIKED_SONGS_NAME: &str = "Liked Songs";

#[frb(ignore)]
pub struct Store {
    pub conn: Mutex<Connection>,
    covers_dir: PathBuf,
    /// Base directory that every stored path is relativized against. On iOS the
    /// app's sandbox container path (and thus the documents dir) carries a UUID
    /// that rotates on every relaunch/reinstall, so absolute paths persisted in
    /// the DB go stale. We store paths relative to this base and rebuild the
    /// absolute path on read against the *current* base. Paths outside the base
    /// (e.g. a desktop music folder) are stored/returned absolute unchanged.
    base_dir: PathBuf,
}

impl Store {
    /// Open (or create) the SQLite database at `db_path` and ensure the covers
    /// directory exists. `base_dir` is the directory all stored paths are made
    /// relative to (see [`Store::base_dir`]).
    pub fn open(db_path: &str, covers_dir: &str, base_dir: &str) -> Result<Store, String> {
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

        // Idempotent migration: add loop_one column to playback_state for
        // databases created before this column existed.
        //
        let _ = conn.execute(
            "ALTER TABLE playback_state ADD COLUMN loop_one INTEGER NOT NULL DEFAULT 0",
            [],
        );

        ensure_liked_songs_playlist(&conn).map_err(|e| format!("seed liked songs: {e}"))?;

        Ok(Store {
            conn: Mutex::new(conn),
            covers_dir: covers_dir_buf,
            base_dir: PathBuf::from(base_dir),
        })
    }

    /// Convert an absolute path to one relative to `base_dir` for storage. If
    /// `abs` is not under `base_dir` (e.g. a desktop music folder outside the
    /// app sandbox), it is returned absolute unchanged.
    fn to_rel(&self, abs: &Path) -> String {
        relativize(abs, &self.base_dir)
    }

    /// Rebuild an absolute path from a stored value. Already-absolute stored
    /// values are returned unchanged; relative ones are joined onto the current
    /// `base_dir`.
    fn to_abs(&self, stored: &str) -> String {
        absolutize(stored, &self.base_dir)
    }

    fn abs_song(&self, mut row: SongRow) -> SongRow {
        row.file_path = self.to_abs(&row.file_path);
        row.cover_path = row.cover_path.map(|c| self.to_abs(&c));
        row
    }

    fn abs_album(&self, mut row: AlbumRow) -> AlbumRow {
        row.cover_path = row.cover_path.map(|c| self.to_abs(&c));
        row
    }

    fn abs_artist(&self, mut row: ArtistRow) -> ArtistRow {
        row.cover_path = row.cover_path.map(|c| self.to_abs(&c));
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

    /// Insert a song with its pre-parsed artists. `leading_artist` is the
    /// primary performer; `feature_artists` are ordered featured artists;
    /// `album_artist` is the artist credited at the album level (falls back to
    /// `leading_artist` when empty).
    pub fn insert_song(
        &self,
        file_path: &Path,
        meta: RawMetadata,
        leading_artist: &str,
        feature_artists: &[String],
        album_artist: &str,
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
            album_artist,
        )
        .map_err(|e| format!("insert: {e}"))
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
        query_playlists(&conn, offset, limit).unwrap_or_else(|e| {
            warn!("query playlists failed: {e}");
            Vec::new()
        })
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
        Ok(())
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
        search_playlists(&conn, query, limit).unwrap_or_else(|e| {
            warn!("search playlists failed: {e}");
            Vec::new()
        })
    }

    /// Create a new artist row with the same name as the album's current
    /// album-artist and reassign the album (plus its songs' primary artist
    /// entries) to that new row. Featured-artist entries on those songs are
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

    /// Remove a single song. `song_artists`, `playlist_songs`, and
    /// `recently_played` rows cascade; `playback_state.song_id` is NULLed by
    /// the FK. If this was the last song in its album, the album row and its
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

    /// Remove an entire album and every song it contains. Cover file is
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

    /// Remove every song whose `file_path` lives under `path`, plus the
    /// `scan_paths` entry itself. Returns the number of songs removed.
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
        // Nuke the entire covers directory and recreate it — clears all cover
        // files including any orphans not tracked in the DB.
        let _ = fs::remove_dir_all(&self.covers_dir);
        let _ = fs::create_dir_all(&self.covers_dir);
        Ok(())
    }
}

/// Drop an album row if it no longer has any songs. Also unlinks the cover
/// file from disk. Called inside `delete_song` / `delete_album` /
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
        // Stored relative; resolve against the current base before unlinking.
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

fn query_songs(conn: &Connection, filter: SongFilter) -> rusqlite::Result<Vec<SongRow>> {
    let base = "\
        SELECT s.id, s.title, s.track_num, s.disc_num, s.file_path, \
               al.title, al.cover_path, pa.name, \
               (SELECT GROUP_CONCAT(a.name, ?1) \
                FROM song_artists sa \
                JOIN artists a ON sa.artist_id = a.id \
                WHERE sa.song_id = s.id AND sa.is_featured = 1 \
                ORDER BY sa.position) AS features \
        FROM songs s \
        LEFT JOIN albums al ON s.album_id = al.id \
        LEFT JOIN song_artists pasa ON pasa.song_id = s.id AND pasa.is_featured = 0 \
        LEFT JOIN artists pa ON pasa.artist_id = pa.id";

    let sep = UNIT_SEP.to_string();
    match filter {
        SongFilter::Page { offset, limit } => {
            let sql = format!(
                "{base} ORDER BY COALESCE(al.title, ''), s.disc_num, s.track_num, s.title \
                 LIMIT ?2 OFFSET ?3"
            );
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![sep, limit as i64, offset as i64], map_song_row)?;
            rows.collect()
        }
        SongFilter::ById(id) => {
            let sql = format!("{base} WHERE s.id = ?2");
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![sep, id], map_song_row)?;
            rows.collect()
        }
        SongFilter::ByAlbumId(album_id) => {
            let sql = format!(
                "{base} WHERE s.album_id = ?2 \
                 ORDER BY s.disc_num, s.track_num, s.title"
            );
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![sep, album_id], map_song_row)?;
            rows.collect()
        }
        SongFilter::ByPlaylistId(playlist_id) => {
            let sql = format!(
                "{base} JOIN playlist_songs ps ON ps.song_id = s.id \
                 WHERE ps.playlist_id = ?2 \
                 ORDER BY ps.position"
            );
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![sep, playlist_id], map_song_row)?;
            rows.collect()
        }
        SongFilter::FeaturedByArtistId(artist_id) => {
            let sql = format!(
                "{base} JOIN song_artists fsa ON fsa.song_id = s.id \
                 WHERE fsa.artist_id = ?2 AND fsa.is_featured = 1 \
                 ORDER BY s.title COLLATE NOCASE"
            );
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![sep, artist_id], map_song_row)?;
            rows.collect()
        }
        SongFilter::Search { query, limit } => {
            let pattern = format!("%{}%", like_escape(&query));
            let sql = format!(
                "{base} WHERE s.title LIKE ?2 ESCAPE '\\' \
                         OR pa.name LIKE ?2 ESCAPE '\\' \
                         OR al.title LIKE ?2 ESCAPE '\\' \
                 ORDER BY s.title COLLATE NOCASE \
                 LIMIT ?3"
            );
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![sep, pattern, limit as i64], map_song_row)?;
            rows.collect()
        }
        SongFilter::RecentlyPlayed { limit } => {
            let sql = format!(
                "{base} JOIN recently_played rp ON rp.song_id = s.id \
                 ORDER BY rp.played_at DESC \
                 LIMIT ?2"
            );
            let mut stmt = conn.prepare(&sql)?;
            let rows = stmt.query_map(params![sep, limit as i64], map_song_row)?;
            rows.collect()
        }
    }
}

fn query_playlists(
    conn: &Connection,
    offset: u32,
    limit: u32,
) -> rusqlite::Result<Vec<PlaylistRow>> {
    let mut stmt = conn.prepare(
        "SELECT p.id, p.name, p.is_system, \
                (SELECT COUNT(*) FROM playlist_songs ps WHERE ps.playlist_id = p.id) AS song_count \
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
        })
    })?;
    rows.collect()
}

fn search_albums(conn: &Connection, query: &str, limit: u32) -> rusqlite::Result<Vec<AlbumRow>> {
    let pattern = format!("%{}%", like_escape(query));
    let mut stmt = conn.prepare(
        "SELECT al.id, al.title, COALESCE(a.name, ?1), al.cover_path, \
                (SELECT COUNT(*) FROM songs s WHERE s.album_id = al.id) AS song_count \
         FROM albums al \
         LEFT JOIN artists a ON al.artist_id = a.id \
         WHERE al.title LIKE ?2 ESCAPE '\\' \
            OR a.name   LIKE ?2 ESCAPE '\\' \
         ORDER BY al.title COLLATE NOCASE \
         LIMIT ?3",
    )?;
    let rows = stmt.query_map(params![MISSING_ARTIST, pattern, limit as i64], |r| {
        Ok(AlbumRow {
            id: r.get(0)?,
            title: r.get(1)?,
            artist: r.get(2)?,
            cover_path: r.get(3)?,
            song_count: r.get(4)?,
        })
    })?;
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
                (SELECT COUNT(*) FROM playlist_songs ps WHERE ps.playlist_id = p.id) AS song_count \
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
        })
    })?;
    rows.collect()
}

fn like_escape(q: &str) -> String {
    q.replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

/// Make `abs` relative to `base` for storage. Stored relative paths always use
/// `/` separators so a library is portable across platforms. If `abs` is not
/// under `base`, it is returned absolute unchanged.
fn relativize(abs: &Path, base: &Path) -> String {
    match abs.strip_prefix(base) {
        Ok(rel) => rel.to_string_lossy().replace('\\', "/"),
        Err(_) => abs.to_string_lossy().to_string(),
    }
}

/// Inverse of [`relativize`]. Already-absolute stored values pass through; a
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
               (SELECT cover_path FROM albums \
                WHERE artist_id = a.id AND cover_path IS NOT NULL LIMIT 1), \
               (SELECT COUNT(*) FROM albums WHERE artist_id = a.id) AS album_count, \
               (SELECT COUNT(DISTINCT song_id) FROM song_artists \
                WHERE artist_id = a.id) AS song_count \
        FROM artists a";

    let map = |row: &rusqlite::Row| -> rusqlite::Result<ArtistRow> {
        Ok(ArtistRow {
            id: row.get(0)?,
            name: row.get(1)?,
            cover_path: row.get(2)?,
            album_count: row.get(3)?,
            song_count: row.get(4)?,
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
         FROM albums al \
         LEFT JOIN artists a ON al.artist_id = a.id \
         WHERE al.artist_id = ?2 \
         ORDER BY al.title COLLATE NOCASE"
    };
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map(params![MISSING_ARTIST, artist_id], |r| {
        Ok(AlbumRow {
            id: r.get(0)?,
            title: r.get(1)?,
            artist: r.get(2)?,
            cover_path: r.get(3)?,
            song_count: r.get(4)?,
        })
    })?;
    rows.collect()
}

fn query_albums(conn: &Connection, offset: u32, limit: u32) -> rusqlite::Result<Vec<AlbumRow>> {
    let mut stmt = conn.prepare(
        "SELECT al.id, al.title, COALESCE(a.name, ?1), al.cover_path, \
                (SELECT COUNT(*) FROM songs s WHERE s.album_id = al.id) AS song_count \
         FROM albums al \
         LEFT JOIN artists a ON al.artist_id = a.id \
         ORDER BY al.title COLLATE NOCASE \
         LIMIT ?2 OFFSET ?3",
    )?;
    let rows = stmt.query_map(params![MISSING_ARTIST, limit as i64, offset as i64], |r| {
        Ok(AlbumRow {
            id: r.get(0)?,
            title: r.get(1)?,
            artist: r.get(2)?,
            cover_path: r.get(3)?,
            song_count: r.get(4)?,
        })
    })?;
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
        cover_path: row.get(6)?,
        primary_artist: row
            .get::<_, Option<String>>(7)?
            .unwrap_or_else(|| MISSING_ARTIST.to_string()),
        featured_artists,
    })
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
    album_artist: &str,
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

    let album_artist_trimmed = album_artist.trim();
    let album_artist_id = if album_artist_trimmed.is_empty() {
        leading_artist_id.clone()
    } else {
        ensure_artist(conn, album_artist_trimmed)?
    };
    let album_id = ensure_album(conn, &album_name, &album_artist_id)?;

    if let Some(cover) = meta.cover {
        write_cover_if_missing(conn, covers_dir, base_dir, &album_id, &cover)?;
    }

    let song_id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO songs (id, title, track_num, disc_num, album_id, file_path) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        params![song_id, title, track_num, disc_num, album_id, file_path_str],
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

fn ensure_album(conn: &Connection, title: &str, artist_id: &str) -> rusqlite::Result<String> {
    let trimmed = title.trim();
    if let Some(id) = conn
        .query_row(
            "SELECT id FROM albums WHERE title = ?1 AND artist_id = ?2",
            params![trimmed, artist_id],
            |r| r.get::<_, String>(0),
        )
        .optional()?
    {
        return Ok(id);
    }
    let id = Uuid::new_v4().to_string();
    conn.execute(
        "INSERT INTO albums (id, title, artist_id, cover_path) VALUES (?1, ?2, ?3, NULL)",
        params![id, trimmed, artist_id],
    )?;
    Ok(id)
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

    fn new_store() -> (Store, TempDir) {
        let tmp = TempDir::new().expect("tempdir");
        let db_path = tmp.path().join("library.db");
        let covers_dir = tmp.path().join("covers");
        let store = Store::open(
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
        store: &Store,
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

    fn album_id_for(store: &Store, album_title: &str) -> String {
        let conn = store.conn.lock().unwrap();
        conn.query_row(
            "SELECT id FROM albums WHERE title = ?1",
            params![album_title],
            |r| r.get::<_, String>(0),
        )
        .expect("find album")
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

        // Two albums sharing the same (merged) "Playboi Carti" row.
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

        // A song on Album B where "Playboi Carti" appears as a feature
        // (primary = Kanye West). Feature role must NOT be moved by the split.
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

        // Album B still points to the old artist row.
        let b_artist: String = conn
            .query_row(
                "SELECT artist_id FROM albums WHERE id = ?1",
                params![album_b_id],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(b_artist, old_id, "other album's artist_id must not change");

        // Primary-artist entries for Album B songs still point to old_id.
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

        // Featured-role entry for old_id on the collab song still exists.
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

        // idempotent: INSERT OR IGNORE
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

        // system Liked Songs is found too
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

        // Re-pinning the same item updates rather than duplicates.
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

        // Initial order: a, b, c
        assert_eq!(
            store
                .get_pinned_items()
                .iter()
                .map(|p| &p.item_id)
                .collect::<Vec<_>>(),
            vec![&ids[0], &ids[1], &ids[2]]
        );

        // Move last to first.
        store.move_pinned_item(&ids[2], "song", 0).expect("move");
        assert_eq!(
            store
                .get_pinned_items()
                .iter()
                .map(|p| &p.item_id)
                .collect::<Vec<_>>(),
            vec![&ids[2], &ids[0], &ids[1]]
        );

        // Move first to second.
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
