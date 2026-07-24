use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

use log::{info, warn};
use walkdir::WalkDir;

use crate::media::tags::{
    extract_raw_metadata, parse_artist_string, RawCover, RawMetadata, MISSING_ARTIST,
};
use crate::storage::sqlite::SqliteLibraryStore;

const SUPPORTED_EXTENSIONS: &[&str] = &["mp3", "flac", "m4a", "mp4", "ogg", "opus", "wav"];

#[derive(Debug, Clone, Copy)]
pub struct ScanOptions {
    pub is_deezer: bool,
}

struct PendingSong {
    path: PathBuf,
    metadata: RawMetadata,
    primary_artist: String,
    featured_artists: Vec<String>,
    album_artists: Vec<String>,
}

pub fn scan_directory(
    store: &SqliteLibraryStore,
    path: &str,
    options: ScanOptions,
) -> Result<(), String> {
    persist_scan_path(store, path);
    let pending = collect_pending_songs(store, path, options);
    let album_covers = choose_album_covers(&pending);
    let processed = persist_songs(store, pending, &album_covers);
    info!("scan complete: {processed} songs indexed from {path}");
    restore_playlists(store);
    Ok(())
}

pub fn index_audio_file(
    store: &SqliteLibraryStore,
    path: &Path,
    options: ScanOptions,
) -> Result<crate::storage::sqlite::SongRow, String> {
    if !is_supported_audio(path) {
        return Err("unsupported audio file".into());
    }
    let pending = read_pending_song(path, options)
        .ok_or_else(|| "could not read downloaded audio metadata".to_string())?;
    store.insert_song_with_album_artists(
        &pending.path,
        pending.metadata,
        &pending.primary_artist,
        &pending.featured_artists,
        &pending.album_artists,
    )?;
    store
        .get_song_by_file(path)
        .ok_or_else(|| "downloaded song was not indexed".into())
}

fn persist_scan_path(store: &SqliteLibraryStore, path: &str) {
    if let Err(error) = store.add_scan_path(path) {
        warn!("failed to persist scan path {path}: {error}");
    }
}

fn collect_pending_songs(
    store: &SqliteLibraryStore,
    root: &str,
    options: ScanOptions,
) -> Vec<PendingSong> {
    WalkDir::new(root)
        .follow_links(true)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter(|entry| is_supported_audio(entry.path()))
        .filter(|entry| !store.contains_song_file(entry.path()))
        .filter_map(|entry| read_pending_song(entry.path(), options))
        .collect()
}

fn read_pending_song(path: &Path, options: ScanOptions) -> Option<PendingSong> {
    let metadata = match extract_raw_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) => {
            warn!("failed to read {path:?}: {error}");
            return None;
        }
    };
    let (primary_artist, featured_artists) = song_artists(&metadata, options);
    let album_artists = album_artists(&metadata, &primary_artist, options);
    Some(PendingSong {
        path: path.to_path_buf(),
        metadata,
        primary_artist,
        featured_artists,
        album_artists,
    })
}

fn song_artists(metadata: &RawMetadata, options: ScanOptions) -> (String, Vec<String>) {
    metadata
        .leading_artist
        .as_deref()
        .map(|raw| parse_artist_string(raw, options.is_deezer))
        .unwrap_or_else(|| (MISSING_ARTIST.to_string(), Vec::new()))
}

fn album_artists(
    metadata: &RawMetadata,
    primary_artist: &str,
    options: ScanOptions,
) -> Vec<String> {
    metadata
        .album_artist
        .as_deref()
        .map(|raw| {
            let (first, rest) = parse_artist_string(raw, options.is_deezer);
            std::iter::once(first).chain(rest).collect()
        })
        .unwrap_or_else(|| vec![primary_artist.to_string()])
}

fn choose_album_covers(pending: &[PendingSong]) -> HashMap<usize, Option<u64>> {
    let mut groups = HashMap::<String, Vec<usize>>::new();
    for (index, song) in pending.iter().enumerate() {
        groups.entry(album_identity(song)).or_default().push(index);
    }
    groups
        .values_mut()
        .flat_map(|indices| choose_group_cover(pending, indices))
        .collect()
}

fn choose_group_cover(pending: &[PendingSong], indices: &mut [usize]) -> Vec<(usize, Option<u64>)> {
    indices.sort_by_key(|index| song_order(&pending[*index]));
    let mut counts = HashMap::<u64, (usize, usize)>::new();
    for (rank, index) in indices.iter().enumerate() {
        if let Some(cover) = pending[*index].metadata.cover.as_ref() {
            let entry = counts.entry(cover_hash(cover)).or_insert((0, rank));
            entry.0 += 1;
        }
    }
    let winner = counts
        .into_iter()
        .max_by(|a, b| a.1 .0.cmp(&b.1 .0).then_with(|| b.1 .1.cmp(&a.1 .1)))
        .map(|(hash, _)| hash);
    indices.iter().map(|index| (*index, winner)).collect()
}

fn persist_songs(
    store: &SqliteLibraryStore,
    pending: Vec<PendingSong>,
    album_covers: &HashMap<usize, Option<u64>>,
) -> usize {
    pending
        .into_iter()
        .enumerate()
        .map(|(index, song)| persist_song(store, index, song, album_covers))
        .filter(|persisted| *persisted)
        .count()
}

fn persist_song(
    store: &SqliteLibraryStore,
    index: usize,
    mut song: PendingSong,
    album_covers: &HashMap<usize, Option<u64>>,
) -> bool {
    let override_cover = take_override_cover(&mut song.metadata, album_covers.get(&index));
    let result = store.insert_song_with_album_artists(
        &song.path,
        song.metadata,
        &song.primary_artist,
        &song.featured_artists,
        &song.album_artists,
    );
    if let Err(error) = result {
        warn!("failed to index {:?}: {error}", song.path);
        return false;
    }
    persist_override_cover(store, &song.path, override_cover);
    true
}

fn take_override_cover(
    metadata: &mut RawMetadata,
    album_hash: Option<&Option<u64>>,
) -> Option<RawCover> {
    let cover_hash = metadata.cover.as_ref().map(cover_hash);
    match (cover_hash, album_hash.copied().flatten()) {
        (Some(song_hash), Some(album_hash)) if song_hash != album_hash => metadata.cover.take(),
        _ => None,
    }
}

fn persist_override_cover(store: &SqliteLibraryStore, path: &Path, cover: Option<RawCover>) {
    let Some(cover) = cover else { return };
    if let Err(error) = store.set_scanned_song_cover(path, &cover) {
        warn!("failed to persist song cover {path:?}: {error}");
    }
}

fn restore_playlists(store: &SqliteLibraryStore) {
    if let Err(error) = store.restore_user_playlists_from_backup() {
        warn!("failed to restore playlists from backup after scan: {error}");
    }
}

fn is_supported_audio(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| extension.to_ascii_lowercase())
        .is_some_and(|extension| SUPPORTED_EXTENSIONS.contains(&extension.as_str()))
}

fn album_identity(song: &PendingSong) -> String {
    let mut artists = song
        .album_artists
        .iter()
        .map(|artist| artist.trim().to_lowercase())
        .collect::<Vec<_>>();
    artists.sort();
    artists.dedup();
    let title = song
        .metadata
        .album
        .as_deref()
        .unwrap_or("")
        .trim()
        .to_lowercase();
    format!("{title}\u{1f}{}", artists.join("\u{1f}"))
}

fn song_order(song: &PendingSong) -> (i64, i64, String) {
    (
        song.metadata.disc_num.unwrap_or(1),
        song.metadata.track_num.unwrap_or(1),
        song.path.to_string_lossy().into_owned(),
    )
}

fn cover_hash(cover: &RawCover) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    cover.mime_type.hash(&mut hasher);
    cover.data.hash(&mut hasher);
    hasher.finish()
}
