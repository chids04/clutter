use super::LibraryCore;
use crate::storage::sqlite::{AlbumRow, ArtistRow, SongRow};

impl LibraryCore {
    pub fn get_total_songs(&self) -> u32 {
        self.store.get_total_songs()
    }

    pub fn get_songs_paginated(&self, offset: u32, limit: u32) -> Vec<SongRow> {
        self.store.get_songs_paginated(offset, limit)
    }

    pub fn get_song_by_id(&self, id: &str) -> Option<SongRow> {
        self.store.get_song_by_id(id)
    }

    pub fn get_total_albums(&self) -> u32 {
        self.store.get_total_albums()
    }

    pub fn get_albums_paginated(&self, offset: u32, limit: u32) -> Vec<AlbumRow> {
        self.store.get_albums_paginated(offset, limit)
    }

    pub fn get_songs_by_album_id(&self, album_id: &str) -> Vec<SongRow> {
        self.store.get_songs_by_album_id(album_id)
    }

    pub fn split_album_to_new_artist(&self, album_id: &str) -> Result<String, String> {
        self.store.split_album_to_new_artist(album_id)
    }

    pub fn get_total_artists(&self) -> u32 {
        self.store.get_total_artists()
    }

    pub fn get_artists_paginated(&self, offset: u32, limit: u32) -> Vec<ArtistRow> {
        self.store.get_artists_paginated(offset, limit)
    }

    pub fn get_artist_by_id(&self, id: &str) -> Option<ArtistRow> {
        self.store.get_artist_by_id(id)
    }

    pub fn get_albums_by_artist_id(&self, artist_id: &str) -> Vec<AlbumRow> {
        self.store.get_albums_by_artist_id(artist_id)
    }

    pub fn get_albums_artist_featured_on(&self, artist_id: &str) -> Vec<AlbumRow> {
        self.store.get_albums_artist_featured_on(artist_id)
    }

    pub fn get_songs_artist_featured_on(&self, artist_id: &str) -> Vec<SongRow> {
        self.store.get_songs_artist_featured_on(artist_id)
    }

    pub fn search_artists(&self, query: &str, limit: u32) -> Vec<ArtistRow> {
        self.store.search_artists(query, limit)
    }

    pub fn search_songs(&self, query: &str, limit: u32) -> Vec<SongRow> {
        self.store.search_songs(query, limit)
    }

    pub fn search_albums(&self, query: &str, limit: u32) -> Vec<AlbumRow> {
        self.store.search_albums(query, limit)
    }

    pub fn delete_song(&self, id: &str) -> Result<(), String> {
        self.store.delete_song(id)
    }

    pub fn delete_album(&self, id: &str) -> Result<(), String> {
        self.store.delete_album(id)
    }

    pub fn delete_scan_path(&self, path: &str) -> Result<u32, String> {
        self.store.delete_scan_path(path)
    }

    pub fn get_scan_paths(&self) -> Vec<String> {
        self.store.get_scan_paths()
    }

    pub fn reset_library(&self) -> Result<(), String> {
        self.store.reset_library()
    }
}
