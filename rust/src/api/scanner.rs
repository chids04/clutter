use flutter_rust_bridge::frb;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::{MetadataOptions, StandardTagKey, Tag, Value};
use symphonia::core::probe::Hint;
use uuid::Uuid;

use indexmap::IndexMap;
use log::{error, info, trace, warn};

use std::collections::HashMap;
use std::path::PathBuf;

const MISSING_ARTIST: &str = "Unknown Artist";
const MISSING_TITLE: &str = "Unknown Title";
const MISSING_ALBUM: &str = "Unknown Album";

/*
 * current architecture ideas
 * every song has its own album, makes grouping songs with missing tags easier since they can just be in the 'unknown album' album
 */

#[frb(opaque)]
#[derive(Debug, Clone)]
pub struct CSong {
    id: Uuid,
    title: String,
    artists: ArtistGroup,
    track_num: i64,
    disc_num: i64,
    album: Uuid,
    cover: Option<CImage>,
    path: PathBuf,
}

impl CSong {
    pub fn get_id(&self) -> String {
        return self.id.to_string();
    }

    pub fn get_title(&self) -> String {
        self.title.clone()
    }

    pub fn get_artists(&self) -> ArtistGroupDart {
        ArtistGroupDart {
            leading: self.artists.leading_artist.to_string(),
            features: self
                .artists
                .features
                .as_ref()
                .map(|feats| {
                    feats
                        .iter()
                        .map(|artist| artist.to_string())
                        .collect::<Vec<_>>()
                })
                .unwrap_or(Vec::new()),
        }
    }
}

#[derive(Debug)]
pub struct ArtistGroupDart {
    pub leading: String,
    pub features: Vec<String>,
}

impl ArtistGroupDart {
    pub fn getArtistStr(&self) {
        return self.to_string();
    }
}

impl std::fmt::Display for ArtistGroupDart {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let mut out = self.leading.clone();

        if self.features.len() > 0 {
            out.push_str(" feat.");
            out.push_str(self.features.join(", ").as_ref())
        }

        write!(f, "{out}")
    }
}

#[derive(Debug)]
pub struct CSongDart {
    pub id: String,
    pub title: String,
    pub artists: ArtistGroupDart,
    pub track_num: i64,
    pub disc_num: i64,
    pub album: String,
    pub cover: Option<CImage>,
    pub path: String,
}

impl From<CSong> for CSongDart {
    fn from(song: CSong) -> Self {
        let artists = {
            let leading = song.artists.leading_artist.to_string();
            let features = song
                .artists
                .features
                .as_ref()
                .map(|feats| {
                    feats
                        .iter()
                        .map(|artist| artist.to_string())
                        .collect::<Vec<_>>()
                })
                .unwrap_or(Vec::new());

            ArtistGroupDart { leading, features }
        };

        Self {
            id: song.id.to_string(),
            title: song.title,
            artists,
            track_num: song.track_num,
            disc_num: song.disc_num,
            album: song.album.to_string(),
            cover: song.cover,

            // change asap
            path: song.path.to_str().unwrap().to_owned(),
        }
    }
}

#[derive(Debug, Clone)]
struct Artist {
    id: Uuid,
    name: String,
}

#[derive(Debug, Clone)]
struct Album {
    id: Uuid,
    title: String,
    artists: ArtistGroup,
    songs: Vec<Uuid>,
    cover: Option<CImage>,
}

#[derive(Debug, Clone)]
pub struct CImage {
    pub data: Vec<u8>,
    pub mime_type: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct ArtistGroup {
    leading_artist: Uuid,
    features: Option<Vec<Uuid>>,
}

#[derive(Debug, Clone)]
struct MetadataCache {
    albums: HashMap<ArtistGroup, Vec<Album>>,
}

impl MetadataCache {
    fn new() -> Self {
        Self {
            albums: HashMap::new(),
        }
    }
}

pub struct Config {
    pub is_deezer: bool,
}

#[frb(opaque)]
#[derive(Debug, Clone)]
pub struct CLibrary {
    albums: HashMap<Uuid, Album>,
    artists: HashMap<Uuid, Artist>,
    songs: IndexMap<Uuid, CSong>,

    metadata_cache: MetadataCache,

    current_song: Option<Uuid>,
}

impl CLibrary {
    #[frb(sync)]
    pub fn new() -> Self {
        Self {
            albums: HashMap::new(),
            artists: HashMap::new(),
            songs: IndexMap::new(),
            metadata_cache: MetadataCache::new(),
            current_song: None,
        }
    }

    pub fn add_song(&mut self, config: &Config, path: &str) {
        extract_metadata(self, config, path);
    }

    #[frb(sync)]
    pub fn num_songs(&self) -> usize {
        return self.songs.len();
    }

    pub fn get_song_by_index(&self, index: usize) -> Option<CSongDart> {
        self.songs
            .get_index(index)
            .map(|(_, song)| song.clone().into())
    }

    pub fn get_song_by_id(&self, id: &str) -> Option<CSongDart> {
        if let Ok(uuid) = Uuid::try_parse(id) {
            if let Some(song) = self.songs.get(&uuid) {
                return Some(song.clone().into());
            }
        }

        None
    }

    #[frb(sync)]
    pub fn get_artist(&self, id: &str) -> Option<String> {
        if let Ok(uuid) = Uuid::parse_str(id) {
            Some(self.artists.get(&uuid).map(|a| a.name.clone())?)
        } else {
            error!("invalid id {id}");
            return None;
        }
    }

    #[frb(sync)]
    pub fn current_song(&self) -> Option<CSongDart> {
        if let Some(uuid) = self.current_song {
            if let Some(song) = self.songs.get(&uuid) {
                return Some(song.clone().into());
            }
        }

        None
    }

    pub fn play_song(&mut self, id: &str) -> Option<CSongDart> {
        if let Ok(uuid) = Uuid::try_parse(id) {
            if let Some(song) = self.songs.get(&uuid) {
                self.current_song = Some(uuid);
                return Some(song.clone().into());
            }
        }

        None
    }
}

fn handle_artist(artist_value: &Value, config: &Config, library: &mut CLibrary) -> ArtistGroup {
    let artist_name = match artist_value {
        Value::String(s) => Some(s),
        _ => None,
    };

    let leading_artist: Uuid;
    let mut features: Option<Vec<Uuid>> = None;

    if config.is_deezer {
        let artist_and_features: Option<Vec<Uuid>> = artist_name.map(|name| {
            name.split("/")
                .map(|a| get_artist_uuid(a, library))
                .collect()
        });

        match artist_and_features {
            Some(artists) if artists.len() > 1 => {
                leading_artist = *artists.first().unwrap();
                features = Some(artists.into_iter().skip(1).collect());
            }
            Some(artist) => {
                leading_artist = *artist.first().unwrap();
            }
            None => {
                leading_artist = get_artist_uuid(MISSING_ARTIST, library);
            }
        };
    } else {
        leading_artist = match artist_name {
            Some(name) => get_artist_uuid(&name, library),
            None => get_artist_uuid(MISSING_ARTIST, library),
        };
    }

    ArtistGroup {
        leading_artist,
        features,
    }
}

fn handle_album(album_value: &Value, album_artists: ArtistGroup, library: &mut CLibrary) -> Uuid {
    let parsed_album_name = match album_value {
        Value::String(name) => name.trim(),
        _ => panic!("unsupported value for album name"),
    };

    let mut album_uuid: Option<Uuid> = None;

    if let Some(albums) = library.metadata_cache.albums.get(&album_artists) {
        album_uuid = albums
            .iter()
            .find(|a| parsed_album_name == a.title.trim())
            .map(|album| album.id);
    }

    match album_uuid {
        Some(uuid) => return uuid,
        None => {
            let uuid = Uuid::new_v4();

            let album = Album {
                id: uuid,
                title: parsed_album_name.into(),
                artists: album_artists.clone(),
                songs: Vec::new(),
                cover: None,
            };

            library
                .metadata_cache
                .albums
                .entry(album_artists)
                .or_default()
                .push(album.clone());
            library.albums.insert(uuid, album);

            return uuid;
        }
    }
}

fn assign_album_cover(album: &Uuid, cover: CImage, library: &mut CLibrary) {
    if let Some(album) = library.albums.get_mut(album) {
        album.cover = Some(cover);
    }
}

fn get_artist_uuid(parsed_artist_name: &str, library: &mut CLibrary) -> Uuid {
    let artist_uuid = library
        .artists
        .iter()
        .find(|(_, artist)| artist.name.trim() == parsed_artist_name.trim())
        .map(|(_, artist)| artist.id);

    if let Some(uuid) = artist_uuid {
        return uuid;
    }

    let artist_uuid = Uuid::new_v4();
    let artist = Artist {
        id: artist_uuid,
        name: parsed_artist_name.trim().into(),
    };

    library.artists.insert(artist_uuid, artist);

    artist_uuid
}

pub fn extract_metadata(library: &mut CLibrary, config: &Config, path: &str) {
    let src = std::fs::File::open(path).expect("failed to open media");

    let mss = MediaSourceStream::new(Box::new(src), Default::default());
    let hint = Hint::new();
    let meta_opts: MetadataOptions = Default::default();
    let fmt_opts: FormatOptions = Default::default();

    let mut artists: Option<ArtistGroup> = None;
    let mut title: Option<String> = None;
    let mut track_num: Option<i64> = None;
    let mut disc_num: Option<i64> = None;
    let mut album: Option<Uuid> = None;
    let mut cover: Option<CImage> = None;

    let mut album_tag: Option<Value> = None;

    let probed = match symphonia::default::get_probe().format(&hint, mss, &fmt_opts, &meta_opts) {
        Ok(probe) => probe,
        Err(e) => {
            println!("failed to probe file for metadata for file {path}: {e:?}",);
            return;
        }
    };

    let mut probed_metadata = probed.metadata;

    if let Some(metadata) = probed_metadata.get() {
        if let Some(rev) = metadata.current() {
            for tag in rev.tags() {
                if let Some(std_key) = tag.std_key {
                    match std_key {
                        StandardTagKey::TrackTitle => {
                            if let Value::String(s) = &tag.value {
                                title = Some(s.clone());
                            }
                        }

                        StandardTagKey::DiscNumber => {
                            disc_num = tag_value_to_i64(&tag.value);
                        }

                        StandardTagKey::TrackNumber => {
                            track_num = tag_value_to_i64(&tag.value);
                        }

                        StandardTagKey::Artist => {
                            artists = Some(handle_artist(&tag.value, &config, library));
                        }
                        StandardTagKey::AlbumArtist => {
                            let album_artists = handle_artist(&tag.value, &config, library);

                            let album_tag_search = rev
                                .tags()
                                .iter()
                                .find(|tag| tag.std_key == Some(StandardTagKey::Album));

                            if let Some(tag) = album_tag_search {
                                handle_album(&tag.value, album_artists, library);
                            }
                        }

                        StandardTagKey::Album => {
                            album_tag = Some(tag.value.clone());
                        }
                        _ => {}
                    }
                }
            }

            if let Some(at) = album_tag {
                if album.is_none() {
                    if let Some(artist) = &artists {
                        album = Some(handle_album(&at, artist.clone(), library));
                    }
                }
            }

            cover = rev
                .visuals()
                .iter()
                .find(|visual| {
                    visual.usage == Some(symphonia::core::meta::StandardVisualKey::FrontCover)
                })
                .map(|cover| CImage {
                    data: cover.data.to_vec(),
                    mime_type: cover.media_type.clone(),
                });

            if let Some(album) = album {
                if let Some(cover) = &cover {
                    update_album_field(&album, AlbumField::Cover(cover.clone()), library);
                }
            }
        }
    }

    if artists.is_none() {
        artists = Some(handle_artist(
            &Value::String(MISSING_ARTIST.into()),
            &config,
            library,
        ));
    }

    if album.is_none() {
        album = Some(handle_album(
            &Value::String(MISSING_ALBUM.into()),
            artists.clone().unwrap(),
            library,
        ))
    }

    let song = CSong {
        id: Uuid::new_v4(),
        title: title.unwrap_or(MISSING_TITLE.into()),
        artists: artists.unwrap(),
        track_num: track_num.unwrap_or(1),
        disc_num: disc_num.unwrap_or(1),
        album: album.unwrap(),
        cover: None,
        path: PathBuf::from(path),
    };

    update_album_field(&song.album, AlbumField::Song(song.id), library);

    library.songs.insert(song.id, song.clone());

    info!("Parsed song with details {:?}", song);
}

enum AlbumField {
    Title(String),
    Artist(ArtistGroup),
    Cover(CImage),
    Song(Uuid),
}

fn update_album_field(album: &Uuid, field: AlbumField, library: &mut CLibrary) {
    match field {
        AlbumField::Title(title) => {
            if let Some(album) = library.albums.get_mut(album) {
                album.title = title;
            }
        }
        AlbumField::Artist(artist) => {
            if let Some(album) = library.albums.get_mut(album) {
                album.artists = artist;
            }
        }
        AlbumField::Cover(cover) => {
            if let Some(album) = library.albums.get_mut(album) {
                album.cover = Some(cover);
            }
        }
        AlbumField::Song(song) => {
            if let Some(album) = library.albums.get_mut(album) {
                album.songs.push(song);
            }
        }
    }
}

fn tag_value_to_i64(tag_val: &Value) -> Option<i64> {
    match tag_val {
        Value::SignedInt(i) => Some(*i),
        Value::UnsignedInt(u) => i64::try_from(*u).ok(),
        Value::String(s) => s.parse::<i64>().ok(),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{path::PathBuf, sync::Mutex};

    fn get_deezer_config() -> Config {
        Config { is_deezer: true }
    }

    #[test]
    fn parse_single_artist_tag() {
        let mut library = CLibrary::new();

        let tag = Tag::new(
            Some(StandardTagKey::Artist),
            "Artist",
            Value::String("A Single Artist".into()),
        );

        let artist = handle_artist(&tag.value, &get_deezer_config(), &mut library);

        let saved_artist = library
            .artists
            .values()
            .find(|a| a.name == tag.value.to_string());

        assert!(saved_artist.is_some());
        assert_eq!(saved_artist.unwrap().id, artist.leading_artist);
    }
}
