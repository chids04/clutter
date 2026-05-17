use std::path::Path;

use flutter_rust_bridge::frb;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::{
    MetadataOptions, StandardTagKey, StandardVisualKey, Tag, Value, Visual,
};
use symphonia::core::probe::Hint;

pub const MISSING_ARTIST: &str = "Unknown Artist";
pub const MISSING_TITLE: &str = "Unknown Title";
pub const MISSING_ALBUM: &str = "Unknown Album";

/// Parsed tags from a single file, before any DB interaction.
#[frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawMetadata {
    pub title: Option<String>,
    pub album: Option<String>,
    pub leading_artist: Option<String>,
    pub album_artist: Option<String>,
    pub track_num: Option<i64>,
    pub disc_num: Option<i64>,
    pub cover: Option<RawCover>,
}

#[frb(ignore)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RawCover {
    pub data: Vec<u8>,
    pub mime_type: String,
}

/// Split a raw artist tag value into `(leading, features)`. When
/// `is_deezer` is set, the tag is expected to use `/` as the separator
/// between the leading artist and any featured artists (the Deezer
/// convention). Otherwise the whole string is treated as a single name.
#[frb(ignore)]
pub fn parse_artist_string(raw: &str, is_deezer: bool) -> (String, Vec<String>) {
    if is_deezer {
        let parts: Vec<String> = raw
            .split('/')
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
            .collect();
        if parts.is_empty() {
            return (MISSING_ARTIST.to_string(), Vec::new());
        }
        let mut iter = parts.into_iter();
        let leading = iter.next().unwrap();
        let features = iter.collect();
        (leading, features)
    } else {
        let trimmed = raw.trim();
        if trimmed.is_empty() {
            (MISSING_ARTIST.to_string(), Vec::new())
        } else {
            (trimmed.to_string(), Vec::new())
        }
    }
}

/// Read tags and cover art from an audio file.
#[frb(ignore)]
pub fn extract_raw_metadata(path: &Path) -> Result<RawMetadata, String> {
    let src = std::fs::File::open(path).map_err(|e| format!("open: {e}"))?;
    let mss = MediaSourceStream::new(Box::new(src), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let mut probed = symphonia::default::get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .map_err(|e| format!("probe: {e}"))?;

    let mut meta = RawMetadata {
        title: None,
        album: None,
        leading_artist: None,
        album_artist: None,
        track_num: None,
        disc_num: None,
        cover: None,
    };

    // ID3v2 tags from the probe (typical for mp3).
    {
        let mut probed_metadata = probed.metadata;
        if let Some(md) = probed_metadata.get() {
            if let Some(rev) = md.current() {
                fill_from_tags(rev.tags(), &mut meta);
                if meta.cover.is_none() {
                    meta.cover = find_cover(rev.visuals());
                }
            }
        }
    }

    // Container-level metadata (flac/m4a/ogg live here).
    {
        let format_meta = probed.format.metadata();
        if let Some(rev) = format_meta.current() {
            fill_from_tags(rev.tags(), &mut meta);
            if meta.cover.is_none() {
                meta.cover = find_cover(rev.visuals());
            }
        }
    }

    Ok(meta)
}

fn fill_from_tags(tags: &[Tag], meta: &mut RawMetadata) {
    for tag in tags {
        let Some(std_key) = tag.std_key else { continue };
        match std_key {
            StandardTagKey::TrackTitle => {
                if meta.title.is_none() {
                    if let Some(s) = value_as_str(&tag.value) {
                        meta.title = Some(s);
                    }
                }
            }
            StandardTagKey::Album => {
                if meta.album.is_none() {
                    if let Some(s) = value_as_str(&tag.value) {
                        meta.album = Some(s);
                    }
                }
            }
            StandardTagKey::Artist => {
                if meta.leading_artist.is_none() {
                    if let Some(s) = value_as_str(&tag.value) {
                        meta.leading_artist = Some(s);
                    }
                }
            }
            StandardTagKey::AlbumArtist => {
                if meta.album_artist.is_none() {
                    if let Some(s) = value_as_str(&tag.value) {
                        meta.album_artist = Some(s);
                    }
                }
            }
            StandardTagKey::TrackNumber => {
                if meta.track_num.is_none() {
                    meta.track_num = tag_value_to_i64(&tag.value);
                }
            }
            StandardTagKey::DiscNumber => {
                if meta.disc_num.is_none() {
                    meta.disc_num = tag_value_to_i64(&tag.value);
                }
            }
            _ => {}
        }
    }
}

fn value_as_str(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => {
            let t = s.trim();
            if t.is_empty() {
                None
            } else {
                Some(t.to_string())
            }
        }
        _ => None,
    }
}

// ID3 TRCK / TPOS often come through as "n/total"; take the leading number.
fn tag_value_to_i64(v: &Value) -> Option<i64> {
    match v {
        Value::SignedInt(i) => Some(*i),
        Value::UnsignedInt(u) => i64::try_from(*u).ok(),
        Value::String(s) => {
            let head = s.split('/').next()?.trim();
            head.parse::<i64>().ok()
        }
        _ => None,
    }
}

fn find_cover(visuals: &[Visual]) -> Option<RawCover> {
    visuals
        .iter()
        .find(|v| v.usage == Some(StandardVisualKey::FrontCover))
        .or_else(|| visuals.first())
        .map(|v| RawCover {
            data: v.data.to_vec(),
            mime_type: v.media_type.clone(),
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn fixture_album_dir() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("test")
            .join("Playboi Carti - Whole Lotta Red")
    }

    #[test]
    fn parse_single_artist() {
        let (lead, feats) = parse_artist_string("Playboi Carti", true);
        assert_eq!(lead, "Playboi Carti");
        assert!(feats.is_empty());
    }

    #[test]
    fn parse_deezer_features() {
        let (lead, feats) = parse_artist_string("Playboi Carti/Kanye West/Future", true);
        assert_eq!(lead, "Playboi Carti");
        assert_eq!(feats, vec!["Kanye West".to_string(), "Future".to_string()]);
    }

    #[test]
    fn parse_deezer_trims_whitespace() {
        let (lead, feats) = parse_artist_string("  Playboi Carti /  Kanye West ", true);
        assert_eq!(lead, "Playboi Carti");
        assert_eq!(feats, vec!["Kanye West".to_string()]);
    }

    #[test]
    fn parse_non_deezer_keeps_as_is() {
        let (lead, feats) = parse_artist_string("Playboi Carti/Kanye West", false);
        assert_eq!(lead, "Playboi Carti/Kanye West");
        assert!(feats.is_empty());
    }

    #[test]
    fn parse_empty_falls_back_to_unknown() {
        let (lead, feats) = parse_artist_string("   ", true);
        assert_eq!(lead, MISSING_ARTIST);
        assert!(feats.is_empty());
    }

    #[test]
    fn extracts_metadata_from_all_test_mp3s() {
        let dir = fixture_album_dir();
        assert!(
            dir.exists(),
            "missing test fixtures at {:?}. Did the test/ folder move?",
            dir
        );

        let mut count = 0;
        for entry in std::fs::read_dir(&dir).expect("read_dir") {
            let entry = entry.expect("entry");
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("mp3") {
                continue;
            }
            let meta = extract_raw_metadata(&path)
                .unwrap_or_else(|e| panic!("failed to read {:?}: {}", path, e));

            assert!(meta.title.is_some(), "missing title: {:?}", path);
            assert!(meta.leading_artist.is_some(), "missing artist: {:?}", path);
            assert!(meta.album.is_some(), "missing album: {:?}", path);
            assert!(meta.track_num.is_some(), "missing track number: {:?}", path);
            count += 1;
        }
        assert_eq!(count, 24, "expected 24 mp3s in the test fixture");
    }
}
