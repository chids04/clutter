use super::paths::{child_relative_path, is_supported_audio_name, resolve_remote_path};
use super::{SftpEntry, SftpEntryKind, SftpProfile};
use anyhow::{anyhow, Context, Result};
use russh::keys::ssh_key::{HashAlg, PublicKey};
use russh::{client, ChannelId};
use russh_sftp::client::SftpSession;
use russh_sftp::protocol::FileType;
use std::sync::{Arc, Mutex};

pub struct SftpConnection {
    pub session: SftpSession,
    _ssh: client::Handle<HostKeyHandler>,
}

#[derive(Clone)]
struct HostKeyHandler {
    expected: Option<String>,
    observed: Arc<Mutex<Option<String>>>,
}

impl client::Handler for HostKeyHandler {
    type Error = anyhow::Error;

    async fn check_server_key(&mut self, key: &PublicKey) -> Result<bool, Self::Error> {
        let fingerprint = key.fingerprint(HashAlg::Sha256).to_string();
        if let Ok(mut observed) = self.observed.lock() {
            *observed = Some(fingerprint.clone());
        }
        Ok(self.expected.as_deref() == Some(fingerprint.as_str()))
    }

    async fn data(
        &mut self,
        _channel: ChannelId,
        _data: &[u8],
        _session: &mut client::Session,
    ) -> Result<(), Self::Error> {
        Ok(())
    }
}

pub async fn probe_fingerprint(host: &str, port: u16) -> Result<String> {
    let observed = Arc::new(Mutex::new(None));
    let handler = HostKeyHandler {
        expected: None,
        observed: observed.clone(),
    };
    let config = Arc::new(client::Config::default());
    let _ = client::connect(config, (host, port), handler).await;
    observed
        .lock()
        .ok()
        .and_then(|value| value.clone())
        .ok_or_else(|| anyhow!("could not read the server host key"))
}

pub async fn connect(profile: &SftpProfile, password: &str) -> Result<SftpConnection> {
    let observed = Arc::new(Mutex::new(None));
    let handler = HostKeyHandler {
        expected: Some(profile.host_key_fingerprint.clone()),
        observed,
    };
    let mut ssh = client::connect(
        Arc::new(client::Config::default()),
        (profile.host.as_str(), profile.port),
        handler,
    )
    .await
    .context("could not connect to the sftp server")?;
    let auth = ssh
        .authenticate_password(&profile.username, password)
        .await
        .context("sftp authentication failed")?;
    if !auth.success() {
        return Err(anyhow!("incorrect sftp username or password"));
    }
    let channel = ssh
        .channel_open_session()
        .await
        .context("could not open an ssh session")?;
    channel
        .request_subsystem(true, "sftp")
        .await
        .context("the server did not allow the sftp subsystem")?;
    let session = SftpSession::new(channel.into_stream())
        .await
        .context("could not initialise sftp")?;
    session.set_timeout(20);
    session
        .read_dir(&profile.root_path)
        .await
        .context("could not read the configured root directory")?;
    Ok(SftpConnection { session, _ssh: ssh })
}

pub async fn browse(
    connection: &SftpConnection,
    profile: &SftpProfile,
    relative: &str,
) -> Result<Vec<SftpEntry>> {
    let path = resolve_remote_path(&profile.root_path, relative).map_err(|error| anyhow!(error))?;
    let entries = connection
        .session
        .read_dir(path)
        .await
        .context("could not read the remote directory")?;
    let mut result = Vec::new();
    for entry in entries {
        let name = entry.file_name();
        let relative_path = child_relative_path(relative, &name).map_err(|error| anyhow!(error))?;
        let metadata = entry.metadata();
        let kind = match entry.file_type() {
            FileType::Dir => SftpEntryKind::Directory,
            FileType::File if is_supported_audio_name(&name) => SftpEntryKind::File,
            _ => SftpEntryKind::Unsupported,
        };
        result.push(SftpEntry {
            name,
            relative_path,
            kind,
            size: metadata.size,
            modified_at: metadata.mtime.map(i64::from),
            downloaded: false,
        });
    }
    result.sort_by(|left, right| {
        entry_rank(left.kind)
            .cmp(&entry_rank(right.kind))
            .then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
    });
    Ok(result)
}

fn entry_rank(kind: SftpEntryKind) -> u8 {
    match kind {
        SftpEntryKind::Directory => 0,
        SftpEntryKind::File => 1,
        SftpEntryKind::Unsupported => 2,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore = "needs SFTP_HOST, SFTP_USERNAME, SFTP_PASSWORD and SFTP_ROOT"]
    async fn live_server_connects_and_lists_the_root() {
        let host = std::env::var("SFTP_HOST").expect("SFTP_HOST");
        let username = std::env::var("SFTP_USERNAME").expect("SFTP_USERNAME");
        let password = std::env::var("SFTP_PASSWORD").expect("SFTP_PASSWORD");
        let root_path = std::env::var("SFTP_ROOT").expect("SFTP_ROOT");
        let port = std::env::var("SFTP_PORT")
            .ok()
            .and_then(|value| value.parse().ok())
            .unwrap_or(22);
        let fingerprint = probe_fingerprint(&host, port).await.expect("fingerprint");
        let profile = SftpProfile {
            id: "live-test".into(),
            name: "live test".into(),
            host,
            port,
            username,
            root_path,
            host_key_fingerprint: fingerprint,
            is_selected: true,
        };
        let connection = connect(&profile, &password).await.expect("connect");
        browse(&connection, &profile, "").await.expect("browse");
    }
}
