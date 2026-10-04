use crate::{
    board_map, direction_from_coordinate, macro_map, ActionInvocation, Board, BoardCoordinate,
    BoardGesturePolicy, BoardProfileCodec, BoardSession, BoardSessionTerminal, Direction8,
    GesturePoint, GestureSize, ProfileBundleV2, ProfileLimits, ProfileV3Codec,
};
use std::collections::{HashMap, HashSet};
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

impl From<BoardSessionTerminal> for FfiGestureTerminal {
    fn from(value: BoardSessionTerminal) -> Self {
        match value {
            BoardSessionTerminal::Committed => Self::Committed,
            BoardSessionTerminal::Cancelled => Self::Cancelled,
            BoardSessionTerminal::Invalidated => Self::Invalidated,
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

impl From<BoardGesturePolicy> for FfiGesturePolicy {
    fn from(value: BoardGesturePolicy) -> Self {
        Self {
            dead_zone: value.dead_zone,
            stage1_commit_distance: value.initial_cell_commit_distance,
            stage2_commit_distance: value.subsequent_cell_commit_distance,
            angular_hysteresis_degrees: value.angular_hysteresis_degrees,
            // Compatibility field for existing platform tuning UI. Board runtime itself is
            // bounded by BOARD_TRANSITIONS_PER_INTERACTION rather than a two-stage ceiling.
            max_directional_stages: ProfileLimits::BOARD_TRANSITIONS_PER_INTERACTION as i64,
        }
    }
}

impl From<FfiGesturePolicy> for BoardGesturePolicy {
    fn from(value: FfiGesturePolicy) -> Self {
        Self {
            dead_zone: value.dead_zone,
            initial_cell_commit_distance: value.stage1_commit_distance,
            subsequent_cell_commit_distance: value.stage2_commit_distance,
            angular_hysteresis_degrees: value.angular_hysteresis_degrees,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiBoardCoordinate {
    pub x: i64,
    pub y: i64,
}

impl From<BoardCoordinate> for FfiBoardCoordinate {
    fn from(value: BoardCoordinate) -> Self {
        Self {
            x: value.x,
            y: value.y,
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
    // Compatibility projection for the existing 8-direction keyboard surface.
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

    // Compatibility projections for existing clients. They are derived from committed
    // Board coordinates and are not the v2 semantic authority.
    pub path: Vec<FfiDirection8>,
    pub eligible_directions: Vec<FfiDirection8>,
    pub candidate_direction: Option<FfiDirection8>,
    pub committed_directional_stages: i64,

    pub anchor: FfiPoint,
    pub commit_anchors: Vec<FfiPoint>,
    pub dispatched_actions: Vec<FfiActionInvocation>,

    // Canonical Board-graph state.
    pub current_board_id: String,
    pub persistent_board_id: String,
    pub eligible_coordinates: Vec<FfiBoardCoordinate>,
    pub candidate_coordinate: Option<FfiBoardCoordinate>,
    pub selected_coordinate: Option<FfiBoardCoordinate>,
    pub committed_coordinates: Vec<FfiBoardCoordinate>,
    pub board_transition_count: i64,
    pub transition_limit_hit: bool,
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
    #[error("key is not present in active layer: {key_id}")]
    MissingKey { key_id: String },
    #[error("missing key definition: {key_id}")]
    MissingKeyDefinition { key_id: String },
    #[error("missing board entry point for {layer_id}:{key_id}")]
    MissingEntryPoint { layer_id: String, key_id: String },
    #[error("board runtime error {code}: {detail:?}")]
    BoardRuntime {
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

    fn board_runtime(error: crate::ProfileValidationError) -> Self {
        Self::BoardRuntime {
            code: error.code.as_str().to_owned(),
            detail: error.detail,
        }
    }
}

#[uniffi::export]
pub fn validate_profile_json(profile_json: String) -> FfiValidationResult {
    let bytes = profile_json.as_bytes();
    let schema = serde_json::from_slice::<serde_json::Value>(bytes)
        .ok()
        .and_then(|value| {
            value
                .get("schema")
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned)
        });

    let result = match schema.as_deref() {
        Some("gesture-ime.profile.v3") => {
            ProfileV3Codec::decode_and_validate(bytes).map(|_| ())
        }
        _ => BoardProfileCodec::decode_and_validate(bytes).map(|_| ()),
    };

    match result {
        Ok(()) => FfiValidationResult {
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

#[uniffi::export]
pub fn migrate_profile_to_v2_json(profile_json: String) -> Result<String, SharedCoreError> {
    BoardProfileCodec::migrate_to_v2_json(profile_json.as_bytes())
        .map_err(SharedCoreError::invalid_profile)
}

#[derive(uniffi::Object)]
pub struct SharedCoreRuntime {
    profile: ProfileBundleV2,
    boards: Arc<HashMap<String, Board>>,
    macros: Arc<HashMap<String, Vec<ActionInvocation>>>,
    persistent_state: Arc<Mutex<HashMap<String, String>>>,
}

#[uniffi::export]
impl SharedCoreRuntime {
    #[uniffi::constructor]
    pub fn new(profile_json: String) -> Result<Arc<Self>, SharedCoreError> {
        let profile = BoardProfileCodec::decode_and_validate(profile_json.as_bytes())
            .map_err(SharedCoreError::invalid_profile)?;
        let boards = Arc::new(board_map(&profile));
        let macros = Arc::new(macro_map(&profile));
        Ok(Arc::new(Self {
            profile,
            boards,
            macros,
            persistent_state: Arc::new(Mutex::new(HashMap::new())),
        }))
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

        let persistent_state = self
            .persistent_state
            .lock()
            .map_err(|_| SharedCoreError::SessionState)?;

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

            let entry_point = self
                .profile
                .entry_points
                .iter()
                .find(|entry| {
                    entry.layer_id == layer_id
                        && entry.key_id == placement.key_id
                        && entry.trigger == "press"
                });

            let root_board = entry_point.and_then(|entry| {
                let active_board_id = persistent_state
                    .get(&entry.id)
                    .unwrap_or(&entry.board_ref);
                self.boards.get(active_board_id)
            });

            let mut eligible_set = HashSet::new();
            let mut first_stage_presentations = Vec::new();

            if let Some(board) = root_board {
                for entry in &board.entries {
                    if entry.coordinate.chebyshev_radius() != 1 {
                        continue;
                    }
                    let Some(direction) = direction_from_coordinate(entry.coordinate) else {
                        continue;
                    };
                    eligible_set.insert(direction);
                    if let Some(presentation) = &entry.presentation {
                        first_stage_presentations.push(FfiDirectionalPresentation {
                            direction: direction.into(),
                            text: presentation.text.clone(),
                            accessibility_label: presentation.accessibility_label.clone(),
                        });
                    }
                }
            }

            let eligible_directions = Direction8::CANONICAL_ORDER
                .into_iter()
                .filter(|direction| eligible_set.contains(direction))
                .map(Into::into)
                .collect();

            first_stage_presentations.sort_by_key(|presentation| {
                Direction8::CANONICAL_ORDER
                    .iter()
                    .position(|direction| FfiDirection8::from(*direction) == presentation.direction)
                    .unwrap_or(usize::MAX)
            });

            let width = placement.width.unwrap_or(1.0).max(1.0);
            let height = placement.height.unwrap_or(1.0).max(1.0);
            row_count = row_count.max(placement.row + height.ceil() as i64);
            column_count = column_count.max(placement.column + width.ceil() as i64);

            let active_title = root_board
                .and_then(|board| {
                    board.entries.iter().find(|entry| {
                        entry.coordinate == BoardCoordinate::ORIGIN
                    })
                })
                .and_then(|entry| entry.presentation.as_ref())
                .and_then(|presentation| presentation.text.clone())
                .or_else(|| {
                    definition
                        .presentation
                        .as_ref()
                        .and_then(|presentation| presentation.text.clone())
                });

            keys.push(FfiKeyLayout {
                id: placement.key_id.clone(),
                title: active_title,
                role: definition.role.clone(),
                row: placement.row,
                column: placement.column,
                width,
                height,
                eligible_directions,
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

        if !layout
            .placements
            .iter()
            .any(|placement| placement.key_id == key_id)
        {
            return Err(SharedCoreError::MissingKey { key_id });
        }

        let entry_point = self
            .profile
            .entry_points
            .iter()
            .find(|entry| {
                entry.layer_id == layer_id
                    && entry.key_id == key_id
                    && entry.trigger == "press"
            })
            .ok_or_else(|| SharedCoreError::MissingEntryPoint {
                layer_id: layer_id.clone(),
                key_id: key_id.clone(),
            })?
            .clone();

        let policy = policy_override
            .map(Into::into)
            .unwrap_or_else(|| self.profile.gesture_policy.clone());

        let session = BoardSession::new(
            &entry_point,
            profile_revision,
            self.boards.clone(),
            self.macros.clone(),
            self.persistent_state.clone(),
            policy,
            key_size.into(),
            touch_down.into(),
            at_ms,
        )
        .map_err(SharedCoreError::board_runtime)?;

        Ok(Arc::new(SharedGestureSession {
            inner: Mutex::new(session),
        }))
    }
}

#[derive(uniffi::Object)]
pub struct SharedGestureSession {
    inner: Mutex<BoardSession>,
}

#[uniffi::export]
impl SharedGestureSession {
    pub fn snapshot(&self) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let session = self
            .inner
            .lock()
            .map_err(|_| SharedCoreError::SessionState)?;
        Ok(snapshot(&session))
    }

    pub fn move_to(
        &self,
        point: FfiPoint,
        at_ms: Option<i64>,
    ) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| SharedCoreError::SessionState)?;
        session.move_to(point.into(), at_ms);
        Ok(snapshot(&session))
    }

    pub fn advance_time(&self, to_ms: i64) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| SharedCoreError::SessionState)?;
        session.advance_time(to_ms);
        Ok(snapshot(&session))
    }

    pub fn touch_up(&self, at_ms: Option<i64>) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| SharedCoreError::SessionState)?;
        session.touch_up(at_ms);
        Ok(snapshot(&session))
    }

    pub fn cancel(&self, at_ms: Option<i64>) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| SharedCoreError::SessionState)?;
        session.cancel(at_ms);
        Ok(snapshot(&session))
    }

    pub fn invalidate(&self, at_ms: Option<i64>) -> Result<FfiSessionSnapshot, SharedCoreError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| SharedCoreError::SessionState)?;
        session.invalidate(at_ms);
        Ok(snapshot(&session))
    }
}

fn snapshot(session: &BoardSession) -> FfiSessionSnapshot {
    let path = session
        .committed_coordinates
        .iter()
        .filter_map(|coordinate| direction_from_coordinate(*coordinate))
        .map(Into::into)
        .collect();

    let eligible_coordinates = session
        .eligible_coordinates()
        .into_iter()
        .map(Into::into)
        .collect::<Vec<_>>();

    let eligible_direction_set = session
        .eligible_coordinates()
        .into_iter()
        .filter_map(direction_from_coordinate)
        .collect::<HashSet<_>>();

    let eligible_directions = Direction8::CANONICAL_ORDER
        .into_iter()
        .filter(|direction| eligible_direction_set.contains(direction))
        .map(Into::into)
        .collect();

    FfiSessionSnapshot {
        terminal: session.terminal.map(Into::into),
        path,
        eligible_directions,
        anchor: session.anchor.into(),
        candidate_direction: session
            .candidate_coordinate
            .and_then(direction_from_coordinate)
            .map(Into::into),
        committed_directional_stages: session.committed_coordinates.len() as i64,
        commit_anchors: session
            .commit_anchors
            .iter()
            .copied()
            .map(Into::into)
            .collect(),
        dispatched_actions: session
            .dispatched_actions
            .iter()
            .map(Into::into)
            .collect(),
        current_board_id: session.current_board_id.clone(),
        persistent_board_id: session.persistent_board_id.clone(),
        eligible_coordinates,
        candidate_coordinate: session.candidate_coordinate.map(Into::into),
        selected_coordinate: session.selected_coordinate.map(Into::into),
        committed_coordinates: session
            .committed_coordinates
            .iter()
            .copied()
            .map(Into::into)
            .collect(),
        board_transition_count: session.transition_count as i64,
        transition_limit_hit: session.transition_limit_hit,
    }
}
