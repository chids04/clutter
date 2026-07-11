use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SongRow {
    pub id: String,
    pub title: String,
    pub track_num: i64,
    pub disc_num: i64,
    pub file_path: String,
    pub album: String,
    pub album_id: String,
    pub album_artists: Vec<String>,
    pub cover_path: Option<String>,
    pub song_cover_path: Option<String>,
    pub primary_artist: String,
    pub featured_artists: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AlbumRow {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub artists: Vec<String>,
    pub cover_path: Option<String>,
    pub song_count: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaylistRow {
    pub id: String,
    pub name: String,
    pub is_system: bool,
    pub song_count: i64,
    pub icon_key: Option<String>,
    pub image_path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaybackStateRow {
    pub song: SongRow,
    pub position_ms: i64,
    pub loop_one: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PinnedItemRow {
    pub item_id: String,
    pub kind: String,
    pub position: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtistRow {
    pub id: String,
    pub name: String,
    pub cover_path: Option<String>,
    pub custom_cover_path: Option<String>,
    pub album_count: i64,
    pub song_count: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ArtworkUpdate {
    Keep,
    Replace(String),
    Remove,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AlbumSelection {
    Existing(String),
    New { title: String, artists: Vec<String> },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SongMetadataUpdate {
    pub song_id: String,
    pub title: String,
    pub primary_artist: String,
    pub featured_artists: Vec<String>,
    pub track_num: i64,
    pub disc_num: i64,
    pub album: AlbumSelection,
    pub cover: ArtworkUpdate,
    pub write_file_tags: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AlbumMetadataUpdate {
    pub album_id: String,
    pub title: String,
    pub artists: Vec<String>,
    pub cover: ArtworkUpdate,
    pub write_file_tags: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlaylistVisualUpdate {
    Keep,
    Initials,
    Icon(String),
    Image(String),
}

#[derive(Debug, Serialize, Deserialize)]
pub(super) struct PlaylistBackup {
    pub playlists: Vec<PlaylistBackupPlaylist>,
}

#[derive(Debug, Serialize, Deserialize)]
pub(super) struct PlaylistBackupPlaylist {
    pub id: String,
    pub name: String,
    pub icon_key: Option<String>,
    pub image_path: Option<String>,
    pub songs: Vec<PlaylistBackupSong>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(super) struct PlaylistBackupSong {
    pub title: String,
    pub album: String,
}
