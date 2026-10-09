//! Canonical Profile v3 authoring state shared by Web, iOS and Android.
//! Platform persistence and UI state are deliberately outside this module.
use crate::profile_v3::{PresentationV3, ProfileBundleV3, ResolvedStringV3, V3Extra};
use crate::profile_v3_validation::ProfileV3Codec;
use serde::Deserialize;
use serde_json::json;

const HISTORY_CAPACITY: usize = 100;
const MAX_COMMAND_BYTES: usize = 32 * 1024;

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
enum EditorCommandV3 {
    RenameProfile { name: String },
    SetEntryDefaultText {
        #[serde(rename = "boardId")]
        board_id: String,
        #[serde(rename = "entryId")]
        entry_id: String,
        text: Option<String>,
    },
}

/// A revisioned, atomic authoring session; platform hosts store the exported JSON.
/// This M2a slice only edits Profile name and the default Key presentation text.
pub struct ProfileEditorV3 {
    current: ProfileBundleV3,
    undo_stack: Vec<ProfileBundleV3>,
    redo_stack: Vec<ProfileBundleV3>,
    revision: u32,
}

impl ProfileEditorV3 {
    pub fn open(profile_json: &str) -> Result<Self, String> {
        let current = ProfileV3Codec::decode_and_validate(profile_json.as_bytes())
            .map_err(|error| format!("{error:?}"))?;
        Ok(Self {
            current,
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            revision: 0,
        })
    }

    pub fn revision(&self) -> u32 {
        self.revision
    }

    pub fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    pub fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    pub fn export_json(&self) -> Result<String, String> {
        let bytes = self.current.encode().map_err(|error| error.to_string())?;
        String::from_utf8(bytes).map_err(|error| error.to_string())
    }

    pub fn snapshot_json(&self) -> Result<String, String> {
        Ok(json!({
            "revision": self.revision,
            "profileId": self.current.id,
            "name": self.current.name,
            "canUndo": self.can_undo(),
            "canRedo": self.can_redo(),
            "profileJSON": self.export_json()?
        }).to_string())
    }

    /// On any error neither current Profile nor undo/redo/revision changes.
    /// No-op mutations are deliberately not added to the history.
    pub fn apply_command_json(
        &mut self,
        command_json: &str,
        expected_revision: u32,
    ) -> Result<bool, String> {
        if self.revision != expected_revision {
            return Err("editor revision mismatch; reload before editing".to_owned());
        }
        if command_json.len() > MAX_COMMAND_BYTES {
            return Err("editor command exceeds 32 KiB".to_owned());
        }
        let command: EditorCommandV3 =
            serde_json::from_str(command_json).map_err(|error| error.to_string())?;
        let mut next = self.current.clone();

        match command {
            EditorCommandV3::RenameProfile { name } => next.name = name,
            EditorCommandV3::SetEntryDefaultText {
                board_id,
                entry_id,
                text,
            } => {
                let board = next
                    .boards
                    .iter_mut()
                    .find(|board| board.id == board_id)
                    .ok_or_else(|| format!("Board not found: {board_id}"))?;
                let entry = board
                    .entries
                    .iter_mut()
                    .find(|entry| entry.id == entry_id)
                    .ok_or_else(|| format!("Key not found: {board_id}/{entry_id}"))?;
                let behavior = &mut entry.resolver.default;
                let mut presentation = behavior.presentation.take().unwrap_or_default();
                presentation.text = text.map(|value| {
                    let mut resolved = presentation.text.take().unwrap_or_else(|| {
                        ResolvedStringV3 {
                            base: String::new(),
                            transforms: Vec::new(),
                            extra: V3Extra::new(),
                        }
                    });
                    resolved.base = value;
                    resolved
                });
                behavior.presentation =
                    if presentation.text.is_none()
                        && presentation.accessibility_label.is_none()
                        && presentation.extra.is_empty()
                    {
                        None
                    } else {
                        Some(presentation)
                    };
            }
        }

        let encoded = next.encode().map_err(|error| error.to_string())?;
        let validated =
            ProfileV3Codec::decode_and_validate(&encoded)
                .map_err(|error| format!("{error:?}"))?;
        if validated == self.current {
            return Ok(false);
        }
        let revision = self
            .revision
            .checked_add(1)
            .ok_or_else(|| "editor revision exhausted".to_owned())?;
        Self::push(&mut self.undo_stack, self.current.clone());
        self.current = validated;
        self.redo_stack.clear();
        self.revision = revision;
        Ok(true)
    }

    pub fn undo(&mut self) -> Result<bool, String> {
        let Some(revision) = self.revision.checked_add(1) else {
            return Err("editor revision exhausted".to_owned());
        };
        let Some(previous) = self.undo_stack.pop() else {
            return Ok(false);
        };
        Self::push(&mut self.redo_stack, self.current.clone());
        self.current = previous;
        self.revision = revision;
        Ok(true)
    }

    pub fn redo(&mut self) -> Result<bool, String> {
        let Some(revision) = self.revision.checked_add(1) else {
            return Err("editor revision exhausted".to_owned());
        };
        let Some(next) = self.redo_stack.pop() else {
            return Ok(false);
        };
        Self::push(&mut self.undo_stack, self.current.clone());
        self.current = next;
        self.revision = revision;
        Ok(true)
    }

    fn push(stack: &mut Vec<ProfileBundleV3>, item: ProfileBundleV3) {
        if stack.len() == HISTORY_CAPACITY {
            stack.remove(0);
        }
        stack.push(item);
    }
}
