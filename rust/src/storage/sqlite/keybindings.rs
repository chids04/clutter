use super::*;

const ACTIONS: [&str; 6] = [
    "play_pause",
    "seek_backward",
    "seek_forward",
    "previous_track",
    "next_track",
    "omni_search",
];

const DEFAULTS: [(&str, &str, bool); 6] = [
    ("play_pause", "space", false),
    ("seek_backward", "arrow_left", false),
    ("seek_forward", "arrow_right", false),
    ("previous_track", "key_h", false),
    ("next_track", "key_l", false),
    ("omni_search", "key_s", true),
];

impl SqliteLibraryStore {
    pub fn get_keybindings(&self) -> Result<Vec<KeybindingRow>, String> {
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        query_keybindings(&conn).map_err(|error| format!("query keybindings: {error}"))
    }

    pub fn update_keybinding(&self, binding: KeybindingRow) -> Result<KeybindingRow, String> {
        validate_binding(&binding)?;
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        reject_conflict(&conn, &binding)?;
        conn.execute(
            "UPDATE keybindings SET key_code = ?1, primary_modifier = ?2, control_modifier = ?3, meta_modifier = ?4, alt_modifier = ?5, shift_modifier = ?6 WHERE action = ?7",
            params![
                binding.key_code,
                binding.primary as i64,
                binding.control as i64,
                binding.meta as i64,
                binding.alt as i64,
                binding.shift as i64,
                binding.action,
            ],
        )
        .map_err(|error| format!("update keybinding: {error}"))?;
        load_keybinding(&conn, &binding.action)
    }

    pub fn reset_keybindings(&self) -> Result<Vec<KeybindingRow>, String> {
        let mut conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        let tx = conn.transaction().map_err(|error| format!("tx: {error}"))?;
        tx.execute("DELETE FROM keybindings", [])
            .map_err(|error| format!("clear keybindings: {error}"))?;
        insert_defaults(&tx)?;
        tx.execute(
            "UPDATE shortcut_settings SET seek_step_seconds = 5 WHERE id = 1",
            [],
        )
        .map_err(|error| format!("reset seek step: {error}"))?;
        tx.commit().map_err(|error| format!("commit: {error}"))?;
        query_keybindings(&conn).map_err(|error| format!("query keybindings: {error}"))
    }

    pub fn get_seek_step_seconds(&self) -> Result<u32, String> {
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        conn.query_row(
            "SELECT seek_step_seconds FROM shortcut_settings WHERE id = 1",
            [],
            |row| row.get::<_, u32>(0),
        )
        .map_err(|error| format!("get seek step: {error}"))
    }

    pub fn update_seek_step_seconds(&self, seconds: u32) -> Result<u32, String> {
        if !(1..=30).contains(&seconds) {
            return Err("seek step must be between 1 and 30 seconds".into());
        }
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        conn.execute(
            "UPDATE shortcut_settings SET seek_step_seconds = ?1 WHERE id = 1",
            [seconds],
        )
        .map_err(|error| format!("update seek step: {error}"))?;
        Ok(seconds)
    }
}

fn validate_binding(binding: &KeybindingRow) -> Result<(), String> {
    if !ACTIONS.contains(&binding.action.as_str()) {
        return Err("unknown keybinding action".into());
    }
    let Some(code) = binding.key_code.as_deref() else {
        return Ok(());
    };
    if !valid_key_code(code) {
        return Err(format!("unsupported key code: {code}"));
    }
    Ok(())
}

fn valid_key_code(code: &str) -> bool {
    code == "space"
        || matches!(
            code,
            "arrow_left" | "arrow_right" | "arrow_up" | "arrow_down"
        )
        || matches!(
            code,
            "home" | "end" | "page_up" | "page_down" | "enter" | "tab"
        )
        || matches!(code, "backspace" | "delete" | "insert")
        || matches!(
            code,
            "minus"
                | "equal"
                | "comma"
                | "period"
                | "slash"
                | "semicolon"
                | "quote"
                | "bracket_left"
                | "bracket_right"
                | "backslash"
                | "backquote"
        )
        || valid_numbered_code(code, "key_", 'a', 'z')
        || valid_numbered_code(code, "digit_", '0', '9')
        || valid_function_key(code)
}

fn valid_numbered_code(code: &str, prefix: &str, start: char, end: char) -> bool {
    let Some(value) = code.strip_prefix(prefix) else {
        return false;
    };
    value.len() == 1
        && value
            .chars()
            .next()
            .is_some_and(|ch| (start..=end).contains(&ch))
}

fn valid_function_key(code: &str) -> bool {
    code.strip_prefix('f')
        .and_then(|value| value.parse::<u8>().ok())
        .is_some_and(|number| (1..=12).contains(&number))
}

fn reject_conflict(conn: &Connection, binding: &KeybindingRow) -> Result<(), String> {
    let Some(code) = binding.key_code.as_deref() else {
        return Ok(());
    };
    let conflict = conn
        .query_row(
            "SELECT action FROM keybindings WHERE action != ?1 AND key_code = ?2 AND primary_modifier = ?3 AND control_modifier = ?4 AND meta_modifier = ?5 AND alt_modifier = ?6 AND shift_modifier = ?7",
            params![binding.action, code, binding.primary as i64, binding.control as i64, binding.meta as i64, binding.alt as i64, binding.shift as i64],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(|error| format!("check keybinding conflict: {error}"))?;
    if let Some(action) = conflict {
        return Err(format!("keybinding already used by {action}"));
    }
    Ok(())
}

fn insert_defaults(conn: &Connection) -> Result<(), String> {
    for (action, key_code, primary) in DEFAULTS {
        conn.execute(
            "INSERT INTO keybindings (action, key_code, primary_modifier) VALUES (?1, ?2, ?3)",
            params![action, key_code, primary as i64],
        )
        .map_err(|error| format!("insert default keybinding: {error}"))?;
    }
    Ok(())
}

fn query_keybindings(conn: &Connection) -> rusqlite::Result<Vec<KeybindingRow>> {
    let mut statement = conn.prepare(
        "SELECT action, key_code, primary_modifier, control_modifier, meta_modifier, alt_modifier, shift_modifier FROM keybindings ORDER BY CASE action WHEN 'play_pause' THEN 0 WHEN 'seek_backward' THEN 1 WHEN 'seek_forward' THEN 2 WHEN 'previous_track' THEN 3 WHEN 'next_track' THEN 4 ELSE 5 END",
    )?;
    let rows = statement.query_map([], map_keybinding)?;
    rows.collect()
}

fn load_keybinding(conn: &Connection, action: &str) -> Result<KeybindingRow, String> {
    conn.query_row(
        "SELECT action, key_code, primary_modifier, control_modifier, meta_modifier, alt_modifier, shift_modifier FROM keybindings WHERE action = ?1",
        params![action],
        map_keybinding,
    )
    .map_err(|error| format!("load keybinding: {error}"))
}

fn map_keybinding(row: &rusqlite::Row<'_>) -> rusqlite::Result<KeybindingRow> {
    Ok(KeybindingRow {
        action: row.get(0)?,
        key_code: row.get(1)?,
        primary: row.get::<_, i64>(2)? != 0,
        control: row.get::<_, i64>(3)? != 0,
        meta: row.get::<_, i64>(4)? != 0,
        alt: row.get::<_, i64>(5)? != 0,
        shift: row.get::<_, i64>(6)? != 0,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn store() -> (SqliteLibraryStore, TempDir) {
        let temp = TempDir::new().unwrap();
        let db = temp.path().join("library.db");
        let covers = temp.path().join("covers");
        let store = SqliteLibraryStore::open(
            &db.to_string_lossy(),
            &covers.to_string_lossy(),
            &temp.path().to_string_lossy(),
        )
        .unwrap();
        (store, temp)
    }

    fn binding(action: &str, key_code: Option<&str>) -> KeybindingRow {
        KeybindingRow {
            action: action.into(),
            key_code: key_code.map(str::to_string),
            primary: false,
            control: false,
            meta: false,
            alt: false,
            shift: false,
        }
    }

    #[test]
    fn seeds_defaults_in_display_order() {
        let (store, _temp) = store();
        let bindings = store.get_keybindings().unwrap();
        assert_eq!(bindings.len(), 6);
        assert_eq!(bindings[0], binding("play_pause", Some("space")));
        assert_eq!(bindings[1], binding("seek_backward", Some("arrow_left")));
        assert_eq!(bindings[2], binding("seek_forward", Some("arrow_right")));
        assert_eq!(bindings[3], binding("previous_track", Some("key_h")));
        assert_eq!(bindings[4], binding("next_track", Some("key_l")));
        assert!(bindings[5].primary);
    }

    #[test]
    fn update_and_unbind_are_persisted() {
        let (store, _temp) = store();
        let mut updated = binding("play_pause", Some("key_p"));
        updated.shift = true;
        assert_eq!(store.update_keybinding(updated.clone()).unwrap(), updated);
        let cleared = binding("play_pause", None);
        assert_eq!(store.update_keybinding(cleared.clone()).unwrap(), cleared);
        assert_eq!(store.get_keybindings().unwrap()[0], cleared);
    }

    #[test]
    fn updated_binding_survives_reopen() {
        let (store, temp) = store();
        store
            .update_keybinding(binding("play_pause", Some("key_p")))
            .unwrap();
        drop(store);
        let reopened = SqliteLibraryStore::open(
            &temp.path().join("library.db").to_string_lossy(),
            &temp.path().join("covers").to_string_lossy(),
            &temp.path().to_string_lossy(),
        )
        .unwrap();
        assert_eq!(
            reopened.get_keybindings().unwrap()[0].key_code.as_deref(),
            Some("key_p")
        );
    }

    #[test]
    fn duplicate_chords_are_rejected_without_changes() {
        let (store, _temp) = store();
        let error = store
            .update_keybinding(binding("next_track", Some("key_h")))
            .unwrap_err();
        assert!(error.contains("previous_track"));
        assert_eq!(
            store.get_keybindings().unwrap()[4].key_code.as_deref(),
            Some("key_l")
        );
    }

    #[test]
    fn reset_restores_every_default() {
        let (store, _temp) = store();
        store
            .update_keybinding(binding("play_pause", None))
            .unwrap();
        store.update_seek_step_seconds(12).unwrap();
        let reset = store.reset_keybindings().unwrap();
        assert_eq!(reset[0].key_code.as_deref(), Some("space"));
        assert!(reset[5].primary);
        assert_eq!(store.get_seek_step_seconds().unwrap(), 5);
    }

    #[test]
    fn invalid_codes_and_actions_are_rejected() {
        let (store, _temp) = store();
        assert!(store
            .update_keybinding(binding("missing", Some("space")))
            .is_err());
        assert!(store
            .update_keybinding(binding("play_pause", Some("escape")))
            .is_err());
    }

    #[test]
    fn seek_step_is_validated_and_persisted() {
        let (store, temp) = store();
        assert_eq!(store.get_seek_step_seconds().unwrap(), 5);
        assert_eq!(store.update_seek_step_seconds(12).unwrap(), 12);
        assert!(store.update_seek_step_seconds(0).is_err());
        assert!(store.update_seek_step_seconds(31).is_err());
        drop(store);

        let reopened = SqliteLibraryStore::open(
            &temp.path().join("library.db").to_string_lossy(),
            &temp.path().join("covers").to_string_lossy(),
            &temp.path().to_string_lossy(),
        )
        .unwrap();
        assert_eq!(reopened.get_seek_step_seconds().unwrap(), 12);
    }
}
