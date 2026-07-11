use super::LibraryCore;
use crate::storage::sqlite::{
    AlbumMetadataUpdate, AlbumRow, ArtistRow, ArtworkUpdate, PlaylistRow, PlaylistVisualUpdate,
    SongMetadataUpdate, SongRow,
};

impl LibraryCore {
    pub fn update_song_metadata(&self, update: SongMetadataUpdate) -> Result<SongRow, String> {
        self.store.update_song_metadata(update)
    }

    pub fn update_album_metadata(&self, update: AlbumMetadataUpdate) -> Result<AlbumRow, String> {
        self.store.update_album_metadata(update)
    }

    pub fn update_artist_image(
        &self,
        artist_id: &str,
        artwork: ArtworkUpdate,
    ) -> Result<ArtistRow, String> {
        self.store.update_artist_image(artist_id, artwork)
    }

    pub fn update_playlist_metadata(
        &self,
        playlist_id: &str,
        name: &str,
        visual: PlaylistVisualUpdate,
    ) -> Result<PlaylistRow, String> {
        self.store
            .update_playlist_metadata(playlist_id, name, visual)
    }
}
