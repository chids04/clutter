use super::client::{self, SftpConnection};
use super::paths::{is_supported_audio_name, local_download_path, resolve_remote_path};
use super::{SftpDownloadProgress, SftpDownloadState, SftpEntryKind, SftpProfile};
use crate::scan::{index_audio_file, ScanOptions};
use crate::storage::sqlite::{SftpDownloadRow, SqliteLibraryStore};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::runtime::Runtime;
use uuid::Uuid;
use zeroize::Zeroizing;

struct ConnectedProfile {
    profile: SftpProfile,
    password: Zeroizing<String>,
    connection: SftpConnection,
}

struct DownloadJob {
    progress: Mutex<SftpDownloadProgress>,
    cancel: AtomicBool,
}

#[derive(Clone)]
struct RemoteFile {
    relative_path: String,
    size: Option<u64>,
    modified_at: Option<i64>,
}

pub struct SftpService {
    runtime: Runtime,
    connections: Mutex<HashMap<String, ConnectedProfile>>,
    jobs: Arc<Mutex<HashMap<String, Arc<DownloadJob>>>>,
}

impl SftpService {
    pub fn new() -> Result<Self, String> {
        let runtime = Runtime::new().map_err(|error| format!("start sftp runtime: {error}"))?;
        Ok(Self {
            runtime,
            connections: Mutex::new(HashMap::new()),
            jobs: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    pub fn probe_fingerprint(&self, host: &str, port: u16) -> Result<String, String> {
        self.runtime
            .block_on(client::probe_fingerprint(host, port))
            .map_err(|error| error.to_string())
    }

    pub fn connect(&self, profile: SftpProfile, password: String) -> Result<(), String> {
        let connection = self
            .runtime
            .block_on(client::connect(&profile, &password))
            .map_err(|error| error.to_string())?;
        let state = ConnectedProfile {
            profile: profile.clone(),
            password: Zeroizing::new(password),
            connection,
        };
        self.connections
            .lock()
            .map_err(|error| format!("lock sftp connections: {error}"))?
            .insert(profile.id, state);
        Ok(())
    }

    pub fn test_connection(&self, profile: &SftpProfile, password: &str) -> Result<(), String> {
        self.runtime
            .block_on(client::connect(profile, password))
            .map(|_| ())
            .map_err(|error| error.to_string())
    }

    pub fn disconnect(&self, profile_id: &str) -> Result<(), String> {
        self.connections
            .lock()
            .map_err(|error| format!("lock sftp connections: {error}"))?
            .remove(profile_id);
        Ok(())
    }

    pub fn browse(
        &self,
        profile_id: &str,
        relative: &str,
    ) -> Result<Vec<super::SftpEntry>, String> {
        let connections = self
            .connections
            .lock()
            .map_err(|error| format!("lock sftp connections: {error}"))?;
        let state = connections
            .get(profile_id)
            .ok_or_else(|| "sftp profile is not connected".to_string())?;
        self.runtime
            .block_on(client::browse(&state.connection, &state.profile, relative))
            .map_err(|error| error.to_string())
    }

    pub fn search(
        &self,
        profile_id: &str,
        relative: &str,
        query: &str,
        limit: usize,
    ) -> Result<Vec<super::SftpEntry>, String> {
        let connections = self
            .connections
            .lock()
            .map_err(|error| format!("lock sftp connections: {error}"))?;
        let state = connections
            .get(profile_id)
            .ok_or_else(|| "sftp profile is not connected".to_string())?;
        self.runtime
            .block_on(client::search(
                &state.connection,
                &state.profile,
                relative,
                query,
                limit,
            ))
            .map_err(|error| error.to_string())
    }

    pub fn start_download(
        &self,
        profile_id: &str,
        relative_path: String,
        recursive: bool,
        store: Arc<SqliteLibraryStore>,
        imports_dir: PathBuf,
    ) -> Result<SftpDownloadProgress, String> {
        let (profile, password) = self.connection_details(profile_id)?;
        let job_id = Uuid::new_v4().to_string();
        let job = Arc::new(DownloadJob {
            progress: Mutex::new(SftpDownloadProgress::new(job_id.clone())),
            cancel: AtomicBool::new(false),
        });
        self.jobs
            .lock()
            .map_err(|error| format!("lock sftp jobs: {error}"))?
            .insert(job_id, job.clone());
        let initial = job.progress.lock().unwrap().clone();
        self.runtime.spawn(run_download(
            job,
            profile,
            password,
            relative_path,
            recursive,
            store,
            imports_dir,
        ));
        Ok(initial)
    }

    pub fn download_progress(&self, job_id: &str) -> Result<SftpDownloadProgress, String> {
        let jobs = self
            .jobs
            .lock()
            .map_err(|error| format!("lock sftp jobs: {error}"))?;
        let job = jobs
            .get(job_id)
            .ok_or_else(|| "sftp download job not found".to_string())?;
        job.progress
            .lock()
            .map_err(|error| format!("lock sftp progress: {error}"))
            .map(|progress| progress.clone())
    }

    pub fn cancel_download(&self, job_id: &str) -> Result<(), String> {
        let jobs = self
            .jobs
            .lock()
            .map_err(|error| format!("lock sftp jobs: {error}"))?;
        let job = jobs
            .get(job_id)
            .ok_or_else(|| "sftp download job not found".to_string())?;
        job.cancel.store(true, Ordering::Relaxed);
        Ok(())
    }

    pub fn remove_finished_download(&self, job_id: &str) {
        let Ok(mut jobs) = self.jobs.lock() else {
            return;
        };
        let terminal = jobs
            .get(job_id)
            .and_then(|job| job.progress.lock().ok())
            .is_some_and(|progress| progress.state.is_terminal());
        if terminal {
            jobs.remove(job_id);
        }
    }

    fn connection_details(&self, profile_id: &str) -> Result<(SftpProfile, String), String> {
        let connections = self
            .connections
            .lock()
            .map_err(|error| format!("lock sftp connections: {error}"))?;
        let state = connections
            .get(profile_id)
            .ok_or_else(|| "sftp profile is not connected".to_string())?;
        Ok((profile_clone(&state.profile), state.password.to_string()))
    }
}

async fn run_download(
    job: Arc<DownloadJob>,
    profile: SftpProfile,
    password: String,
    relative_path: String,
    recursive: bool,
    store: Arc<SqliteLibraryStore>,
    imports_dir: PathBuf,
) {
    let result = run_download_inner(
        &job,
        &profile,
        &password,
        &relative_path,
        recursive,
        &store,
        &imports_dir,
    )
    .await;
    if let Err(error) = result {
        finish_with_error(&job, error);
    }
}

async fn run_download_inner(
    job: &DownloadJob,
    profile: &SftpProfile,
    password: &str,
    relative_path: &str,
    recursive: bool,
    store: &SqliteLibraryStore,
    imports_dir: &Path,
) -> Result<(), String> {
    let connection = client::connect(profile, password)
        .await
        .map_err(|error| error.to_string())?;
    let files = discover_files(&connection, profile, relative_path, recursive).await?;
    set_totals(job, &files);
    for file in files {
        if job.cancel.load(Ordering::Relaxed) {
            set_state(job, SftpDownloadState::Cancelled, None);
            return Ok(());
        }
        if let Err(error) =
            transfer_and_import(job, &connection, profile, &file, store, imports_dir).await
        {
            record_file_failure(job, error);
        }
    }
    finish_download(job);
    Ok(())
}

async fn discover_files(
    connection: &SftpConnection,
    profile: &SftpProfile,
    relative_path: &str,
    recursive: bool,
) -> Result<Vec<RemoteFile>, String> {
    if !recursive {
        if !is_supported_audio_name(relative_path) {
            return Err("only supported audio files can be downloaded".into());
        }
        let absolute = resolve_remote_path(&profile.root_path, relative_path)?;
        let metadata = connection
            .session
            .metadata(absolute)
            .await
            .map_err(|error| format!("read remote file metadata: {error}"))?;
        return Ok(vec![RemoteFile {
            relative_path: relative_path.into(),
            size: metadata.size,
            modified_at: metadata.mtime.map(i64::from),
        }]);
    }
    discover_directory(connection, profile, relative_path).await
}

async fn discover_directory(
    connection: &SftpConnection,
    profile: &SftpProfile,
    root: &str,
) -> Result<Vec<RemoteFile>, String> {
    let mut directories = vec![root.to_string()];
    let mut files = Vec::new();
    while let Some(directory) = directories.pop() {
        let entries = client::browse(connection, profile, &directory)
            .await
            .map_err(|error| error.to_string())?;
        for entry in entries {
            match entry.kind {
                SftpEntryKind::Directory => directories.push(entry.relative_path),
                SftpEntryKind::File => files.push(RemoteFile {
                    relative_path: entry.relative_path,
                    size: entry.size,
                    modified_at: entry.modified_at,
                }),
                SftpEntryKind::Unsupported => {}
            }
        }
    }
    files.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
    Ok(files)
}

async fn transfer_and_import(
    job: &DownloadJob,
    connection: &SftpConnection,
    profile: &SftpProfile,
    file: &RemoteFile,
    store: &SqliteLibraryStore,
    imports_dir: &Path,
) -> Result<(), String> {
    update_current(job, SftpDownloadState::Downloading, &file.relative_path);
    let destination = local_download_path(imports_dir, &profile.id, &file.relative_path);
    let partial = partial_path(&destination);
    if let Some(parent) = destination.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|error| format!("create download directory: {error}"))?;
    }
    let result = copy_remote_file(job, connection, profile, file, &partial).await;
    if let Err(error) = result {
        let _ = tokio::fs::remove_file(&partial).await;
        return Err(error);
    }
    tokio::fs::rename(&partial, &destination)
        .await
        .map_err(|error| format!("finish download: {error}"))?;
    update_current(job, SftpDownloadState::Importing, &file.relative_path);
    import_download(profile, file, store, &destination).inspect_err(|_| {
        let _ = fs::remove_file(&destination);
    })?;
    mark_file_complete(job);
    Ok(())
}

async fn copy_remote_file(
    job: &DownloadJob,
    connection: &SftpConnection,
    profile: &SftpProfile,
    file: &RemoteFile,
    partial: &Path,
) -> Result<(), String> {
    let absolute = resolve_remote_path(&profile.root_path, &file.relative_path)?;
    let mut remote = connection
        .session
        .open(absolute)
        .await
        .map_err(|error| format!("open remote file: {error}"))?;
    let mut local = tokio::fs::File::create(partial)
        .await
        .map_err(|error| format!("create partial download: {error}"))?;
    let mut buffer = vec![0_u8; 64 * 1024];
    loop {
        if job.cancel.load(Ordering::Relaxed) {
            return Err("download cancelled".into());
        }
        let read = remote
            .read(&mut buffer)
            .await
            .map_err(|error| format!("read remote file: {error}"))?;
        if read == 0 {
            break;
        }
        local
            .write_all(&buffer[..read])
            .await
            .map_err(|error| format!("write partial download: {error}"))?;
        add_downloaded_bytes(job, read as u64);
    }
    local
        .flush()
        .await
        .map_err(|error| format!("flush partial download: {error}"))
}

fn import_download(
    profile: &SftpProfile,
    file: &RemoteFile,
    store: &SqliteLibraryStore,
    destination: &Path,
) -> Result<(), String> {
    let song = index_audio_file(store, destination, ScanOptions { is_deezer: true })?;
    let song_id = song.id;
    let record = store.record_sftp_download(SftpDownloadRow {
        id: Uuid::new_v4().to_string(),
        profile_id: profile.id.clone(),
        remote_path: file.relative_path.clone(),
        remote_size: file.size,
        remote_mtime: file.modified_at,
        song_id: song_id.clone(),
    });
    if let Err(error) = record {
        let _ = store.delete_song(&song_id);
        return Err(error);
    }
    Ok(())
}

fn partial_path(destination: &Path) -> PathBuf {
    let name = destination
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or("audio");
    destination.with_file_name(format!(".{name}.partial"))
}

fn set_totals(job: &DownloadJob, files: &[RemoteFile]) {
    if let Ok(mut progress) = job.progress.lock() {
        progress.files_total = files.len() as u32;
        progress.bytes_total = if files.iter().all(|file| file.size.is_some()) {
            files.iter().filter_map(|file| file.size).sum()
        } else {
            0
        };
        progress.state = SftpDownloadState::Downloading;
    }
}

fn update_current(job: &DownloadJob, state: SftpDownloadState, name: &str) {
    if let Ok(mut progress) = job.progress.lock() {
        progress.state = state;
        progress.current_name = Some(name.to_string());
    }
}

fn add_downloaded_bytes(job: &DownloadJob, bytes: u64) {
    if let Ok(mut progress) = job.progress.lock() {
        progress.bytes_completed = progress.bytes_completed.saturating_add(bytes);
    }
}

fn mark_file_complete(job: &DownloadJob) {
    if let Ok(mut progress) = job.progress.lock() {
        progress.files_completed += 1;
    }
}

fn record_file_failure(job: &DownloadJob, error: String) {
    if let Ok(mut progress) = job.progress.lock() {
        if error == "download cancelled" {
            progress.state = SftpDownloadState::Cancelled;
        } else {
            progress.failed_files += 1;
            progress.message = Some(error);
        }
    }
}

fn finish_download(job: &DownloadJob) {
    if let Ok(mut progress) = job.progress.lock() {
        if progress.state == SftpDownloadState::Cancelled {
            return;
        }
        progress.current_name = None;
        progress.state = if progress.failed_files == 0 {
            SftpDownloadState::Completed
        } else {
            SftpDownloadState::CompletedWithErrors
        };
    }
}

fn finish_with_error(job: &DownloadJob, error: String) {
    if let Ok(mut progress) = job.progress.lock() {
        progress.state = SftpDownloadState::Failed;
        progress.message = Some(error);
    }
}

fn set_state(job: &DownloadJob, state: SftpDownloadState, message: Option<String>) {
    if let Ok(mut progress) = job.progress.lock() {
        progress.state = state;
        progress.message = message;
    }
}

fn profile_clone(profile: &SftpProfile) -> SftpProfile {
    profile.clone()
}
