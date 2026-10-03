use crate::model::*;
use serde_json::{Map, Value};
use std::collections::{HashMap, HashSet};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProfileValidationCode {
    ProfileTooLarge,
    UnsupportedSchema,
    LimitKeys,
    LimitLayouts,
    LimitPlacements,
    LimitLayers,
    LimitBindingSets,
    LimitBindingsPerKey,
    LimitBindingsTotal,
    LimitTrieNodes,
    PathDepth,
    LimitMacros,
    LimitActions,
    ArgumentTooLarge,
    LimitLayerStack,
    DuplicateId,
    MissingReference,
    DuplicateBindingPath,
    UnknownAction,
    InvalidActionArguments,
    MacroNesting,
    InvalidGesturePolicy,
    LimitBoards,
    LimitBoardEntries,
    DuplicateBoardCoordinate,
}

impl ProfileValidationCode {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::ProfileTooLarge => "E_PROFILE_TOO_LARGE",
            Self::UnsupportedSchema => "E_UNSUPPORTED_SCHEMA",
            Self::LimitKeys => "E_LIMIT_KEYS",
            Self::LimitLayouts => "E_LIMIT_LAYOUTS",
            Self::LimitPlacements => "E_LIMIT_PLACEMENTS",
            Self::LimitLayers => "E_LIMIT_LAYERS",
            Self::LimitBindingSets => "E_LIMIT_BINDING_SETS",
            Self::LimitBindingsPerKey => "E_LIMIT_BINDINGS_PER_KEY",
            Self::LimitBindingsTotal => "E_LIMIT_BINDINGS_TOTAL",
            Self::LimitTrieNodes => "E_LIMIT_TRIE_NODES",
            Self::PathDepth => "E_PATH_DEPTH",
            Self::LimitMacros => "E_LIMIT_MACROS",
            Self::LimitActions => "E_LIMIT_ACTIONS",
            Self::ArgumentTooLarge => "E_ARGUMENT_TOO_LARGE",
            Self::LimitLayerStack => "E_LIMIT_LAYER_STACK",
            Self::DuplicateId => "E_DUPLICATE_ID",
            Self::MissingReference => "E_MISSING_REFERENCE",
            Self::DuplicateBindingPath => "E_DUPLICATE_BINDING_PATH",
            Self::UnknownAction => "E_UNKNOWN_ACTION",
            Self::InvalidActionArguments => "E_INVALID_ACTION_ARGUMENTS",
            Self::MacroNesting => "E_MACRO_NESTING",
            Self::InvalidGesturePolicy => "E_INVALID_GESTURE_POLICY",
            Self::LimitBoards => "E_LIMIT_BOARDS",
            Self::LimitBoardEntries => "E_LIMIT_BOARD_ENTRIES",
            Self::DuplicateBoardCoordinate => "E_DUPLICATE_BOARD_COORDINATE",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
#[error("{code}: {detail:?}", code = .code.as_str())]
pub struct ProfileValidationError {
    pub code: ProfileValidationCode,
    pub detail: Option<String>,
}

impl ProfileValidationError {
    pub fn new(code: ProfileValidationCode, detail: impl Into<Option<String>>) -> Self {
        Self {
            code,
            detail: detail.into(),
        }
    }

    pub fn simple(code: ProfileValidationCode) -> Self {
        Self { code, detail: None }
    }
}

pub struct ProfileLimits;

impl ProfileLimits {
    pub const ENCODED_BYTES: usize = 1_048_576;
    pub const KEYS: usize = 256;
    pub const LAYOUTS: usize = 32;
    pub const PLACEMENTS_PER_LAYOUT: usize = 256;
    pub const LAYERS: usize = 32;
    pub const BINDING_SETS: usize = 64;
    pub const BINDINGS_PER_KEY: usize = 128;
    pub const BINDINGS_TOTAL: usize = 8192;
    pub const TRIE_NODES: usize = 16384;
    pub const PATH_DEPTH: usize = 2;
    pub const MACROS: usize = 128;
    pub const ENDPOINT_ACTIONS: usize = 16;
    pub const MACRO_ACTIONS: usize = 32;
    pub const STRING_ARGUMENT_BYTES: usize = 4096;
    pub const ARGUMENTS_BYTES: usize = 16384;
    pub const LAYER_STACK_DEPTH: usize = 16;
}

pub struct ProfileCodec;

impl ProfileCodec {
    pub fn decode_and_validate(bytes: &[u8]) -> Result<ProfileBundle, ProfileValidationError> {
        if bytes.len() > ProfileLimits::ENCODED_BYTES {
            return Err(ProfileValidationError::simple(ProfileValidationCode::ProfileTooLarge));
        }
        let profile: ProfileBundle = serde_json::from_slice(bytes).map_err(|error| {
            ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some(error.to_string()),
            )
        })?;
        ProfileValidator::validate(&profile, Some(bytes.len()))?;
        Ok(profile)
    }
}

pub struct ProfileValidator;

impl ProfileValidator {
    pub fn validate(
        profile: &ProfileBundle,
        encoded_bytes: Option<usize>,
    ) -> Result<(), ProfileValidationError> {
        if encoded_bytes.is_some_and(|size| size > ProfileLimits::ENCODED_BYTES) {
            return Err(ProfileValidationError::simple(ProfileValidationCode::ProfileTooLarge));
        }
        if profile.schema != "gesture-ime.profile.v1"
            || profile.version < 1
            || !is_valid_id(&profile.id)
            || profile.name.is_empty()
            || profile.name.chars().count() > 128
        {
            return Err(ProfileValidationError::simple(ProfileValidationCode::UnsupportedSchema));
        }

        check_limit(profile.key_definitions.len(), ProfileLimits::KEYS, ProfileValidationCode::LimitKeys)?;
        check_limit(profile.layouts.len(), ProfileLimits::LAYOUTS, ProfileValidationCode::LimitLayouts)?;
        check_limit(profile.layers.len(), ProfileLimits::LAYERS, ProfileValidationCode::LimitLayers)?;
        check_limit(profile.binding_sets.len(), ProfileLimits::BINDING_SETS, ProfileValidationCode::LimitBindingSets)?;
        check_limit(profile.macros.len(), ProfileLimits::MACROS, ProfileValidationCode::LimitMacros)?;

        for layout in &profile.layouts {
            if layout.placements.len() > ProfileLimits::PLACEMENTS_PER_LAYOUT {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::LimitPlacements,
                    Some(layout.id.clone()),
                ));
            }
        }

        validate_unique_ids(profile.key_definitions.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.layouts.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.binding_sets.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.layers.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.macros.iter().map(|item| item.id.as_str()))?;

        for id in profile
            .key_definitions
            .iter()
            .map(|item| item.id.as_str())
            .chain(profile.layouts.iter().map(|item| item.id.as_str()))
            .chain(profile.binding_sets.iter().map(|item| item.id.as_str()))
            .chain(profile.layers.iter().map(|item| item.id.as_str()))
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

        for layout in &profile.layouts {
            for placement in &layout.placements {
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

        validate_gesture_policy(&profile.gesture_policy)?;

        let key_ids: HashSet<&str> = profile.key_definitions.iter().map(|item| item.id.as_str()).collect();
        let layout_ids: HashSet<&str> = profile.layouts.iter().map(|item| item.id.as_str()).collect();
        let binding_set_ids: HashSet<&str> = profile.binding_sets.iter().map(|item| item.id.as_str()).collect();
        let layer_ids: HashSet<&str> = profile.layers.iter().map(|item| item.id.as_str()).collect();
        let macro_ids: HashSet<&str> = profile.macros.iter().map(|item| item.id.as_str()).collect();

        for layout in &profile.layouts {
            for placement in &layout.placements {
                if !key_ids.contains(placement.key_id.as_str()) {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::MissingReference,
                        Some(placement.key_id.clone()),
                    ));
                }
            }
        }

        for layer in &profile.layers {
            if !layout_ids.contains(layer.layout_ref.as_str())
                || !binding_set_ids.contains(layer.binding_set_ref.as_str())
            {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(layer.id.clone()),
                ));
            }
        }

        let total_bindings: usize = profile.binding_sets.iter().map(|set| set.bindings.len()).sum();
        if total_bindings > ProfileLimits::BINDINGS_TOTAL {
            return Err(ProfileValidationError::simple(ProfileValidationCode::LimitBindingsTotal));
        }

        let mut preflight_trie_nodes = 0usize;

        for set in &profile.binding_sets {
            let mut seen_by_key: HashMap<&str, HashSet<GesturePath>> = HashMap::new();
            let mut prefixes_by_key: HashMap<&str, HashSet<GesturePath>> = HashMap::new();
            let mut count_by_key: HashMap<&str, usize> = HashMap::new();

            for binding in &set.bindings {
                if !key_ids.contains(binding.key_id.as_str()) {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::MissingReference,
                        Some(binding.key_id.clone()),
                    ));
                }

                if binding.path.0.len() > ProfileLimits::PATH_DEPTH {
                    return Err(ProfileValidationError::simple(ProfileValidationCode::PathDepth));
                }

                let count = count_by_key.entry(binding.key_id.as_str()).or_default();
                *count += 1;
                if *count > ProfileLimits::BINDINGS_PER_KEY {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::LimitBindingsPerKey,
                        Some(binding.key_id.clone()),
                    ));
                }

                let seen = seen_by_key.entry(binding.key_id.as_str()).or_default();
                if !seen.insert(binding.path.clone()) {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::DuplicateBindingPath,
                        Some(format!("{}:{}", set.id, binding.key_id)),
                    ));
                }

                if !binding.path.0.is_empty() {
                    let prefixes = prefixes_by_key.entry(binding.key_id.as_str()).or_default();
                    for index in 1..=binding.path.0.len() {
                        prefixes.insert(GesturePath(binding.path.0[..index].to_vec()));
                    }
                }

                validate_presentation(
                    binding.behavior.presentation.as_ref(),
                    &format!("{}:{}", set.id, binding.key_id),
                )?;

                let endpoint_count = binding.behavior.on_release.len()
                    + binding.behavior.hold.as_ref().map_or(0, |hold| hold.on_start.len())
                    + binding
                        .behavior
                        .hold
                        .as_ref()
                        .and_then(|hold| hold.repeat_behavior.as_ref())
                        .map_or(0, |repeat| repeat.actions.len());

                if endpoint_count > ProfileLimits::ENDPOINT_ACTIONS {
                    return Err(ProfileValidationError::simple(ProfileValidationCode::LimitActions));
                }

                validate_actions(
                    &binding.behavior.on_release,
                    false,
                    &layer_ids,
                    &macro_ids,
                )?;

                if let Some(hold) = &binding.behavior.hold {
                    if !(50..=5000).contains(&hold.delay_ms) {
                        return Err(ProfileValidationError::new(
                            ProfileValidationCode::UnsupportedSchema,
                            Some("hold.delayMs".into()),
                        ));
                    }
                    validate_actions(&hold.on_start, false, &layer_ids, &macro_ids)?;

                    if let Some(repeat) = &hold.repeat_behavior {
                        if !(16..=5000).contains(&repeat.interval_ms) {
                            return Err(ProfileValidationError::new(
                                ProfileValidationCode::UnsupportedSchema,
                                Some("repeat.intervalMs".into()),
                            ));
                        }
                        validate_actions(&repeat.actions, false, &layer_ids, &macro_ids)?;
                    }
                }
            }

            preflight_trie_nodes += seen_by_key.len();
            preflight_trie_nodes += prefixes_by_key.values().map(HashSet::len).sum::<usize>();
        }

        if preflight_trie_nodes > ProfileLimits::TRIE_NODES {
            return Err(ProfileValidationError::simple(ProfileValidationCode::LimitTrieNodes));
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

fn check_limit(
    actual: usize,
    limit: usize,
    code: ProfileValidationCode,
) -> Result<(), ProfileValidationError> {
    if actual > limit {
        Err(ProfileValidationError::simple(code))
    } else {
        Ok(())
    }
}

pub(crate) fn validate_unique_ids<'a>(
    values: impl Iterator<Item = &'a str>,
) -> Result<(), ProfileValidationError> {
    let mut seen = HashSet::new();
    for value in values {
        if !seen.insert(value) {
            return Err(ProfileValidationError::simple(ProfileValidationCode::DuplicateId));
        }
    }
    Ok(())
}

pub(crate) fn validate_presentation(
    presentation: Option<&BindingPresentation>,
    owner: &str,
) -> Result<(), ProfileValidationError> {
    let Some(presentation) = presentation else {
        return Ok(());
    };
    if presentation.text.as_ref().is_some_and(|text| text.chars().count() > 256)
        || presentation
            .accessibility_label
            .as_ref()
            .is_some_and(|label| label.chars().count() > 256)
    {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::UnsupportedSchema,
            Some(owner.to_owned()),
        ));
    }
    Ok(())
}

pub(crate) fn validate_dimension(value: Option<f64>, owner: &str) -> Result<(), ProfileValidationError> {
    if let Some(value) = value {
        if !value.is_finite() || value <= 0.0 || value > 32.0 {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some(owner.to_owned()),
            ));
        }
    }
    Ok(())
}

fn validate_gesture_policy(policy: &GesturePolicy) -> Result<(), ProfileValidationError> {
    let valid = policy.dead_zone.is_finite()
        && policy.stage1_commit_distance.is_finite()
        && policy.stage2_commit_distance.is_finite()
        && policy.angular_hysteresis_degrees.is_finite()
        && (0.0..=2.0).contains(&policy.dead_zone)
        && policy.stage1_commit_distance > 0.0
        && policy.stage1_commit_distance <= 4.0
        && policy.stage2_commit_distance > 0.0
        && policy.stage2_commit_distance <= 4.0
        && policy.stage1_commit_distance >= policy.dead_zone
        && policy.stage2_commit_distance >= policy.dead_zone
        && policy.angular_hysteresis_degrees >= 0.0
        && policy.angular_hysteresis_degrees < 45.0
        && policy.max_directional_stages == 2;

    if valid {
        Ok(())
    } else {
        Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidGesturePolicy,
        ))
    }
}

pub(crate) fn validate_actions(
    actions: &[ActionInvocation],
    in_macro: bool,
    layer_ids: &HashSet<&str>,
    macro_ids: &HashSet<&str>,
) -> Result<(), ProfileValidationError> {
    for action in actions {
        if !is_common_action(&action.action_id) {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::UnknownAction,
                Some(action.action_id.clone()),
            ));
        }
        if in_macro && action.action_id == "macro.run" {
            return Err(ProfileValidationError::simple(ProfileValidationCode::MacroNesting));
        }
        validate_argument_size(action)?;
        validate_action_shape(action, layer_ids, macro_ids)?;
    }
    Ok(())
}

fn is_common_action(action_id: &str) -> bool {
    matches!(
        action_id,
        "noop"
            | "text.insert"
            | "text.directInsert"
            | "edit.delete"
            | "cursor.move"
            | "layer.set"
            | "layer.push"
            | "layer.pop"
            | "profile.switch"
            | "conversion.commit"
            | "conversion.selectCandidate"
            | "panel.open"
            | "macro.run"
            | "system.nextKeyboard"
            | "system.dismissKeyboard"
    )
}

fn validate_argument_size(action: &ActionInvocation) -> Result<(), ProfileValidationError> {
    let encoded = serde_json::to_vec(&Value::Object(action.arguments.clone())).map_err(|error| {
        ProfileValidationError::new(
            ProfileValidationCode::InvalidActionArguments,
            Some(error.to_string()),
        )
    })?;

    if encoded.len() > ProfileLimits::ARGUMENTS_BYTES {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::ArgumentTooLarge,
            Some(action.action_id.clone()),
        ));
    }

    for value in action.arguments.values() {
        scan_string_sizes(value, &action.action_id)?;
    }
    Ok(())
}

fn scan_string_sizes(value: &Value, action_id: &str) -> Result<(), ProfileValidationError> {
    match value {
        Value::String(text) => {
            if text.len() > ProfileLimits::STRING_ARGUMENT_BYTES {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::ArgumentTooLarge,
                    Some(action_id.to_owned()),
                ));
            }
        }
        Value::Array(values) => {
            for value in values {
                scan_string_sizes(value, action_id)?;
            }
        }
        Value::Object(values) => {
            for value in values.values() {
                scan_string_sizes(value, action_id)?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn validate_action_shape(
    action: &ActionInvocation,
    layer_ids: &HashSet<&str>,
    macro_ids: &HashSet<&str>,
) -> Result<(), ProfileValidationError> {
    let arguments = &action.arguments;
    let invalid = || {
        ProfileValidationError::new(
            ProfileValidationCode::InvalidActionArguments,
            Some(action.action_id.clone()),
        )
    };

    match action.action_id.as_str() {
        "noop"
        | "layer.pop"
        | "conversion.commit"
        | "system.nextKeyboard"
        | "system.dismissKeyboard" => {
            ensure_exact_keys(arguments, &[]).map_err(|_| invalid())?;
        }
        "text.insert" | "text.directInsert" => {
            ensure_exact_keys(arguments, &["text"]).map_err(|_| invalid())?;
            get_string(arguments, "text").ok_or_else(invalid)?;
        }
        "edit.delete" => {
            ensure_exact_keys(arguments, &["count"]).map_err(|_| invalid())?;
            let count = get_i64(arguments, "count").ok_or_else(invalid)?;
            if count == 0 || !(-64..=64).contains(&count) {
                return Err(invalid());
            }
        }
        "cursor.move" => {
            ensure_exact_keys(arguments, &["offset"]).map_err(|_| invalid())?;
            let offset = get_i64(arguments, "offset").ok_or_else(invalid)?;
            if offset == 0 || !(-64..=64).contains(&offset) {
                return Err(invalid());
            }
        }
        "layer.set" | "layer.push" => {
            ensure_exact_keys(arguments, &["layer"]).map_err(|_| invalid())?;
            let layer = get_string(arguments, "layer").ok_or_else(invalid)?;
            if !layer_ids.contains(layer) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(layer.to_owned()),
                ));
            }
        }
        "profile.switch" => {
            ensure_exact_keys(arguments, &["profile"]).map_err(|_| invalid())?;
            get_string(arguments, "profile").ok_or_else(invalid)?;
        }
        "conversion.selectCandidate" => {
            ensure_exact_keys(arguments, &["index"]).map_err(|_| invalid())?;
            let index = get_i64(arguments, "index").ok_or_else(invalid)?;
            if index < 0 {
                return Err(invalid());
            }
        }
        "panel.open" => {
            ensure_exact_keys(arguments, &["panel"]).map_err(|_| invalid())?;
            get_string(arguments, "panel").ok_or_else(invalid)?;
        }
        "macro.run" => {
            ensure_exact_keys(arguments, &["macro"]).map_err(|_| invalid())?;
            let macro_id = get_string(arguments, "macro").ok_or_else(invalid)?;
            if !macro_ids.contains(macro_id) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(macro_id.to_owned()),
                ));
            }
        }
        _ => {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::UnknownAction,
                Some(action.action_id.clone()),
            ));
        }
    }

    Ok(())
}

fn ensure_exact_keys(arguments: &Map<String, Value>, expected: &[&str]) -> Result<(), ()> {
    if arguments.len() != expected.len() {
        return Err(());
    }
    if expected.iter().all(|key| arguments.contains_key(*key)) {
        Ok(())
    } else {
        Err(())
    }
}

fn get_string<'a>(arguments: &'a Map<String, Value>, key: &str) -> Option<&'a str> {
    arguments.get(key)?.as_str()
}

fn get_i64(arguments: &Map<String, Value>, key: &str) -> Option<i64> {
    arguments.get(key)?.as_i64()
}

pub(crate) fn is_valid_id(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.is_empty() || bytes.len() > 128 || !bytes[0].is_ascii_alphanumeric() {
        return false;
    }
    bytes[1..]
        .iter()
        .all(|byte| byte.is_ascii_alphanumeric() || matches!(*byte, b'.' | b'_' | b'-'))
}