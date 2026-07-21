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
    pub crop: Option<SongCropRow>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SongCropRow {
    pub original_file_path: String,
    pub retained_file_path: String,
    pub start_ms: i64,
    pub end_ms: i64,
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

#[derive(Debug, Clone, PartialEq)]
pub enum ArtworkUpdate {
    Keep,
    Replace {
        original_source_path: String,
        cropped_source_path: String,
        crop: ArtworkCropRect,
    },
    Remove,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ArtworkCropRect {
    pub left: f64,
    pub top: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ArtworkOwnerKind {
    Song,
    Album,
    Artist,
    Playlist,
}

impl ArtworkOwnerKind {
    pub(super) fn as_str(self) -> &'static str {
        match self {
            Self::Song => "song",
            Self::Album => "album",
            Self::Artist => "artist",
            Self::Playlist => "playlist",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ArtworkEditRow {
    pub original_path: String,
    pub crop: ArtworkCropRect,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AlbumSelection {
    Existing(String),
    New { title: String, artists: Vec<String> },
}

#[derive(Debug, Clone, PartialEq)]
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
    pub audio: SongAudioUpdate,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SongAudioUpdate {
    Keep,
    ApplyCrop {
        source_path: String,
        start_ms: i64,
        end_ms: i64,
    },
    RestoreOriginal,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExtractedSongImport {
    pub source_path: String,
    pub title: String,
    pub primary_artist: String,
    pub featured_artists: Vec<String>,
    pub track_num: i64,
    pub disc_num: i64,
    pub album: AlbumSelection,
    pub cover: ArtworkUpdate,
    pub crop: Option<ExtractedSongCrop>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExtractedSongCrop {
    pub original_source_path: String,
    pub start_ms: i64,
    pub end_ms: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AlbumMetadataUpdate {
    pub album_id: String,
    pub title: String,
    pub artists: Vec<String>,
    pub cover: ArtworkUpdate,
    pub write_file_tags: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum PlaylistVisualUpdate {
    Keep,
    Initials,
    Icon(String),
    Image {
        original_source_path: String,
        cropped_source_path: String,
        crop: ArtworkCropRect,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeybindingRow {
    pub action: String,
    pub key_code: Option<String>,
    pub primary: bool,
    pub control: bool,
    pub meta: bool,
    pub alt: bool,
    pub shift: bool,
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
