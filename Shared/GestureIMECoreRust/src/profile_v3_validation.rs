use crate::profile_v3::*;
use crate::validation::{
    is_valid_id, validate_unique_ids, ProfileLimits, ProfileValidationCode,
    ProfileValidationError,
};
use serde_json::{Map, Value};
use std::collections::{HashMap, HashSet};

pub struct ProfileV3Limits;

impl ProfileV3Limits {
    pub const BOARD_ENTRIES_PER_BOARD: usize = 400;
    pub const STATES: usize = 128;
    pub const ENUM_VALUES_PER_STATE: usize = 32;
    pub const CONDITIONAL_CASES_PER_ENTRY: usize = 16;
    pub const CONDITION_DEPTH: usize = 8;
    pub const CONDITION_NODES_PER_RESOLVER: usize = 64;
    pub const TRANSFORM_TABLES: usize = 256;
    pub const TRANSFORM_ENTRIES_PER_TABLE: usize = 2048;
    pub const TRANSFORM_ENTRIES_TOTAL: usize = 8192;
    pub const CONDITIONAL_TRANSFORMS_PER_STRING: usize = 8;
    pub const BOARD_ATOMIC_EXTENT: i64 = 20;
    pub const BOARD_BOUNDARY_MIN: i64 = -20;
    pub const BOARD_BOUNDARY_MAX: i64 = 20;
}

pub struct ProfileV3Codec;

impl ProfileV3Codec {
    pub fn decode_and_validate(bytes: &[u8]) -> Result<ProfileBundleV3, ProfileValidationError> {
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
        validate_v3_structural_contract(&value)?;

        let profile: ProfileBundleV3 = serde_json::from_value(value).map_err(|error| {
            ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some(error.to_string()),
            )
        })?;

        ProfileV3Validator::validate(&profile, Some(bytes.len()))?;
        Ok(profile)
    }
}

pub struct ProfileV3Validator;

#[derive(Debug, Clone, PartialEq, Eq)]
enum ValueKind {
    Boolean,
    String,
    Enum(HashSet<String>),
}

impl ProfileV3Validator {
    pub fn validate(
        profile: &ProfileBundleV3,
        encoded_bytes: Option<usize>,
    ) -> Result<(), ProfileValidationError> {
        if encoded_bytes.is_some_and(|size| size > ProfileLimits::ENCODED_BYTES) {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::ProfileTooLarge,
            ));
        }

        if profile.schema != "gesture-ime.profile.v3"
            || profile.version < 1
            || !is_valid_id(&profile.id)
            || profile.name.is_empty()
            || profile.name.chars().count() > 128
        {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::UnsupportedSchema,
            ));
        }

        check_count(
            profile.layers.len(),
            ProfileLimits::LAYERS,
            ProfileValidationCode::LimitLayers,
        )?;
        check_count(
            profile.boards.len(),
            ProfileLimits::BOARDS,
            ProfileValidationCode::LimitBoards,
        )?;
        check_count(
            profile.states.len(),
            ProfileV3Limits::STATES,
            ProfileValidationCode::LimitStates,
        )?;
        check_count(
            profile.transform_tables.len(),
            ProfileV3Limits::TRANSFORM_TABLES,
            ProfileValidationCode::LimitTransformTables,
        )?;
        check_count(
            profile.macros.len(),
            ProfileLimits::MACROS,
            ProfileValidationCode::LimitMacros,
        )?;

        validate_unique_ids(profile.layers.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.boards.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.states.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.transform_tables.iter().map(|item| item.id.as_str()))?;
        validate_unique_ids(profile.macros.iter().map(|item| item.id.as_str()))?;

        for id in profile
            .layers
            .iter()
            .map(|item| item.id.as_str())
            .chain(profile.boards.iter().map(|item| item.id.as_str()))
            .chain(profile.states.iter().map(|item| item.id.as_str()))
            .chain(profile.transform_tables.iter().map(|item| item.id.as_str()))
            .chain(profile.macros.iter().map(|item| item.id.as_str()))
        {
            validate_id(id)?;
        }

        validate_gesture_policy(&profile.gesture_policy)?;
        for board in &profile.boards {
            for entry in &board.entries {
                if let Some(overrides) = entry.guide_label_overrides.as_ref() {
                    validate_guide_label_overrides(profile, board, entry, overrides)?;
                }
                if let Some(partial) = entry.gesture_policy_override.as_ref() {
                    // Each override field is checked in the context of the policy it
                    // produces, so inherited + overridden values stay coherent.
                    validate_gesture_policy(&profile.gesture_policy.with_override(Some(partial)))
                        .map_err(|_| {
                            ProfileValidationError::new(
                                ProfileValidationCode::InvalidGesturePolicy,
                                Some(format!("{}:{}", board.id, entry.id)),
                            )
                        })?;
                }
            }
        }

        let layer_ids: HashSet<&str> =
            profile.layers.iter().map(|item| item.id.as_str()).collect();
        let board_ids: HashSet<&str> =
            profile.boards.iter().map(|item| item.id.as_str()).collect();
        let table_ids: HashSet<&str> = profile
            .transform_tables
            .iter()
            .map(|item| item.id.as_str())
            .collect();
        let macro_ids: HashSet<&str> =
            profile.macros.iter().map(|item| item.id.as_str()).collect();
        let macro_map: HashMap<&str, &MacroV3> = profile
            .macros
            .iter()
            .map(|item| (item.id.as_str(), item))
            .collect();

        if !layer_ids.contains(profile.initial_layer_ref.as_str()) {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::MissingReference,
                Some(profile.initial_layer_ref.clone()),
            ));
        }

        for layer in &profile.layers {
            validate_id(&layer.id)?;
            validate_string_option(layer.name.as_deref(), &layer.id)?;
            if !board_ids.contains(layer.root_board_ref.as_str()) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(layer.root_board_ref.clone()),
                ));
            }
        }

        let state_kinds = validate_states(&profile.states)?;
        validate_transform_tables(&profile.transform_tables)?;

        // User-facing Macro names are distinct from immutable internal IDs.
        // Existing unnamed macros are legal; authoring a name is opt-in.
        let mut macro_names = HashSet::new();
        for macro_item in &profile.macros {
            if let Some(name) = macro_item.name.as_ref() {
                let canonical = name.trim().to_lowercase();
                if name.trim().is_empty()
                    || name.chars().count() > 100
                    || name.trim() != name
                    || !macro_names.insert(canonical)
                {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::InvalidPresentation,
                        Some(macro_item.id.clone()),
                    ));
                }
            }
            if macro_item.actions.len() > ProfileLimits::MACRO_ACTIONS {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::LimitActions,
                    Some(macro_item.id.clone()),
                ));
            }
            for action in &macro_item.actions {
                // The 64-node bound is defined per resolver. Macro Actions do not
                // share a resolver, so each embedded conditional string gets an
                // independent bounded validation counter.
                let mut standalone_nodes = 0usize;
                validate_actions(
                    std::slice::from_ref(action),
                    true,
                    &layer_ids,
                    &board_ids,
                    &table_ids,
                    &macro_ids,
                    &macro_map,
                    &state_kinds,
                    &mut standalone_nodes,
                )?;
            }
        }

        for board in &profile.boards {
            validate_board(
                board,
                &layer_ids,
                &board_ids,
                &table_ids,
                &macro_ids,
                &macro_map,
                &state_kinds,
            )?;
        }

        Ok(())
    }
}

fn validate_guide_label_overrides(
    profile: &ProfileBundleV3,
    board: &crate::profile_v3::BoardV3,
    entry: &crate::profile_v3::BoardEntryV3,
    overrides: &std::collections::BTreeMap<String, String>,
) -> Result<(), ProfileValidationError> {
    let invalid = || {
        ProfileValidationError::new(
            ProfileValidationCode::InvalidPresentation,
            Some(format!("{}:{}", board.id, entry.id)),
        )
    };
    // Overrides belong to the source transition context: every key must be an
    // entry of the source's default transition target Board.
    let target = entry
        .resolver
        .default
        .transition
        .as_ref()
        .and_then(|transition| profile.boards.iter().find(|b| b.id == transition.target_board_ref))
        .ok_or_else(invalid)?;
    if overrides.len() > 32 {
        return Err(invalid());
    }
    for (target_entry, label) in overrides {
        let scalars = label.chars().count();
        if !target.entries.iter().any(|e| &e.id == target_entry) || scalars == 0 || scalars > 16 {
            return Err(invalid());
        }
    }
    Ok(())
}

fn validate_gesture_policy(policy: &GesturePolicyV3) -> Result<(), ProfileValidationError> {
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
        && policy.angular_hysteresis_degrees < 45.0
        && policy.stage_backtrack_dwell_ms.is_none_or(|dwell| {
            (GesturePolicyV3::MIN_STAGE_BACKTRACK_DWELL_MS
                ..=GesturePolicyV3::MAX_STAGE_BACKTRACK_DWELL_MS)
                .contains(&dwell)
        });

    if valid {
        Ok(())
    } else {
        Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidGesturePolicy,
        ))
    }
}

fn validate_states(
    states: &[StateDeclarationV3],
) -> Result<HashMap<String, ValueKind>, ProfileValidationError> {
    let mut kinds = HashMap::new();

    for state in states {
        validate_id(&state.id)?;

        let kind = match state.state_type.as_str() {
            "boolean" => {
                if state.values.is_some() || !state.default.is_boolean() {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::InvalidState,
                        Some(state.id.clone()),
                    ));
                }
                ValueKind::Boolean
            }
            "enum" => {
                let Some(values) = state.values.as_ref() else {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::InvalidState,
                        Some(state.id.clone()),
                    ));
                };
                if values.is_empty() || values.len() > ProfileV3Limits::ENUM_VALUES_PER_STATE {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::InvalidState,
                        Some(state.id.clone()),
                    ));
                }

                let mut unique = HashSet::new();
                for value in values {
                    validate_string(value, &state.id)?;
                    if !unique.insert(value.clone()) {
                        return Err(ProfileValidationError::new(
                            ProfileValidationCode::InvalidState,
                            Some(state.id.clone()),
                        ));
                    }
                }

                let Some(default) = state.default.as_str() else {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::InvalidState,
                        Some(state.id.clone()),
                    ));
                };
                validate_string(default, &state.id)?;
                if !unique.contains(default) {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::InvalidState,
                        Some(state.id.clone()),
                    ));
                }

                ValueKind::Enum(unique)
            }
            _ => {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::InvalidState,
                    Some(state.id.clone()),
                ));
            }
        };

        kinds.insert(state.id.clone(), kind);
    }

    Ok(kinds)
}

fn validate_transform_tables(
    tables: &[TransformTableV3],
) -> Result<(), ProfileValidationError> {
    let mut total = 0usize;

    for table in tables {
        validate_id(&table.id)?;
        if table.entries.len() > ProfileV3Limits::TRANSFORM_ENTRIES_PER_TABLE {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::LimitTransformEntries,
                Some(table.id.clone()),
            ));
        }

        total = total
            .checked_add(table.entries.len())
            .ok_or_else(|| {
                ProfileValidationError::simple(ProfileValidationCode::LimitTransformEntries)
            })?;

        if total > ProfileV3Limits::TRANSFORM_ENTRIES_TOTAL {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::LimitTransformEntries,
            ));
        }

        let mut seen = HashSet::new();
        for entry in &table.entries {
            if entry.from.is_empty() {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::InvalidTransformReference,
                    Some(table.id.clone()),
                ));
            }
            validate_string(&entry.from, &table.id)?;
            validate_string(&entry.to, &table.id)?;
            if !seen.insert(entry.from.as_str()) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::DuplicateTransformSource,
                    Some(table.id.clone()),
                ));
            }
        }

        if table.has_reverse() {
            let effective = table.effective_entries().map_err(|error| match error {
                crate::profile_v3::TransformCompileErrorV3::ConflictingSource(from) => {
                    ProfileValidationError::new(
                        ProfileValidationCode::DuplicateTransformSource,
                        Some(format!("{}:{}", table.id, from)),
                    )
                }
                crate::profile_v3::TransformCompileErrorV3::EmptyReverseSource => {
                    ProfileValidationError::new(
                        ProfileValidationCode::InvalidTransformReference,
                        Some(table.id.clone()),
                    )
                }
            })?;
            total = total
                .checked_add(effective.len() - table.entries.len())
                .ok_or_else(|| {
                    ProfileValidationError::simple(ProfileValidationCode::LimitTransformEntries)
                })?;
            if effective.len() > ProfileV3Limits::TRANSFORM_ENTRIES_PER_TABLE
                || total > ProfileV3Limits::TRANSFORM_ENTRIES_TOTAL
            {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::LimitTransformEntries,
                    Some(table.id.clone()),
                ));
            }
        }
    }

    Ok(())
}

fn validate_board(
    board: &BoardV3,
    layer_ids: &HashSet<&str>,
    board_ids: &HashSet<&str>,
    table_ids: &HashSet<&str>,
    macro_ids: &HashSet<&str>,
    macro_map: &HashMap<&str, &MacroV3>,
    state_kinds: &HashMap<String, ValueKind>,
) -> Result<(), ProfileValidationError> {
    validate_id(&board.id)?;
    if board.entries.len() > ProfileV3Limits::BOARD_ENTRIES_PER_BOARD {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::LimitBoardEntries,
            Some(board.id.clone()),
        ));
    }

    validate_unique_ids(board.entries.iter().map(|item| item.id.as_str()))?;

    let mut occupied = HashSet::new();
    let mut origin_count = 0usize;
    let mut min_x: Option<i64> = None;
    let mut min_y: Option<i64> = None;
    let mut max_x: Option<i64> = None;
    let mut max_y: Option<i64> = None;

    for entry in &board.entries {
        validate_id(&entry.id)?;
        let rect = &entry.rect;
        let Some(rect_max_x) = rect.max_x() else {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::BoardRect,
                Some(format!("{}:{}", board.id, entry.id)),
            ));
        };
        let Some(rect_max_y) = rect.max_y() else {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::BoardRect,
                Some(format!("{}:{}", board.id, entry.id)),
            ));
        };

        let valid_rect = rect.width >= 1
            && rect.width <= ProfileV3Limits::BOARD_ATOMIC_EXTENT
            && rect.height >= 1
            && rect.height <= ProfileV3Limits::BOARD_ATOMIC_EXTENT
            && (ProfileV3Limits::BOARD_BOUNDARY_MIN..=ProfileV3Limits::BOARD_BOUNDARY_MAX)
                .contains(&rect.x)
            && (ProfileV3Limits::BOARD_BOUNDARY_MIN..=ProfileV3Limits::BOARD_BOUNDARY_MAX)
                .contains(&rect.y)
            && (ProfileV3Limits::BOARD_BOUNDARY_MIN..=ProfileV3Limits::BOARD_BOUNDARY_MAX)
                .contains(&rect_max_x)
            && (ProfileV3Limits::BOARD_BOUNDARY_MIN..=ProfileV3Limits::BOARD_BOUNDARY_MAX)
                .contains(&rect_max_y);

        if !valid_rect {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::BoardRect,
                Some(format!("{}:{}", board.id, entry.id)),
            ));
        }

        min_x = Some(min_x.map_or(rect.x, |value| value.min(rect.x)));
        min_y = Some(min_y.map_or(rect.y, |value| value.min(rect.y)));
        max_x = Some(max_x.map_or(rect_max_x, |value| value.max(rect_max_x)));
        max_y = Some(max_y.map_or(rect_max_y, |value| value.max(rect_max_y)));

        if rect.contains_origin() {
            origin_count += 1;
            if origin_count > 1 {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::BoardOriginOverlap,
                    Some(board.id.clone()),
                ));
            }
        }

        for x in rect.x..rect_max_x {
            for y in rect.y..rect_max_y {
                if !occupied.insert((x, y)) {
                    return Err(ProfileValidationError::new(
                        ProfileValidationCode::BoardOverlap,
                        Some(board.id.clone()),
                    ));
                }
            }
        }

        validate_resolver(
            &entry.resolver,
            &format!("{}:{}", board.id, entry.id),
            layer_ids,
            board_ids,
            table_ids,
            macro_ids,
            macro_map,
            state_kinds,
        )?;
    }

    if let (Some(min_x), Some(min_y), Some(max_x), Some(max_y)) =
        (min_x, min_y, max_x, max_y)
    {
        if max_x - min_x > ProfileV3Limits::BOARD_ATOMIC_EXTENT
            || max_y - min_y > ProfileV3Limits::BOARD_ATOMIC_EXTENT
        {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::BoardExtent,
                Some(board.id.clone()),
            ));
        }
    }

    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn validate_resolver(
    resolver: &EntryResolverV3,
    owner: &str,
    layer_ids: &HashSet<&str>,
    board_ids: &HashSet<&str>,
    table_ids: &HashSet<&str>,
    macro_ids: &HashSet<&str>,
    macro_map: &HashMap<&str, &MacroV3>,
    state_kinds: &HashMap<String, ValueKind>,
) -> Result<(), ProfileValidationError> {
    if resolver.cases.len() > ProfileV3Limits::CONDITIONAL_CASES_PER_ENTRY {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::LimitConditions,
            Some(owner.to_owned()),
        ));
    }

    let mut condition_nodes = 0usize;

    for case_item in &resolver.cases {
        validate_condition(
            &case_item.when.0,
            state_kinds,
            table_ids,
            1,
            &mut condition_nodes,
        )?;
        validate_endpoint(
            &case_item.behavior,
            owner,
            layer_ids,
            board_ids,
            table_ids,
            macro_ids,
            macro_map,
            state_kinds,
            &mut condition_nodes,
        )?;
    }

    validate_endpoint(
        &resolver.default,
        owner,
        layer_ids,
        board_ids,
        table_ids,
        macro_ids,
        macro_map,
        state_kinds,
        &mut condition_nodes,
    )?;

    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn validate_endpoint(
    behavior: &EndpointBehaviorV3,
    owner: &str,
    layer_ids: &HashSet<&str>,
    board_ids: &HashSet<&str>,
    table_ids: &HashSet<&str>,
    macro_ids: &HashSet<&str>,
    macro_map: &HashMap<&str, &MacroV3>,
    state_kinds: &HashMap<String, ValueKind>,
    condition_nodes: &mut usize,
) -> Result<(), ProfileValidationError> {
    let hold_action_count = behavior.hold.as_ref().map_or(0, |hold| {
        hold.on_start.len()
            + hold
                .repeat_behavior
                .as_ref()
                .map_or(0, |repeat| repeat.actions.len())
    });
    let total_actions = behavior.on_release.len() + hold_action_count;
    if total_actions > ProfileLimits::ENDPOINT_ACTIONS {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::LimitActions,
            Some(owner.to_owned()),
        ));
    }

    if let Some(presentation) = &behavior.presentation {
        validate_presentation_v3(
            presentation,
            owner,
            state_kinds,
            table_ids,
            condition_nodes,
        )?;
    }

    if let Some(transition) = &behavior.transition {
        validate_transition(transition, owner, board_ids)?;
        if actions_change_control_plane(&behavior.on_release, macro_map) {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::ConflictingControlFlow,
                Some(owner.to_owned()),
            ));
        }
    }

    validate_actions(
        &behavior.on_release,
        false,
        layer_ids,
        board_ids,
        table_ids,
        macro_ids,
        macro_map,
        state_kinds,
        condition_nodes,
    )?;

    if let Some(hold) = &behavior.hold {
        if !(50..=5000).contains(&hold.delay_ms) {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some(format!("{owner}.hold.delayMs")),
            ));
        }

        if let Some(transition) = &hold.transition {
            validate_transition(transition, owner, board_ids)?;
            if actions_change_control_plane(&hold.on_start, macro_map) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::ConflictingControlFlow,
                    Some(owner.to_owned()),
                ));
            }
        }

        validate_actions(
            &hold.on_start,
            false,
            layer_ids,
            board_ids,
            table_ids,
            macro_ids,
            macro_map,
            state_kinds,
            condition_nodes,
        )?;

        if let Some(repeat) = &hold.repeat_behavior {
            if !(16..=5000).contains(&repeat.interval_ms) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::UnsupportedSchema,
                    Some(format!("{owner}.hold.repeat.intervalMs")),
                ));
            }
            validate_actions(
                &repeat.actions,
                false,
                layer_ids,
                board_ids,
                table_ids,
                macro_ids,
                macro_map,
                state_kinds,
                condition_nodes,
            )?;
        }
    }

    Ok(())
}

fn validate_transition(
    transition: &BoardTransitionV3,
    owner: &str,
    board_ids: &HashSet<&str>,
) -> Result<(), ProfileValidationError> {
    if !board_ids.contains(transition.target_board_ref.as_str()) {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::MissingReference,
            Some(format!("{owner}:{}", transition.target_board_ref)),
        ));
    }
    Ok(())
}

fn validate_presentation_v3(
    presentation: &PresentationV3,
    owner: &str,
    state_kinds: &HashMap<String, ValueKind>,
    table_ids: &HashSet<&str>,
    condition_nodes: &mut usize,
) -> Result<(), ProfileValidationError> {
    if let Some(text) = &presentation.text {
        validate_resolved_string(text, owner, state_kinds, table_ids, condition_nodes)?;
    }
    validate_string_option(presentation.accessibility_label.as_deref(), owner)
}

fn validate_resolved_string(
    resolved: &ResolvedStringV3,
    owner: &str,
    state_kinds: &HashMap<String, ValueKind>,
    table_ids: &HashSet<&str>,
    condition_nodes: &mut usize,
) -> Result<(), ProfileValidationError> {
    validate_string(&resolved.base, owner)?;

    if resolved.transforms.len() > ProfileV3Limits::CONDITIONAL_TRANSFORMS_PER_STRING {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::LimitConditionalTransforms,
            Some(owner.to_owned()),
        ));
    }

    for transform in &resolved.transforms {
        if !table_ids.contains(transform.table_ref.as_str()) {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::InvalidTransformReference,
                Some(transform.table_ref.clone()),
            ));
        }
        validate_condition(
            &transform.when.0,
            state_kinds,
            table_ids,
            1,
            condition_nodes,
        )?;
    }

    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn validate_actions(
    actions: &[ActionInvocationV3],
    in_macro: bool,
    layer_ids: &HashSet<&str>,
    board_ids: &HashSet<&str>,
    table_ids: &HashSet<&str>,
    macro_ids: &HashSet<&str>,
    macro_map: &HashMap<&str, &MacroV3>,
    state_kinds: &HashMap<String, ValueKind>,
    condition_nodes: &mut usize,
) -> Result<(), ProfileValidationError> {
    for action in actions {
        if in_macro && action.action_id == "macro.run" {
            return Err(ProfileValidationError::simple(
                ProfileValidationCode::MacroNesting,
            ));
        }

        validate_action_argument_size(action)?;
        validate_action_shape(
            action,
            layer_ids,
            board_ids,
            table_ids,
            macro_ids,
            macro_map,
            state_kinds,
            condition_nodes,
        )?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn validate_action_shape(
    action: &ActionInvocationV3,
    layer_ids: &HashSet<&str>,
    _board_ids: &HashSet<&str>,
    table_ids: &HashSet<&str>,
    macro_ids: &HashSet<&str>,
    _macro_map: &HashMap<&str, &MacroV3>,
    state_kinds: &HashMap<String, ValueKind>,
    condition_nodes: &mut usize,
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
            let value = arguments.get("text").cloned().ok_or_else(invalid)?;
            let resolved: ResolvedStringV3 =
                serde_json::from_value(value).map_err(|_| invalid())?;
            validate_resolved_string(
                &resolved,
                &action.action_id,
                state_kinds,
                table_ids,
                condition_nodes,
            )?;
        }
        "text.transform" => {
            ensure_exact_keys(arguments, &["table"]).map_err(|_| invalid())?;
            let table = get_string(arguments, "table").ok_or_else(invalid)?;
            if !table_ids.contains(table) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::InvalidTransformReference,
                    Some(table.to_owned()),
                ));
            }
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
            return Err(ProfileValidationError::new(
                ProfileValidationCode::UnavailableCapability,
                Some("profile.switch".into()),
            ));
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
        "state.set" => {
            ensure_exact_keys(arguments, &["state", "value"]).map_err(|_| invalid())?;
            let state_id = get_string(arguments, "state").ok_or_else(invalid)?;
            let Some(kind) = state_kinds.get(state_id) else {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(state_id.to_owned()),
                ));
            };
            let value = arguments.get("value").ok_or_else(invalid)?;
            if !state_value_matches(kind, value) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::InvalidState,
                    Some(state_id.to_owned()),
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

fn actions_change_control_plane(
    actions: &[ActionInvocationV3],
    macro_map: &HashMap<&str, &MacroV3>,
) -> bool {
    actions.iter().any(|action| match action.action_id.as_str() {
        "layer.set" | "layer.push" | "layer.pop" | "profile.switch" => true,
        "macro.run" => get_string(&action.arguments, "macro")
            .and_then(|macro_id| macro_map.get(macro_id).copied())
            .is_some_and(|macro_item| {
                macro_item.actions.iter().any(|nested| {
                    matches!(
                        nested.action_id.as_str(),
                        "layer.set" | "layer.push" | "layer.pop" | "profile.switch"
                    )
                })
            }),
        _ => false,
    })
}

fn validate_action_argument_size(
    action: &ActionInvocationV3,
) -> Result<(), ProfileValidationError> {
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

fn scan_string_sizes(value: &Value, owner: &str) -> Result<(), ProfileValidationError> {
    match value {
        Value::String(text) => validate_string(text, owner)?,
        Value::Array(values) => {
            for value in values {
                scan_string_sizes(value, owner)?;
            }
        }
        Value::Object(values) => {
            for value in values.values() {
                scan_string_sizes(value, owner)?;
            }
        }
        _ => {}
    }
    Ok(())
}

fn validate_condition(
    value: &Value,
    state_kinds: &HashMap<String, ValueKind>,
    table_ids: &HashSet<&str>,
    depth: usize,
    nodes: &mut usize,
) -> Result<(), ProfileValidationError> {
    if depth > ProfileV3Limits::CONDITION_DEPTH {
        return Err(ProfileValidationError::simple(
            ProfileValidationCode::LimitConditions,
        ));
    }

    let Some(object) = value.as_object() else {
        return Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidCondition,
        ));
    };

    if object.len() != 1 {
        return Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidCondition,
        ));
    }

    let (operator, operand) = object.iter().next().expect("one condition member");

    match operator.as_str() {
        "state" | "fact" | "literal" => {
            let kind = validate_value_expression(
                value,
                state_kinds,
                depth,
                nodes,
            )?;
            if kind == ValueKind::Boolean {
                Ok(())
            } else {
                Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ))
            }
        }
        "eq" => {
            bump_condition_node(nodes)?;
            let array = exact_array(operand, 2)?;
            let left = validate_value_expression(&array[0], state_kinds, depth, nodes)?;
            let right = validate_value_expression(&array[1], state_kinds, depth, nodes)?;
            if value_kinds_compatible(&left, &right)
                && enum_literal_compatible(&left, &array[1])
                && enum_literal_compatible(&right, &array[0])
            {
                Ok(())
            } else {
                Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ))
            }
        }
        "in" => {
            bump_condition_node(nodes)?;
            let array = exact_array(operand, 2)?;
            let left = validate_value_expression(&array[0], state_kinds, depth, nodes)?;
            let Some(literals) = array[1].as_array() else {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            };
            if literals.is_empty() {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            }
            for literal in literals {
                bump_condition_node(nodes)?;
                let literal_kind = literal_kind(literal)?;
                if !value_kinds_compatible(&left, &literal_kind)
                    || !enum_raw_literal_compatible(&left, literal)
                {
                    return Err(ProfileValidationError::simple(
                        ProfileValidationCode::InvalidCondition,
                    ));
                }
            }
            Ok(())
        }
        "all" | "any" => {
            bump_condition_node(nodes)?;
            let Some(conditions) = operand.as_array() else {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            };
            if conditions.is_empty() {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            }
            for condition in conditions {
                validate_condition(
                    condition,
                    state_kinds,
                    table_ids,
                    depth + 1,
                    nodes,
                )?;
            }
            Ok(())
        }
        "not" => {
            bump_condition_node(nodes)?;
            validate_condition(operand, state_kinds, table_ids, depth + 1, nodes)
        }
        "transformMatch" => {
            bump_condition_node(nodes)?;
            let Some(match_object) = operand.as_object() else {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            };
            if match_object.len() != 2
                || !match_object.contains_key("tableRef")
                || !match_object.contains_key("target")
            {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            }
            let Some(table_ref) = match_object.get("tableRef").and_then(Value::as_str) else {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            };
            let Some(target) = match_object.get("target").and_then(Value::as_str) else {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            };
            if target != "compositionTail" {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            }
            if !table_ids.contains(table_ref) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::InvalidTransformReference,
                    Some(table_ref.to_owned()),
                ));
            }
            Ok(())
        }
        _ => Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidCondition,
        )),
    }
}

fn validate_value_expression(
    value: &Value,
    state_kinds: &HashMap<String, ValueKind>,
    _depth: usize,
    nodes: &mut usize,
) -> Result<ValueKind, ProfileValidationError> {
    bump_condition_node(nodes)?;

    let Some(object) = value.as_object() else {
        return Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidCondition,
        ));
    };
    if object.len() != 1 {
        return Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidCondition,
        ));
    }

    let (kind, operand) = object.iter().next().expect("one value-expression member");

    match kind.as_str() {
        "state" => {
            let Some(state_id) = operand.as_str() else {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            };
            state_kinds.get(state_id).cloned().ok_or_else(|| {
                ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(state_id.to_owned()),
                )
            })
        }
        "fact" => {
            let Some(fact_id) = operand.as_str() else {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::InvalidCondition,
                ));
            };
            match fact_id {
                "composition.empty"
                | "conversion.active"
                | "conversion.hasCandidates"
                | "host.autocapitalizeNext"
                | "host.needsInputModeSwitchKey" => Ok(ValueKind::Boolean),
                "layer.id" | "host.returnKey" | "host.keyboardType" => Ok(ValueKind::String),
                _ => Err(ProfileValidationError::new(
                    ProfileValidationCode::UnknownRuntimeFact,
                    Some(fact_id.to_owned()),
                )),
            }
        }
        "literal" => literal_kind(operand),
        _ => Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidCondition,
        )),
    }
}

fn literal_kind(value: &Value) -> Result<ValueKind, ProfileValidationError> {
    match value {
        Value::Bool(_) => Ok(ValueKind::Boolean),
        Value::String(text) => {
            validate_string(text, "condition.literal")?;
            Ok(ValueKind::String)
        }
        _ => Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidCondition,
        )),
    }
}

fn value_kinds_compatible(left: &ValueKind, right: &ValueKind) -> bool {
    matches!(
        (left, right),
        (ValueKind::Boolean, ValueKind::Boolean)
            | (ValueKind::String, ValueKind::String)
            | (ValueKind::Enum(_), ValueKind::String)
            | (ValueKind::String, ValueKind::Enum(_))
            | (ValueKind::Enum(_), ValueKind::Enum(_))
    )
}

fn enum_literal_compatible(kind: &ValueKind, expression: &Value) -> bool {
    let ValueKind::Enum(values) = kind else {
        return true;
    };
    expression
        .as_object()
        .and_then(|object| object.get("literal"))
        .and_then(Value::as_str)
        .is_none_or(|literal| values.contains(literal))
}

fn enum_raw_literal_compatible(kind: &ValueKind, literal: &Value) -> bool {
    let ValueKind::Enum(values) = kind else {
        return true;
    };
    literal
        .as_str()
        .is_some_and(|value| values.contains(value))
}

fn state_value_matches(kind: &ValueKind, value: &Value) -> bool {
    match kind {
        ValueKind::Boolean => value.is_boolean(),
        ValueKind::String => value.is_string(),
        ValueKind::Enum(values) => value
            .as_str()
            .is_some_and(|candidate| values.contains(candidate)),
    }
}

fn bump_condition_node(nodes: &mut usize) -> Result<(), ProfileValidationError> {
    *nodes = nodes.saturating_add(1);
    if *nodes > ProfileV3Limits::CONDITION_NODES_PER_RESOLVER {
        Err(ProfileValidationError::simple(
            ProfileValidationCode::LimitConditions,
        ))
    } else {
        Ok(())
    }
}

fn exact_array(value: &Value, length: usize) -> Result<&[Value], ProfileValidationError> {
    let Some(array) = value.as_array() else {
        return Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidCondition,
        ));
    };
    if array.len() != length {
        return Err(ProfileValidationError::simple(
            ProfileValidationCode::InvalidCondition,
        ));
    }
    Ok(array)
}

fn validate_id(value: &str) -> Result<(), ProfileValidationError> {
    if is_valid_id(value) {
        Ok(())
    } else {
        Err(ProfileValidationError::new(
            ProfileValidationCode::UnsupportedSchema,
            Some(value.to_owned()),
        ))
    }
}

fn validate_string(value: &str, owner: &str) -> Result<(), ProfileValidationError> {
    if value.len() <= ProfileLimits::STRING_ARGUMENT_BYTES {
        Ok(())
    } else {
        Err(ProfileValidationError::new(
            ProfileValidationCode::ArgumentTooLarge,
            Some(owner.to_owned()),
        ))
    }
}

fn validate_string_option(value: Option<&str>, owner: &str) -> Result<(), ProfileValidationError> {
    if let Some(value) = value {
        validate_string(value, owner)?;
    }
    Ok(())
}

fn check_count(
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


fn reject_explicit_null(
    object: &Map<String, Value>,
    key: &str,
    owner: &str,
) -> Result<(), ProfileValidationError> {
    if object.get(key).is_some_and(Value::is_null) {
        return Err(ProfileValidationError::new(
            ProfileValidationCode::UnsupportedSchema,
            Some(format!("{owner}.{key} must not be null")),
        ));
    }
    Ok(())
}

fn validate_presentation_structural_contract(
    value: Option<&Value>,
    owner: &str,
) -> Result<(), ProfileValidationError> {
    let Some(object) = value.and_then(Value::as_object) else {
        return Ok(());
    };
    reject_explicit_null(object, "text", owner)?;
    reject_explicit_null(object, "accessibilityLabel", owner)
}

fn validate_behavior_structural_contract(
    value: Option<&Value>,
    owner: &str,
) -> Result<(), ProfileValidationError> {
    let Some(object) = value.and_then(Value::as_object) else {
        return Ok(());
    };

    reject_explicit_null(object, "presentation", owner)?;
    reject_explicit_null(object, "transition", owner)?;
    reject_explicit_null(object, "hold", owner)?;
    validate_presentation_structural_contract(
        object.get("presentation"),
        &format!("{owner}.presentation"),
    )?;

    if let Some(hold) = object.get("hold").and_then(Value::as_object) {
        reject_explicit_null(hold, "transition", &format!("{owner}.hold"))?;
        reject_explicit_null(hold, "repeat", &format!("{owner}.hold"))?;
    }

    Ok(())
}

fn validate_v3_structural_contract(value: &Value) -> Result<(), ProfileValidationError> {
    let Some(root) = value.as_object() else {
        return Err(ProfileValidationError::simple(
            ProfileValidationCode::UnsupportedSchema,
        ));
    };

    reject_explicit_null(root, "theme", "profile")?;

    if let Some(layers) = root.get("layers").and_then(Value::as_array) {
        for (index, layer) in layers.iter().enumerate() {
            if let Some(object) = layer.as_object() {
                reject_explicit_null(object, "name", &format!("layers[{index}]"))?;
            }
        }
    }

    if let Some(states) = root.get("states").and_then(Value::as_array) {
        for (index, state) in states.iter().enumerate() {
            if let Some(object) = state.as_object() {
                reject_explicit_null(object, "values", &format!("states[{index}]"))?;
            }
        }
    }

    if let Some(boards) = root.get("boards").and_then(Value::as_array) {
        for (board_index, board) in boards.iter().enumerate() {
            let Some(entries) = board.get("entries").and_then(Value::as_array) else {
                continue;
            };

            for (entry_index, entry) in entries.iter().enumerate() {
                let Some(resolver) = entry.get("resolver").and_then(Value::as_object) else {
                    continue;
                };
                let owner = format!("boards[{board_index}].entries[{entry_index}].resolver");

                if let Some(cases) = resolver.get("cases").and_then(Value::as_array) {
                    for (case_index, case_item) in cases.iter().enumerate() {
                        validate_behavior_structural_contract(
                            case_item.get("behavior"),
                            &format!("{owner}.cases[{case_index}].behavior"),
                        )?;
                    }
                }

                validate_behavior_structural_contract(
                    resolver.get("default"),
                    &format!("{owner}.default"),
                )?;
            }
        }
    }

    Ok(())
}
