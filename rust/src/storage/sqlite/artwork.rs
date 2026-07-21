use super::*;

#[derive(Debug, Clone)]
pub(super) struct StagedArtwork {
    pub display_path: String,
    pub original_path: String,
    pub crop: ArtworkCropRect,
}

impl SqliteLibraryStore {
    pub fn get_artwork_edit(
        &self,
        owner: ArtworkOwnerKind,
        owner_id: &str,
    ) -> Option<ArtworkEditRow> {
        let conn = self.conn.lock().ok()?;
        let mut row = query_artwork_edit(&conn, owner, owner_id).ok()??;
        row.original_path = self.to_abs(&row.original_path);
        Some(row)
    }

    pub(super) fn load_artwork_edit(
        &self,
        owner: ArtworkOwnerKind,
        owner_id: &str,
    ) -> Result<Option<ArtworkEditRow>, String> {
        let conn = self.conn.lock().map_err(|error| format!("lock: {error}"))?;
        query_artwork_edit(&conn, owner, owner_id)
    }

    pub(super) fn stage_artwork_update(
        &self,
        update: &ArtworkUpdate,
        category: &str,
        owner_id: &str,
    ) -> Result<Option<StagedArtwork>, String> {
        let ArtworkUpdate::Replace {
            original_source_path,
            cropped_source_path,
            crop,
        } = update
        else {
            return Ok(None);
        };
        validate_artwork_crop(*crop)?;
        self.stage_artwork_pair(
            original_source_path,
            cropped_source_path,
            *crop,
            category,
            owner_id,
        )
        .map(Some)
    }

    fn stage_artwork_pair(
        &self,
        original_source: &str,
        cropped_source: &str,
        crop: ArtworkCropRect,
        category: &str,
        owner_id: &str,
    ) -> Result<StagedArtwork, String> {
        let originals = format!("{category}/originals");
        let original_path = self.stage_managed_artwork(original_source, &originals, owner_id)?;
        let display_path = self.stage_managed_artwork(cropped_source, category, owner_id);
        match display_path {
            Ok(display_path) => Ok(StagedArtwork {
                display_path,
                original_path,
                crop,
            }),
            Err(error) => {
                self.remove_managed_path(Some(&original_path));
                Err(error)
            }
        }
    }

    pub(super) fn cleanup_staged_artwork(&self, staged: Option<&StagedArtwork>) {
        let Some(staged) = staged else { return };
        self.remove_managed_path(Some(&staged.display_path));
        self.remove_managed_path(Some(&staged.original_path));
    }

    pub(super) fn cleanup_previous_artwork(
        &self,
        old_display: Option<&str>,
        old_edit: Option<&ArtworkEditRow>,
        staged: Option<&StagedArtwork>,
    ) {
        if old_display != staged.map(|value| value.display_path.as_str()) {
            self.remove_managed_path(old_display);
        }
        if old_edit.map(|value| value.original_path.as_str())
            != staged.map(|value| value.original_path.as_str())
        {
            self.remove_managed_path(old_edit.map(|value| value.original_path.as_str()));
        }
    }
}

pub(super) fn apply_artwork_edit(
    tx: &rusqlite::Transaction<'_>,
    owner: ArtworkOwnerKind,
    owner_id: &str,
    update: &ArtworkUpdate,
    staged: Option<&StagedArtwork>,
) -> Result<(), String> {
    match update {
        ArtworkUpdate::Keep => Ok(()),
        ArtworkUpdate::Remove => delete_artwork_edit(tx, owner, owner_id),
        ArtworkUpdate::Replace { .. } => {
            let staged = staged.ok_or_else(|| "staged artwork is missing".to_string())?;
            upsert_artwork_edit(tx, owner, owner_id, staged)
        }
    }
}

pub(super) fn delete_artwork_edit(
    conn: &Connection,
    owner: ArtworkOwnerKind,
    owner_id: &str,
) -> Result<(), String> {
    conn.execute(
        "DELETE FROM artwork_sources WHERE owner_kind = ?1 AND owner_id = ?2",
        params![owner.as_str(), owner_id],
    )
    .map(|_| ())
    .map_err(|error| format!("delete artwork source: {error}"))
}

fn upsert_artwork_edit(
    tx: &rusqlite::Transaction<'_>,
    owner: ArtworkOwnerKind,
    owner_id: &str,
    staged: &StagedArtwork,
) -> Result<(), String> {
    tx.execute(
        "INSERT INTO artwork_sources (owner_kind, owner_id, original_path, crop_left, crop_top, crop_width, crop_height) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) ON CONFLICT(owner_kind, owner_id) DO UPDATE SET original_path = excluded.original_path, crop_left = excluded.crop_left, crop_top = excluded.crop_top, crop_width = excluded.crop_width, crop_height = excluded.crop_height",
        params![owner.as_str(), owner_id, staged.original_path, staged.crop.left, staged.crop.top, staged.crop.width, staged.crop.height],
    )
    .map(|_| ())
    .map_err(|error| format!("store artwork source: {error}"))
}

pub(super) fn query_artwork_edit(
    conn: &Connection,
    owner: ArtworkOwnerKind,
    owner_id: &str,
) -> Result<Option<ArtworkEditRow>, String> {
    conn.query_row(
        "SELECT original_path, crop_left, crop_top, crop_width, crop_height FROM artwork_sources WHERE owner_kind = ?1 AND owner_id = ?2",
        params![owner.as_str(), owner_id],
        |row| {
            Ok(ArtworkEditRow {
                original_path: row.get(0)?,
                crop: ArtworkCropRect {
                    left: row.get(1)?,
                    top: row.get(2)?,
                    width: row.get(3)?,
                    height: row.get(4)?,
                },
            })
        },
    )
    .optional()
    .map_err(|error| format!("load artwork source: {error}"))
}

fn validate_artwork_crop(crop: ArtworkCropRect) -> Result<(), String> {
    let values = [crop.left, crop.top, crop.width, crop.height];
    if values.iter().any(|value| !value.is_finite()) {
        return Err("artwork crop must contain finite values".into());
    }
    if crop.left < 0.0 || crop.top < 0.0 || crop.width <= 0.0 || crop.height <= 0.0 {
        return Err("artwork crop must have positive bounds".into());
    }
    Ok(())
}
