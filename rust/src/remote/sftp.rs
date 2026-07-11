#![allow(dead_code)]

use std::sync::Arc;

use anyhow;
use log::{error, info};
use russh::{client, keys::ssh_key, ChannelId};
use russh_sftp::{client::SftpSession, protocol::FileType};

use anyhow::*;

struct Csftp {
    session: SftpSession,
    init_dir: String,
    entries: Vec<CsftpEntry>,
}

struct CsftpEntry {
    file_name: String,
    path: String,
    file_type: FileType,
    downloaded: bool,
}

// when initiating this frontend gets a csftp client object they init,
// the should pass a directory that you want to init the connection with

// plan, we should be able to view a list of file system entries
// should show a simple 'maybe downloaded' icon to indicate that this may be saved
// files are downloaded, folders should be downloadable or allow u to navigate inside of them

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

async fn init_session(
    ip_addr: &str,
    music_path: &str,
    username: &str,
    password: &str,
) -> Result<Csftp> {
    let config = russh::client::Config::default();
    let sh = Client {};

    let mut session = russh::client::connect(Arc::new(config), (ip_addr, 22), sh)
        .await
        .context("SSH Connection failed, check the IP")?;

    session
        .authenticate_password(username, password)
        .await
        .context("Incorrect username and password")?;

    // this can fail, send to ui needs to know about this
    let channel = session.channel_open_session().await.map_err(|e| {
        error!("Failed to open SSH session: {e}");
        anyhow!("Failed to open SFTP session, please try again")
    })?;

    channel.request_subsystem(true, "sftp").await.map_err(|e| {
        error!("Failed to open request subsystem: {e}");
        anyhow!("Failed to open SFTP session, please try again")
    })?;

    let sftp = SftpSession::new(channel.into_stream()).await.map_err(|e| {
        error!("Failed to create SFTP session: {e}");
        anyhow!("Failed to open SFTP session, please try again")
    })?;

    //info!("current path: {:?}", sftp.canonicalize(".").await.unwrap());

    // create dir and symlink
    // let path = "./some_kind_of_dir";
    // let symlink = "./symlink";
    //
    // sftp.create_dir(path).await.unwrap();
    // sftp.symlink(path, symlink).await.unwrap();
    //
    // info!("dir info: {:?}", sftp.metadata(path).await.unwrap());
    // info!(
    //     "symlink info: {:?}",
    //     sftp.symlink_metadata(path).await.unwrap()
    // );

    // this can fail too
    let music_dir = sftp.read_dir(music_path).await.map_err(|e| {
        error!("Failed to read directory: {e}");
        anyhow!("Failed to read initial directroy, please try again later")
    })?;

    let mut init_items = Vec::new();

    // scanning directory
    for entry in music_dir {
        info!("file in directory: {:?}", entry.file_name());

        let csftp_entry = match entry.file_type() {
            FileType::File | FileType::Dir => CsftpEntry {
                path: entry.path(),
                file_name: entry.file_name(),
                file_type: entry.file_type(),
                downloaded: false,
            },
            _ => {
                info!("unsupported file type {} skipping", entry.file_name());
                continue;
            }
        };

        init_items.push(csftp_entry);
    }

    let csftp = Csftp {
        session: sftp,
        init_dir: music_path.to_string(),
        entries: init_items,
    };

    Ok(csftp)

    // interaction with i/o
    // let filename = "test_new.txt";
    // let mut file = sftp
    //     .open_with_flags(
    //         filename,
    //         openflags::create | openflags::truncate | openflags::write | openflags::read,
    //     )
    //     .await
    //     .unwrap();
    // info!("metadata by handle: {:?}", file.metadata().await.unwrap());
    //
    // file.write_all(b"magic text").await.unwrap();
    // info!("flush: {:?}", file.flush().await); // or file.sync_all()
    // info!(
    //     "current cursor position: {:?}",
    //     file.stream_position().await
    // );
    //
    // let mut str = string::new();
    //
    // file.rewind().await.unwrap();
    // file.read_to_string(&mut str).await.unwrap();
    // file.rewind().await.unwrap();
    //
    // info!(
    //     "our magical contents: {}, after rewind: {:?}",
    //     str,
    //     file.stream_position().await
    // );
    //
    // file.shutdown().await.unwrap();
    // sftp.remove_file(filename).await.unwrap();
    //
    // // should fail because handle was closed
    // error!("should fail: {:?}", file.read_u8().await);
}

#[cfg(test)]
mod tests {
    use super::init_session;

    #[tokio::test]
    #[ignore = "needs a live sftp host"]
    async fn start_session() {
        let ip_addr = "100.92.4.57";
        let music_path = "/home/c/docker/deemix/downloads";

        let cstfp = init_session(ip_addr, music_path, "test", "test").await;

        assert!(cstfp.is_ok());
    }
}
