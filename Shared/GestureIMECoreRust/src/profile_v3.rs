use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::HashMap;

pub type V3Extra = Map<String, Value>;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GesturePolicyV3 {
    pub dead_zone: f64,
    pub initial_cell_commit_distance: f64,
    pub subsequent_cell_commit_distance: f64,
    pub angular_hysteresis_degrees: f64,
    /// Dwell before a rollback-eligible stage pops one Stage Stack frame (#69 §4.8).
    /// Absent means [`GesturePolicyV3::DEFAULT_STAGE_BACKTRACK_DWELL_MS`].
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stage_backtrack_dwell_ms: Option<i64>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

impl GesturePolicyV3 {
    pub const DEFAULT_STAGE_BACKTRACK_DWELL_MS: i64 = 1000;
    pub const MIN_STAGE_BACKTRACK_DWELL_MS: i64 = 100;
    pub const MAX_STAGE_BACKTRACK_DWELL_MS: i64 = 10_000;

    pub fn effective_stage_backtrack_dwell_ms(&self) -> i64 {
        self.stage_backtrack_dwell_ms
            .unwrap_or(Self::DEFAULT_STAGE_BACKTRACK_DWELL_MS)
    }

    /// Resolves a source-entry partial override against this Profile-wide policy
    /// (#69 §3.2). Unset override fields inherit the common value.
    pub fn with_override(&self, partial: Option<&GesturePolicyOverrideV3>) -> Self {
        let Some(partial) = partial else {
            return self.clone();
        };
        Self {
            dead_zone: partial.dead_zone.unwrap_or(self.dead_zone),
            initial_cell_commit_distance: partial
                .initial_cell_commit_distance
                .unwrap_or(self.initial_cell_commit_distance),
            subsequent_cell_commit_distance: partial
                .subsequent_cell_commit_distance
                .unwrap_or(self.subsequent_cell_commit_distance),
            angular_hysteresis_degrees: partial
                .angular_hysteresis_degrees
                .unwrap_or(self.angular_hysteresis_degrees),
            stage_backtrack_dwell_ms: Some(
                partial
                    .stage_backtrack_dwell_ms
                    .unwrap_or_else(|| self.effective_stage_backtrack_dwell_ms()),
            ),
            extra: self.extra.clone(),
        }
    }
}

/// Optional per-source partial GesturePolicy override (#69 §3.2). It applies to
/// the gesture stage entered from the BoardEntry that carries it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct GesturePolicyOverrideV3 {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dead_zone: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub initial_cell_commit_distance: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subsequent_cell_commit_distance: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub angular_hysteresis_degrees: Option<f64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stage_backtrack_dwell_ms: Option<i64>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LayerV3 {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    pub root_board_ref: String,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardRectV3 {
    pub x: i64,
    pub y: i64,
    pub width: i64,
    pub height: i64,
    #[serde(flatten)]
    pub extra: V3Extra,
}

impl BoardRectV3 {
    pub fn max_x(&self) -> Option<i64> {
        self.x.checked_add(self.width)
    }

    pub fn max_y(&self) -> Option<i64> {
        self.y.checked_add(self.height)
    }

    pub fn contains_origin(&self) -> bool {
        self.x <= 0
            && self.y <= 0
            && self.max_x().is_some_and(|max_x| 0 < max_x)
            && self.max_y().is_some_and(|max_y| 0 < max_y)
    }

    pub fn overlaps_positive_area(&self, other: &Self) -> bool {
        let (Some(self_max_x), Some(self_max_y), Some(other_max_x), Some(other_max_y)) =
            (self.max_x(), self.max_y(), other.max_x(), other.max_y())
        else {
            return true;
        };

        self.x < other_max_x
            && other.x < self_max_x
            && self.y < other_max_y
            && other.y < self_max_y
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolvedStringV3 {
    pub base: String,
    pub transforms: Vec<ConditionalTransformV3>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConditionalTransformV3 {
    pub when: ConditionV3,
    pub table_ref: String,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct ConditionV3(pub Value);

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct PresentationV3 {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<ResolvedStringV3>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub accessibility_label: Option<String>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActionInvocationV3 {
    #[serde(rename = "actionID")]
    pub action_id: String,
    pub arguments: Map<String, Value>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BoardTransitionLifetimeV3 {
    Persistent,
    Transient,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardTransitionV3 {
    pub target_board_ref: String,
    pub lifetime: BoardTransitionLifetimeV3,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepeatBehaviorV3 {
    pub interval_ms: i64,
    pub actions: Vec<ActionInvocationV3>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HoldBehaviorV3 {
    pub delay_ms: i64,
    pub on_start: Vec<ActionInvocationV3>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub transition: Option<BoardTransitionV3>,
    #[serde(rename = "repeat", default, skip_serializing_if = "Option::is_none")]
    pub repeat_behavior: Option<RepeatBehaviorV3>,
    pub suppress_on_release_after_start: bool,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct EndpointBehaviorV3 {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub presentation: Option<PresentationV3>,
    #[serde(default)]
    pub on_release: Vec<ActionInvocationV3>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub transition: Option<BoardTransitionV3>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub hold: Option<HoldBehaviorV3>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolverCaseV3 {
    pub when: ConditionV3,
    pub behavior: EndpointBehaviorV3,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct EntryResolverV3 {
    pub cases: Vec<ResolverCaseV3>,
    pub default: EndpointBehaviorV3,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardEntryV3 {
    pub id: String,
    pub rect: BoardRectV3,
    pub resolver: EntryResolverV3,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub gesture_policy_override: Option<GesturePolicyOverrideV3>,
    /// Display-only flick-guide labels for this source's transition target,
    /// keyed by target BoardEntry ID (#69 §6.2–6.3). Absent key = AUTO.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub guide_label_overrides: Option<std::collections::BTreeMap<String, String>>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BoardV3 {
    pub id: String,
    pub entries: Vec<BoardEntryV3>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StateDeclarationV3 {
    pub id: String,
    #[serde(rename = "type")]
    pub state_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub values: Option<Vec<String>>,
    pub default: Value,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransformEntryV3 {
    pub from: String,
    pub to: String,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TransformTableV3 {
    pub id: String,
    pub entries: Vec<TransformEntryV3>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MacroV3 {
    pub id: String,
    pub actions: Vec<ActionInvocationV3>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileBundleV3 {
    pub schema: String,
    pub id: String,
    pub name: String,
    pub version: i64,
    pub gesture_policy: GesturePolicyV3,
    pub initial_layer_ref: String,
    pub layers: Vec<LayerV3>,
    pub boards: Vec<BoardV3>,
    pub states: Vec<StateDeclarationV3>,
    pub transform_tables: Vec<TransformTableV3>,
    pub macros: Vec<MacroV3>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub theme: Option<HashMap<String, Value>>,
    #[serde(flatten)]
    pub extra: V3Extra,
}

impl ProfileBundleV3 {
    pub fn decode_unvalidated(bytes: &[u8]) -> Result<Self, serde_json::Error> {
        serde_json::from_slice(bytes)
    }

    pub fn encode(&self) -> Result<Vec<u8>, serde_json::Error> {
        serde_json::to_vec(self)
    }

    pub fn encode_pretty(&self) -> Result<Vec<u8>, serde_json::Error> {
        serde_json::to_vec_pretty(self)
    }
}
