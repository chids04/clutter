CREATE TABLE IF NOT EXISTS artists (
    id                TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    custom_cover_path TEXT
);

CREATE INDEX IF NOT EXISTS artists_name ON artists(name);

CREATE TABLE IF NOT EXISTS albums (
    id           TEXT PRIMARY KEY,
    title        TEXT NOT NULL,
    artist_id    TEXT,
    artist_key   TEXT NOT NULL,
    cover_path   TEXT,
    FOREIGN KEY (artist_id) REFERENCES artists(id)
);

CREATE UNIQUE INDEX IF NOT EXISTS albums_identity ON albums(title COLLATE NOCASE, artist_key);

CREATE TABLE IF NOT EXISTS album_artists (
    album_id  TEXT NOT NULL,
    artist_id TEXT NOT NULL,
    position  INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (album_id, artist_id),
    FOREIGN KEY (album_id) REFERENCES albums(id) ON DELETE CASCADE,
    FOREIGN KEY (artist_id) REFERENCES artists(id)
);

CREATE INDEX IF NOT EXISTS album_artists_album ON album_artists(album_id, position);
CREATE INDEX IF NOT EXISTS album_artists_artist ON album_artists(artist_id);

CREATE TABLE IF NOT EXISTS songs (
    id         TEXT PRIMARY KEY,
    title      TEXT NOT NULL,
    track_num  INTEGER NOT NULL DEFAULT 1,
    disc_num   INTEGER NOT NULL DEFAULT 1,
    album_id   TEXT,
    cover_path TEXT,
    file_path  TEXT NOT NULL UNIQUE,
    added_at   INTEGER NOT NULL,
    FOREIGN KEY (album_id) REFERENCES albums(id)
);

CREATE INDEX IF NOT EXISTS songs_album ON songs(album_id);
CREATE INDEX IF NOT EXISTS songs_added_at ON songs(added_at DESC);

CREATE TABLE IF NOT EXISTS artwork_sources (
    owner_kind   TEXT NOT NULL CHECK (owner_kind IN ('song', 'album', 'artist', 'playlist')),
    owner_id     TEXT NOT NULL,
    original_path TEXT NOT NULL,
    crop_left    REAL NOT NULL,
    crop_top     REAL NOT NULL,
    crop_width   REAL NOT NULL,
    crop_height  REAL NOT NULL,
    PRIMARY KEY (owner_kind, owner_id)
);

CREATE TABLE IF NOT EXISTS song_audio_crops (
    song_id            TEXT PRIMARY KEY,
    original_file_path TEXT NOT NULL,
    retained_file_path TEXT NOT NULL UNIQUE,
    start_ms            INTEGER NOT NULL,
    end_ms              INTEGER NOT NULL,
    FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS song_artists (
    song_id     TEXT NOT NULL,
    artist_id   TEXT NOT NULL,
    is_featured INTEGER NOT NULL DEFAULT 0,
    position    INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (song_id, artist_id),
    FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE,
    FOREIGN KEY (artist_id) REFERENCES artists(id)
);

CREATE INDEX IF NOT EXISTS song_artists_song ON song_artists(song_id);

CREATE TABLE IF NOT EXISTS playlists (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    icon_key   TEXT,
    image_path TEXT,
    is_system  INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS playlist_songs (
    playlist_id TEXT NOT NULL,
    song_id     TEXT NOT NULL,
    position    INTEGER NOT NULL,
    added_at    INTEGER NOT NULL,
    PRIMARY KEY (playlist_id, song_id),
    FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
    FOREIGN KEY (song_id)     REFERENCES songs(id)     ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS playlist_songs_playlist ON playlist_songs(playlist_id);
CREATE INDEX IF NOT EXISTS playlist_songs_song     ON playlist_songs(song_id);

CREATE TABLE IF NOT EXISTS scan_paths (
    path     TEXT PRIMARY KEY,
    added_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS recently_played (
    song_id   TEXT PRIMARY KEY,
    played_at INTEGER NOT NULL,
    FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS recently_played_time ON recently_played(played_at DESC);

CREATE TABLE IF NOT EXISTS pinned_items (
    item_id   TEXT NOT NULL,
    kind      TEXT NOT NULL CHECK (kind IN ('song', 'album', 'playlist')),
    position  INTEGER NOT NULL DEFAULT 0,
    pinned_at INTEGER NOT NULL,
    PRIMARY KEY (item_id, kind)
);

CREATE INDEX IF NOT EXISTS pinned_items_position ON pinned_items(position, pinned_at DESC);

CREATE TABLE IF NOT EXISTS metadata_operations (
    id TEXT PRIMARY KEY,
    committed_at INTEGER NOT NULL
);

-- Singleton (id must be 1) so the MediaBar can restore on relaunch.
CREATE TABLE IF NOT EXISTS playback_state (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    song_id     TEXT,
    position_ms INTEGER NOT NULL DEFAULT 0,
    loop_one    INTEGER NOT NULL DEFAULT 0,
    updated_at  INTEGER NOT NULL,
    FOREIGN KEY (song_id) REFERENCES songs(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS keybindings (
    action           TEXT PRIMARY KEY CHECK (action IN ('play_pause', 'previous_track', 'next_track', 'omni_search')),
    key_code         TEXT,
    primary_modifier INTEGER NOT NULL DEFAULT 0,
    control_modifier INTEGER NOT NULL DEFAULT 0,
    meta_modifier    INTEGER NOT NULL DEFAULT 0,
    alt_modifier     INTEGER NOT NULL DEFAULT 0,
    shift_modifier   INTEGER NOT NULL DEFAULT 0
);

CREATE UNIQUE INDEX IF NOT EXISTS keybindings_unique_chord
ON keybindings (
    key_code,
    primary_modifier,
    control_modifier,
    meta_modifier,
    alt_modifier,
    shift_modifier
)
WHERE key_code IS NOT NULL;

INSERT OR IGNORE INTO keybindings (action, key_code) VALUES ('play_pause', 'space');
INSERT OR IGNORE INTO keybindings (action, key_code) VALUES ('previous_track', 'key_h');
INSERT OR IGNORE INTO keybindings (action, key_code) VALUES ('next_track', 'key_l');
INSERT OR IGNORE INTO keybindings (action, key_code, primary_modifier)
VALUES ('omni_search', 'key_s', 1);
