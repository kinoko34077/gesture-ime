use crate::model::{
    ActionInvocation, BindingBehavior, BindingPresentation, Direction8, KeyDefinition, Layout, Macro,
    ProfileBundle, RepeatBehavior,
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
}
