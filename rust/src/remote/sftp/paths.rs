use std::path::{Path, PathBuf};
use uuid::Uuid;

const AUDIO_EXTENSIONS: &[&str] = &["mp3", "flac", "m4a", "mp4", "ogg", "opus", "wav"];

pub fn resolve_remote_path(root: &str, relative: &str) -> Result<String, String> {
    if !root.starts_with('/') {
        return Err("sftp root path must be absolute".into());
    }
    if relative.starts_with('/') {
        return Err("remote path must be relative to the configured root".into());
    }
    let mut parts = Vec::new();
    for part in relative.split('/') {
        match part {
            "" | "." => {}
            ".." => return Err("remote path cannot leave the configured root".into()),
            value => parts.push(value),
        }
    }
    let root = root.trim_end_matches('/');
    if parts.is_empty() {
        return Ok(if root.is_empty() {
            "/".into()
        } else {
            root.into()
        });
    }
    Ok(format!("{}/{}", root, parts.join("/")))
}

pub fn child_relative_path(parent: &str, name: &str) -> Result<String, String> {
    if name.is_empty() || name == "." || name == ".." || name.contains('/') {
        return Err("server returned an unsafe file name".into());
    }
    Ok(if parent.is_empty() {
        name.to_string()
    } else {
        format!("{}/{}", parent.trim_end_matches('/'), name)
    })
}

pub fn is_supported_audio_name(name: &str) -> bool {
    name.rsplit_once('.')
        .map(|(_, extension)| extension.to_ascii_lowercase())
        .is_some_and(|value| AUDIO_EXTENSIONS.contains(&value.as_str()))
}

pub fn local_download_path(imports: &Path, profile_id: &str, relative: &str) -> PathBuf {
    let mut parts = relative
        .split('/')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>();
    let file_name = parts.pop().unwrap_or("audio.mp3");
    let (stem, extension) = file_name.rsplit_once('.').unwrap_or((file_name, "mp3"));
    let mut destination = imports.join("sftp").join(safe_name(profile_id));
    for part in parts {
        destination = destination.join(safe_name(part));
    }
    destination.join(format!(
        "{}-{}.{}",
        safe_name(stem),
        Uuid::new_v4(),
        safe_name(extension)
    ))
}

pub fn cleanup_partial_downloads(imports: &Path) {
    let root = imports.join("sftp");
    if !root.exists() {
        return;
    }
    for entry in walkdir::WalkDir::new(root)
        .into_iter()
        .filter_map(Result::ok)
    {
        let path = entry.path();
        let name = path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("");
        if entry.file_type().is_file() && name.starts_with('.') && name.ends_with(".partial") {
            let _ = std::fs::remove_file(path);
        }
    }
}

fn safe_name(value: &str) -> String {
    let safe = value
        .chars()
        .map(|character| match character {
            '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' => '_',
            value if value.is_control() => '_',
            value => value,
        })
        .take(100)
        .collect::<String>();
    let safe = safe.trim().trim_matches('.');
    if safe.is_empty() {
        "item".into()
    } else {
        safe.into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remote_paths_are_confined_to_the_profile_root() {
        assert_eq!(
            resolve_remote_path("/music", "albums/a").unwrap(),
            "/music/albums/a"
        );
        assert!(resolve_remote_path("/music", "../private").is_err());
        assert!(resolve_remote_path("/music", "/etc/passwd").is_err());
    }

    #[test]
    fn duplicate_destinations_are_unique_and_keep_the_extension() {
        let base = Path::new("/tmp/imports");
        let first = local_download_path(base, "home", "album/song.flac");
        let second = local_download_path(base, "home", "album/song.flac");
        assert_ne!(first, second);
        assert_eq!(
            first.extension().and_then(|value| value.to_str()),
            Some("flac")
        );
        assert!(first.starts_with("/tmp/imports/sftp/home/album"));
    }

    #[test]
    fn windows_separators_in_remote_names_cannot_escape_imports() {
        let base = Path::new("/tmp/imports");
        let destination = local_download_path(base, "home", r"album/..\evil.mp3");
        assert!(destination.starts_with("/tmp/imports/sftp/home/album"));
        assert!(destination
            .file_name()
            .unwrap()
            .to_string_lossy()
            .starts_with("_evil-"));
    }
}
