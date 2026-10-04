use crate::profile_v3::{
    ActionInvocationV3, BoardEntryV3, ConditionV3, EndpointBehaviorV3, HoldBehaviorV3,
    PresentationV3, ProfileBundleV3, RepeatBehaviorV3, ResolvedStringV3, StateDeclarationV3,
    TransformTableV3,
};
use crate::profile_v3_board_runtime::BoardSemanticsV3;
use crate::profile_v3_validation::ProfileV3Validator;
use crate::validation::ProfileValidationError;
use serde_json::{Map, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompositionTailTransformV3 {
    pub table_id: String,
    pub matched_source: String,
    pub replacement: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum RuntimeDispatchV3 {
    Action(ActionInvocationV3),
    CompositionTailTransform(CompositionTailTransformV3),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RuntimeSemanticContextV3 {
    pub composition: String,
    pub conversion_active: bool,
    pub conversion_has_candidates: bool,
    pub layer_id: String,
    pub host: HostInputFactsV3,
}

/// Bounded, read-only host input facts (#69 §14). Platform adapters normalize
/// native traits into these closed vocabularies; they feed Profile conditions
/// and never become a second layout engine.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HostInputFactsV3 {
    /// default | go | search | send | next | done | join | route | continue | emergencyCall
    pub return_key: String,
    /// default | ascii | numbers | url | email | phone | decimal | twitter | webSearch
    pub keyboard_type: String,
    /// True when host autocapitalization asks to capitalize the next letter.
    pub autocapitalize_next: bool,
    pub needs_input_mode_switch_key: bool,
}

impl Default for HostInputFactsV3 {
    fn default() -> Self {
        Self {
            return_key: "default".into(),
            keyboard_type: "default".into(),
            autocapitalize_next: false,
            needs_input_mode_switch_key: true,
        }
    }
}

impl HostInputFactsV3 {
    pub const RETURN_KEYS: &'static [&'static str] = &[
        "default", "go", "search", "send", "next", "done", "join", "route", "continue",
        "emergencyCall",
    ];
    pub const KEYBOARD_TYPES: &'static [&'static str] = &[
        "default", "ascii", "numbers", "url", "email", "phone", "decimal", "twitter",
        "webSearch",
    ];

    /// Unknown native values collapse to `default` so the vocabulary stays closed.
    pub fn normalized(
        return_key: &str,
        keyboard_type: &str,
        autocapitalize_next: bool,
        needs_input_mode_switch_key: bool,
    ) -> Self {
        let pick = |value: &str, allowed: &[&str]| {
            if allowed.contains(&value) { value.to_owned() } else { "default".to_owned() }
        };
        Self {
            return_key: pick(return_key, Self::RETURN_KEYS),
            keyboard_type: pick(keyboard_type, Self::KEYBOARD_TYPES),
            autocapitalize_next,
            needs_input_mode_switch_key,
        }
    }
}

impl RuntimeSemanticContextV3 {
    pub fn new(layer_id: impl Into<String>) -> Self {
        Self {
            composition: String::new(),
            conversion_active: false,
            conversion_has_candidates: false,
            layer_id: layer_id.into(),
            host: HostInputFactsV3::default(),
        }
    }
}

pub type RuntimeSemanticContextHandleV3 = Arc<Mutex<RuntimeSemanticContextV3>>;

#[derive(Debug, Clone)]
struct SemanticSnapshotV3 {
    states: HashMap<String, Value>,
    context: RuntimeSemanticContextV3,
}

#[derive(Clone)]
pub struct ProfileSemanticsRuntimeV3 {
    tables: Arc<HashMap<String, TransformTableV3>>,
    declarations: Arc<HashMap<String, StateDeclarationV3>>,
    states: Arc<Mutex<HashMap<String, Value>>>,
}

impl ProfileSemanticsRuntimeV3 {
    pub fn compile(profile: &ProfileBundleV3) -> Result<Self, ProfileValidationError> {
        ProfileV3Validator::validate(profile, None)?;

        let declarations = profile
            .states
            .iter()
            .cloned()
            .map(|declaration| (declaration.id.clone(), declaration))
            .collect::<HashMap<_, _>>();
        let states = profile
            .states
            .iter()
            .map(|declaration| (declaration.id.clone(), declaration.default.clone()))
            .collect::<HashMap<_, _>>();
        let tables = profile
            .transform_tables
            .iter()
            .cloned()
            .map(|table| (table.id.clone(), table))
            .collect::<HashMap<_, _>>();

        Ok(Self {
            tables: Arc::new(tables),
            declarations: Arc::new(declarations),
            states: Arc::new(Mutex::new(states)),
        })
    }

    pub fn context_handle(
        context: RuntimeSemanticContextV3,
    ) -> RuntimeSemanticContextHandleV3 {
        Arc::new(Mutex::new(context))
    }

    pub fn board_semantics(
        &self,
        context: RuntimeSemanticContextHandleV3,
    ) -> ProfileBoardSemanticsV3 {
        ProfileBoardSemanticsV3 {
            runtime: self.clone(),
            context,
        }
    }

    pub fn state_value(&self, state_id: &str) -> Option<Value> {
        self.states.lock().ok()?.get(state_id).cloned()
    }

    fn snapshot(
        &self,
        context: &RuntimeSemanticContextHandleV3,
    ) -> Option<SemanticSnapshotV3> {
        let states = self.states.lock().ok()?.clone();
        let context = context.lock().ok()?.clone();
        Some(SemanticSnapshotV3 { states, context })
    }

    fn apply_state_mutations(&self, mutations: &[(String, Value)]) {
        let Ok(mut states) = self.states.lock() else {
            return;
        };

        for (state_id, value) in mutations {
            let Some(declaration) = self.declarations.get(state_id) else {
                continue;
            };
            if state_value_matches(declaration, value) {
                states.insert(state_id.clone(), value.clone());
            }
        }
    }

    fn resolve_endpoint_with_snapshot(
        &self,
        entry: &BoardEntryV3,
        snapshot: &SemanticSnapshotV3,
    ) -> EndpointBehaviorV3 {
        let authored = entry
            .resolver
            .cases
            .iter()
            .find(|case_item| {
                evaluate_condition(
                    &case_item.when,
                    snapshot,
                    &self.tables,
                )
            })
            .map(|case_item| &case_item.behavior)
            .unwrap_or(&entry.resolver.default);

        resolve_endpoint_behavior(authored, snapshot, &self.tables)
    }

    fn resolve_dispatch_batch_with_snapshot(
        &self,
        actions: &[ActionInvocationV3],
        snapshot: &SemanticSnapshotV3,
    ) -> (Vec<RuntimeDispatchV3>, Vec<(String, Value)>) {
        let mut dispatches = Vec::new();
        let mut mutations = Vec::new();

        for action in actions {
            match action.action_id.as_str() {
                "state.set" => {
                    let state_id = action
                        .arguments
                        .get("state")
                        .and_then(Value::as_str)
                        .map(str::to_owned);
                    let value = action.arguments.get("value").cloned();
                    if let (Some(state_id), Some(value)) = (state_id, value) {
                        mutations.push((state_id, value));
                    }
                }
                "text.transform" => {
                    let Some(table_id) = action.arguments.get("table").and_then(Value::as_str)
                    else {
                        continue;
                    };
                    let Some(table) = self.tables.get(table_id) else {
                        continue;
                    };
                    let Some(hit) = longest_suffix_match(table, &snapshot.context.composition)
                    else {
                        continue;
                    };
                    dispatches.push(RuntimeDispatchV3::CompositionTailTransform(
                        CompositionTailTransformV3 {
                            table_id: table_id.to_owned(),
                            matched_source: hit.from.clone(),
                            replacement: hit.to.clone(),
                        },
                    ));
                }
                "text.insert" | "text.directInsert" => {
                    let Some(resolved) = resolve_runtime_text_action(
                        action,
                        snapshot,
                        &self.tables,
                    ) else {
                        continue;
                    };
                    dispatches.push(RuntimeDispatchV3::Action(resolved));
                }
                _ => {
                    dispatches.push(RuntimeDispatchV3::Action(action.clone()));
                }
            }
        }

        (dispatches, mutations)
    }
}

pub struct ProfileBoardSemanticsV3 {
    runtime: ProfileSemanticsRuntimeV3,
    context: RuntimeSemanticContextHandleV3,
}

impl BoardSemanticsV3 for ProfileBoardSemanticsV3 {
    fn resolve_endpoint(&mut self, entry: &BoardEntryV3) -> EndpointBehaviorV3 {
        let Some(snapshot) = self.runtime.snapshot(&self.context) else {
            return entry.resolver.default.clone();
        };
        self.runtime.resolve_endpoint_with_snapshot(entry, &snapshot)
    }

    fn resolve_dispatch_batch(
        &mut self,
        actions: &[ActionInvocationV3],
    ) -> Vec<RuntimeDispatchV3> {
        let Some(snapshot) = self.runtime.snapshot(&self.context) else {
            return Vec::new();
        };

        let (dispatches, mutations) = self
            .runtime
            .resolve_dispatch_batch_with_snapshot(actions, &snapshot);
        self.runtime.apply_state_mutations(&mutations);
        dispatches
    }
}

fn resolve_endpoint_behavior(
    behavior: &EndpointBehaviorV3,
    snapshot: &SemanticSnapshotV3,
    tables: &HashMap<String, TransformTableV3>,
) -> EndpointBehaviorV3 {
    let mut resolved = behavior.clone();

    if let Some(presentation) = &behavior.presentation {
        resolved.presentation = Some(resolve_presentation(
            presentation,
            snapshot,
            tables,
        ));
    }

    resolved.on_release = behavior
        .on_release
        .iter()
        .map(|action| resolve_endpoint_action(action, snapshot, tables))
        .collect();

    if let Some(hold) = &behavior.hold {
        resolved.hold = Some(resolve_hold(hold, snapshot, tables));
    }

    resolved
}

fn resolve_presentation(
    presentation: &PresentationV3,
    snapshot: &SemanticSnapshotV3,
    tables: &HashMap<String, TransformTableV3>,
) -> PresentationV3 {
    let mut resolved = presentation.clone();
    if let Some(text) = &presentation.text {
        resolved.text = Some(concrete_resolved_string(
            resolve_string(text, snapshot, tables),
        ));
    }
    resolved
}

fn resolve_hold(
    hold: &HoldBehaviorV3,
    snapshot: &SemanticSnapshotV3,
    tables: &HashMap<String, TransformTableV3>,
) -> HoldBehaviorV3 {
    let mut resolved = hold.clone();
    resolved.on_start = hold
        .on_start
        .iter()
        .map(|action| resolve_endpoint_action(action, snapshot, tables))
        .collect();

    if let Some(repeat) = &hold.repeat_behavior {
        resolved.repeat_behavior = Some(RepeatBehaviorV3 {
            interval_ms: repeat.interval_ms,
            actions: repeat
                .actions
                .iter()
                .map(|action| resolve_endpoint_action(action, snapshot, tables))
                .collect(),
            extra: repeat.extra.clone(),
        });
    }

    resolved
}

fn resolve_endpoint_action(
    action: &ActionInvocationV3,
    snapshot: &SemanticSnapshotV3,
    tables: &HashMap<String, TransformTableV3>,
) -> ActionInvocationV3 {
    if !matches!(action.action_id.as_str(), "text.insert" | "text.directInsert") {
        return action.clone();
    }

    let Some(value) = action.arguments.get("text") else {
        return action.clone();
    };
    let Ok(resolved_string) = serde_json::from_value::<ResolvedStringV3>(value.clone()) else {
        return action.clone();
    };

    let concrete = concrete_resolved_string(resolve_string(
        &resolved_string,
        snapshot,
        tables,
    ));
    let Ok(concrete_value) = serde_json::to_value(concrete) else {
        return action.clone();
    };

    let mut resolved = action.clone();
    resolved.arguments.insert("text".into(), concrete_value);
    resolved
}

fn resolve_runtime_text_action(
    action: &ActionInvocationV3,
    snapshot: &SemanticSnapshotV3,
    tables: &HashMap<String, TransformTableV3>,
) -> Option<ActionInvocationV3> {
    let value = action.arguments.get("text")?;

    let concrete = if let Some(text) = value.as_str() {
        text.to_owned()
    } else {
        let resolved_string =
            serde_json::from_value::<ResolvedStringV3>(value.clone()).ok()?;
        resolve_string(&resolved_string, snapshot, tables)
    };

    let mut resolved = action.clone();
    resolved
        .arguments
        .insert("text".into(), Value::String(concrete));
    Some(resolved)
}

fn concrete_resolved_string(value: String) -> ResolvedStringV3 {
    ResolvedStringV3 {
        base: value,
        transforms: Vec::new(),
        extra: Map::new(),
    }
}

fn resolve_string(
    resolved: &ResolvedStringV3,
    snapshot: &SemanticSnapshotV3,
    tables: &HashMap<String, TransformTableV3>,
) -> String {
    let mut current = resolved.base.clone();

    for transform in &resolved.transforms {
        if !evaluate_condition(&transform.when, snapshot, tables) {
            continue;
        }
        let Some(table) = tables.get(&transform.table_ref) else {
            continue;
        };
        current = exact_whole_string_transform(table, &current);
    }

    current
}

fn exact_whole_string_transform(table: &TransformTableV3, input: &str) -> String {
    table
        .entries
        .iter()
        .find(|entry| entry.from == input)
        .map(|entry| entry.to.clone())
        .unwrap_or_else(|| input.to_owned())
}

fn longest_suffix_match<'a>(
    table: &'a TransformTableV3,
    composition: &str,
) -> Option<&'a crate::profile_v3::TransformEntryV3> {
    table
        .entries
        .iter()
        .filter(|entry| composition.ends_with(entry.from.as_str()))
        .max_by(|lhs, rhs| {
            lhs.from
                .chars()
                .count()
                .cmp(&rhs.from.chars().count())
        })
}

fn evaluate_condition(
    condition: &ConditionV3,
    snapshot: &SemanticSnapshotV3,
    tables: &HashMap<String, TransformTableV3>,
) -> bool {
    evaluate_condition_checked(condition, snapshot, tables).unwrap_or(false)
}

fn evaluate_condition_checked(
    condition: &ConditionV3,
    snapshot: &SemanticSnapshotV3,
    tables: &HashMap<String, TransformTableV3>,
) -> Option<bool> {
    let object = condition.0.as_object()?;
    if object.len() != 1 {
        return None;
    }

    let (operator, operand) = object.iter().next()?;

    match operator.as_str() {
        "state" | "fact" | "literal" => {
            value_expression(&condition.0, snapshot)?.as_bool()
        }
        "eq" => {
            let values = operand.as_array()?;
            if values.len() != 2 {
                return None;
            }
            let lhs = value_expression(&values[0], snapshot)?;
            let rhs = value_expression(&values[1], snapshot)?;
            Some(lhs == rhs)
        }
        "in" => {
            let values = operand.as_array()?;
            if values.len() != 2 {
                return None;
            }
            let lhs = value_expression(&values[0], snapshot)?;
            let items = values[1].as_array()?;
            if items.is_empty()
                || items
                    .iter()
                    .any(|item| !matches!(item, Value::Bool(_) | Value::String(_)))
            {
                return None;
            }
            Some(items.iter().any(|item| item == &lhs))
        }
        "all" => {
            let items = operand.as_array()?;
            if items.is_empty() {
                return None;
            }
            let mut result = true;
            for item in items {
                result &= evaluate_condition_checked(
                    &ConditionV3(item.clone()),
                    snapshot,
                    tables,
                )?;
            }
            Some(result)
        }
        "any" => {
            let items = operand.as_array()?;
            if items.is_empty() {
                return None;
            }
            let mut result = false;
            for item in items {
                result |= evaluate_condition_checked(
                    &ConditionV3(item.clone()),
                    snapshot,
                    tables,
                )?;
            }
            Some(result)
        }
        "not" => Some(!evaluate_condition_checked(
            &ConditionV3(operand.clone()),
            snapshot,
            tables,
        )?),
        "transformMatch" => {
            let match_object = operand.as_object()?;
            if match_object.len() != 2
                || match_object.get("target").and_then(Value::as_str)
                    != Some("compositionTail")
            {
                return None;
            }
            let table_ref = match_object.get("tableRef")?.as_str()?;
            let table = tables.get(table_ref)?;
            Some(
                longest_suffix_match(table, &snapshot.context.composition)
                    .is_some(),
            )
        }
        _ => None,
    }
}

fn value_expression(
    expression: &Value,
    snapshot: &SemanticSnapshotV3,
) -> Option<Value> {
    let object = expression.as_object()?;
    if object.len() != 1 {
        return None;
    }
    let (kind, operand) = object.iter().next()?;

    match kind.as_str() {
        "state" => snapshot
            .states
            .get(operand.as_str()?)
            .cloned(),
        "fact" => match operand.as_str()? {
            "composition.empty" => Some(Value::Bool(
                snapshot.context.composition.is_empty(),
            )),
            "conversion.active" => {
                Some(Value::Bool(snapshot.context.conversion_active))
            }
            "conversion.hasCandidates" => Some(Value::Bool(
                snapshot.context.conversion_has_candidates,
            )),
            "layer.id" => Some(Value::String(snapshot.context.layer_id.clone())),
            "host.returnKey" => Some(Value::String(snapshot.context.host.return_key.clone())),
            "host.keyboardType" => {
                Some(Value::String(snapshot.context.host.keyboard_type.clone()))
            }
            "host.autocapitalizeNext" => {
                Some(Value::Bool(snapshot.context.host.autocapitalize_next))
            }
            "host.needsInputModeSwitchKey" => {
                Some(Value::Bool(snapshot.context.host.needs_input_mode_switch_key))
            }
            _ => None,
        },
        "literal" => match operand {
            Value::Bool(_) | Value::String(_) => Some(operand.clone()),
            _ => None,
        },
        _ => None,
    }
}

fn state_value_matches(
    declaration: &StateDeclarationV3,
    value: &Value,
) -> bool {
    match declaration.state_type.as_str() {
        "boolean" => value.is_boolean(),
        "enum" => {
            let Some(candidate) = value.as_str() else {
                return false;
            };
            declaration
                .values
                .as_ref()
                .is_some_and(|values| values.iter().any(|value| value == candidate))
        }
        _ => false,
    }
}

