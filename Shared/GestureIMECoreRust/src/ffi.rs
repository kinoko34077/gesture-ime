use crate::{
    ActionInvocation, BindingTrieCompiler, Direction8, GesturePoint, GesturePolicy, GestureSession,
    GestureSize, GestureTerminal, ProfileBundle, ProfileCodec,
};
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiDirection8 {
    N,
    Ne,
    E,
    Se,
    S,
    Sw,
    W,
    Nw,
}

impl From<Direction8> for FfiDirection8 {
    fn from(value: Direction8) -> Self {
        match value {
            Direction8::N => Self::N,
            Direction8::Ne => Self::Ne,
            Direction8::E => Self::E,
            Direction8::Se => Self::Se,
            Direction8::S => Self::S,
            Direction8::Sw => Self::Sw,
            Direction8::W => Self::W,
            Direction8::Nw => Self::Nw,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiGestureTerminal {
    Committed,
    Cancelled,
    Invalidated,
}

impl From<GestureTerminal> for FfiGestureTerminal {
    fn from(value: GestureTerminal) -> Self {
        match value {
            GestureTerminal::Committed => Self::Committed,
            GestureTerminal::Cancelled => Self::Cancelled,
            GestureTerminal::Invalidated => Self::Invalidated,
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiPoint {
    pub x: f64,
    pub y: f64,
}

impl From<FfiPoint> for GesturePoint {
    fn from(value: FfiPoint) -> Self {
        Self {
            x: value.x,
            y: value.y,
        }
    }
}

impl From<GesturePoint> for FfiPoint {
    fn from(value: GesturePoint) -> Self {
        Self {
            x: value.x,
            y: value.y,
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiSize {
    pub width: f64,
    pub height: f64,
}

impl From<FfiSize> for GestureSize {
    fn from(value: FfiSize) -> Self {
        Self {
            width: value.width,
            height: value.height,
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiGesturePolicy {
    pub dead_zone: f64,
    pub stage1_commit_distance: f64,
    pub stage2_commit_distance: f64,
    pub angular_hysteresis_degrees: f64,
    pub max_directional_stages: i64,
}

impl From<GesturePolicy> for FfiGesturePolicy {
    fn from(value: GesturePolicy) -> Self {
        Self {
            dead_zone: value.dead_zone,
            stage1_commit_distance: value.stage1_commit_distance,
            stage2_commit_distance: value.stage2_commit_distance,
            angular_hysteresis_degrees: value.angular_hysteresis_degrees,
            max_directional_stages: value.max_directional_stages,
        }
    }
}

impl From<FfiGesturePolicy> for GesturePolicy {
    fn from(value: FfiGesturePolicy) -> Self {
        Self {
            dead_zone: value.dead_zone,
            stage1_commit_distance: value.stage1_commit_distance,
            stage2_commit_distance: value.stage2_commit_distance,
            angular_hysteresis_degrees: value.angular_hysteresis_degrees,
            max_directional_stages: value.max_directional_stages,
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiActionInvocation {
    pub action_id: String,
    pub arguments_json: String,
}

impl From<&ActionInvocation> for FfiActionInvocation {
    fn from(value: &ActionInvocation) -> Self {
        Self {
            action_id: value.action_id.clone(),
            arguments_json: serde_json::Value::Object(value.arguments.clone()).to_string(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiValidationResult {
    pub valid: bool,
    pub error_code: Option<String>,
    pub detail: Option<String>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiDirectionalPresentation {
    pub direction: FfiDirection8,
    pub text: Option<String>,
    pub accessibility_label: Option<String>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiKeyLayout {
    pub id: String,
    pub title: Option<String>,
    pub role: Option<String>,
    pub row: i64,
    pub column: i64,
    pub width: f64,
    pub height: f64,
    pub eligible_directions: Vec<FfiDirection8>,
    pub first_stage_presentations: Vec<FfiDirectionalPresentation>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiLayoutSnapshot {
    pub layer_id: String,
    pub row_count: i64,
    pub column_count: i64,
    pub keys: Vec<FfiKeyLayout>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiSessionSnapshot {
    pub terminal: Option<FfiGestureTerminal>,
    pub path: Vec<FfiDirection8>,
    pub eligible_directions: Vec<FfiDirection8>,
    pub anchor: FfiPoint,
    pub candidate_direction: Option<FfiDirection8>,
    pub committed_directional_stages: i64,
    pub commit_anchors: Vec<FfiPoint>,
    pub dispatched_actions: Vec<FfiActionInvocation>,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum SharedCoreError {
    #[error("invalid profile {code}: {detail:?}")]
    InvalidProfile {
        code: String,
        detail: Option<String>,
    },
    #[error("missing layer: {layer_id}")]
    MissingLayer { layer_id: String },
    #[error("missing layout for layer: {layer_id}")]
    MissingLayout { layer_id: String },
    #[error("missing binding set for layer: {layer_id}")]
    MissingBindingSet { layer_id: String },
    #[error("key is not present in active layer: {key_id}")]
    MissingKey { key_id: String },
    #[error("missing key definition: {key_id}")]
    MissingKeyDefinition { key_id: String },
    #[error("binding trie error {code}: {detail:?}")]
    BindingTrie {
        code: String,
        detail: Option<String>,
    },
    #[error("session state lock poisoned")]
    SessionState,
}

impl SharedCoreError {
    fn invalid_profile(error: crate::ProfileValidationError) -> Self {
        Self::InvalidProfile {
            code: error.code.as_str().to_owned(),
            detail: error.detail,
        }
    }

    fn binding_trie(error: crate::ProfileValidationError) -> Self {
        Self::BindingTrie {
            code: error.code.as_str().to_owned(),
            detail: error.detail,
        }
    }
}

#[uniffi::export]
pub fn validate_profile_json(profile_json: String) -> FfiValidationResult {
    match ProfileCodec::decode_and_validate(profile_json.as_bytes()) {
        Ok(_) => FfiValidationResult {
            valid: true,
            error_code: None,
            detail: None,
        },
        Err(error) => FfiValidationResult {
            valid: false,
            error_code: Some(error.code.as_str().to_owned()),
            detail: error.detail,
        },
    }
}

#[derive(uniffi::Object)]
pub struct SharedCoreRuntime {
    profile: ProfileBundle,
}

#[uniffi::export]
impl SharedCoreRuntime {
    #[uniffi::constructor]
    pub fn new(profile_json: String) -> Result<Arc<Self>, SharedCoreError> {
        let profile =
            ProfileCodec::decode_and_validate(profile_json.as_bytes()).map_err(SharedCoreError::invalid_profile)?;
        Ok(Arc::new(Self { profile }))
    }

    pub fn profile_id(&self) -> String {
        self.profile.id.clone()
    }

    pub fn profile_revision(&self) -> String {
        format!("{}:{}", self.profile.id, self.profile.version)
    }

    pub fn default_policy(&self) -> FfiGesturePolicy {
        self.profile.gesture_policy.clone().into()
    }

    pub fn compile_layout(
        &self,
        layer_id: String,
    ) -> Result<FfiLayoutSnapshot, SharedCoreError> {
        let layer = self
            .profile
            .layers
            .iter()
            .find(|layer| layer.id == layer_id)
            .ok_or_else(|| SharedCoreError::MissingLayer {
                layer_id: layer_id.clone(),
            })?;

        let layout = self
            .profile
            .layouts
            .iter()
            .find(|layout| layout.id == layer.layout_ref)
            .ok_or_else(|| SharedCoreError::MissingLayout {
                layer_id: layer_id.clone(),
            })?;

        let binding_set = self
            .profile
            .binding_sets
            .iter()
            .find(|set| set.id == layer.binding_set_ref)
            .ok_or_else(|| SharedCoreError::MissingBindingSet {
                layer_id: layer_id.clone(),
            })?;

        let mut keys = Vec::with_capacity(layout.placements.len());
        let mut row_count = 0_i64;
        let mut column_count = 0_i64;

        for placement in &layout.placements {
            let definition = self
                .profile
                .key_definitions
                .iter()
                .find(|definition| definition.id == placement.key_id)
                .ok_or_else(|| SharedCoreError::MissingKeyDefinition {
                    key_id: placement.key_id.clone(),
                })?;

            let trie = BindingTrieCompiler::compile(binding_set, &placement.key_id)
                .map_err(SharedCoreError::binding_trie)?;

            let eligible: Vec<FfiDirection8> = Direction8::CANONICAL_ORDER
                .into_iter()
                .filter(|direction| trie.root.eligible_directions().contains(direction))
                .map(Into::into)
                .collect();

            let mut first_stage_presentations = Vec::new();
            for direction in Direction8::CANONICAL_ORDER {
                let path = crate::GesturePath(vec![crate::GestureToken { direction }]);
                if let Some(node) = trie.node(&path) {
                    if let Some(behavior) = &node.behavior {
                        first_stage_presentations.push(FfiDirectionalPresentation {
                            direction: direction.into(),
                            text: behavior
                                .presentation
                                .as_ref()
                                .and_then(|presentation| presentation.text.clone()),
                            accessibility_label: behavior
                                .presentation
                                .as_ref()
                                .and_then(|presentation| presentation.accessibility_label.clone()),
                        });
                    }
                }
            }

            let width = placement.width.unwrap_or(1.0).max(1.0);
            let height = placement.height.unwrap_or(1.0).max(1.0);
            row_count = row_count.max(placement.row + height.ceil() as i64);
            column_count = column_count.max(placement.column + width.ceil() as i64);

            keys.push(FfiKeyLayout {
                id: placement.key_id.clone(),
                title: definition
                    .presentation
                    .as_ref()
                    .and_then(|presentation| presentation.text.clone()),
                role: definition.role.clone(),
                row: placement.row,
                column: placement.column,
                width,
                height,
                eligible_directions: eligible,
                first_stage_presentations,
            });
        }

        Ok(FfiLayoutSnapshot {
            layer_id,
            row_count,
            column_count,
            keys,
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub fn create_session(
        &self,
        layer_id: String,
        key_id: String,
        profile_revision: String,
        key_size: FfiSize,
        touch_down: FfiPoint,
        at_ms: i64,
        policy_override: Option<FfiGesturePolicy>,
    ) -> Result<Arc<SharedGestureSession>, SharedCoreError> {
        let layer = self
            .profile
            .layers
            .iter()
            .find(|layer| layer.id == layer_id)
            .ok_or_else(|| SharedCoreError::MissingLayer {
                layer_id: layer_id.clone(),
            })?;

        let layout = self
            .profile
            .layouts
            .iter()
            .find(|layout| layout.id == layer.layout_ref)
            .ok_or_else(|| SharedCoreError::MissingLayout {
                layer_id: layer_id.clone(),
            })?;

        if !layout.placements.iter().any(|placement| placement.key_id == key_id) {
            return Err(SharedCoreError::MissingKey { key_id });
        }

        let binding_set = self
            .profile
            .binding_sets
            .iter()
            .find(|set| set.id == layer.binding_set_ref)
            .ok_or_else(|| SharedCoreError::MissingBindingSet {
                layer_id: layer_id.clone(),
            })?;

        let trie =
            BindingTrieCompiler::compile(binding_set, &key_id).map_err(SharedCoreError::binding_trie)?;

        let policy = policy_override
            .map(Into::into)
            .unwrap_or_else(|| self.profile.gesture_policy.clone());

        Ok(Arc::new(SharedGestureSession {
            inner: Mutex::new(GestureSession::new(
                key_id,
                profile_revision,
                trie,
                policy,
                key_size.into(),
                touch_down.into(),
                at_ms,
            )),
        }))
    }
}

#[derive(uniffi::Object)]
pub struct SharedGestureSession {
    inner: Mutex<GestureSession>,
}

#[uniffi::export]
impl SharedGestureSession {
    pub fn snapshot(&self) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let session = self.inner.lock().map_err(|_| SharedCoreError::SessionState)?;
        Ok(snapshot(&session))
    }

    pub fn move_to(
        &self,
        point: FfiPoint,
        at_ms: Option<i64>,
    ) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self.inner.lock().map_err(|_| SharedCoreError::SessionState)?;
        session.move_to(point.into(), at_ms);
        Ok(snapshot(&session))
    }

    pub fn advance_time(&self, to_ms: i64) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self.inner.lock().map_err(|_| SharedCoreError::SessionState)?;
        session.advance_time(to_ms);
        Ok(snapshot(&session))
    }

    pub fn touch_up(&self, at_ms: Option<i64>) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self.inner.lock().map_err(|_| SharedCoreError::SessionState)?;
        session.touch_up(at_ms);
        Ok(snapshot(&session))
    }

    pub fn cancel(&self, at_ms: Option<i64>) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self.inner.lock().map_err(|_| SharedCoreError::SessionState)?;
        session.cancel(at_ms);
        Ok(snapshot(&session))
    }

    pub fn invalidate(&self, at_ms: Option<i64>) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self.inner.lock().map_err(|_| SharedCoreError::SessionState)?;
        session.invalidate(at_ms);
        Ok(snapshot(&session))
    }
}

fn snapshot(session: &GestureSession) -> FfiSessionSnapshot {
    let eligible = Direction8::CANONICAL_ORDER
        .into_iter()
        .filter(|direction| session.eligible_directions().contains(direction))
        .map(Into::into)
        .collect();

    FfiSessionSnapshot {
        terminal: session.terminal.map(Into::into),
        path: session
            .path
            .0
            .iter()
            .map(|token| token.direction.into())
            .collect(),
        eligible_directions: eligible,
        anchor: session.anchor.into(),
        candidate_direction: session.candidate_direction.map(Into::into),
        committed_directional_stages: session.committed_directional_stages,
        commit_anchors: session.commit_anchors.iter().copied().map(Into::into).collect(),
        dispatched_actions: session
            .dispatched_actions
            .iter()
            .map(Into::into)
            .collect(),
    }
}
