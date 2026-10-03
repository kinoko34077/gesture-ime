use crate::model::{
    ActionInvocation, BindingBehavior, BindingPresentation, Direction8, GesturePoint, GestureSize,
    GestureTerminal, KeyDefinition, Layout, Macro, ProfileBundle, RepeatBehavior,
};
use crate::trie::{BindingTrieCompiler, BindingTrieNode};
use crate::validation::{
    is_valid_id, validate_actions, validate_dimension, validate_presentation, validate_unique_ids,
    ProfileCodec, ProfileLimits, ProfileValidationCode, ProfileValidationError,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardCoordinate {
    pub x: i64,
    pub y: i64,
}

impl BoardCoordinate {
    pub const CENTER: Self = Self { x: 0, y: 0 };
}

pub const fn coordinate_for_direction(direction: Direction8) -> BoardCoordinate {
    match direction {
        Direction8::N => BoardCoordinate { x: 0, y: -1 },
        Direction8::Ne => BoardCoordinate { x: 1, y: -1 },
        Direction8::E => BoardCoordinate { x: 1, y: 0 },
        Direction8::Se => BoardCoordinate { x: 1, y: 1 },
        Direction8::S => BoardCoordinate { x: 0, y: 1 },
        Direction8::Sw => BoardCoordinate { x: -1, y: 1 },
        Direction8::W => BoardCoordinate { x: -1, y: 0 },
        Direction8::Nw => BoardCoordinate { x: -1, y: -1 },
    }
}

pub fn direction_for_unit_coordinate(coordinate: BoardCoordinate) -> Option<Direction8> {
    Direction8::CANONICAL_ORDER
        .into_iter()
        .find(|direction| coordinate_for_direction(*direction) == coordinate)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BoardTransitionLifetime {
    Persistent,
    Transient,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardTransition {
    pub target_board: String,
    pub lifetime: BoardTransitionLifetime,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardHoldTrigger {
    pub delay_ms: i64,
    #[serde(default)]
    pub on_start: Option<Vec<ActionInvocation>>,
    #[serde(default)]
    pub transition: Option<BoardTransition>,
    #[serde(rename = "repeat", default)]
    pub repeat_behavior: Option<RepeatBehavior>,
    #[serde(default)]
    pub suppress_on_release_after_start: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardEntry {
    pub coordinate: BoardCoordinate,
    #[serde(default)]
    pub presentation: Option<BindingPresentation>,
    #[serde(default)]
    pub on_release: Option<Vec<ActionInvocation>>,
    #[serde(default)]
    pub on_transition: Option<Vec<ActionInvocation>>,
    #[serde(default)]
    pub transition: Option<BoardTransition>,
    #[serde(default)]
    pub hold: Option<BoardHoldTrigger>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Board {
    pub id: String,
    pub entries: Vec<BoardEntry>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyBoardRef {
    #[serde(rename = "keyID")]
    pub key_id: String,
    pub board_ref: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardLayer {
    pub id: String,
    pub layout_ref: String,
    pub key_boards: Vec<KeyBoardRef>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardGesturePolicy {
    pub dead_zone: f64,
    pub initial_commit_distance: f64,
    pub continuation_commit_distance: f64,
    pub angular_hysteresis_degrees: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardProfileV2 {
    pub schema: String,
    pub id: String,
    pub name: String,
    pub version: i64,
    pub gesture_policy: BoardGesturePolicy,
    pub key_definitions: Vec<KeyDefinition>,
    pub layouts: Vec<Layout>,
    pub layers: Vec<BoardLayer>,
    pub boards: Vec<Board>,
    pub macros: Vec<Macro>,
    #[serde(default)]
    pub theme: Option<HashMap<String, Value>>,
}

pub struct BoardProfileLimits;

impl BoardProfileLimits {
    pub const BOARDS: usize = 512;
    pub const ENTRIES_PER_BOARD: usize = 256;
    pub const ENTRIES_TOTAL: usize = 16_384;
    pub const KEY_BOARD_REFS_PER_LAYER: usize = 256;
    pub const COORDINATE_ABS: i64 = 127;
    pub const TRANSITIONS_PER_INTERACTION: usize = 64;
}

pub struct BoardProfileCodec;

impl BoardProfileCodec {
    pub fn decode_v2_and_validate(bytes: &[u8]) -> Result<BoardProfileV2, ProfileValidationError> {
        if bytes.len() > ProfileLimits::ENCODED_BYTES {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::ProfileTooLarge,
            ));
        }
        let profile: BoardProfileV2 = serde_json::from_slice(bytes).map_err(|error| {
            ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some(error.to_string()),
            )
        })?;
        BoardProfileValidator::validate(&profile, Some(bytes.len()))?;
        Ok(profile)
    }

    pub fn decode_any_to_v2(bytes: &[u8]) -> Result<BoardProfileV2, ProfileValidationError> {
        if bytes.len() > ProfileLimits::ENCODED_BYTES {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::ProfileTooLarge,
            ));
        }
        let value: Value = serde_json::from_slice(bytes).map_err(|error| {
            ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some(error.to_string()),
            )
        })?;
        match value.get("schema").and_then(Value::as_str) {
            Some("gesture-ime.profile.v2") => Self::decode_v2_and_validate(bytes),
            Some("gesture-ime.profile.v1") => {
                let v1 = ProfileCodec::decode_and_validate(bytes)?;
                let v2 = compile_v1_compatibility_profile(&v1)?;
                BoardProfileValidator::validate(&v2, None)?;
                Ok(v2)
            }
            _ => Err(ProfileValidationError::simple(
                ProfileValidationCode::UnsupportedSchema,
            )),
        }
    }
}

pub struct BoardProfileValidator;

impl BoardProfileValidator {
    pub fn validate(
        profile: &BoardProfileV2,
        encoded_bytes: Option<usize>,
    ) -> Result<(), ProfileValidationError> {
        if encoded_bytes.is_some_and(|size| size > ProfileLimits::ENCODED_BYTES) {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::ProfileTooLarge,
            ));
        }
        if profile.schema != "gesture-ime.profile.v2"
            || profile.version < 1
            || !is_valid_id(&profile.id)
            || profile.name.is_empty()
            || profile.name.chars().count() > 128
        {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::UnsupportedSchema,
            ));
        }

        validate_board_gesture_policy(&profile.gesture_policy)?;

        if profile.key_definitions.len() > ProfileLimits::KEYS {
            return Err(ProfileValidationError::simple(ProfileValidationCode::LimitKeys));
        }
        if profile.layouts.len() > ProfileLimits::LAYOUTS {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::LimitLayouts,
            ));
        }
        if profile.layers.len() > ProfileLimits::LAYERS {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::LimitLayers,
            ));
        }
        if profile.boards.len() > BoardProfileLimits::BOARDS {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::LimitBoards,
            ));
        }
        if profile.macros.len() > ProfileLimits::MACROS {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::LimitMacros,
            ));
        }

        validate_unique_ids(profile.key_definitions.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.layouts.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.layers.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.boards.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.macros.iter().map(|item| item.id.as_str()))?;

        for id in profile
            .key_definitions
            .iter()
            .map(|item| item.id.as_str())
            .chain(profile.layouts.iter().map(|item| item.id.as_str()))
            .chain(profile.layers.iter().map(|item| item.id.as_str()))
            .chain(profile.boards.iter().map(|item| item.id.as_str()))
            .chain(profile.macros.iter().map(|item| item.id.as_str()))
        {
            if !is_valid_id(id) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::UnsupportedSchema,
                    Some(id.to_owned()),
                ));
            }
        }

        for key in &profile.key_definitions {
            validate_presentation(key.presentation.as_ref(), &key.id)?;
            if key.role.as_ref().is_some_and(|role| role.chars().count() > 64) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::UnsupportedSchema,
                    Some(key.id.clone()),
                ));
            }
        }

        let key_ids: HashSet<&str> =
            profile.key_definitions.iter().map(|item| item.id.as_str()).collect();
        let layout_ids: HashSet<&str> =
            profile.layouts.iter().map(|item| item.id.as_str()).collect();
        let board_ids: HashSet<&str> =
            profile.boards.iter().map(|item| item.id.as_str()).collect();
        let layer_ids: HashSet<&str> =
            profile.layers.iter().map(|item| item.id.as_str()).collect();
        let macro_ids: HashSet<&str> =
            profile.macros.iter().map(|item| item.id.as_str()).collect();

        for layout in &profile.layouts {
            if layout.placements.len() > ProfileLimits::PLACEMENTS_PER_LAYOUT {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::LimitPlacements,
                    Some(layout.id.clone()),
                ));
            }
            let mut placed = HashSet::new();
            for placement in &layout.placements {
                if !key_ids.contains(placement.key_id.as_str()) || !placed.insert(&placement.key_id) {
                    return Err(ProfileValidationError::new(
                        if key_ids.contains(placement.key_id.as_str()) {
                            ProfileValidationCode::DuplicateId
                        } else {
                            ProfileValidationCode::MissingReference
                        },
                        Some(placement.key_id.clone()),
                    ));
                }
                if !(0..=255).contains(&placement.row) || !(0..=255).contains(&placement.column) {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::UnsupportedSchema,
                        Some(layout.id.clone()),
                    ));
                }
                validate_dimension(placement.width, &layout.id)?;
                validate_dimension(placement.height, &layout.id)?;
            }
        }

        for layer in &profile.layers {
            if !layout_ids.contains(layer.layout_ref.as_str()) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(layer.layout_ref.clone()),
                ));
            }
            if layer.key_boards.len() > BoardProfileLimits::KEY_BOARD_REFS_PER_LAYER {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::LimitBoardEntries,
                    Some(layer.id.clone()),
                ));
            }
            let layout = profile
                .layouts
                .iter()
                .find(|layout| layout.id == layer.layout_ref)
                .expect("validated layout reference");
            let placed: HashSet<&str> =
                layout.placements.iter().map(|placement| placement.key_id.as_str()).collect();
            let mut mapped = HashSet::new();
            for mapping in &layer.key_boards {
                if !key_ids.contains(mapping.key_id.as_str())
                    || !placed.contains(mapping.key_id.as_str())
                    || !board_ids.contains(mapping.board_ref.as_str())
                {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::MissingReference,
                        Some(format!("{}:{}", layer.id, mapping.key_id)),
                    ));
                }
                if !mapped.insert(mapping.key_id.as_str()) {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::DuplicateId,
                        Some(format!("{}:{}", layer.id, mapping.key_id)),
                    ));
                }
            }
            if mapped != placed {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(layer.id.clone()),
                ));
            }
        }

        let mut total_entries = 0usize;
        for board in &profile.boards {
            if board.entries.len() > BoardProfileLimits::ENTRIES_PER_BOARD {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::LimitBoardEntries,
                    Some(board.id.clone()),
                ));
            }
            total_entries += board.entries.len();
            let mut coordinates = HashSet::new();
            for entry in &board.entries {
                if entry.coordinate.x.abs() > BoardProfileLimits::COORDINATE_ABS
                    || entry.coordinate.y.abs() > BoardProfileLimits::COORDINATE_ABS
                {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::UnsupportedSchema,
                        Some(board.id.clone()),
                    ));
                }
                if !coordinates.insert(entry.coordinate) {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::DuplicateBoardCoordinate,
                        Some(board.id.clone()),
                    ));
                }
                validate_presentation(
                    entry.presentation.as_ref(),
                    &format!("{}:{},{}", board.id, entry.coordinate.x, entry.coordinate.y),
                )?;

                let has_release = entry.on_release.is_some();
                let has_transition = entry.transition.is_some();
                let has_hold = entry.hold.is_some();
                if !has_release && !has_transition && !has_hold {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::UnsupportedSchema,
                        Some(board.id.clone()),
                    ));
                }
                if entry.on_transition.is_some() && !has_transition {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::UnsupportedSchema,
                        Some(board.id.clone()),
                    ));
                }

                if let Some(actions) = &entry.on_release {
                    if actions.len() > ProfileLimits::ENDPOINT_ACTIONS {
                        return Err(ProfileValidationError::simple(
                            ProfileValidationCode::LimitActions,
                        ));
                    }
                    validate_actions(actions, false, &layer_ids, &macro_ids)?;
                }
                if let Some(actions) = &entry.on_transition {
                    if actions.len() > ProfileLimits::ENDPOINT_ACTIONS {
                        return Err(ProfileValidationError::simple(
                            ProfileValidationCode::LimitActions,
                        ));
                    }
                    validate_actions(actions, false, &layer_ids, &macro_ids)?;
                }
                if let Some(transition) = &entry.transition {
                    validate_transition(transition, &board_ids)?;
                }
                if let Some(hold) = &entry.hold {
                    validate_hold(hold, &board_ids, &layer_ids, &macro_ids)?;
                }
            }
        }
        if total_entries > BoardProfileLimits::ENTRIES_TOTAL {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::LimitBoardEntries,
            ));
        }

        for macro_item in &profile.macros {
            if macro_item.actions.len() > ProfileLimits::MACRO_ACTIONS {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::LimitActions,
                    Some(macro_item.id.clone()),
                ));
            }
            validate_actions(&macro_item.actions, true, &layer_ids, &macro_ids)?;
        }

        Ok(())
    }
}

fn validate_board_gesture_policy(
    policy: &BoardGesturePolicy,
) -> Result<(), ProfileValidationError> {
    let valid = policy.dead_zone.is_finite()
        && policy.initial_commit_distance.is_finite()
        && policy.continuation_commit_distance.is_finite()
        && policy.angular_hysteresis_degrees.is_finite()
        && (0.0..=2.0).contains(&policy.dead_zone)
        && policy.initial_commit_distance >= policy.dead_zone
        && policy.initial_commit_distance > 0.0
        && policy.initial_commit_distance <= 4.0
        && policy.continuation_commit_distance >= policy.dead_zone
        && policy.continuation_commit_distance > 0.0
        && policy.continuation_commit_distance <= 4.0
        && policy.angular_hysteresis_degrees >= 0.0
        && policy.angular_hysteresis_degrees < 45.0;
    if valid {
        Ok(())
    } else {
        Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidGesturePolicy,
        ))
    }
}

fn validate_transition(
    transition: &BoardTransition,
    board_ids: &HashSet<&str>,
) -> Result<(), ProfileValidationError> {
    if board_ids.contains(transition.target_board.as_str()) {
        Ok(())
    } else {
        Err(ProfileValidationError::new(
            ProfileValidationCode::MissingReference,
            Some(transition.target_board.clone()),
        ))
    }
}

fn validate_hold(
    hold: &BoardHoldTrigger,
    board_ids: &HashSet<&str>,
    layer_ids: &HashSet<&str>,
    macro_ids: &HashSet<&str>,
) -> Result<(), ProfileValidationError> {
    if !(50..=5000).contains(&hold.delay_ms) {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::UnsupportedSchema,
            Some("hold.delayMs".into()),
        ));
    }
    if hold.transition.is_some() && hold.repeat_behavior.is_some() {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::UnsupportedSchema,
            Some("hold.transition+repeat".into()),
        ));
    }
    if hold.on_start.is_none() && hold.transition.is_none() && hold.repeat_behavior.is_none() {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::UnsupportedSchema,
            Some("hold".into()),
        ));
    }
    if let Some(actions) = &hold.on_start {
        validate_actions(actions, false, layer_ids, macro_ids)?;
    }
    if let Some(transition) = &hold.transition {
        validate_transition(transition, board_ids)?;
    }
    if let Some(repeat) = &hold.repeat_behavior {
        if !(16..=5000).contains(&repeat.interval_ms) {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some("repeat.intervalMs".into()),
            ));
        }
        validate_actions(&repeat.actions, false, layer_ids, macro_ids)?;
    }
    Ok(())
}

pub fn compile_v1_compatibility_profile(
    profile: &ProfileBundle,
) -> Result<BoardProfileV2, ProfileValidationError> {
    let mut boards = Vec::new();
    let mut layers = Vec::new();
    let mut next_board_index = 0usize;

    for (layer_index, layer) in profile.layers.iter().enumerate() {
        let layout = profile
            .layouts
            .iter()
            .find(|layout| layout.id == layer.layout_ref)
            .ok_or_else(|| {
                ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(layer.layout_ref.clone()),
                )
            })?;
        let binding_set = profile
            .binding_sets
            .iter()
            .find(|set| set.id == layer.binding_set_ref)
            .ok_or_else(|| {
                ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(layer.binding_set_ref.clone()),
                )
            })?;

        let mut key_boards = Vec::new();
        for (key_index, placement) in layout.placements.iter().enumerate() {
            let trie = BindingTrieCompiler::compile(binding_set, &placement.key_id)?;
            let root = compile_v1_node(
                &trie.root,
                layer_index,
                key_index,
                &mut next_board_index,
                &mut boards,
            )?;
            key_boards.push(KeyBoardRef {
                key_id: placement.key_id.clone(),
                board_ref: root,
            });
        }
        layers.push(BoardLayer {
            id: layer.id.clone(),
            layout_ref: layer.layout_ref.clone(),
            key_boards,
        });
    }

    Ok(BoardProfileV2 {
        schema: "gesture-ime.profile.v2".into(),
        id: profile.id.clone(),
        name: profile.name.clone(),
        version: profile.version,
        gesture_policy: BoardGesturePolicy {
            dead_zone: profile.gesture_policy.dead_zone,
            initial_commit_distance: profile.gesture_policy.stage1_commit_distance,
            continuation_commit_distance: profile.gesture_policy.stage2_commit_distance,
            angular_hysteresis_degrees: profile.gesture_policy.angular_hysteresis_degrees,
        },
        key_definitions: profile.key_definitions.clone(),
        layouts: profile.layouts.clone(),
        layers,
        boards,
        macros: profile.macros.clone(),
        theme: profile.theme.clone(),
    })
}

fn compile_v1_node(
    node: &BindingTrieNode,
    layer_index: usize,
    key_index: usize,
    next_board_index: &mut usize,
    boards: &mut Vec<Board>,
) -> Result<String, ProfileValidationError> {
    let board_id = format!(
        "compat.l{layer_index}.k{key_index}.b{}",
        *next_board_index
    );
    *next_board_index += 1;

    let mut entries = Vec::new();
    if let Some(behavior) = &node.behavior {
        entries.push(entry_from_v1_behavior(BoardCoordinate::CENTER, behavior));
    }

    for direction in Direction8::CANONICAL_ORDER {
        let Some(child) = node.children.get(&direction) else {
            continue;
        };
        let coordinate = coordinate_for_direction(direction);
        if child.children.is_empty() {
            if let Some(behavior) = &child.behavior {
                entries.push(entry_from_v1_behavior(coordinate, behavior));
            }
        } else {
            let target = compile_v1_node(
                child,
                layer_index,
                key_index,
                next_board_index,
                boards,
            )?;
            entries.push(BoardEntry {
                coordinate,
                presentation: child
                    .behavior
                    .as_ref()
                    .and_then(|behavior| behavior.presentation.clone()),
                on_release: None,
                on_transition: None,
                transition: Some(BoardTransition {
                    target_board: target,
                    lifetime: BoardTransitionLifetime::Transient,
                }),
                hold: None,
            });
        }
    }

    boards.push(Board {
        id: board_id.clone(),
        entries,
    });
    Ok(board_id)
}

fn entry_from_v1_behavior(
    coordinate: BoardCoordinate,
    behavior: &BindingBehavior,
) -> BoardEntry {
    BoardEntry {
        coordinate,
        presentation: behavior.presentation.clone(),
        on_release: Some(behavior.on_release.clone()),
        on_transition: None,
        transition: None,
        hold: behavior.hold.as_ref().map(|hold| BoardHoldTrigger {
            delay_ms: hold.delay_ms,
            on_start: Some(hold.on_start.clone()),
            transition: None,
            repeat_behavior: hold.repeat_behavior.clone(),
            suppress_on_release_after_start: hold.suppress_on_release_after_start,
        }),
    }
}

impl BoardProfileV2 {
    pub fn board(&self, board_id: &str) -> Option<&Board> {
        self.boards.iter().find(|board| board.id == board_id)
    }

    pub fn root_board_for_key(&self, layer_id: &str, key_id: &str) -> Option<&str> {
        let layer = self.layers.iter().find(|layer| layer.id == layer_id)?;
        layer
            .key_boards
            .iter()
            .find(|mapping| mapping.key_id == key_id)
            .map(|mapping| mapping.board_ref.as_str())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct BoardSelectionOutcome {
    pub actions: Vec<ActionInvocation>,
    pub transitioned: bool,
    pub terminal: bool,
    pub persistent_board: String,
    pub current_board: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BoardContextState {
    pub root_board: String,
    pub persistent_board: String,
    pub current_board: String,
    pub transition_count: usize,
}

impl BoardContextState {
    pub fn new(
        profile: &BoardProfileV2,
        layer_id: &str,
        key_id: &str,
    ) -> Result<Self, ProfileValidationError> {
        let root = profile
            .root_board_for_key(layer_id, key_id)
            .ok_or_else(|| {
                ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(format!("{layer_id}:{key_id}")),
                )
            })?
            .to_owned();
        Ok(Self {
            root_board: root.clone(),
            persistent_board: root.clone(),
            current_board: root,
            transition_count: 0,
        })
    }

    pub fn select(
        &mut self,
        profile: &BoardProfileV2,
        coordinate: BoardCoordinate,
    ) -> Result<BoardSelectionOutcome, ProfileValidationError> {
        let board = profile.board(&self.current_board).ok_or_else(|| {
            ProfileValidationError::new(
                ProfileValidationCode::MissingReference,
                Some(self.current_board.clone()),
            )
        })?;
        let Some(entry) = board.entries.iter().find(|entry| entry.coordinate == coordinate) else {
            self.complete_transient_chain();
            return Ok(self.outcome(Vec::new(), false, true));
        };

        if let Some(transition) = &entry.transition {
            let actions = entry.on_transition.clone().unwrap_or_default();
            self.apply_transition(profile, transition)?;
            return Ok(self.outcome(actions, true, false));
        }

        let actions = entry.on_release.clone().unwrap_or_default();
        self.complete_transient_chain();
        Ok(self.outcome(actions, false, true))
    }

    pub fn trigger_hold(
        &mut self,
        profile: &BoardProfileV2,
        coordinate: BoardCoordinate,
    ) -> Result<BoardSelectionOutcome, ProfileValidationError> {
        let board = profile.board(&self.current_board).ok_or_else(|| {
            ProfileValidationError::new(
                ProfileValidationCode::MissingReference,
                Some(self.current_board.clone()),
            )
        })?;
        let Some(hold) = board
            .entries
            .iter()
            .find(|entry| entry.coordinate == coordinate)
            .and_then(|entry| entry.hold.as_ref())
        else {
            return Ok(self.outcome(Vec::new(), false, false));
        };

        let actions = hold.on_start.clone().unwrap_or_default();
        if let Some(transition) = &hold.transition {
            self.apply_transition(profile, transition)?;
            Ok(self.outcome(actions, true, false))
        } else {
            Ok(self.outcome(actions, false, false))
        }
    }

    pub fn cancel_transient_chain(&mut self) {
        self.complete_transient_chain();
    }

    fn apply_transition(
        &mut self,
        profile: &BoardProfileV2,
        transition: &BoardTransition,
    ) -> Result<(), ProfileValidationError> {
        if profile.board(&transition.target_board).is_none() {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::MissingReference,
                Some(transition.target_board.clone()),
            ));
        }
        self.transition_count += 1;
        if self.transition_count > BoardProfileLimits::TRANSITIONS_PER_INTERACTION {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::LimitBoardEntries,
                Some("board transition limit".into()),
            ));
        }
        self.current_board = transition.target_board.clone();
        if transition.lifetime == BoardTransitionLifetime::Persistent {
            self.persistent_board = transition.target_board.clone();
        }
        Ok(())
    }

    fn complete_transient_chain(&mut self) {
        self.current_board = self.persistent_board.clone();
        self.transition_count = 0;
    }

    fn outcome(
        &self,
        actions: Vec<ActionInvocation>,
        transitioned: bool,
        terminal: bool,
    ) -> BoardSelectionOutcome {
        BoardSelectionOutcome {
            actions,
            transitioned,
            terminal,
            persistent_board: self.persistent_board.clone(),
            current_board: self.current_board.clone(),
        }
    }
}


#[derive(Debug, Clone, PartialEq)]
pub struct BoardGestureSessionResult {
    pub terminal: GestureTerminal,
    pub dispatched_actions: Vec<ActionInvocation>,
    pub persistent_board: String,
    pub current_board: String,
}

#[derive(Debug, Clone)]
pub struct BoardGestureSession {
    profile: std::sync::Arc<BoardProfileV2>,
    pub profile_revision: String,
    pub context: BoardContextState,
    pub key_size: GestureSize,
    pub selected_coordinate: BoardCoordinate,
    pub anchor: GesturePoint,
    pub last_point: GesturePoint,
    pub candidate_direction: Option<Direction8>,
    pub committed_coordinates: Vec<BoardCoordinate>,
    pub commit_anchors: Vec<GesturePoint>,
    pub terminal: Option<GestureTerminal>,
    pub dispatched_actions: Vec<ActionInvocation>,

    current_time_ms: i64,
    hold_due_ms: Option<i64>,
    repeat_due_ms: Option<i64>,
    hold_started: bool,
    hold_locked: bool,
    selection_locked: bool,
}

impl BoardGestureSession {
    pub fn new(
        profile: std::sync::Arc<BoardProfileV2>,
        profile_revision: impl Into<String>,
        context: BoardContextState,
        key_size: GestureSize,
        touch_down: GesturePoint,
        at_ms: i64,
    ) -> Self {
        let mut session = Self {
            profile,
            profile_revision: profile_revision.into(),
            context,
            key_size,
            selected_coordinate: BoardCoordinate::CENTER,
            anchor: touch_down,
            last_point: touch_down,
            candidate_direction: None,
            committed_coordinates: Vec::new(),
            commit_anchors: Vec::new(),
            terminal: None,
            dispatched_actions: Vec::new(),
            current_time_ms: at_ms,
            hold_due_ms: None,
            repeat_due_ms: None,
            hold_started: false,
            hold_locked: false,
            selection_locked: false,
        };
        session.schedule_current_hold(at_ms);
        session
    }

    pub fn eligible_directions(&self) -> HashSet<Direction8> {
        if self.terminal.is_some() || self.hold_locked || self.selection_locked {
            return HashSet::new();
        }
        let Some(board) = self.profile.board(&self.context.current_board) else {
            return HashSet::new();
        };
        board
            .entries
            .iter()
            .filter_map(|entry| {
                if entry.coordinate == BoardCoordinate::CENTER {
                    None
                } else {
                    direction_for_unit_coordinate(entry.coordinate)
                }
            })
            .collect()
    }

    pub fn move_to(
        &mut self,
        point: GesturePoint,
        at_ms: Option<i64>,
    ) -> Result<(), ProfileValidationError> {
        if self.terminal.is_some() {
            return Ok(());
        }
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms)?;
        }
        self.last_point = point;
        if self.hold_locked || self.selection_locked {
            return Ok(());
        }

        let scale = self.key_size.minimum_dimension();
        if !scale.is_finite() || scale <= 0.0 {
            return Ok(());
        }

        let dx = point.x - self.anchor.x;
        let dy = point.y - self.anchor.y;
        let normalized = dx.hypot(dy) / scale;
        if normalized < self.profile.gesture_policy.dead_zone {
            self.candidate_direction = None;
            return Ok(());
        }

        let eligible = self.eligible_directions();
        if eligible.is_empty() {
            self.candidate_direction = None;
            return Ok(());
        }

        let angle = Self::angle_degrees(dx, dy);
        let nearest = eligible.into_iter().min_by(|lhs, rhs| {
            let lhs_distance = Self::angular_distance(angle, lhs.center_degrees());
            let rhs_distance = Self::angular_distance(angle, rhs.center_degrees());
            lhs_distance
                .total_cmp(&rhs_distance)
                .then_with(|| Self::rank(*lhs).cmp(&Self::rank(*rhs)))
        });
        let Some(nearest) = nearest else {
            return Ok(());
        };

        match self.candidate_direction {
            Some(current) if current != nearest => {
                let nearest_distance =
                    Self::angular_distance(angle, nearest.center_degrees());
                let current_distance =
                    Self::angular_distance(angle, current.center_degrees());
                if nearest_distance + self.profile.gesture_policy.angular_hysteresis_degrees
                    < current_distance
                {
                    self.candidate_direction = Some(nearest);
                }
            }
            None => self.candidate_direction = Some(nearest),
            _ => {}
        }

        let threshold = if self.committed_coordinates.is_empty() {
            self.profile.gesture_policy.initial_commit_distance
        } else {
            self.profile.gesture_policy.continuation_commit_distance
        };

        let Some(direction) = self.candidate_direction else {
            return Ok(());
        };
        if normalized < threshold {
            return Ok(());
        }
        let coordinate = coordinate_for_direction(direction);
        let entry = self
            .current_entry(coordinate)
            .cloned()
            .ok_or_else(|| {
                ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(format!(
                        "{}:{},{}",
                        self.context.current_board, coordinate.x, coordinate.y
                    )),
                )
            })?;

        self.cancel_hold_schedule();
        self.committed_coordinates.push(coordinate);
        self.commit_anchors.push(point);
        self.anchor = point;
        self.selected_coordinate = coordinate;
        self.candidate_direction = None;

        if let Some(transition) = &entry.transition {
            self.dispatched_actions
                .extend(entry.on_transition.clone().unwrap_or_default());
            let profile = std::sync::Arc::clone(&self.profile);
            self.context.apply_transition(&profile, transition)?;
            self.selected_coordinate = BoardCoordinate::CENTER;
            self.selection_locked = false;
            self.hold_started = false;
            self.hold_locked = false;
            self.schedule_current_hold(self.current_time_ms);
        } else {
            self.selection_locked = true;
            self.schedule_current_hold(self.current_time_ms);
        }

        Ok(())
    }

    pub fn advance_time(&mut self, target_ms: i64) -> Result<(), ProfileValidationError> {
        if self.terminal.is_some() || target_ms < self.current_time_ms {
            return Ok(());
        }

        if let Some(due_ms) = self.hold_due_ms {
            if due_ms <= target_ms && !self.hold_started {
                let hold = self
                    .current_entry(self.selected_coordinate)
                    .and_then(|entry| entry.hold.clone());
                if let Some(hold) = hold {
                    self.dispatched_actions
                        .extend(hold.on_start.clone().unwrap_or_default());
                    self.candidate_direction = None;

                    if let Some(transition) = &hold.transition {
                        let profile = std::sync::Arc::clone(&self.profile);
                        self.context.apply_transition(&profile, transition)?;
                        self.anchor = self.last_point;
                        self.selected_coordinate = BoardCoordinate::CENTER;
                        self.selection_locked = false;
                        self.hold_started = false;
                        self.hold_locked = false;
                        self.repeat_due_ms = None;
                        self.hold_due_ms = None;
                        self.current_time_ms = target_ms;
                        self.schedule_current_hold(target_ms);
                        return Ok(());
                    }

                    self.hold_started = true;
                    self.hold_locked = true;
                    if let Some(repeating) = &hold.repeat_behavior {
                        self.repeat_due_ms = Some(due_ms + repeating.interval_ms);
                    }
                }
            }
        }

        if self.hold_started {
            if let Some(repeating) = self
                .current_entry(self.selected_coordinate)
                .and_then(|entry| entry.hold.as_ref())
                .and_then(|hold| hold.repeat_behavior.as_ref())
                .cloned()
            {
                while let Some(due_ms) = self.repeat_due_ms {
                    if due_ms > target_ms || self.terminal.is_some() {
                        break;
                    }
                    self.dispatched_actions.extend(repeating.actions.clone());
                    self.repeat_due_ms = Some(due_ms + repeating.interval_ms);
                }
            }
        }

        self.current_time_ms = target_ms;
        Ok(())
    }

    pub fn touch_up(
        &mut self,
        at_ms: Option<i64>,
    ) -> Result<BoardGestureSessionResult, ProfileValidationError> {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms)?;
        }
        if self.terminal.is_some() {
            return Ok(self.result());
        }

        let entry = self.current_entry(self.selected_coordinate).cloned();
        if let Some(entry) = entry {
            if let Some(transition) = &entry.transition {
                self.dispatched_actions
                    .extend(entry.on_transition.clone().unwrap_or_default());
                let profile = std::sync::Arc::clone(&self.profile);
                self.context.apply_transition(&profile, transition)?;
                self.selected_coordinate = BoardCoordinate::CENTER;
            } else {
                let suppress_release = self.hold_started
                    && entry
                        .hold
                        .as_ref()
                        .is_some_and(|hold| hold.suppress_on_release_after_start);
                if !suppress_release {
                    self.dispatched_actions
                        .extend(entry.on_release.unwrap_or_default());
                }
                self.context.complete_transient_chain();
            }
        } else {
            self.context.complete_transient_chain();
        }

        self.terminal = Some(GestureTerminal::Committed);
        self.cancel_hold_schedule();
        Ok(self.result())
    }

    pub fn cancel(
        &mut self,
        at_ms: Option<i64>,
    ) -> Result<BoardGestureSessionResult, ProfileValidationError> {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms)?;
        }
        if self.terminal.is_none() {
            self.context.cancel_transient_chain();
            self.terminal = Some(GestureTerminal::Cancelled);
            self.cancel_hold_schedule();
        }
        Ok(self.result())
    }

    pub fn invalidate(
        &mut self,
        at_ms: Option<i64>,
    ) -> Result<BoardGestureSessionResult, ProfileValidationError> {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms)?;
        }
        if self.terminal.is_none() {
            self.context.cancel_transient_chain();
            self.terminal = Some(GestureTerminal::Invalidated);
            self.cancel_hold_schedule();
        }
        Ok(self.result())
    }

    fn current_entry(&self, coordinate: BoardCoordinate) -> Option<&BoardEntry> {
        self.profile
            .board(&self.context.current_board)?
            .entries
            .iter()
            .find(|entry| entry.coordinate == coordinate)
    }

    fn schedule_current_hold(&mut self, at_ms: i64) {
        self.hold_started = false;
        self.hold_locked = false;
        self.repeat_due_ms = None;
        self.hold_due_ms = self
            .current_entry(self.selected_coordinate)
            .and_then(|entry| entry.hold.as_ref())
            .map(|hold| at_ms + hold.delay_ms);
    }

    fn cancel_hold_schedule(&mut self) {
        self.hold_due_ms = None;
        self.repeat_due_ms = None;
    }

    fn result(&self) -> BoardGestureSessionResult {
        BoardGestureSessionResult {
            terminal: self.terminal.unwrap_or(GestureTerminal::Cancelled),
            dispatched_actions: self.dispatched_actions.clone(),
            persistent_board: self.context.persistent_board.clone(),
            current_board: self.context.current_board.clone(),
        }
    }

    fn rank(direction: Direction8) -> usize {
        Direction8::CANONICAL_ORDER
            .iter()
            .position(|candidate| *candidate == direction)
            .unwrap_or(usize::MAX)
    }

    fn angle_degrees(dx: f64, dy: f64) -> f64 {
        let raw = dy.atan2(dx).to_degrees();
        if raw < 0.0 { raw + 360.0 } else { raw }
    }

    fn angular_distance(lhs: f64, rhs: f64) -> f64 {
        let delta = (lhs - rhs).abs() % 360.0;
        delta.min(360.0 - delta)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const V2_CARDINAL: &[u8] = include_bytes!(
        "../../../spec/conformance/fixtures/profile-v2-cardinal-chain.valid.json"
    );
    const V2_LIFETIME: &[u8] = include_bytes!(
        "../../../spec/conformance/fixtures/profile-v2-lifetime-hold.valid.json"
    );
    const V2_MISSING: &[u8] = include_bytes!(
        "../../../spec/conformance/fixtures/profile-v2-missing-board.invalid.json"
    );
    const V2_DUPLICATE: &[u8] = include_bytes!(
        "../../../spec/conformance/fixtures/profile-v2-duplicate-coordinate.invalid.json"
    );
    const V1_TWO_STAGE: &[u8] = include_bytes!(
        "../../../spec/conformance/fixtures/profile-diagonal-two-stage.valid.json"
    );

    #[test]
    fn validates_native_v2_and_sparse_coordinates() {
        let profile = BoardProfileCodec::decode_v2_and_validate(V2_CARDINAL).unwrap();
        let board = profile.board("board.kana.a.e").unwrap();
        assert!(board
            .entries
            .iter()
            .any(|entry| entry.coordinate == BoardCoordinate { x: 2, y: -3 }));
    }

    #[test]
    fn rejects_v2_missing_board_and_duplicate_coordinate() {
        let missing = BoardProfileCodec::decode_v2_and_validate(V2_MISSING).unwrap_err();
        assert_eq!(missing.code, ProfileValidationCode::MissingReference);

        let duplicate = BoardProfileCodec::decode_v2_and_validate(V2_DUPLICATE).unwrap_err();
        assert_eq!(
            duplicate.code,
            ProfileValidationCode::DuplicateBoardCoordinate
        );
    }

    #[test]
    fn v1_normalizes_to_v2_boards() {
        let profile = BoardProfileCodec::decode_any_to_v2(V1_TWO_STAGE).unwrap();
        assert_eq!(profile.schema, "gesture-ime.profile.v2");
        assert!(!profile.boards.is_empty());
        let root = profile.root_board_for_key("base", "kana.a").unwrap();
        let root_board = profile.board(root).unwrap();
        let east = root_board
            .entries
            .iter()
            .find(|entry| entry.coordinate == BoardCoordinate { x: 1, y: 0 })
            .unwrap();
        assert!(east.transition.is_some());
    }

    #[test]
    fn transient_chain_returns_to_baseline_and_persistent_replaces_it() {
        let profile = BoardProfileCodec::decode_v2_and_validate(V2_LIFETIME).unwrap();
        let mut context = BoardContextState::new(&profile, "base", "key.mode").unwrap();

        let first = context
            .select(&profile, BoardCoordinate { x: 1, y: 0 })
            .unwrap();
        assert!(first.transitioned);
        assert_eq!(context.current_board, "board.transient");
        assert_eq!(context.persistent_board, "board.root");

        context
            .select(&profile, BoardCoordinate { x: 1, y: 1 })
            .unwrap();
        assert_eq!(context.current_board, "board.transient.deep");
        context.select(&profile, BoardCoordinate::CENTER).unwrap();
        assert_eq!(context.current_board, "board.root");

        context
            .select(&profile, BoardCoordinate { x: 0, y: -1 })
            .unwrap();
        assert_eq!(context.persistent_board, "board.persistent");
        assert_eq!(context.current_board, "board.persistent");
        context.select(&profile, BoardCoordinate::CENTER).unwrap();
        assert_eq!(context.current_board, "board.persistent");
    }

    #[test]
    fn hold_uses_the_same_transition_semantics() {
        let profile = BoardProfileCodec::decode_v2_and_validate(V2_LIFETIME).unwrap();
        let mut context = BoardContextState::new(&profile, "base", "key.mode").unwrap();
        let outcome = context
            .trigger_hold(&profile, BoardCoordinate::CENTER)
            .unwrap();
        assert!(outcome.transitioned);
        assert_eq!(context.current_board, "board.hold");
        assert_eq!(context.persistent_board, "board.root");
        context.select(&profile, BoardCoordinate::CENTER).unwrap();
        assert_eq!(context.current_board, "board.root");
    }

    #[test]
    fn gesture_session_chains_board_transition_with_anchor_reset() {
        let profile = std::sync::Arc::new(
            BoardProfileCodec::decode_v2_and_validate(V2_CARDINAL).unwrap(),
        );
        let context = BoardContextState::new(&profile, "base", "kana.a").unwrap();
        let mut session = BoardGestureSession::new(
            profile,
            "r1",
            context,
            GestureSize { width: 1.0, height: 1.0 },
            GesturePoint { x: 0.0, y: 0.0 },
            0,
        );

        session
            .move_to(GesturePoint { x: 0.5, y: 0.0 }, Some(10))
            .unwrap();
        assert_eq!(session.context.current_board, "board.kana.a.e");
        assert_eq!(session.anchor, GesturePoint { x: 0.5, y: 0.0 });
        assert_eq!(session.eligible_directions(), HashSet::from([Direction8::N]));

        session
            .move_to(GesturePoint { x: 0.5, y: -0.5 }, Some(20))
            .unwrap();
        assert_eq!(
            session.committed_coordinates,
            vec![BoardCoordinate { x: 1, y: 0 }, BoardCoordinate { x: 0, y: -1 }]
        );
        let result = session.touch_up(Some(30)).unwrap();
        assert_eq!(result.terminal, GestureTerminal::Committed);
        assert_eq!(result.current_board, "board.kana.a");
        assert_eq!(result.dispatched_actions.len(), 1);
        assert_eq!(result.dispatched_actions[0].action_id, "text.insert");
        assert_eq!(
            result.dispatched_actions[0]
                .arguments
                .get("text")
                .and_then(Value::as_str),
            Some("ゑ")
        );
    }

    #[test]
    fn gesture_session_release_after_transition_uses_target_center_endpoint() {
        let profile = std::sync::Arc::new(
            BoardProfileCodec::decode_v2_and_validate(V2_CARDINAL).unwrap(),
        );
        let context = BoardContextState::new(&profile, "base", "kana.a").unwrap();
        let mut session = BoardGestureSession::new(
            profile,
            "r1",
            context,
            GestureSize { width: 1.0, height: 1.0 },
            GesturePoint { x: 0.0, y: 0.0 },
            0,
        );
        session
            .move_to(GesturePoint { x: 0.5, y: 0.0 }, Some(10))
            .unwrap();
        let result = session.touch_up(Some(11)).unwrap();
        assert_eq!(
            result.dispatched_actions[0]
                .arguments
                .get("text")
                .and_then(Value::as_str),
            Some("え")
        );
        assert_eq!(result.current_board, "board.kana.a");
    }

    #[test]
    fn gesture_session_hold_can_transition_then_release_target_center() {
        let profile = std::sync::Arc::new(
            BoardProfileCodec::decode_v2_and_validate(V2_LIFETIME).unwrap(),
        );
        let context = BoardContextState::new(&profile, "base", "key.mode").unwrap();
        let mut session = BoardGestureSession::new(
            profile,
            "r1",
            context,
            GestureSize { width: 1.0, height: 1.0 },
            GesturePoint { x: 0.0, y: 0.0 },
            0,
        );
        session.advance_time(450).unwrap();
        assert_eq!(session.context.current_board, "board.hold");
        let result = session.touch_up(Some(451)).unwrap();
        assert_eq!(result.current_board, "board.root");
        assert_eq!(
            result.dispatched_actions[0]
                .arguments
                .get("text")
                .and_then(Value::as_str),
            Some("H")
        );
    }

    #[test]
    fn wider_sparse_coordinates_are_not_misclassified_as_direction8() {
        let profile = std::sync::Arc::new(
            BoardProfileCodec::decode_v2_and_validate(V2_CARDINAL).unwrap(),
        );
        let mut context = BoardContextState::new(&profile, "base", "kana.a").unwrap();
        context
            .select(&profile, BoardCoordinate { x: 1, y: 0 })
            .unwrap();
        let session = BoardGestureSession::new(
            profile,
            "r1",
            context,
            GestureSize { width: 1.0, height: 1.0 },
            GesturePoint { x: 0.0, y: 0.0 },
            0,
        );
        assert_eq!(session.eligible_directions(), HashSet::from([Direction8::N]));
    }
}
