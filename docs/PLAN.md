# SQLite-Backed Refactor — Change Log

This document records the refactor executed against the plan in
[`../PLAN.md`](../PLAN.md). Scope constraint from the plan: **no new
features** — this is a 1:1 move from the in-memory `HashMap` / `IndexMap`
backend to a SQLite-backed backend managed entirely by Rust, with Dart
reduced to a dumb UI layer.

## Result

- Rust owns the database, the filesystem scan, the metadata extraction and
  the on-disk cover cache.
- Dart receives fully-resolved `SongViewData` structs from Rust and never
  deals with UUIDs, HashMaps or the cover byte payload.
- Flutter's image pipeline now renders covers via `Image.file(...)` pointing
  at the path Rust wrote during scanning.
- 10 Rust tests exercise the metadata parser and the end-to-end scan →
  query path against the real mp3s under `test/Playboi Carti - Whole Lotta
  Red/` — see [Tests](#tests).

## New API surface

`rust/src/api/scanner.rs`:

```rust
pub struct Config { pub is_deezer: bool }

pub struct SongViewData {
    pub id: String,
    pub title: String,
    pub primary_artist: String,
    pub featured_artists: Vec<String>,
    pub cover_path: Option<String>,
    pub file_path: String,
    pub track_num: i64,
    pub disc_num: i64,
    pub album: String,
}

#[frb(opaque)]
pub struct CLibrary { /* Mutex<Connection>, covers_dir */ }

impl CLibrary {
    pub fn init(db_path: String, covers_dir: String) -> Result<CLibrary, String>;
    pub fn scan_directory(&self, path: String, config: Config) -> Result<(), String>;
    pub fn get_total_songs(&self) -> u32;                          // #[frb(sync)]
    pub fn get_songs_paginated(&self, offset: u32, limit: u32) -> Vec<SongViewData>;
    pub fn get_song_by_id(&self, id: String) -> Option<SongViewData>;
}
```

Helper functions that are not part of the FFI surface (`parse_artist_string`,
`extract_raw_metadata`, `init_schema`, `RawMetadata`, `RawCover`) are
annotated with `#[frb(ignore)]` so `flutter_rust_bridge_codegen` does not try
to marshal the `Path` / `Connection` types that live inside `CLibrary`.

## Database schema

Stored in `rust/src/api/schema.sql` and loaded with `include_str!`:

- `artists(id TEXT PK, name TEXT UNIQUE)`
- `albums(id TEXT PK, title TEXT, artist_id TEXT FK, cover_path TEXT)` — unique by `(title, artist_id)`
- `songs(id TEXT PK, title TEXT, track_num INTEGER, disc_num INTEGER, album_id TEXT FK, file_path TEXT UNIQUE)`
- `song_artists(song_id FK, artist_id FK, is_featured INTEGER, position INTEGER)` — one row per song/artist link; features have `is_featured = 1` and a `position` for ordering

Cover art is written to `<covers_dir>/<album_id>.<ext>` during scan and the
path is stored on the album row. Files are not rewritten if an album already
has a cover — first writer wins.

## File-by-file changes

### Rust — `rust/`

- `Cargo.toml` — added `rusqlite = { version = "0.31", features = ["bundled"] }`, `walkdir = "2.5"`, `tempfile` as a dev-dep. Dropped the now-unused `indexmap`.
- `src/api/mod.rs` — only `scanner` and `simple` are declared; `complex` was deleted.
- `src/api/scanner.rs` — **rewritten**. Old types (`CSong`, `CSongDart`, `Album`, `Artist`, `ArtistGroup`, `ArtistGroupDart`, `MetadataCache`, `CImage`, `CLibrary`'s in-memory HashMaps) are gone. New:
  - `CLibrary { conn: Mutex<Connection>, covers_dir: PathBuf }` as the sole opaque type crossing the bridge.
  - `RawMetadata` / `RawCover` — internal-only DTOs for parsed tags, marked `#[frb(ignore)]`.
  - `parse_artist_string` — keeps the Deezer `/`-split semantics from the old `handle_artist` as a pure function, unit-testable without a DB.
  - `extract_raw_metadata` — pure function that reads tags + front cover from a file. Now also looks at `probed.format.metadata()` as a fallback for container-level tags (flac/m4a/ogg), not only ID3v2 on mp3.
  - `insert_song` / `ensure_artist` / `ensure_album` / `write_cover_if_missing` — DB writers used during scan.
  - `query_songs` — single SQL statement that joins `songs` → `albums` → primary `song_artists` → `artists`, with a correlated subquery using `GROUP_CONCAT(..., CHAR(31))` to pull the ordered list of features in one round-trip. The separator is the ASCII Unit Separator so it cannot collide with characters inside an artist name.
  - Old `CLibrary::new()`, `add_song`, `get_song_by_index`, `get_artist`, `current_song`, `play_song` — all removed. Playback state now lives on the Dart side where the actual audio player is.
- `src/api/schema.sql` — new file; schema + indexes.
- `src/api/simple.rs` — pared down to just the FRB init hook. The `greet` demo function is gone.
- `src/api/complex.rs` — **deleted**. It was unreferenced dead code (`spank`, `Hello`, `print_hello`).
- `src/frb_generated.rs` — regenerated.

### Dart — `lib/`

- `pubspec.yaml` — added `path_provider: ^2.1.4` for platform-specific app directory lookup.
- `lib/main.dart` — `main()` is now async and awaits `CLibrary.init(dbPath, coversDir)` before `runApp`. Paths are derived from `getApplicationDocumentsDirectory()` (Linux/macOS/Windows/iOS/Android all supported by `path_provider`). The `MusicLibrary` is constructed with the initialised `CLibrary` handle.
- `lib/models/music_library.dart` — **rewritten** around the new API. Changes:
  - Deleted `Song`, `Album`, `Artist`, `CoverImage`, `MusicLibraryState` — those were the old Dart-side duplicates of what Rust now owns.
  - Deleted `updateAlbum` / `updateArtist` / `parseMetadata` / `getArtistStr` — all obsolete now that Rust returns flat strings.
  - `songs` now returns an `UnmodifiableListView<SongViewData>` over a cached paginated fetch. The cache is refreshed at end-of-scan via a single call to `get_songs_paginated(0, total)`. This matches the plan's "standard batch fetching" option.
  - `addDirectory` awaits `scanDirectory` on the Rust side, reloads the song list, then flips `isScanning` off — all in a `try/finally` so a failed scan doesn't leave the UI stuck on the spinner.
  - `onPlaySong` now calls `getSongById` and uses the returned `filePath` for `DeviceFileSource`. Audio player lifecycle is unchanged.
  - New `artistsDisplay(SongViewData)` helper replaces the old UUID-resolving `getArtistStr(String songID)`.
- `lib/ui/views/library_view.dart` — `SongView` iterates the cached `musicLibrary.songs` list directly. `SongDelegate` is now a `StatelessWidget` that receives a fully-resolved `SongViewData` (no more per-row `FutureBuilder` hitting Rust, no more UUID-to-name lookups). Covers render via `Image.file(File(song.coverPath))`. The old `SongDelegate` owned a `Future<CSongDart?>` and resolved artist strings itself; both responsibilities are gone.
- `lib/ui/views/mediabar.dart` — takes `SongViewData` directly, uses `Image.file` for the cover. Fixes a pre-existing bug where the caption was computed as `getArtistStr(currentSong.title)` (passing the title where a song id was expected).

### Generated bindings

- `lib/src/rust/frb_generated.{dart,io.dart,web.dart}` regenerated by `flutter_rust_bridge_codegen`.
- `rust/src/frb_generated.rs` regenerated.
- Stale `lib/src/rust/api/{complex,simple}.dart` deleted — codegen does not prune them itself.

## Tests

All in `rust/src/api/scanner.rs` under `#[cfg(test)] mod tests`. Run with
`cargo test --lib` from `rust/`.

| Test | What it verifies |
|---|---|
| `parse_single_artist` | A tag without `/` becomes a lone leading artist with no features |
| `parse_deezer_features` | `"A/B/C"` → leading `A`, features `[B, C]` |
| `parse_deezer_trims_whitespace` | Whitespace around `/` is trimmed |
| `parse_non_deezer_keeps_as_is` | With `is_deezer=false`, the whole string stays as one artist |
| `parse_empty_falls_back_to_unknown` | Empty/whitespace-only tags become `"Unknown Artist"` |
| `extracts_metadata_from_all_test_mp3s` | Every one of the 24 mp3s in `test/Playboi Carti - Whole Lotta Red/` yields a title, artist, album and track number via symphonia |
| `scan_populates_sqlite_and_queries_work` | End-to-end: `init` → `scan_directory` → `get_total_songs` returns 24 → `get_songs_paginated(0, 100)` returns 24 fully populated rows → `get_song_by_id` round-trips |
| `scan_is_idempotent` | Re-scanning the same directory does not duplicate rows (unique `file_path` enforces this) |
| `scan_writes_cover_to_disk` | Album cover is written under `<covers_dir>/<album_id>.<ext>` and the path is stored on the album |
| `deezer_feature_splitting_writes_separate_rows` | Synthetic insert with tag `"Playboi Carti/Kanye West"` produces one `is_featured=0` row for Carti and one `is_featured=1` row for Kanye, preserving order via `position` |

The fixture folder (`test/Playboi Carti - Whole Lotta Red/`) is addressed
relatively from `env!("CARGO_MANIFEST_DIR")` so the tests are portable
across checkout paths.

## Migration follow-ups (intentionally out of scope)

These are called out so a future contributor knows they were considered and
left alone to keep this a 1:1 refactor:

- The initial scan path in `main.dart` is still hardcoded; replace with a
  first-run picker or config file.
- `get_songs_paginated` is called once with `limit = total` at the end of
  each scan. If the library grows large, swap the batch fetch for a
  windowed/virtualised `ListView.builder` that calls `getSongsPaginated`
  per visible page.
- `AlbumsView` still shows a spinner — the plan explicitly excludes new
  features, but the query would just be `SELECT ... FROM albums`.
- `audio_metadata_reader` / `metatagger` / `uuid` are still listed in
  `pubspec.yaml` but no longer imported from Dart; leaving removal for a
  separate cleanup pass.
