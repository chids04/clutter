use crate::scan::{scan_directory, ScanOptions};
use crate::storage::sqlite::SqliteLibraryStore;
use std::path::PathBuf;
use std::sync::Arc;

mod catalog;
mod editing;
mod imports;
mod keybindings;
mod playback;
mod playlists;
mod remote;

pub struct LibraryCore {
    store: Arc<SqliteLibraryStore>,
    imports_dir: PathBuf,
    originals_dir: PathBuf,
    sftp: crate::remote::sftp::SftpService,
}

impl LibraryCore {
    pub fn open(db_path: &str, covers_dir: &str, base_dir: &str) -> Result<Self, String> {
        let store = Arc::new(SqliteLibraryStore::open(db_path, covers_dir, base_dir)?);
        let imports_dir = PathBuf::from(base_dir).join("Music").join("imports");
        let originals_dir = PathBuf::from(base_dir).join("Music").join("originals");
        crate::remote::sftp::cleanup_partial_downloads(&imports_dir);
        let sftp = crate::remote::sftp::SftpService::new()?;
        Ok(Self {
            store,
            imports_dir,
            originals_dir,
            sftp,
        })
    }

    pub fn scan_directory(&self, path: &str, is_deezer: bool) -> Result<(), String> {
        scan_directory(&self.store, path, ScanOptions { is_deezer })
    }
}
