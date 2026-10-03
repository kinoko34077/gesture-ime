use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction8 {
    N,
    Ne,
    E,
    Se,
    S,
    Sw,
    W,
    Nw,
}

impl Direction8 {
    pub const CANONICAL_ORDER: [Direction8; 8] = [
        Direction8::N,
        Direction8::Ne,
        Direction8::E,
        Direction8::Se,
        Direction8::S,
        Direction8::Sw,
        Direction8::W,
        Direction8::Nw,
    ];

    pub const fn center_degrees(self) -> f64 {
        match self {
            Direction8::E => 0.0,
            Direction8::Se => 45.0,
            Direction8::S => 90.0,
            Direction8::Sw => 135.0,
            Direction8::W => 180.0,
            Direction8::Nw => 225.0,
            Direction8::N => 270.0,
            Direction8::Ne => 315.0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GestureToken {
    pub direction: Direction8,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(transparent)]
pub struct GesturePath(pub Vec<GestureToken>);

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GesturePoint {
    pub x: f64,
    pub y: f64,
}

impl GesturePoint {
    pub fn distance_to(self, other: GesturePoint) -> f64 {
        (other.x - self.x).hypot(other.y - self.y)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GestureSize {
    pub width: f64,
    pub height: f64,
}

impl GestureSize {
    pub fn minimum_dimension(self) -> f64 {
        self.width.min(self.height)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GesturePolicy {
    pub dead_zone: f64,
    pub stage1_commit_distance: f64,
    pub stage2_commit_distance: f64,
    pub angular_hysteresis_degrees: f64,
    pub max_directional_stages: i64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActionInvocation {
    #[serde(rename = "actionID")]
    pub action_id: String,
    pub arguments: Map<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct BindingPresentation {
    #[serde(default)]
    pub text: Option<String>,
    #[serde(default)]
    pub accessibility_label: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RepeatBehavior {
    pub interval_ms: i64,
    pub actions: Vec<ActionInvocation>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HoldBehavior {
    pub delay_ms: i64,
    pub on_start: Vec<ActionInvocation>,
    #[serde(rename = "repeat", default)]
    pub repeat_behavior: Option<RepeatBehavior>,
    pub suppress_on_release_after_start: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BindingBehavior {
    #[serde(default)]
    pub presentation: Option<BindingPresentation>,
    pub on_release: Vec<ActionInvocation>,
    #[serde(default)]
    pub hold: Option<HoldBehavior>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Binding {
    #[serde(rename = "keyID")]
    pub key_id: String,
    pub path: GesturePath,
    pub behavior: BindingBehavior,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BindingSet {
    pub id: String,
    pub bindings: Vec<Binding>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct KeyDefinition {
    pub id: String,
    #[serde(default)]
    pub presentation: Option<BindingPresentation>,
    #[serde(default)]
    pub role: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LayoutPlacement {
    #[serde(rename = "keyID")]
    pub key_id: String,
    pub row: i64,
    pub column: i64,
    #[serde(default)]
    pub width: Option<f64>,
    #[serde(default)]
    pub height: Option<f64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Layout {
    pub id: String,
    pub placements: Vec<LayoutPlacement>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Layer {
    pub id: String,
    pub layout_ref: String,
    pub binding_set_ref: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Macro {
    pub id: String,
    pub actions: Vec<ActionInvocation>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileBundle {
    pub schema: String,
    pub id: String,
    pub name: String,
    pub version: i64,
    pub gesture_policy: GesturePolicy,
    pub key_definitions: Vec<KeyDefinition>,
    pub layouts: Vec<Layout>,
    pub binding_sets: Vec<BindingSet>,
    pub layers: Vec<Layer>,
    pub macros: Vec<Macro>,
    #[serde(default)]
    pub theme: Option<HashMap<String, Value>>,
}