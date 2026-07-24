mod client;
mod jobs;
mod paths;

pub use jobs::SftpService;
pub use paths::cleanup_partial_downloads;
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SftpProfile {
    pub id: String,
    pub name: String,
    pub host: String,
    pub port: u16,
    pub username: String,
    pub root_path: String,
    pub host_key_fingerprint: String,
    pub is_selected: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SftpEntryKind {
    File,
    Directory,
    Unsupported,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SftpEntry {
    pub name: String,
    pub relative_path: String,
    pub kind: SftpEntryKind,
    pub size: Option<u64>,
    pub modified_at: Option<i64>,
    pub downloaded: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SftpDownloadState {
    Discovering,
    Downloading,
    Importing,
    Completed,
    CompletedWithErrors,
    Cancelled,
    Failed,
}

impl SftpDownloadState {
    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            Self::Completed | Self::CompletedWithErrors | Self::Cancelled | Self::Failed
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SftpDownloadProgress {
    pub job_id: String,
    pub state: SftpDownloadState,
    pub current_name: Option<String>,
    pub files_completed: u32,
    pub files_total: u32,
    pub bytes_completed: u64,
    pub bytes_total: u64,
    pub failed_files: u32,
    pub message: Option<String>,
}

impl SftpDownloadProgress {
    fn new(job_id: String) -> Self {
        Self {
            job_id,
            state: SftpDownloadState::Discovering,
            current_name: None,
            files_completed: 0,
            files_total: 0,
            bytes_completed: 0,
            bytes_total: 0,
            failed_files: 0,
            message: None,
        }
    }
}
