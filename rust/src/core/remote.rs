use super::LibraryCore;
use crate::remote::sftp::{SftpDownloadProgress, SftpEntry, SftpProfile};
use crate::storage::sqlite::{new_sftp_profile_id, SftpProfileRow};

impl LibraryCore {
    pub fn get_sftp_profiles(&self) -> Result<Vec<SftpProfile>, String> {
        self.store
            .get_sftp_profiles()
            .map(|rows| rows.into_iter().map(Into::into).collect())
    }

    pub fn save_sftp_profile(&self, mut profile: SftpProfile) -> Result<SftpProfile, String> {
        if profile.id.is_empty() {
            profile.id = new_sftp_profile_id();
        }
        self.store
            .save_sftp_profile(profile.clone().into())
            .map(Into::into)
    }

    pub fn delete_sftp_profile(&self, profile_id: &str) -> Result<(), String> {
        self.sftp.disconnect(profile_id)?;
        self.store.delete_sftp_profile(profile_id)
    }

    pub fn select_sftp_profile(&self, profile_id: &str) -> Result<(), String> {
        self.store.select_sftp_profile(profile_id)
    }

    pub fn probe_sftp_fingerprint(&self, host: &str, port: u16) -> Result<String, String> {
        self.sftp.probe_fingerprint(host, port)
    }

    pub fn connect_sftp(&self, profile_id: &str, password: String) -> Result<(), String> {
        let profile = self
            .get_sftp_profiles()?
            .into_iter()
            .find(|profile| profile.id == profile_id)
            .ok_or_else(|| "sftp profile not found".to_string())?;
        self.sftp.connect(profile, password)
    }

    pub fn test_sftp_connection(&self, profile: SftpProfile, password: &str) -> Result<(), String> {
        self.sftp.test_connection(&profile, password)
    }

    pub fn disconnect_sftp(&self, profile_id: &str) -> Result<(), String> {
        self.sftp.disconnect(profile_id)
    }

    pub fn browse_sftp(&self, profile_id: &str, relative: &str) -> Result<Vec<SftpEntry>, String> {
        let mut entries = self.sftp.browse(profile_id, relative)?;
        let paths = entries
            .iter()
            .map(|entry| entry.relative_path.clone())
            .collect::<Vec<_>>();
        let downloaded = self.store.sftp_downloaded_paths(profile_id, &paths)?;
        for entry in &mut entries {
            entry.downloaded = downloaded.contains(&entry.relative_path);
        }
        Ok(entries)
    }

    pub fn start_sftp_download(
        &self,
        profile_id: &str,
        relative_path: String,
        recursive: bool,
    ) -> Result<SftpDownloadProgress, String> {
        self.sftp.start_download(
            profile_id,
            relative_path,
            recursive,
            self.store.clone(),
            self.imports_dir.clone(),
        )
    }

    pub fn get_sftp_download_progress(&self, job_id: &str) -> Result<SftpDownloadProgress, String> {
        self.sftp.download_progress(job_id)
    }

    pub fn cancel_sftp_download(&self, job_id: &str) -> Result<(), String> {
        self.sftp.cancel_download(job_id)
    }

    pub fn remove_finished_sftp_download(&self, job_id: &str) {
        self.sftp.remove_finished_download(job_id);
    }
}

impl From<SftpProfileRow> for SftpProfile {
    fn from(value: SftpProfileRow) -> Self {
        Self {
            id: value.id,
            name: value.name,
            host: value.host,
            port: value.port,
            username: value.username,
            root_path: value.root_path,
            host_key_fingerprint: value.host_key_fingerprint,
            is_selected: value.is_selected,
        }
    }
}

impl From<SftpProfile> for SftpProfileRow {
    fn from(value: SftpProfile) -> Self {
        Self {
            id: value.id,
            name: value.name,
            host: value.host,
            port: value.port,
            username: value.username,
            root_path: value.root_path,
            host_key_fingerprint: value.host_key_fingerprint,
            is_selected: value.is_selected,
        }
    }
}
