use std::path::PathBuf;
use std::sync::Arc;

use anyhow;
use log::{error, info};
use russh::client::Handle;
use russh::{client, keys::ssh_key, ChannelId};
use russh_sftp::protocol::OpenFlags;
use russh_sftp::{client::SftpSession, protocol::FileType};
use tokio::io::{AsyncReadExt, AsyncSeekExt, AsyncWriteExt};

struct Csftp {
    client: Handle<Client>,
    init_dir: PathBuf,
    entries: Vec<CsftpEntry>,
}

struct CsftpEntry {
    file_name: String,
    path: String,
    file_type: FileType,
}

// when initiating this frontend gets a csftp client object they init,
// the should pass a directory that you want to init the connection with

struct Client;
impl client::Handler for Client {
    type Error = anyhow::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &ssh_key::PublicKey,
    ) -> Result<bool, Self::Error> {
        info!("check_server_key: {server_public_key:?}");
        Ok(true)
    }

    async fn data(
        &mut self,
        channel: ChannelId,
        data: &[u8],
        _session: &mut client::Session,
    ) -> Result<(), Self::Error> {
        info!("data on channel {:?}: {}", channel, data.len());
        Ok(())
    }
}

async fn init_session(ip_addr: &str, music_path: String) {
    let config = russh::client::Config::default();
    let sh = Client {};

    let mut session = russh::client::connect(Arc::new(config), (ip_addr, 22), sh)
        .await
        .unwrap();
    if session
        .authenticate_password("root", "password")
        .await
        .unwrap()
        .success()
    {
        let channel = session.channel_open_session().await.unwrap();
        channel.request_subsystem(true, "sftp").await.unwrap();
        let sftp = SftpSession::new(channel.into_stream()).await.unwrap();
        info!("current path: {:?}", sftp.canonicalize(".").await.unwrap());

        // create dir and symlink
        let path = "./some_kind_of_dir";
        let symlink = "./symlink";

        sftp.create_dir(path).await.unwrap();
        sftp.symlink(path, symlink).await.unwrap();

        info!("dir info: {:?}", sftp.metadata(path).await.unwrap());
        info!(
            "symlink info: {:?}",
            sftp.symlink_metadata(path).await.unwrap()
        );

        let music_dir = match sftp.read_dir(music_path).await {
            Ok(dir) => dir,
            Err(e) => {
                error!("sftp: failed to read directory {path} reason: {e}");
                return;
            }
        };

        // scanning directory
        for entry in music_dir {
            info!("file in directory: {:?}", entry.file_name());

            let csftp_entry = match entry.file_type() {
                FileType::File | FileType::Dir => CsftpEntry {
                    path: entry.path(),
                    file_name: entry.file_name(),
                    file_type: entry.file_type(),
                },
                _ => {
                    info!("unsupported file type {} skipping", entry.file_name());
                    return;
                }
            };
        }

        // interaction with i/o
        let filename = "test_new.txt";
        let mut file = sftp
            .open_with_flags(
                filename,
                OpenFlags::CREATE | OpenFlags::TRUNCATE | OpenFlags::WRITE | OpenFlags::READ,
            )
            .await
            .unwrap();
        info!("metadata by handle: {:?}", file.metadata().await.unwrap());

        file.write_all(b"magic text").await.unwrap();
        info!("flush: {:?}", file.flush().await); // or file.sync_all()
        info!(
            "current cursor position: {:?}",
            file.stream_position().await
        );

        let mut str = String::new();

        file.rewind().await.unwrap();
        file.read_to_string(&mut str).await.unwrap();
        file.rewind().await.unwrap();

        info!(
            "our magical contents: {}, after rewind: {:?}",
            str,
            file.stream_position().await
        );

        file.shutdown().await.unwrap();
        sftp.remove_file(filename).await.unwrap();

        // should fail because handle was closed
        error!("should fail: {:?}", file.read_u8().await);
    }
}
