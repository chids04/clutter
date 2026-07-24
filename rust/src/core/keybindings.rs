use super::LibraryCore;
use crate::storage::sqlite::KeybindingRow;

impl LibraryCore {
    pub fn get_keybindings(&self) -> Result<Vec<KeybindingRow>, String> {
        self.store.get_keybindings()
    }

    pub fn update_keybinding(&self, binding: KeybindingRow) -> Result<KeybindingRow, String> {
        self.store.update_keybinding(binding)
    }

    pub fn reset_keybindings(&self) -> Result<Vec<KeybindingRow>, String> {
        self.store.reset_keybindings()
    }

    pub fn get_seek_step_seconds(&self) -> Result<u32, String> {
        self.store.get_seek_step_seconds()
    }

    pub fn update_seek_step_seconds(&self, seconds: u32) -> Result<u32, String> {
        self.store.update_seek_step_seconds(seconds)
    }
}
