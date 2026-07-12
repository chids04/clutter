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
}
