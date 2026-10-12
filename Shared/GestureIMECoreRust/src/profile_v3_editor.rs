//! Canonical Profile v3 authoring state shared by Web, iOS and Android.
//! Platform persistence and UI state are deliberately outside this module.
use crate::profile_v3::{
    ActionInvocationV3, BoardEntryV3, BoardRectV3, BoardV3, BoardTransitionLifetimeV3,
    BoardTransitionV3, EndpointBehaviorV3, EntryResolverV3, HoldBehaviorV3, MacroV3,
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
    CreateDirectionalStage {
        #[serde(rename = "boardId")]
        board_id: String,
        direction: String,
        // Required: never discard authored output via an omitted flag.
        #[serde(rename = "replaceExistingOutput")]
        replace_existing_output: bool,
    },
    CreateReachableHoldSurface {
        #[serde(rename = "boardId")]
        board_id: String,
        #[serde(rename = "entryId")]
        entry_id: String,
        #[serde(rename = "delayMs")]
        delay_ms: i64,
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
            EditorCommandV3::CreateDirectionalStage {
                board_id, direction, replace_existing_output,
            } => {
                // Fixed 3x3 *authoring* slots. Missing directions are not
                // semantic hit targets until explicitly authored.
                let (dx, dy, short) = match direction.as_str() {
                    "northWest" => (-3, -3, "nw"),
                    "north" => (-1, -3, "n"),
                    "northEast" => (1, -3, "ne"),
                    "west" => (-3, -1, "w"),
                    "east" => (1, -1, "e"),
                    "southWest" => (-3, 1, "sw"),
                    "south" => (-1, 1, "s"),
                    "southEast" => (1, 1, "se"),
                    _ => return Err("direction must be one of the eight named directions".to_owned()),
                };
                let rect = BoardRectV3 {
                    x: dx, y: dy, width: 2, height: 2, extra: V3Extra::new()
                };
                let board_index = next.boards.iter()
                    .position(|board| board.id == board_id)
                    .ok_or_else(|| format!("Board not found: {board_id}"))?;
                let parent = &next.boards[board_index];
                if !parent.entries.iter().any(|entry| entry.rect.contains_origin()) {
                    return Err("directional Stage needs a Board with an origin".to_owned());
                }
                let overlaps: Vec<usize> = parent.entries.iter().enumerate()
                    .filter(|(_, entry)| entry.rect.overlaps_positive_area(&rect))
                    .map(|(index, _)| index).collect();
                if overlaps.len() > 1 {
                    return Err("direction overlaps several existing inputs".to_owned());
                }
                if let Some(&index) = overlaps.first() {
                    let previous = &parent.entries[index];
                    if previous.rect.x != dx || previous.rect.y != dy
                        || previous.rect.width != 2 || previous.rect.height != 2
                    {
                        return Err("direction is occupied by a nonstandard input region".to_owned());
                    }
                    let behavior = &previous.resolver.default;
                    if !previous.resolver.cases.is_empty() || behavior.hold.is_some() {
                        return Err("existing conditions or Hold require advanced editing".to_owned());
                    }
                    if behavior.transition.is_some() {
                        return Err("direction already has a next Stage".to_owned());
                    }
                    if !behavior.on_release.is_empty() && !replace_existing_output {
                        return Err("confirm before replacing this direction's output".to_owned());
                    }
                }
                let serial = (1..=1_000_000u32)
                    .find(|id| !next.boards.iter()
                        .any(|board| board.id == format!("board.user.stage.{id}")))
                    .ok_or_else(|| "no available Stage Board ID".to_owned())?;
                let target_id = format!("board.user.stage.{serial}");
                let target_center_id = format!("entry.user.stage.center.{serial}");
                let parent_entry_id = format!("entry.user.direction.{short}.{serial}");
                let transition = BoardTransitionV3 {
                    target_board_ref: target_id.clone(),
                    lifetime: BoardTransitionLifetimeV3::Transient,
                    extra: V3Extra::new(),
                };
                let parent = &mut next.boards[board_index];
                if let Some(&index) = overlaps.first() {
                    let behavior = &mut parent.entries[index].resolver.default;
                    // The explicit replacement flag is required for nonempty output.
                    behavior.on_release.clear();
                    behavior.transition = Some(transition);
                } else {
                    parent.entries.push(BoardEntryV3 {
                        id: parent_entry_id,
                        rect,
                        resolver: EntryResolverV3 {
                            cases: Vec::new(),
                            default: EndpointBehaviorV3 {
                                transition: Some(transition),
                                ..EndpointBehaviorV3::default()
                            },
                            extra: V3Extra::new(),
                        },
                        gesture_policy_override: None,
                        guide_label_overrides: None,
                        extra: V3Extra::new(),
                    });
                }
                next.boards.push(BoardV3 {
                    id: target_id,
                    entries: vec![BoardEntryV3 {
                        id: target_center_id,
                        rect: BoardRectV3 {
                            x: -1, y: -1, width: 2, height: 2, extra: V3Extra::new()
                        },
                        resolver: EntryResolverV3 {
                            cases: Vec::new(),
                            default: EndpointBehaviorV3::default(),
                            extra: V3Extra::new(),
                        },
                        gesture_policy_override: None,
                        guide_label_overrides: None,
                        extra: V3Extra::new(),
                    }],
                    extra: V3Extra::new(),
                });
            }
            EditorCommandV3::CreateReachableHoldSurface {
                board_id, entry_id, delay_ms,
            } => {
                if !(50..=5000).contains(&delay_ms) {
                    return Err("Hold delayMs must be from 50 to 5000".to_owned());
                }
                // Resolve the *reachable* entry. An ordinary root key with an
                // immediate transition cannot itself receive a useful Hold.
                let source = next.boards.iter()
                    .find(|board| board.id == board_id)
                    .ok_or_else(|| format!("Board not found: {board_id}"))?
                    .entries.iter()
                    .find(|entry| entry.id == entry_id)
                    .ok_or_else(|| format!("Key not found: {board_id}/{entry_id}"))?;
                if !source.resolver.cases.is_empty() {
                    return Err("conditional source Hold requires advanced editing".to_owned());
                }
                if source.resolver.default.hold.is_some() {
                    return Err("source already has Hold behavior".to_owned());
                }
                let relative = source.resolver.default.transition.as_ref()
                    .map(|transition| transition.target_board_ref.clone());
                // A shared relative Board may be reached from other keys or
                // conditional/Hold paths. Mutating its origin would also alter
                // those inputs: reject rather than silently share this Hold.
                if let Some(target) = relative.as_ref() {
                    let incoming = next.boards.iter().flat_map(|b| b.entries.iter())
                        .map(|entry| {
                            std::iter::once(&entry.resolver.default)
                                .chain(entry.resolver.cases.iter().map(|case| &case.behavior))
                                .map(|behavior| {
                                    usize::from(behavior.transition.as_ref()
                                        .is_some_and(|t| &t.target_board_ref == target))
                                        + usize::from(behavior.hold.as_ref()
                                            .and_then(|h| h.transition.as_ref())
                                            .is_some_and(|t| &t.target_board_ref == target))
                                }).sum::<usize>()
                        }).sum::<usize>();
                    if incoming != 1 {
                        return Err("shared relative Board requires separate Hold authoring".to_owned());
                    }
                }
                let (effective_board_id, effective_entry_id) = match relative {
                    Some(target) => {
                        let relative_board = next.boards.iter()
                            .find(|board| board.id == target)
                            .ok_or_else(|| format!("relative Board not found: {target}"))?;
                        let origins: Vec<&BoardEntryV3> = relative_board.entries.iter()
                            .filter(|entry| entry.rect.contains_origin()).collect();
                        if origins.len() != 1 {
                            return Err("relative Board must have exactly one origin for Hold".to_owned());
                        }
                        (target, origins[0].id.clone())
                    }
                    None => (board_id, entry_id),
                };
                let serial = (1..=1_000_000u32)
                    .find(|id| !next.boards.iter()
                        .any(|board| board.id == format!("board.user.hold.{id}")))
                    .ok_or_else(|| "no available Hold Board ID".to_owned())?;
                let hold_board_id = format!("board.user.hold.{serial}");
                let center_id = format!("entry.user.hold.center.{serial}");
                let effective_board = next.boards.iter_mut()
                    .find(|board| board.id == effective_board_id)
                    .ok_or_else(|| "Hold source Board is missing".to_owned())?;
                let endpoint = effective_board.entries.iter_mut()
                    .find(|entry| entry.id == effective_entry_id)
                    .ok_or_else(|| "Hold source endpoint is missing".to_owned())?;
                if endpoint.resolver.default.hold.is_some()
                    || endpoint.resolver.cases.iter().any(|case| case.behavior.hold.is_some())
                {
                    return Err("endpoint already has Hold behavior".to_owned());
                }
                if endpoint.resolver.default.transition.is_some()
                    || endpoint.resolver.cases.iter().any(|case| case.behavior.transition.is_some())
                {
                    return Err("immediate transition makes this Hold unreachable".to_owned());
                }
                // A conditional key (e.g. Latin upper-case output) must use
                // the SAME reachable Hold transition in every existing resolver
                // branch; adding only to default would disable Hold on matches.
                // Conditions and existing release actions remain unchanged.
                let new_hold = HoldBehaviorV3 {
                    delay_ms,
                    on_start: Vec::new(),
                    transition: Some(BoardTransitionV3 {
                        target_board_ref: hold_board_id.clone(),
                        lifetime: BoardTransitionLifetimeV3::Transient,
                        extra: V3Extra::new(),
                    }),
                    repeat_behavior: None,
                    suppress_on_release_after_start: true,
                    extra: V3Extra::new(),
                };
                endpoint.resolver.default.hold = Some(new_hold.clone());
                for case in &mut endpoint.resolver.cases {
                    case.behavior.hold = Some(new_hold.clone());
                }
                next.boards.push(BoardV3 {
                    id: hold_board_id,
                    entries: vec![BoardEntryV3 {
                        id: center_id,
                        rect: BoardRectV3 {
                            x: -1, y: -1, width: 2, height: 2, extra: V3Extra::new()
                        },
                        resolver: EntryResolverV3 {
                            cases: Vec::new(),
                            default: EndpointBehaviorV3::default(),
                            extra: V3Extra::new(),
                        },
                        gesture_policy_override: None,
                        guide_label_overrides: None,
                        extra: V3Extra::new(),
                    }],
                    extra: V3Extra::new(),
                });
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
