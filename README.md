# clutter

a local-first music player built with flutter, dart, and rust.

clutter scans your music, manages songs, albums, artists, and playlists, supports metadata and artwork editing, and provides queue and playback controls.

features:

- turn videos into fully tagged audio files
- fully customise imported albums, songs and playlists with changes persisting to the audio files
- fast indexing of songs so searching and querying is fast
- sftp downloader interface to download songs from a remote filesystem

dart owns the interface and platform playback while rust owns library data, scanning, and metadata changes.

## images


see [the architecture guide](docs/ARCHITECTURE.md) for the project structure.
