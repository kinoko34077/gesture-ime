use crate::model::{
    ActionInvocation, BindingBehavior, BindingPresentation, Direction8, GesturePoint, GestureSize,
    HoldBehavior, KeyDefinition, Layout, Macro, ProfileBundle,
};
use crate::trie::BindingTrieCompiler;
use crate::validation::{
    check_limit, is_valid_id, validate_actions, validate_dimension, validate_presentation,
    validate_unique_ids, ProfileCodec, ProfileLimits, ProfileValidationCode, ProfileValidationError,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardCoordinate {
    pub x: i64,
    pub y: i64,
}

impl BoardCoordinate {
    pub const ORIGIN: Self = Self { x: 0, y: 0 };

    pub fn chebyshev_radius(self) -> i64 {
        self.x.abs().max(self.y.abs())
    }

    pub fn is_origin(self) -> bool {
        self == Self::ORIGIN
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BoardTransitionLifetime {
    Persistent,
    Transient,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardTransition {
    pub target_board_ref: String,
    pub lifetime: BoardTransitionLifetime,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardEntry {
    pub coordinate: BoardCoordinate,
    #[serde(default)]
    pub presentation: Option<BindingPresentation>,
    #[serde(default)]
    pub on_release: Vec<ActionInvocation>,
    #[serde(default)]
    pub hold: Option<HoldBehavior>,
    #[serde(default)]
    pub transition: Option<BoardTransition>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardTrigger {
    #[serde(rename = "type")]
    pub trigger_type: String,
    #[serde(default)]
    pub delay_ms: Option<i64>,
    pub transition: BoardTransition,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardSelectionPolicy {
    pub kind: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Board {
    pub id: String,
    pub selection_policy: BoardSelectionPolicy,
    pub entries: Vec<BoardEntry>,
    #[serde(default)]
    pub triggers: Vec<BoardTrigger>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardEntryPoint {
    pub id: String,
    #[serde(rename = "layerID")]
    pub layer_id: String,
    #[serde(rename = "keyID")]
    pub key_id: String,
    pub trigger: String,
    pub board_ref: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardLayer {
    pub id: String,
    pub layout_ref: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardGesturePolicy {
    pub dead_zone: f64,
    pub initial_cell_commit_distance: f64,
    pub subsequent_cell_commit_distance: f64,
    pub angular_hysteresis_degrees: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileBundleV2 {
    pub schema: String,
    pub id: String,
    pub name: String,
    pub version: i64,
    pub gesture_policy: BoardGesturePolicy,
    pub key_definitions: Vec<KeyDefinition>,
    pub layouts: Vec<Layout>,
    pub layers: Vec<BoardLayer>,
    pub boards: Vec<Board>,
    pub entry_points: Vec<BoardEntryPoint>,
    pub macros: Vec<Macro>,
    #[serde(default)]
    pub theme: Option<HashMap<String, Value>>,
}

pub struct BoardProfileCodec;

impl BoardProfileCodec {
    pub fn decode_and_validate(bytes: &[u8]) -> Result<ProfileBundleV2, ProfileValidationError> {
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
        let schema = value
            .get("schema")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                ProfileValidationError::simple(ProfileValidationCode::UnsupportedSchema)
            })?;

        let profile = match schema {
            "gesture-ime.profile.v1" => {
                let legacy = ProfileCodec::decode_and_validate(bytes)?;
                normalize_v1_profile(&legacy)?
            }
            "gesture-ime.profile.v2" => serde_json::from_value::<ProfileBundleV2>(value).map_err(
                |error| {
                    ProfileValidationError::new(
                        ProfileValidationCode::UnsupportedSchema,
                        Some(error.to_string()),
                    )
                },
            )?,
            _ => {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::UnsupportedSchema,
                ));
            }
        };

        BoardProfileValidator::validate(&profile, Some(bytes.len()))?;
        Ok(profile)
    }

    pub fn migrate_to_v2_json(bytes: &[u8]) -> Result<String, ProfileValidationError> {
        let profile = Self::decode_and_validate(bytes)?;
        serde_json::to_string_pretty(&profile).map_err(|error| {
            ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some(error.to_string()),
            )
        })
    }
}

pub struct BoardProfileValidator;

impl BoardProfileValidator {
    pub fn validate(
        profile: &ProfileBundleV2,
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

        check_limit(
            profile.key_definitions.len(),
            ProfileLimits::KEYS,
            ProfileValidationCode::LimitKeys,
        )?;
        check_limit(
            profile.layouts.len(),
            ProfileLimits::LAYOUTS,
            ProfileValidationCode::LimitLayouts,
        )?;
        check_limit(
            profile.layers.len(),
            ProfileLimits::LAYERS,
            ProfileValidationCode::LimitLayers,
        )?;
        check_limit(
            profile.boards.len(),
            ProfileLimits::BOARDS,
            ProfileValidationCode::LimitBoards,
        )?;
        check_limit(
            profile.entry_points.len(),
            ProfileLimits::ENTRY_POINTS,
            ProfileValidationCode::LimitEntryPoints,
        )?;
        check_limit(
            profile.macros.len(),
            ProfileLimits::MACROS,
            ProfileValidationCode::LimitMacros,
        )?;

        validate_unique_ids(profile.key_definitions.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.layouts.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.layers.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.boards.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.entry_points.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.macros.iter().map(|item| item.id.as_str()))?;

        for id in profile
            .key_definitions
            .iter()
            .map(|item| item.id.as_str())
            .chain(profile.layouts.iter().map(|item| item.id.as_str()))
            .chain(profile.layers.iter().map(|item| item.id.as_str()))
            .chain(profile.boards.iter().map(|item| item.id.as_str()))
            .chain(profile.entry_points.iter().map(|item| item.id.as_str()))
            .chain(profile.macros.iter().map(|item| item.id.as_str()))
        {
            if !is_valid_id(id) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::UnsupportedSchema,
                    Some(id.to_owned()),
                ));
            }
        }

        validate_board_gesture_policy(&profile.gesture_policy)?;

        let key_ids: HashSet<&str> =
            profile.key_definitions.iter().map(|item| item.id.as_str()).collect();
        let layout_ids: HashSet<&str> =
            profile.layouts.iter().map(|item| item.id.as_str()).collect();
        let layer_ids: HashSet<&str> =
            profile.layers.iter().map(|item| item.id.as_str()).collect();
        let board_ids: HashSet<&str> =
            profile.boards.iter().map(|item| item.id.as_str()).collect();
        let macro_ids: HashSet<&str> =
            profile.macros.iter().map(|item| item.id.as_str()).collect();

        for key in &profile.key_definitions {
            validate_presentation(key.presentation.as_ref(), &key.id)?;
            if key
                .role
                .as_ref()
                .is_some_and(|role| role.chars().count() > 64)
            {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::UnsupportedSchema,
                    Some(key.id.clone()),
                ));
            }
        }

        for layout in &profile.layouts {
            check_limit(
                layout.placements.len(),
                ProfileLimits::PLACEMENTS_PER_LAYOUT,
                ProfileValidationCode::LimitPlacements,
            )?;
            for placement in &layout.placements {
                if !key_ids.contains(placement.key_id.as_str()) {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::MissingReference,
                        Some(placement.key_id.clone()),
                    ));
                }
                if !(0..=255).contains(&placement.row)
                    || !(0..=255).contains(&placement.column)
                {
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
                    Some(layer.id.clone()),
                ));
            }
        }

        let mut entry_point_keys = HashSet::new();
        for entry_point in &profile.entry_points {
            if entry_point.trigger != "press"
                || !layer_ids.contains(entry_point.layer_id.as_str())
                || !key_ids.contains(entry_point.key_id.as_str())
                || !board_ids.contains(entry_point.board_ref.as_str())
            {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(entry_point.id.clone()),
                ));
            }
            let unique_key = (
                entry_point.layer_id.as_str(),
                entry_point.key_id.as_str(),
                entry_point.trigger.as_str(),
            );
            if !entry_point_keys.insert(unique_key) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::DuplicateId,
                    Some(format!(
                        "{}:{}:{}",
                        entry_point.layer_id, entry_point.key_id, entry_point.trigger
                    )),
                ));
            }
        }

        for board in &profile.boards {
            if board.selection_policy.kind != "relativeCoordinate" {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::UnsupportedSchema,
                    Some(board.id.clone()),
                ));
            }
            check_limit(
                board.entries.len(),
                ProfileLimits::BOARD_ENTRIES_PER_BOARD,
                ProfileValidationCode::LimitBoardEntries,
            )?;
            check_limit(
                board.triggers.len(),
                ProfileLimits::BOARD_TRIGGERS_PER_BOARD,
                ProfileValidationCode::LimitBoardTriggers,
            )?;

            let mut coordinates = HashSet::new();
            for entry in &board.entries {
                if !(-32..=32).contains(&entry.coordinate.x)
                    || !(-32..=32).contains(&entry.coordinate.y)
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
                    &format!(
                        "{}:{},{}",
                        board.id, entry.coordinate.x, entry.coordinate.y
                    ),
                )?;

                let mut endpoint_actions = entry.on_release.len();
                validate_actions(&entry.on_release, false, &layer_ids, &macro_ids)?;

                if let Some(hold) = &entry.hold {
                    if !(50..=5000).contains(&hold.delay_ms) {
                        return Err(ProfileValidationError::new(
                            ProfileValidationCode::UnsupportedSchema,
                            Some(format!("{}:hold.delayMs", board.id)),
                        ));
                    }
                    endpoint_actions += hold.on_start.len();
                    validate_actions(&hold.on_start, false, &layer_ids, &macro_ids)?;
                    if let Some(repeating) = &hold.repeat_behavior {
                        if !(16..=5000).contains(&repeating.interval_ms) {
                            return Err(ProfileValidationError::new(
                                ProfileValidationCode::UnsupportedSchema,
                                Some(format!("{}:repeat.intervalMs", board.id)),
                            ));
                        }
                        endpoint_actions += repeating.actions.len();
                        validate_actions(&repeating.actions, false, &layer_ids, &macro_ids)?;
                    }
                }
                if endpoint_actions > ProfileLimits::ENDPOINT_ACTIONS {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::LimitActions,
                        Some(board.id.clone()),
                    ));
                }

                if let Some(transition) = &entry.transition {
                    validate_transition(transition, &board_ids, &board.id)?;
                }
            }

            for trigger in &board.triggers {
                if trigger.trigger_type != "hold"
                    || trigger
                        .delay_ms
                        .is_some_and(|delay| !(50..=5000).contains(&delay))
                {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::UnsupportedSchema,
                        Some(board.id.clone()),
                    ));
                }
                validate_transition(&trigger.transition, &board_ids, &board.id)?;
            }
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

fn validate_transition(
    transition: &BoardTransition,
    board_ids: &HashSet<&str>,
    owner: &str,
) -> Result<(), ProfileValidationError> {
    if !board_ids.contains(transition.target_board_ref.as_str()) {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::MissingReference,
            Some(format!("{owner}:{}", transition.target_board_ref)),
        ));
    }
    Ok(())
}

fn validate_board_gesture_policy(
    policy: &BoardGesturePolicy,
) -> Result<(), ProfileValidationError> {
    let valid = policy.dead_zone.is_finite()
        && policy.initial_cell_commit_distance.is_finite()
        && policy.subsequent_cell_commit_distance.is_finite()
        && policy.angular_hysteresis_degrees.is_finite()
        && (0.0..=2.0).contains(&policy.dead_zone)
        && policy.initial_cell_commit_distance > 0.0
        && policy.initial_cell_commit_distance <= 4.0
        && policy.subsequent_cell_commit_distance > 0.0
        && policy.subsequent_cell_commit_distance <= 4.0
        && policy.initial_cell_commit_distance >= policy.dead_zone
        && policy.subsequent_cell_commit_distance >= policy.dead_zone
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

#[derive(Default, Clone)]
struct PrefixNode {
    behavior: Option<BindingBehavior>,
    children: HashSet<Direction8>,
}

pub fn normalize_v1_profile(
    profile: &ProfileBundle,
) -> Result<ProfileBundleV2, ProfileValidationError> {
    let mut boards = Vec::new();
    let mut entry_points = Vec::new();

    for layer in &profile.layers {
        let layout = profile
            .layouts
            .iter()
            .find(|candidate| candidate.id == layer.layout_ref)
            .ok_or_else(|| {
                ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(layer.layout_ref.clone()),
                )
            })?;
        let binding_set = profile
            .binding_sets
            .iter()
            .find(|candidate| candidate.id == layer.binding_set_ref)
            .ok_or_else(|| {
                ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(layer.binding_set_ref.clone()),
                )
            })?;

        for placement in &layout.placements {
            // Reuse the accepted compiler as a compatibility preflight.
            BindingTrieCompiler::compile(binding_set, &placement.key_id)?;

            let mut nodes: HashMap<Vec<Direction8>, PrefixNode> = HashMap::new();
            nodes.entry(Vec::new()).or_default();

            for binding in binding_set
                .bindings
                .iter()
                .filter(|binding| binding.key_id == placement.key_id)
            {
                let path: Vec<Direction8> =
                    binding.path.0.iter().map(|token| token.direction).collect();
                nodes.entry(path.clone()).or_default().behavior =
                    Some(binding.behavior.clone());

                for index in 0..path.len() {
                    let parent = path[..index].to_vec();
                    let child = path[index];
                    nodes.entry(parent).or_default().children.insert(child);
                    nodes.entry(path[..=index].to_vec()).or_default();
                }
            }

            let mut prefixes: Vec<Vec<Direction8>> = nodes.keys().cloned().collect();
            prefixes.sort_by(|lhs, rhs| {
                lhs.len().cmp(&rhs.len()).then_with(|| {
                    direction_path_key(lhs).cmp(&direction_path_key(rhs))
                })
            });

            for prefix in &prefixes {
                let node = nodes.get(prefix).expect("prefix node");
                let board_id = compat_board_id(&layer.id, &placement.key_id, prefix);
                let mut entries = Vec::new();

                if let Some(behavior) = &node.behavior {
                    entries.push(BoardEntry {
                        coordinate: BoardCoordinate::ORIGIN,
                        presentation: behavior.presentation.clone(),
                        on_release: behavior.on_release.clone(),
                        hold: behavior.hold.clone(),
                        transition: None,
                    });
                }

                let mut children: Vec<Direction8> = node.children.iter().copied().collect();
                children.sort_by_key(|direction| direction_rank(*direction));

                for direction in children {
                    let mut child_prefix = prefix.clone();
                    child_prefix.push(direction);
                    let child_node = nodes
                        .get(&child_prefix)
                        .expect("child prefix node");
                    let coordinate = coordinate_from_direction(direction);

                    if child_node.children.is_empty() {
                        let behavior = child_node.behavior.clone().unwrap_or(BindingBehavior {
                            presentation: None,
                            on_release: Vec::new(),
                            hold: None,
                        });
                        entries.push(BoardEntry {
                            coordinate,
                            presentation: behavior.presentation,
                            on_release: behavior.on_release,
                            hold: behavior.hold,
                            transition: None,
                        });
                    } else {
                        entries.push(BoardEntry {
                            coordinate,
                            presentation: child_node
                                .behavior
                                .as_ref()
                                .and_then(|behavior| behavior.presentation.clone()),
                            on_release: Vec::new(),
                            hold: None,
                            transition: Some(BoardTransition {
                                target_board_ref: compat_board_id(
                                    &layer.id,
                                    &placement.key_id,
                                    &child_prefix,
                                ),
                                lifetime: BoardTransitionLifetime::Transient,
                            }),
                        });
                    }
                }

                boards.push(Board {
                    id: board_id,
                    selection_policy: BoardSelectionPolicy {
                        kind: "relativeCoordinate".into(),
                    },
                    entries,
                    triggers: Vec::new(),
                });
            }

            entry_points.push(BoardEntryPoint {
                id: compat_entry_point_id(&layer.id, &placement.key_id),
                layer_id: layer.id.clone(),
                key_id: placement.key_id.clone(),
                trigger: "press".into(),
                board_ref: compat_board_id(&layer.id, &placement.key_id, &[]),
            });
        }
    }

    let normalized = ProfileBundleV2 {
        schema: "gesture-ime.profile.v2".into(),
        id: profile.id.clone(),
        name: profile.name.clone(),
        version: profile.version,
        gesture_policy: BoardGesturePolicy {
            dead_zone: profile.gesture_policy.dead_zone,
            initial_cell_commit_distance: profile.gesture_policy.stage1_commit_distance,
            subsequent_cell_commit_distance: profile.gesture_policy.stage2_commit_distance,
            angular_hysteresis_degrees: profile.gesture_policy.angular_hysteresis_degrees,
        },
        key_definitions: profile.key_definitions.clone(),
        layouts: profile.layouts.clone(),
        layers: profile
            .layers
            .iter()
            .map(|layer| BoardLayer {
                id: layer.id.clone(),
                layout_ref: layer.layout_ref.clone(),
            })
            .collect(),
        boards,
        entry_points,
        macros: profile.macros.clone(),
        theme: profile.theme.clone(),
    };

    BoardProfileValidator::validate(&normalized, None)?;
    Ok(normalized)
}

fn direction_path_key(path: &[Direction8]) -> Vec<usize> {
    path.iter().map(|direction| direction_rank(*direction)).collect()
}

fn direction_rank(direction: Direction8) -> usize {
    Direction8::CANONICAL_ORDER
        .iter()
        .position(|candidate| *candidate == direction)
        .unwrap_or(usize::MAX)
}

pub fn coordinate_from_direction(direction: Direction8) -> BoardCoordinate {
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

pub fn direction_from_coordinate(coordinate: BoardCoordinate) -> Option<Direction8> {
    if coordinate.is_origin() {
        return None;
    }
    let x = coordinate.x.signum();
    let y = coordinate.y.signum();
    match (x, y) {
        (0, -1) => Some(Direction8::N),
        (1, -1) => Some(Direction8::Ne),
        (1, 0) => Some(Direction8::E),
        (1, 1) => Some(Direction8::Se),
        (0, 1) => Some(Direction8::S),
        (-1, 1) => Some(Direction8::Sw),
        (-1, 0) => Some(Direction8::W),
        (-1, -1) => Some(Direction8::Nw),
        _ => None,
    }
}

fn compat_board_id(layer_id: &str, key_id: &str, prefix: &[Direction8]) -> String {
    let raw = format!(
        "board|{layer_id}|{key_id}|{}",
        prefix
            .iter()
            .map(|direction| format!("{direction:?}"))
            .collect::<Vec<_>>()
            .join(",")
    );
    format!("compat.board.{:016x}", fnv1a64(raw.as_bytes()))
}

fn compat_entry_point_id(layer_id: &str, key_id: &str) -> String {
    let raw = format!("entry|{layer_id}|{key_id}|press");
    format!("compat.entry.{:016x}", fnv1a64(raw.as_bytes()))
}

fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BoardSessionTerminal {
    Committed,
    Cancelled,
    Invalidated,
}

#[derive(Debug, Clone)]
pub struct BoardSession {
    pub entry_point_id: String,
    pub profile_revision: String,
    pub policy: BoardGesturePolicy,
    pub key_size: GestureSize,
    pub anchor: GesturePoint,
    pub last_point: GesturePoint,
    pub current_board_id: String,
    pub persistent_board_id: String,
    pub candidate_coordinate: Option<BoardCoordinate>,
    pub selected_coordinate: Option<BoardCoordinate>,
    pub committed_coordinates: Vec<BoardCoordinate>,
    pub transition_count: usize,
    pub transition_limit_hit: bool,
    pub terminal: Option<BoardSessionTerminal>,
    pub dispatched_actions: Vec<ActionInvocation>,
    pub commit_anchors: Vec<GesturePoint>,

    boards: Arc<HashMap<String, Board>>,
    persistent_state: Arc<Mutex<HashMap<String, String>>>,
    current_time_ms: i64,
    entry_hold_due_ms: Option<i64>,
    board_hold_due_ms: Option<(i64, BoardTransition)>,
    repeat_due_ms: Option<i64>,
    hold_started: bool,
    hold_locked: bool,
}

impl BoardSession {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        entry_point: &BoardEntryPoint,
        profile_revision: impl Into<String>,
        boards: Arc<HashMap<String, Board>>,
        persistent_state: Arc<Mutex<HashMap<String, String>>>,
        policy: BoardGesturePolicy,
        key_size: GestureSize,
        touch_down: GesturePoint,
        at_ms: i64,
    ) -> Result<Self, ProfileValidationError> {
        let persistent_board_id = persistent_state
            .lock()
            .ok()
            .and_then(|state| state.get(&entry_point.id).cloned())
            .unwrap_or_else(|| entry_point.board_ref.clone());

        if !boards.contains_key(&persistent_board_id) {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::MissingReference,
                Some(persistent_board_id),
            ));
        }

        let mut session = Self {
            entry_point_id: entry_point.id.clone(),
            profile_revision: profile_revision.into(),
            policy,
            key_size,
            anchor: touch_down,
            last_point: touch_down,
            current_board_id: persistent_board_id.clone(),
            persistent_board_id,
            candidate_coordinate: None,
            selected_coordinate: None,
            committed_coordinates: Vec::new(),
            transition_count: 0,
            transition_limit_hit: false,
            terminal: None,
            dispatched_actions: Vec::new(),
            commit_anchors: Vec::new(),
            boards,
            persistent_state,
            current_time_ms: at_ms,
            entry_hold_due_ms: None,
            board_hold_due_ms: None,
            repeat_due_ms: None,
            hold_started: false,
            hold_locked: false,
        };
        session.schedule_holds(at_ms, true);
        Ok(session)
    }

    pub fn current_board(&self) -> Option<&Board> {
        self.boards.get(&self.current_board_id)
    }

    pub fn eligible_coordinates(&self) -> Vec<BoardCoordinate> {
        let mut coordinates = self
            .current_board()
            .map(|board| {
                board
                    .entries
                    .iter()
                    .filter(|entry| !entry.coordinate.is_origin())
                    .map(|entry| entry.coordinate)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        coordinates.sort_by_key(|coordinate| {
            (
                coordinate.chebyshev_radius(),
                coordinate.y,
                coordinate.x,
            )
        });
        coordinates
    }

    pub fn current_entry(&self) -> Option<&BoardEntry> {
        let coordinate = self.selected_coordinate.unwrap_or(BoardCoordinate::ORIGIN);
        self.current_board()?
            .entries
            .iter()
            .find(|entry| entry.coordinate == coordinate)
    }

    pub fn move_to(&mut self, point: GesturePoint, at_ms: Option<i64>) {
        if self.terminal.is_some() {
            return;
        }
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        self.last_point = point;
        if self.hold_locked || self.selected_coordinate.is_some() {
            return;
        }

        let scale = self.key_size.minimum_dimension();
        if !scale.is_finite() || scale <= 0.0 {
            return;
        }
        let dx = point.x - self.anchor.x;
        let dy = point.y - self.anchor.y;
        let normalized = dx.hypot(dy) / scale;

        if normalized < self.policy.dead_zone {
            self.candidate_coordinate = None;
            return;
        }

        let base_commit = if self.committed_coordinates.is_empty() {
            self.policy.initial_cell_commit_distance
        } else {
            self.policy.subsequent_cell_commit_distance
        };

        let angle = angle_degrees(dx, dy);
        let Some(nearest) = self.nearest_reachable_coordinate(angle, normalized, base_commit) else {
            self.candidate_coordinate = None;
            return;
        };

        match self.candidate_coordinate {
            Some(current) if current != nearest => {
                let current_angle = coordinate_angle(current);
                let nearest_angle = coordinate_angle(nearest);
                let current_distance = angular_distance(angle, current_angle);
                let nearest_distance = angular_distance(angle, nearest_angle);
                let same_ray = angular_distance(current_angle, nearest_angle) < f64::EPSILON;
                if same_ray
                    || nearest_distance + self.policy.angular_hysteresis_degrees
                        < current_distance
                {
                    self.candidate_coordinate = Some(nearest);
                }
            }
            None => self.candidate_coordinate = Some(nearest),
            _ => {}
        }

        let Some(coordinate) = self.candidate_coordinate else {
            return;
        };
        let Some(entry) = self.entry_at(coordinate).cloned() else {
            return;
        };

        self.committed_coordinates.push(coordinate);
        self.commit_anchors.push(point);
        self.cancel_holds();

        if let Some(transition) = entry.transition {
            self.apply_transition(transition, point, self.current_time_ms);
        } else {
            self.selected_coordinate = Some(coordinate);
            self.candidate_coordinate = Some(coordinate);
            self.schedule_holds(self.current_time_ms, false);
        }
    }

    pub fn advance_time(&mut self, target_ms: i64) {
        if self.terminal.is_some() || target_ms < self.current_time_ms {
            return;
        }

        if !self.hold_locked {
            if let Some((due_ms, transition)) = self.board_hold_due_ms.clone() {
                if due_ms <= target_ms {
                    self.board_hold_due_ms = None;
                    self.entry_hold_due_ms = None;
                    self.apply_transition(transition, self.last_point, due_ms);
                }
            }
        }

        if !self.hold_started {
            if let Some(due_ms) = self.entry_hold_due_ms {
                if due_ms <= target_ms {
                    if let Some(hold) = self
                        .current_entry()
                        .and_then(|entry| entry.hold.as_ref())
                        .cloned()
                    {
                        self.dispatched_actions.extend(hold.on_start.clone());
                        self.hold_started = true;
                        self.hold_locked = true;
                        self.candidate_coordinate = self.selected_coordinate;
                        self.board_hold_due_ms = None;
                        if let Some(repeating) = hold.repeat_behavior {
                            self.repeat_due_ms = Some(due_ms + repeating.interval_ms);
                        }
                    }
                }
            }
        }

        if self.hold_started {
            if let Some(repeating) = self
                .current_entry()
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
    }

    pub fn touch_up(&mut self, at_ms: Option<i64>) {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        if self.terminal.is_some() {
            return;
        }

        if self.selected_coordinate.is_none() {
            if let Some(center) = self.entry_at(BoardCoordinate::ORIGIN).cloned() {
                if let Some(transition) = center.transition {
                    self.apply_transition(transition, self.last_point, self.current_time_ms);
                }
            }
        }

        if let Some(entry) = self.current_entry().cloned() {
            let suppress_release = self.hold_started
                && entry
                    .hold
                    .as_ref()
                    .is_some_and(|hold| hold.suppress_on_release_after_start);
            if !suppress_release {
                self.dispatched_actions.extend(entry.on_release);
            }
        }

        self.terminal = Some(BoardSessionTerminal::Committed);
        self.current_board_id = self.persistent_board_id.clone();
        self.cancel_holds();
    }

    pub fn cancel(&mut self, at_ms: Option<i64>) {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        if self.terminal.is_some() {
            return;
        }
        self.terminal = Some(BoardSessionTerminal::Cancelled);
        self.current_board_id = self.persistent_board_id.clone();
        self.cancel_holds();
    }

    pub fn invalidate(&mut self, at_ms: Option<i64>) {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        if self.terminal.is_some() {
            return;
        }
        self.terminal = Some(BoardSessionTerminal::Invalidated);
        self.current_board_id = self.persistent_board_id.clone();
        self.cancel_holds();
    }

    fn nearest_reachable_coordinate(
        &self,
        angle: f64,
        normalized_distance: f64,
        base_commit: f64,
    ) -> Option<BoardCoordinate> {
        self.current_board()?
            .entries
            .iter()
            .filter(|entry| !entry.coordinate.is_origin())
            .filter(|entry| {
                normalized_distance
                    >= base_commit * entry.coordinate.chebyshev_radius() as f64
            })
            .map(|entry| entry.coordinate)
            .min_by(|lhs, rhs| {
                let lhs_angle = angular_distance(angle, coordinate_angle(*lhs));
                let rhs_angle = angular_distance(angle, coordinate_angle(*rhs));
                lhs_angle
                    .total_cmp(&rhs_angle)
                    .then_with(|| {
                        rhs.chebyshev_radius()
                            .cmp(&lhs.chebyshev_radius())
                    })
                    .then_with(|| lhs.y.cmp(&rhs.y))
                    .then_with(|| lhs.x.cmp(&rhs.x))
            })
    }

    fn entry_at(&self, coordinate: BoardCoordinate) -> Option<&BoardEntry> {
        self.current_board()?
            .entries
            .iter()
            .find(|entry| entry.coordinate == coordinate)
    }

    fn apply_transition(
        &mut self,
        transition: BoardTransition,
        point: GesturePoint,
        at_ms: i64,
    ) {
        if self.transition_count >= ProfileLimits::BOARD_TRANSITIONS_PER_INTERACTION {
            self.transition_limit_hit = true;
            return;
        }
        if !self.boards.contains_key(&transition.target_board_ref) {
            return;
        }

        self.transition_count += 1;
        if transition.lifetime == BoardTransitionLifetime::Persistent {
            self.persistent_board_id = transition.target_board_ref.clone();
            if let Ok(mut state) = self.persistent_state.lock() {
                state.insert(
                    self.entry_point_id.clone(),
                    transition.target_board_ref.clone(),
                );
            }
        }
        self.current_board_id = transition.target_board_ref;
        self.anchor = point;
        self.last_point = point;
        self.candidate_coordinate = None;
        self.selected_coordinate = None;
        self.hold_started = false;
        self.hold_locked = false;
        self.schedule_holds(at_ms, true);
    }

    fn schedule_holds(&mut self, at_ms: i64, include_board_trigger: bool) {
        self.entry_hold_due_ms = self
            .current_entry()
            .and_then(|entry| entry.hold.as_ref())
            .map(|hold| at_ms + hold.delay_ms);
        self.repeat_due_ms = None;
        self.hold_started = false;
        self.hold_locked = false;

        self.board_hold_due_ms = if include_board_trigger {
            self.current_board()
                .and_then(|board| {
                    board
                        .triggers
                        .iter()
                        .filter(|trigger| trigger.trigger_type == "hold")
                        .map(|trigger| {
                            (
                                at_ms + trigger.delay_ms.unwrap_or(500),
                                trigger.transition.clone(),
                            )
                        })
                        .min_by_key(|(due_ms, _)| *due_ms)
                })
        } else {
            None
        };
    }

    fn cancel_holds(&mut self) {
        self.entry_hold_due_ms = None;
        self.board_hold_due_ms = None;
        self.repeat_due_ms = None;
    }
}

fn coordinate_angle(coordinate: BoardCoordinate) -> f64 {
    angle_degrees(coordinate.x as f64, coordinate.y as f64)
}

fn angle_degrees(dx: f64, dy: f64) -> f64 {
    let raw = dy.atan2(dx).to_degrees();
    if raw < 0.0 {
        raw + 360.0
    } else {
        raw
    }
}

fn angular_distance(lhs: f64, rhs: f64) -> f64 {
    let delta = (lhs - rhs).abs() % 360.0;
    delta.min(360.0 - delta)
}

pub fn board_map(profile: &ProfileBundleV2) -> HashMap<String, Board> {
    profile
        .boards
        .iter()
        .cloned()
        .map(|board| (board.id.clone(), board))
        .collect()
}
