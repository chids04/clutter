# Repository Instructions

## Local SQLite schema changes

- Do not add runtime database migrations while this project is in development.
- When `rust/src/storage/sqlite/schema.sql` changes incompatibly, update the schema directly and delete the local development database at the resolved app-documents path `clutter/library.db` so the app recreates it.
- Resolve and verify the exact database path before deletion. Never add application code that deletes a user's database automatically.
