use crate::storage::sqlite::{
    AlbumRow, ArtistRow, ArtworkUpdate, KeybindingRow, PinnedItemRow, PlaybackStateRow,
    PlaylistRow, SongRow,
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
    Replace { source_path: String },
}

impl From<CoverArtEdit> for ArtworkUpdate {
    fn from(value: CoverArtEdit) -> Self {
        match value {
            CoverArtEdit::Keep => ArtworkUpdate::Keep,
            CoverArtEdit::Remove => ArtworkUpdate::Remove,
            CoverArtEdit::Replace { source_path } => ArtworkUpdate::Replace(source_path),
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
    Icon { key: String },
    Image { source_path: String },
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
