use super::LibraryCore;
use crate::storage::sqlite::{PlaylistRow, SongRow};

impl LibraryCore {
    pub fn get_total_playlists(&self) -> u32 {
        self.store.get_total_playlists()
    }

    pub fn get_playlists_paginated(&self, offset: u32, limit: u32) -> Vec<PlaylistRow> {
        self.store.get_playlists_paginated(offset, limit)
    }

    pub fn get_songs_in_playlist(&self, playlist_id: &str) -> Vec<SongRow> {
        self.store.get_songs_in_playlist(playlist_id)
    }

    pub fn get_liked_song_ids(&self) -> Vec<String> {
        self.store.get_liked_song_ids()
    }

    pub fn get_liked_songs_playlist_id(&self) -> Option<String> {
        self.store.get_liked_songs_playlist_id()
    }

    pub fn create_playlist(&self, name: &str) -> Result<String, String> {
        self.store.create_playlist(name)
    }

    pub fn delete_playlist(&self, id: &str) -> Result<(), String> {
        self.store.delete_playlist(id)
    }

    pub fn add_song_to_playlist(&self, playlist_id: &str, song_id: &str) -> Result<(), String> {
        self.store.add_song_to_playlist(playlist_id, song_id)
    }

    pub fn remove_song_from_playlist(
        &self,
        playlist_id: &str,
        song_id: &str,
    ) -> Result<(), String> {
        self.store.remove_song_from_playlist(playlist_id, song_id)
    }

    pub fn search_playlists(&self, query: &str, limit: u32) -> Vec<PlaylistRow> {
        self.store.search_playlists(query, limit)
    }
}
