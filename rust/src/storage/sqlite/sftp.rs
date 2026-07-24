use super::{now_secs, SftpDownloadRow, SftpProfileRow, SqliteLibraryStore};
use rusqlite::{params, OptionalExtension};
use uuid::Uuid;

impl SqliteLibraryStore {
    pub fn get_sftp_profiles(&self) -> Result<Vec<SftpProfileRow>, String> {
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let mut statement = conn
            .prepare(
                "SELECT id, name, host, port, username, root_path, \
                 host_key_fingerprint, is_selected FROM sftp_profiles \
                 ORDER BY is_selected DESC, name COLLATE NOCASE",
            )
            .map_err(|error| format!("prepare sftp profiles: {error}"))?;
        let rows = statement
            .query_map([], profile_from_row)
            .map_err(|error| format!("query sftp profiles: {error}"))?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|error| format!("read sftp profiles: {error}"))
    }

    pub fn save_sftp_profile(&self, profile: SftpProfileRow) -> Result<SftpProfileRow, String> {
        validate_profile(&profile)?;
        let mut conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let tx = conn.transaction().map_err(|error| format!("tx: {error}"))?;
        if profile.is_selected {
            tx.execute("UPDATE sftp_profiles SET is_selected = 0", [])
                .map_err(|error| format!("clear selected sftp profile: {error}"))?;
        }
        tx.execute(
            "INSERT INTO sftp_profiles \
             (id, name, host, port, username, root_path, host_key_fingerprint, is_selected, created_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9) \
             ON CONFLICT(id) DO UPDATE SET name = excluded.name, host = excluded.host, \
             port = excluded.port, username = excluded.username, root_path = excluded.root_path, \
             host_key_fingerprint = excluded.host_key_fingerprint, is_selected = excluded.is_selected",
            params![
                profile.id,
                profile.name,
                profile.host,
                i64::from(profile.port),
                profile.username,
                profile.root_path,
                profile.host_key_fingerprint,
                profile.is_selected,
                now_secs(),
            ],
        )
        .map_err(|error| format!("save sftp profile: {error}"))?;
        tx.commit()
            .map_err(|error| format!("commit sftp profile: {error}"))?;
        Ok(profile)
    }

    pub fn delete_sftp_profile(&self, profile_id: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let removed = conn
            .execute(
                "DELETE FROM sftp_profiles WHERE id = ?1",
                params![profile_id],
            )
            .map_err(|error| format!("delete sftp profile: {error}"))?;
        if removed == 0 {
            return Err("sftp profile not found".into());
        }
        Ok(())
    }

    pub fn select_sftp_profile(&self, profile_id: &str) -> Result<(), String> {
        let mut conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let tx = conn.transaction().map_err(|error| format!("tx: {error}"))?;
        let exists = tx
            .query_row(
                "SELECT 1 FROM sftp_profiles WHERE id = ?1",
                params![profile_id],
                |_| Ok(()),
            )
            .optional()
            .map_err(|error| format!("find sftp profile: {error}"))?;
        if exists.is_none() {
            return Err("sftp profile not found".into());
        }
        tx.execute("UPDATE sftp_profiles SET is_selected = 0", [])
            .map_err(|error| format!("clear selected sftp profile: {error}"))?;
        tx.execute(
            "UPDATE sftp_profiles SET is_selected = 1 WHERE id = ?1",
            params![profile_id],
        )
        .map_err(|error| format!("select sftp profile: {error}"))?;
        tx.commit()
            .map_err(|error| format!("commit selected sftp profile: {error}"))
    }

    pub fn record_sftp_download(&self, row: SftpDownloadRow) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        conn.execute(
            "INSERT INTO sftp_downloads \
             (id, profile_id, remote_path, remote_size, remote_mtime, song_id, downloaded_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                row.id,
                row.profile_id,
                row.remote_path,
                row.remote_size.map(|value| value as i64),
                row.remote_mtime,
                row.song_id,
                now_secs(),
            ],
        )
        .map_err(|error| format!("record sftp download: {error}"))?;
        Ok(())
    }

    pub fn sftp_downloaded_paths(
        &self,
        profile_id: &str,
        remote_paths: &[String],
    ) -> Result<Vec<String>, String> {
        if remote_paths.is_empty() {
            return Ok(Vec::new());
        }
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let mut statement = conn
            .prepare(
                "SELECT DISTINCT d.remote_path FROM sftp_downloads d \
                 JOIN songs s ON s.id = d.song_id \
                 WHERE d.profile_id = ?1 AND d.remote_path = ?2",
            )
            .map_err(|error| format!("prepare downloaded lookup: {error}"))?;
        let mut downloaded = Vec::new();
        for path in remote_paths {
            let exists = statement
                .query_row(params![profile_id, path], |row| row.get::<_, String>(0))
                .optional()
                .map_err(|error| format!("query downloaded path: {error}"))?;
            downloaded.extend(exists);
        }
        Ok(downloaded)
    }
}

fn profile_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<SftpProfileRow> {
    let port = row.get::<_, i64>(3)?;
    Ok(SftpProfileRow {
        id: row.get(0)?,
        name: row.get(1)?,
        host: row.get(2)?,
        port: u16::try_from(port).unwrap_or(22),
        username: row.get(4)?,
        root_path: row.get(5)?,
        host_key_fingerprint: row.get(6)?,
        is_selected: row.get(7)?,
    })
}

fn validate_profile(profile: &SftpProfileRow) -> Result<(), String> {
    if profile.name.trim().is_empty() {
        return Err("profile name is required".into());
    }
    if profile.host.trim().is_empty() {
        return Err("host is required".into());
    }
    if profile.username.trim().is_empty() {
        return Err("username is required".into());
    }
    if !profile.root_path.starts_with('/') {
        return Err("root path must be absolute".into());
    }
    if profile.host_key_fingerprint.trim().is_empty() {
        return Err("host key fingerprint is required".into());
    }
    Ok(())
}

pub fn new_sftp_profile_id() -> String {
    Uuid::new_v4().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::media::tags::RawMetadata;
    use std::path::Path;
    use tempfile::TempDir;

    fn store() -> (SqliteLibraryStore, TempDir) {
        let temp = TempDir::new().expect("temp dir");
        let store = SqliteLibraryStore::open(
            &temp.path().join("library.db").to_string_lossy(),
            &temp.path().join("covers").to_string_lossy(),
            &temp.path().to_string_lossy(),
        )
        .expect("open store");
        (store, temp)
    }

    fn profile(name: &str, selected: bool) -> SftpProfileRow {
        SftpProfileRow {
            id: new_sftp_profile_id(),
            name: name.into(),
            host: "100.64.0.1".into(),
            port: 22,
            username: "music".into(),
            root_path: "/music".into(),
            host_key_fingerprint: "SHA256:test".into(),
            is_selected: selected,
        }
    }

    #[test]
    fn profiles_round_trip_without_a_password_column() {
        let (store, _temp) = store();
        let saved = store.save_sftp_profile(profile("home", true)).unwrap();
        assert_eq!(store.get_sftp_profiles().unwrap(), vec![saved]);
        let conn = store.conn.lock().unwrap();
        let columns = conn
            .prepare("PRAGMA table_info(sftp_profiles)")
            .unwrap()
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert!(!columns.iter().any(|name| name.contains("password")));
    }

    #[test]
    fn selecting_a_profile_clears_the_previous_selection() {
        let (store, _temp) = store();
        let first = store.save_sftp_profile(profile("one", true)).unwrap();
        let second = store.save_sftp_profile(profile("two", false)).unwrap();
        store.select_sftp_profile(&second.id).unwrap();
        let rows = store.get_sftp_profiles().unwrap();
        assert!(
            rows.iter()
                .find(|row| row.id == second.id)
                .unwrap()
                .is_selected
        );
        assert!(
            !rows
                .iter()
                .find(|row| row.id == first.id)
                .unwrap()
                .is_selected
        );
    }

    #[test]
    fn repeated_remote_downloads_remain_distinct_and_mark_the_path() {
        let (store, _temp) = store();
        let profile = store.save_sftp_profile(profile("home", true)).unwrap();
        for index in 0..2 {
            let path = format!("/tmp/remote-{index}.mp3");
            store
                .insert_song(
                    Path::new(&path),
                    RawMetadata {
                        title: Some(format!("song {index}")),
                        album: Some("album".into()),
                        leading_artist: Some("artist".into()),
                        album_artist: Some("artist".into()),
                        track_num: Some(1),
                        disc_num: Some(1),
                        cover: None,
                    },
                    "artist",
                    &[],
                    "artist",
                )
                .unwrap();
            let song = store.get_songs_paginated(index, 1).pop().unwrap();
            store
                .record_sftp_download(SftpDownloadRow {
                    id: Uuid::new_v4().to_string(),
                    profile_id: profile.id.clone(),
                    remote_path: "/music/song.mp3".into(),
                    remote_size: Some(42),
                    remote_mtime: Some(7),
                    song_id: song.id,
                })
                .unwrap();
        }
        let paths = store
            .sftp_downloaded_paths(&profile.id, &["/music/song.mp3".into()])
            .unwrap();
        assert_eq!(paths, vec!["/music/song.mp3"]);
    }
}
