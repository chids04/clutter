use crate::scan::{scan_directory, ScanOptions};
use crate::storage::sqlite::SqliteLibraryStore;

mod catalog;
mod editing;
mod keybindings;
mod playback;
mod playlists;

pub struct LibraryCore {
    store: SqliteLibraryStore,
}

impl LibraryCore {
    pub fn open(db_path: &str, covers_dir: &str, base_dir: &str) -> Result<Self, String> {
        let store = SqliteLibraryStore::open(db_path, covers_dir, base_dir)?;
        Ok(Self { store })
    }

    pub fn scan_directory(&self, path: &str, is_deezer: bool) -> Result<(), String> {
        scan_directory(&self.store, path, ScanOptions { is_deezer })
    }
}
