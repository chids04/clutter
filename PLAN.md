# Plan: Architectural Refactor to SQLite-Driven Backend

## Overview
This plan outlines a structural refactor to transition the `clutter` music player from an in-memory architecture to a highly scalable, decoupled architecture using a local SQLite database managed entirely by Rust.

**Core Principle:** Rust acts as the complete backend (Indexer, Database, and Business Logic). Dart acts *strictly* as a dumb UI layer.

## Objective
Establish a robust, UI-agnostic API boundary where:
1.  **Source of Truth:** A local SQLite database (`library.db`), managed exclusively by Rust.
2.  **Rust Role:** Handles filesystem scanning (`symphonia`), metadata extraction, database writes, and exposing a clean, typed query API for any frontend.
3.  **Dart Role:** Calls the typed Rust API to request specific data and renders the UI. It does not manage the database connection or complex state.
4.  **Scope Constraints:** No new features are being added. This is a 1:1 refactor of the existing scanning and playback capabilities to use SQLite instead of `HashMap`/`IndexMap`.

## Phase 1: The Rust Backend (Core Engine)

### 1. Dependencies
Add a SQLite crate to `rust/Cargo.toml` (e.g., `rusqlite` or `sqlx`).

### 2. Database Initialization
Create a database initialization routine in Rust that sets up the schema in the Application Documents Directory.
*Schema:*
-   `artists` (id, name)
-   `albums` (id, title, artist_id, cover_path)
-   `songs` (id, title, track_num, disc_num, album_id, file_path)
-   `song_artists` (song_id, artist_id, is_featured)

### 3. Refactoring the Indexer
Update the `extract_metadata` function to write directly to SQLite instead of the in-memory `CLibrary` struct. Extracted album covers should be written to disk (`covers/<album_id>.jpg`) and their file path saved in the database.

## Phase 2: The API Boundary (UI-Agnostic)

Define a clear, typed API in Rust that any frontend (Flutter, Tauri, CLI, etc.) could consume.

```rust
// API Models (Data Transfer Objects)
pub struct SongViewData {
    pub id: String,
    pub title: String,
    pub primary_artist: String,
    pub featured_artists: Vec<String>,
    pub cover_path: Option<String>,
    pub file_path: String,
}

// The API Surface
impl CLibrary {
    // Initialization
    pub fn init(db_path: String, covers_dir: String) -> Result<Self, String>;

    // Commands
    pub fn scan_directory(&self, path: String) -> Result<(), String>;
    
    // Queries
    pub fn get_total_songs(&self) -> u32;
    pub fn get_songs_paginated(&self, offset: u32, limit: u32) -> Vec<SongViewData>;
    pub fn get_song_by_id(&self, id: String) -> Option<SongViewData>;
}
```

## Phase 3: Dart UI Refactor

### 1. Initialization
When the app starts, Dart provides the platform-specific paths (AppDir) to Rust via the `init` function.

### 2. UI Updates (`lib/ui/views/library_view.dart`)
-   Transition `ListView` to use pagination or standard batch fetching via `get_songs_paginated`.
-   Replace the complex `MemoryImage` logic with `Image.file(File(song.coverPath))` since Rust now saves covers to disk.
-   Dart no longer needs to resolve UUIDs to names; the Rust `SongViewData` struct provides the final strings ready for display.

## Migration Strategy
1.  **Implement SQLite in Rust:** Add `rusqlite`, create the schema, and modify the scanner to insert data.
2.  **Expose the Query API:** Write the `get_songs_paginated` methods in Rust that return the flattened `SongViewData` structs.
3.  **Refactor Dart:** Point the Flutter UI to use the new typed Rust API, tear down the old FFI opaque handles, and switch to loading images from disk.
