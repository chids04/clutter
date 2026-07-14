use super::LibraryCore;
use crate::storage::sqlite::{ExtractedSongImport, SongRow};

impl LibraryCore {
    pub fn import_extracted_song(&self, request: ExtractedSongImport) -> Result<SongRow, String> {
        self.store
            .import_extracted_song(request, &self.imports_dir, &self.originals_dir)
    }
}
