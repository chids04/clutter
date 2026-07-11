use super::LibraryCore;
use crate::storage::sqlite::{PinnedItemRow, PlaybackStateRow, SongRow};

impl LibraryCore {
    pub fn record_play(&self, song_id: &str) -> Result<(), String> {
        self.store.record_play(song_id)
    }

    pub fn get_recently_played(&self, limit: u32) -> Vec<SongRow> {
        self.store.get_recently_played(limit)
    }

    pub fn save_playback_state(
        &self,
        song_id: Option<&str>,
        position_ms: i64,
        loop_one: bool,
    ) -> Result<(), String> {
        self.store
            .save_playback_state(song_id, position_ms, loop_one)
    }

    pub fn load_playback_state(&self) -> Option<PlaybackStateRow> {
        self.store.load_playback_state()
    }

    pub fn pin_item(&self, item_id: &str, kind: &str) -> Result<(), String> {
        self.store.pin_item(item_id, kind)
    }

    pub fn unpin_item(&self, item_id: &str, kind: &str) -> Result<(), String> {
        self.store.unpin_item(item_id, kind)
    }

    pub fn get_pinned_items(&self) -> Vec<PinnedItemRow> {
        self.store.get_pinned_items()
    }

    pub fn move_pinned_item(
        &self,
        item_id: &str,
        kind: &str,
        new_index: usize,
    ) -> Result<(), String> {
        self.store.move_pinned_item(item_id, kind, new_index)
    }
}
