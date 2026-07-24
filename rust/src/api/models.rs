use crate::remote::sftp::{
    SftpDownloadProgress, SftpDownloadState, SftpEntry, SftpEntryKind, SftpProfile,
};
use crate::storage::sqlite::{
    AlbumRow, AlbumSelection, ArtistRow, ArtworkCropRect, ArtworkEditRow, ArtworkUpdate,
    ExtractedSongCrop, ExtractedSongImport, KeybindingRow, PinnedItemRow, PlaybackStateRow,
    PlaylistRow, SongAudioUpdate, SongRow,
};

#[derive(Debug, Clone)]
pub struct ScanConfig {
    pub is_deezer: bool,
}

// these are resolved values ready for the ui, dart never has to join ids
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
    pub album_id: String,
    pub album_artists: Vec<String>,
    pub song_cover_path: Option<String>,
    pub crop: Option<SongCropData>,
}

#[derive(Debug, Clone)]
pub struct SongCropData {
    pub original_audio_path: String,
    pub start_ms: i64,
    pub end_ms: i64,
}

impl From<SongRow> for SongViewData {
    fn from(row: SongRow) -> Self {
        Self {
            id: row.id,
            title: row.title,
            primary_artist: row.primary_artist,
            featured_artists: row.featured_artists,
            cover_path: row.cover_path,
            file_path: row.file_path,
            track_num: row.track_num,
            disc_num: row.disc_num,
            album: row.album,
            album_id: row.album_id,
            album_artists: row.album_artists,
            song_cover_path: row.song_cover_path,
            crop: row.crop.map(|crop| SongCropData {
                original_audio_path: crop.retained_file_path,
                start_ms: crop.start_ms,
                end_ms: crop.end_ms,
            }),
        }
    }
}

#[derive(Debug, Clone)]
pub struct AlbumViewData {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub cover_path: Option<String>,
    pub song_count: i64,
    pub artists: Vec<String>,
}

impl From<AlbumRow> for AlbumViewData {
    fn from(row: AlbumRow) -> Self {
        Self {
            id: row.id,
            title: row.title,
            artist: row.artist,
            cover_path: row.cover_path,
            song_count: row.song_count,
            artists: row.artists,
        }
    }
}

#[derive(Debug, Clone)]
pub struct PlaylistViewData {
    pub id: String,
    pub name: String,
    pub is_system: bool,
    pub song_count: i64,
    pub icon_key: Option<String>,
    pub image_path: Option<String>,
}

impl From<PlaylistRow> for PlaylistViewData {
    fn from(row: PlaylistRow) -> Self {
        Self {
            id: row.id,
            name: row.name,
            is_system: row.is_system,
            song_count: row.song_count,
            icon_key: row.icon_key,
            image_path: row.image_path,
        }
    }
}

// cover_path is the effective fallback, custom_cover_path tells the editor state
#[derive(Debug, Clone)]
pub struct ArtistViewData {
    pub id: String,
    pub name: String,
    pub cover_path: Option<String>,
    pub album_count: i64,
    pub song_count: i64,
    pub custom_cover_path: Option<String>,
}

impl From<ArtistRow> for ArtistViewData {
    fn from(row: ArtistRow) -> Self {
        Self {
            id: row.id,
            name: row.name,
            cover_path: row.cover_path,
            album_count: row.album_count,
            song_count: row.song_count,
            custom_cover_path: row.custom_cover_path,
        }
    }
}

#[derive(Debug, Clone)]
pub enum CoverArtEdit {
    Keep,
    Remove,
    Replace {
        original_source_path: String,
        cropped_source_path: String,
        crop: ArtworkCropRectData,
    },
}

#[derive(Debug, Clone, Copy)]
pub struct ArtworkCropRectData {
    pub left: f64,
    pub top: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone)]
pub struct ArtworkEditData {
    pub original_path: String,
    pub crop: ArtworkCropRectData,
}

#[derive(Debug, Clone, Copy)]
pub enum ArtworkOwner {
    Song,
    Album,
    Artist,
    Playlist,
}

impl From<ArtworkCropRectData> for ArtworkCropRect {
    fn from(value: ArtworkCropRectData) -> Self {
        Self {
            left: value.left,
            top: value.top,
            width: value.width,
            height: value.height,
        }
    }
}

impl From<ArtworkEditRow> for ArtworkEditData {
    fn from(value: ArtworkEditRow) -> Self {
        Self {
            original_path: value.original_path,
            crop: ArtworkCropRectData {
                left: value.crop.left,
                top: value.crop.top,
                width: value.crop.width,
                height: value.crop.height,
            },
        }
    }
}

impl From<CoverArtEdit> for ArtworkUpdate {
    fn from(value: CoverArtEdit) -> Self {
        match value {
            CoverArtEdit::Keep => ArtworkUpdate::Keep,
            CoverArtEdit::Remove => ArtworkUpdate::Remove,
            CoverArtEdit::Replace {
                original_source_path,
                cropped_source_path,
                crop,
            } => ArtworkUpdate::Replace {
                original_source_path,
                cropped_source_path,
                crop: crop.into(),
            },
        }
    }
}

#[derive(Debug, Clone)]
pub enum AlbumChoice {
    Existing { album_id: String },
    New { title: String, artists: Vec<String> },
}

#[derive(Debug, Clone)]
pub struct SongEditRequest {
    pub song_id: String,
    pub title: String,
    pub primary_artist: String,
    pub featured_artists: Vec<String>,
    pub track_num: i64,
    pub disc_num: i64,
    pub album: AlbumChoice,
    pub cover: CoverArtEdit,
    pub audio: SongAudioEdit,
}

#[derive(Debug, Clone)]
pub enum SongAudioEdit {
    Keep,
    ApplyCrop {
        source_path: String,
        start_ms: i64,
        end_ms: i64,
    },
    RestoreOriginal,
}

impl From<SongAudioEdit> for SongAudioUpdate {
    fn from(value: SongAudioEdit) -> Self {
        match value {
            SongAudioEdit::Keep => Self::Keep,
            SongAudioEdit::ApplyCrop {
                source_path,
                start_ms,
                end_ms,
            } => Self::ApplyCrop {
                source_path,
                start_ms,
                end_ms,
            },
            SongAudioEdit::RestoreOriginal => Self::RestoreOriginal,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ExtractedSongImportRequest {
    pub source_path: String,
    pub title: String,
    pub primary_artist: String,
    pub featured_artists: Vec<String>,
    pub track_num: i64,
    pub disc_num: i64,
    pub album: AlbumChoice,
    pub cover: CoverArtEdit,
    pub crop: Option<ExtractedSongCropRequest>,
}

#[derive(Debug, Clone)]
pub struct ExtractedSongCropRequest {
    pub original_source_path: String,
    pub start_ms: i64,
    pub end_ms: i64,
}

impl ExtractedSongImportRequest {
    pub(crate) fn into_internal(self) -> ExtractedSongImport {
        ExtractedSongImport {
            source_path: self.source_path,
            title: self.title,
            primary_artist: self.primary_artist,
            featured_artists: self.featured_artists,
            track_num: self.track_num,
            disc_num: self.disc_num,
            album: match self.album {
                AlbumChoice::Existing { album_id } => AlbumSelection::Existing(album_id),
                AlbumChoice::New { title, artists } => AlbumSelection::New { title, artists },
            },
            cover: self.cover.into(),
            crop: self.crop.map(|crop| ExtractedSongCrop {
                original_source_path: crop.original_source_path,
                start_ms: crop.start_ms,
                end_ms: crop.end_ms,
            }),
        }
    }
}

#[derive(Debug, Clone)]
pub struct AlbumEditRequest {
    pub album_id: String,
    pub title: String,
    pub artists: Vec<String>,
    pub cover: CoverArtEdit,
}

#[derive(Debug, Clone)]
pub enum PlaylistVisualEdit {
    Keep,
    Initials,
    Icon {
        key: String,
    },
    Image {
        original_source_path: String,
        cropped_source_path: String,
        crop: ArtworkCropRectData,
    },
}

#[derive(Debug, Clone)]
pub struct PlaylistEditRequest {
    pub playlist_id: String,
    pub name: String,
    pub visual: PlaylistVisualEdit,
}

#[derive(Debug, Clone)]
pub struct PlaybackStateData {
    pub song: SongViewData,
    pub position_ms: i64,
    pub loop_one: bool,
}

impl From<PlaybackStateRow> for PlaybackStateData {
    fn from(row: PlaybackStateRow) -> Self {
        Self {
            song: row.song.into(),
            position_ms: row.position_ms,
            loop_one: row.loop_one,
        }
    }
}

#[derive(Debug, Clone)]
pub struct PinnedItemData {
    pub item_id: String,
    pub kind: String,
    pub position: i64,
}

impl From<PinnedItemRow> for PinnedItemData {
    fn from(row: PinnedItemRow) -> Self {
        Self {
            item_id: row.item_id,
            kind: row.kind,
            position: row.position,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeybindingAction {
    PlayPause,
    PreviousTrack,
    NextTrack,
    OmniSearch,
}

impl KeybindingAction {
    fn as_str(self) -> &'static str {
        match self {
            Self::PlayPause => "play_pause",
            Self::PreviousTrack => "previous_track",
            Self::NextTrack => "next_track",
            Self::OmniSearch => "omni_search",
        }
    }

    fn from_str(value: &str) -> Self {
        match value {
            "play_pause" => Self::PlayPause,
            "previous_track" => Self::PreviousTrack,
            "next_track" => Self::NextTrack,
            "omni_search" => Self::OmniSearch,
            _ => unreachable!("storage only returns known keybinding actions"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeybindingData {
    pub action: KeybindingAction,
    pub key_code: Option<String>,
    pub primary: bool,
    pub control: bool,
    pub meta: bool,
    pub alt: bool,
    pub shift: bool,
}

impl KeybindingData {
    pub(crate) fn into_row(self) -> KeybindingRow {
        KeybindingRow {
            action: self.action.as_str().into(),
            key_code: self.key_code,
            primary: self.primary,
            control: self.control,
            meta: self.meta,
            alt: self.alt,
            shift: self.shift,
        }
    }
}

impl From<KeybindingRow> for KeybindingData {
    fn from(row: KeybindingRow) -> Self {
        Self {
            action: KeybindingAction::from_str(&row.action),
            key_code: row.key_code,
            primary: row.primary,
            control: row.control,
            meta: row.meta,
            alt: row.alt,
            shift: row.shift,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SftpProfileData {
    pub id: String,
    pub name: String,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub root_path: String,
    pub host_key_fingerprint: String,
    pub is_selected: bool,
}

impl From<SftpProfile> for SftpProfileData {
    fn from(value: SftpProfile) -> Self {
        Self {
            id: value.id,
            name: value.name,
            host: value.host,
            port: value.port,
            username: value.username,
            root_path: value.root_path,
            host_key_fingerprint: value.host_key_fingerprint,
            is_selected: value.is_selected,
        }
    }
}

impl From<SftpProfileData> for SftpProfile {
    fn from(value: SftpProfileData) -> Self {
        Self {
            id: value.id,
            name: value.name,
            host: value.host,
            port: value.port,
            username: value.username,
            root_path: value.root_path,
            host_key_fingerprint: value.host_key_fingerprint,
            is_selected: value.is_selected,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SftpEntryKindData {
    File,
    Directory,
    Unsupported,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SftpEntryData {
    pub name: String,
    pub relative_path: String,
    pub kind: SftpEntryKindData,
    pub size: Option<u64>,
    pub modified_at: Option<i64>,
    pub downloaded: bool,
}

impl From<SftpEntry> for SftpEntryData {
    fn from(value: SftpEntry) -> Self {
        Self {
            name: value.name,
            relative_path: value.relative_path,
            kind: match value.kind {
                SftpEntryKind::File => SftpEntryKindData::File,
                SftpEntryKind::Directory => SftpEntryKindData::Directory,
                SftpEntryKind::Unsupported => SftpEntryKindData::Unsupported,
            },
            size: value.size,
            modified_at: value.modified_at,
            downloaded: value.downloaded,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SftpDownloadStateData {
    Discovering,
    Downloading,
    Importing,
    Completed,
    CompletedWithErrors,
    Cancelled,
    Failed,
}

impl SftpDownloadStateData {
    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            Self::Completed | Self::CompletedWithErrors | Self::Cancelled | Self::Failed
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SftpDownloadProgressData {
    pub job_id: String,
    pub state: SftpDownloadStateData,
    pub current_name: Option<String>,
    pub files_completed: u32,
    pub files_total: u32,
    pub bytes_completed: u64,
    pub bytes_total: u64,
    pub failed_files: u32,
    pub message: Option<String>,
}

impl From<SftpDownloadProgress> for SftpDownloadProgressData {
    fn from(value: SftpDownloadProgress) -> Self {
        Self {
            job_id: value.job_id,
            state: match value.state {
                SftpDownloadState::Discovering => SftpDownloadStateData::Discovering,
                SftpDownloadState::Downloading => SftpDownloadStateData::Downloading,
                SftpDownloadState::Importing => SftpDownloadStateData::Importing,
                SftpDownloadState::Completed => SftpDownloadStateData::Completed,
                SftpDownloadState::CompletedWithErrors => {
                    SftpDownloadStateData::CompletedWithErrors
                }
                SftpDownloadState::Cancelled => SftpDownloadStateData::Cancelled,
                SftpDownloadState::Failed => SftpDownloadStateData::Failed,
            },
            current_name: value.current_name,
            files_completed: value.files_completed,
            files_total: value.files_total,
            bytes_completed: value.bytes_completed,
            bytes_total: value.bytes_total,
            failed_files: value.failed_files,
            message: value.message,
        }
    }
}
