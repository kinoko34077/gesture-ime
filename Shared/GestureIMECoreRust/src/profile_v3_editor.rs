//! Canonical Profile v3 authoring state shared by Web, iOS and Android.
//! Platform persistence and UI state are deliberately outside this module.
use crate::profile_v3::{
    ActionInvocationV3, BoardTransitionLifetimeV3, BoardTransitionV3, MacroV3,
    ProfileBundleV3, ResolvedStringV3, V3Extra,
};
use crate::profile_v3_validation::ProfileV3Codec;
use serde::Deserialize;
use serde_json::{Value, json};

const HISTORY_CAPACITY: usize = 100;
const MAX_COMMAND_BYTES: usize = 32 * 1024;

#[derive(Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
enum EditorCommandV3 {
    RenameProfile { name: String },
    CreateMacro {
        name: String,
        #[serde(default)]
        actions: Vec<ActionInvocationV3>,
    },
    RenameMacro {
        #[serde(rename = "macroId")]
        macro_id: String,
        name: String,
    },
    SetMacroActions {
        #[serde(rename = "macroId")]
        macro_id: String,
        actions: Vec<ActionInvocationV3>,
    },
    SetEntryDefaultMacroInvocation {
        #[serde(rename = "boardId")]
        board_id: String,
        #[serde(rename = "entryId")]
        entry_id: String,
        #[serde(rename = "macroId")]
        macro_id: String,
        // Required by serde: a missing flag must never silently remove actions.
        enabled: bool,
    },
    SetEntryDefaultText {
        #[serde(rename = "boardId")]
        board_id: String,
        #[serde(rename = "entryId")]
        entry_id: String,
        text: Option<String>,
    },
    SetEntryDefaultTransition {
        #[serde(rename = "boardId")]
        board_id: String,
        #[serde(rename = "entryId")]
        entry_id: String,
        #[serde(rename = "targetBoardId")]
        // Value (not Option<T>) intentionally REQUIRES the field to be present.
        // A missing target must never be interpreted as a destructive clear.
        target_board_id: Value,
        lifetime: Value,
    },
}

/// A revisioned, atomic authoring session; platform hosts store the exported JSON.
/// Commands include stable Macro identity/name/action authoring and key defaults.
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
            EditorCommandV3::CreateMacro { name, actions } => {
                let name = Self::validate_macro_name(&next.macros, name, None)?;
                let id = (1..=1_000_000u32)
                    .map(|serial| format!("macro.user.{serial}"))
                    .find(|id| !next.macros.iter().any(|item| item.id == *id))
                    .ok_or_else(|| "no available Macro ID".to_owned())?;
                next.macros.push(MacroV3 {
                    id,
                    name: Some(name),
                    actions,
                    extra: V3Extra::new(),
                });
            }
            EditorCommandV3::RenameMacro { macro_id, name } => {
                if !next.macros.iter().any(|item| item.id == macro_id) {
                    return Err(format!("Macro not found: {macro_id}"));
                }
                let name = Self::validate_macro_name(&next.macros, name, Some(&macro_id))?;
                let item = next.macros.iter_mut().find(|item| item.id == macro_id)
                    .ok_or_else(|| format!("Macro not found: {macro_id}"))?;
                item.name = Some(name);
            }
            EditorCommandV3::SetMacroActions { macro_id, actions } => {
                let item = next.macros.iter_mut().find(|item| item.id == macro_id)
                    .ok_or_else(|| format!("Macro not found: {macro_id}"))?;
                item.actions = actions;
            }
            EditorCommandV3::SetEntryDefaultMacroInvocation {
                board_id, entry_id, macro_id, enabled,
            } => {
                if !next.macros.iter().any(|item| item.id == macro_id) {
                    return Err(format!("Macro not found: {macro_id}"));
                }
                let board = next.boards.iter_mut()
                    .find(|item| item.id == board_id)
                    .ok_or_else(|| format!("Board not found: {board_id}"))?;
                let entry = board.entries.iter_mut()
                    .find(|item| item.id == entry_id)
                    .ok_or_else(|| format!("Key not found: {board_id}/{entry_id}"))?;
                let actions = &mut entry.resolver.default.on_release;
                let matches_macro = |item: &ActionInvocationV3| {
                    item.action_id == "macro.run"
                        && item.arguments.get("macro").and_then(Value::as_str)
                            == Some(macro_id.as_str())
                };
                if enabled {
                    if !actions.iter().any(matches_macro) {
                        let mut arguments = serde_json::Map::new();
                        arguments.insert("macro".to_owned(), Value::String(macro_id));
                        actions.push(ActionInvocationV3 {
                            action_id: "macro.run".to_owned(),
                            arguments,
                            extra: V3Extra::new(),
                        });
                    }
                } else {
                    // Explicit unassignment removes ONLY the selected Macro call.
                    // Never rewrite unrelated actions or other resolver fields.
                    actions.retain(|item| !matches_macro(item));
                }
            }
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
                let existing_text = presentation.text.take();
                presentation.text = text.map(|value| {
                    let mut resolved = existing_text.unwrap_or_else(|| {
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
            EditorCommandV3::SetEntryDefaultTransition {
                board_id,
                entry_id,
                target_board_id,
                lifetime,
            } => {
                let (target_board_id, lifetime) = match (target_board_id, lifetime) {
                    (Value::Null, Value::Null) => (None, None),
                    (Value::String(target), lifetime) => {
                        let lifetime = serde_json::from_value::<BoardTransitionLifetimeV3>(lifetime)
                            .map_err(|_| "transition lifetime must be persistent or transient".to_owned())?;
                        (Some(target), Some(lifetime))
                    }
                    _ => return Err("transition target and lifetime must both be supplied or both null".to_owned()),
                };
                if let Some(target) = target_board_id.as_deref() {
                    if !next.boards.iter().any(|board| board.id == target) {
                        return Err(format!("Target Board not found: {target}"));
                    }
                }
                let board = next.boards.iter_mut()
                    .find(|board| board.id == board_id)
                    .ok_or_else(|| format!("Board not found: {board_id}"))?;
                let entry = board.entries.iter_mut()
                    .find(|entry| entry.id == entry_id)
                    .ok_or_else(|| format!("Key not found: {board_id}/{entry_id}"))?;
                let previous = entry.resolver.default.transition.take();
                entry.resolver.default.transition = match (target_board_id, lifetime) {
                    (Some(target_board_ref), Some(lifetime)) => Some(BoardTransitionV3 {
                        target_board_ref,
                        lifetime,
                        extra: previous.map(|transition| transition.extra)
                            .unwrap_or_else(V3Extra::new),
                    }),
                    (None, None) => None,
                    _ => unreachable!("target and lifetime already checked"),
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

    /// Canonical authoring comparison: Unicode whitespace trimmed, Unicode lowercase.
    /// Does not perform NFC folding; normalized display strings are stored as entered.
    fn validate_macro_name(
        macros: &[MacroV3],
        name: String,
        except_id: Option<&str>,
    ) -> Result<String, String> {
        let trimmed = name.trim();
        if trimmed.is_empty() || trimmed.chars().count() > 100 {
            return Err("Macro name must be 1–100 characters".to_owned());
        }
        let comparable = trimmed.to_lowercase();
        if macros.iter().filter(|item| Some(item.id.as_str()) != except_id)
            .filter_map(|item| item.name.as_deref())
            .any(|existing| existing.trim().to_lowercase() == comparable)
        {
            return Err("Macro name already exists in this Profile".to_owned());
        }
        Ok(trimmed.to_owned())
    }

    fn push(stack: &mut Vec<ProfileBundleV3>, item: ProfileBundleV3) {
        if stack.len() == HISTORY_CAPACITY {
            stack.remove(0);
        }
        stack.push(item);
    }
}
