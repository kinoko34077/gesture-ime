use crate::ffi::{FfiGestureTerminal, FfiPoint, FfiSize};
use crate::profile_v3::{
    BoardRectV3, EndpointBehaviorV3, ProfileBundleV3,
};
use crate::profile_v3_board_runtime::{
    BoardContextV3, BoardFrameV3, BoardSemanticsV3, BoardSessionTerminalV3,
    BoardSessionV3, ProfileV3BoardRuntime,
};
use crate::profile_v3_semantics::{
    ProfileSemanticsRuntimeV3, RuntimeDispatchV3, RuntimeSemanticContextHandleV3,
    RuntimeSemanticContextV3,
};
use crate::profile_v3_validation::ProfileV3Codec;
use crate::validation::ProfileValidationError;
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiProfileV3BoardContext {
    Direct,
    Relative,
}

impl From<BoardContextV3> for FfiProfileV3BoardContext {
    fn from(value: BoardContextV3) -> Self {
        match value {
            BoardContextV3::Direct => Self::Direct,
            BoardContextV3::Relative => Self::Relative,
        }
    }
}

impl From<BoardSessionTerminalV3> for FfiGestureTerminal {
    fn from(value: BoardSessionTerminalV3) -> Self {
        match value {
            BoardSessionTerminalV3::Committed => Self::Committed,
            BoardSessionTerminalV3::Cancelled => Self::Cancelled,
            BoardSessionTerminalV3::Invalidated => Self::Invalidated,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiProfileV3Rect {
    pub x: i64,
    pub y: i64,
    pub width: i64,
    pub height: i64,
}

impl From<BoardRectV3> for FfiProfileV3Rect {
    fn from(value: BoardRectV3) -> Self {
        Self {
            x: value.x,
            y: value.y,
            width: value.width,
            height: value.height,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiProfileV3Bounds {
    pub min_x: i64,
    pub min_y: i64,
    pub max_x: i64,
    pub max_y: i64,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiProfileV3SurfaceEntry {
    pub id: String,
    pub rect: FfiProfileV3Rect,
    pub text: Option<String>,
    pub accessibility_label: Option<String>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiProfileV3BoardSurface {
    pub layer_id: String,
    pub board_id: String,
    pub context: FfiProfileV3BoardContext,
    pub entries: Vec<FfiProfileV3SurfaceEntry>,
    pub bounds: Option<FfiProfileV3Bounds>,
    pub candidate_entry_id: Option<String>,
    pub current_endpoint_entry_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiProfileV3DispatchKind {
    Action,
    CompositionTailTransform,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiProfileV3RuntimeDispatch {
    pub kind: FfiProfileV3DispatchKind,
    pub action_id: Option<String>,
    pub arguments_json: Option<String>,
    pub table_id: Option<String>,
    pub matched_source: Option<String>,
    pub replacement: Option<String>,
}

impl From<&RuntimeDispatchV3> for FfiProfileV3RuntimeDispatch {
    fn from(value: &RuntimeDispatchV3) -> Self {
        match value {
            RuntimeDispatchV3::Action(action) => Self {
                kind: FfiProfileV3DispatchKind::Action,
                action_id: Some(action.action_id.clone()),
                arguments_json: Some(
                    serde_json::Value::Object(action.arguments.clone()).to_string(),
                ),
                table_id: None,
                matched_source: None,
                replacement: None,
            },
            RuntimeDispatchV3::CompositionTailTransform(effect) => Self {
                kind: FfiProfileV3DispatchKind::CompositionTailTransform,
                action_id: None,
                arguments_json: None,
                table_id: Some(effect.table_id.clone()),
                matched_source: Some(effect.matched_source.clone()),
                replacement: Some(effect.replacement.clone()),
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiProfileV3SessionSnapshot {
    pub terminal: Option<FfiGestureTerminal>,
    pub current_board_id: String,
    pub persistent_board_id: String,
    pub context: FfiProfileV3BoardContext,
    pub anchor: FfiPoint,
    pub commit_anchors: Vec<FfiPoint>,
    pub candidate_entry_id: Option<String>,
    pub current_endpoint_entry_id: Option<String>,
    pub committed_entry_ids: Vec<String>,
    pub board_transition_count: i64,
    pub transition_limit_hit: bool,
    pub surface: FfiProfileV3BoardSurface,
    pub runtime_dispatches: Vec<FfiProfileV3RuntimeDispatch>,
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiProfileV3GesturePolicy {
    pub dead_zone: f64,
    pub initial_cell_commit_distance: f64,
    pub subsequent_cell_commit_distance: f64,
    pub angular_hysteresis_degrees: f64,
}

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum ProfileV3PlatformError {
    #[error("invalid profile {code}: {detail:?}")]
    InvalidProfile {
        code: String,
        detail: Option<String>,
    },
    #[error("missing layer: {layer_id}")]
    MissingLayer { layer_id: String },
    #[error("missing board: {board_id}")]
    MissingBoard { board_id: String },
    #[error("layer stack limit reached")]
    LayerStackLimit,
    #[error("runtime state lock poisoned")]
    StateLock,
    #[error("board runtime error {code}: {detail:?}")]
    BoardRuntime {
        code: String,
        detail: Option<String>,
    },
}

impl ProfileV3PlatformError {
    fn invalid_profile(error: ProfileValidationError) -> Self {
        Self::InvalidProfile {
            code: error.code.as_str().to_owned(),
            detail: error.detail,
        }
    }

    fn board_runtime(error: ProfileValidationError) -> Self {
        Self::BoardRuntime {
            code: error.code.as_str().to_owned(),
            detail: error.detail,
        }
    }
}

#[derive(Clone)]
struct LayerFrameHandleV3 {
    layer_id: String,
    frame: Arc<Mutex<BoardFrameV3>>,
}

#[derive(uniffi::Object)]
pub struct ProfileV3PlatformRuntime {
    profile: Arc<ProfileBundleV3>,
    board_runtime: ProfileV3BoardRuntime,
    semantic_runtime: ProfileSemanticsRuntimeV3,
    semantic_context: RuntimeSemanticContextHandleV3,
    layer_stack: Mutex<Vec<LayerFrameHandleV3>>,
}

#[uniffi::export]
impl ProfileV3PlatformRuntime {
    #[uniffi::constructor]
    pub fn new(profile_json: String) -> Result<Arc<Self>, ProfileV3PlatformError> {
        let profile = ProfileV3Codec::decode_and_validate(profile_json.as_bytes())
            .map_err(ProfileV3PlatformError::invalid_profile)?;
        let revision = format!("{}:{}", profile.id, profile.version);
        let board_runtime = ProfileV3BoardRuntime::compile(&profile, revision)
            .map_err(ProfileV3PlatformError::board_runtime)?;
        let semantic_runtime = ProfileSemanticsRuntimeV3::compile(&profile)
            .map_err(ProfileV3PlatformError::invalid_profile)?;

        let initial_layer = profile.initial_layer_ref.clone();
        let frame = board_runtime
            .new_frame(&initial_layer)
            .map_err(ProfileV3PlatformError::board_runtime)?;
        let semantic_context = ProfileSemanticsRuntimeV3::context_handle(
            RuntimeSemanticContextV3::new(initial_layer.clone()),
        );

        Ok(Arc::new(Self {
            profile: Arc::new(profile),
            board_runtime,
            semantic_runtime,
            semantic_context,
            layer_stack: Mutex::new(vec![LayerFrameHandleV3 {
                layer_id: initial_layer,
                frame,
            }]),
        }))
    }

    pub fn profile_id(&self) -> String {
        self.profile.id.clone()
    }

    pub fn profile_revision(&self) -> String {
        self.board_runtime.profile_revision.clone()
    }

    pub fn active_layer_id(&self) -> Result<String, ProfileV3PlatformError> {
        self.active_layer_handle().map(|handle| handle.layer_id)
    }

    pub fn default_policy(&self) -> FfiProfileV3GesturePolicy {
        FfiProfileV3GesturePolicy {
            dead_zone: self.board_runtime.policy.dead_zone,
            initial_cell_commit_distance: self
                .board_runtime
                .policy
                .initial_cell_commit_distance,
            subsequent_cell_commit_distance: self
                .board_runtime
                .policy
                .subsequent_cell_commit_distance,
            angular_hysteresis_degrees: self
                .board_runtime
                .policy
                .angular_hysteresis_degrees,
        }
    }

    pub fn update_semantic_context(
        &self,
        composition: String,
        conversion_active: bool,
        conversion_has_candidates: bool,
    ) -> Result<(), ProfileV3PlatformError> {
        let layer_id = self.active_layer_id()?;
        let mut context = self
            .semantic_context
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?;
        context.composition = composition;
        context.conversion_active = conversion_active;
        context.conversion_has_candidates = conversion_has_candidates;
        context.layer_id = layer_id;
        Ok(())
    }

    pub fn direct_surface(
        &self,
    ) -> Result<FfiProfileV3BoardSurface, ProfileV3PlatformError> {
        let active = self.active_layer_handle()?;
        let board_id = active
            .frame
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?
            .persistent_board_id
            .clone();

        self.sync_layer_context(&active.layer_id)?;
        build_surface(
            &self.profile,
            &self.semantic_runtime,
            &self.semantic_context,
            &active.layer_id,
            &board_id,
            FfiProfileV3BoardContext::Direct,
            None,
            None,
            None,
        )
    }

    pub fn preview_surface(
        &self,
        board_id: String,
    ) -> Result<FfiProfileV3BoardSurface, ProfileV3PlatformError> {
        let active = self.active_layer_handle()?;
        self.sync_layer_context(&active.layer_id)?;
        build_surface(
            &self.profile,
            &self.semantic_runtime,
            &self.semantic_context,
            &active.layer_id,
            &board_id,
            FfiProfileV3BoardContext::Direct,
            None,
            None,
            None,
        )
    }

    pub fn set_layer(
        &self,
        layer_id: String,
    ) -> Result<FfiProfileV3BoardSurface, ProfileV3PlatformError> {
        let frame = self
            .board_runtime
            .new_frame(&layer_id)
            .map_err(|_| ProfileV3PlatformError::MissingLayer {
                layer_id: layer_id.clone(),
            })?;

        {
            let mut stack = self
                .layer_stack
                .lock()
                .map_err(|_| ProfileV3PlatformError::StateLock)?;
            *stack = vec![LayerFrameHandleV3 {
                layer_id: layer_id.clone(),
                frame,
            }];
        }

        self.sync_layer_context(&layer_id)?;
        self.direct_surface()
    }

    pub fn push_layer(
        &self,
        layer_id: String,
    ) -> Result<FfiProfileV3BoardSurface, ProfileV3PlatformError> {
        let frame = self
            .board_runtime
            .new_frame(&layer_id)
            .map_err(|_| ProfileV3PlatformError::MissingLayer {
                layer_id: layer_id.clone(),
            })?;

        {
            let mut stack = self
                .layer_stack
                .lock()
                .map_err(|_| ProfileV3PlatformError::StateLock)?;
            if stack.len() >= 16 {
                return Err(ProfileV3PlatformError::LayerStackLimit);
            }
            stack.push(LayerFrameHandleV3 {
                layer_id: layer_id.clone(),
                frame,
            });
        }

        self.sync_layer_context(&layer_id)?;
        self.direct_surface()
    }

    pub fn pop_layer(
        &self,
    ) -> Result<FfiProfileV3BoardSurface, ProfileV3PlatformError> {
        let layer_id = {
            let mut stack = self
                .layer_stack
                .lock()
                .map_err(|_| ProfileV3PlatformError::StateLock)?;
            if stack.len() > 1 {
                stack.pop();
            }
            stack
                .last()
                .map(|handle| handle.layer_id.clone())
                .ok_or(ProfileV3PlatformError::StateLock)?
        };

        self.sync_layer_context(&layer_id)?;
        self.direct_surface()
    }

    pub fn begin_session(
        &self,
        entry_id: String,
        logical_cell_size: FfiSize,
        touch_down: FfiPoint,
        at_ms: i64,
    ) -> Result<Arc<ProfileV3PlatformSession>, ProfileV3PlatformError> {
        let active = self.active_layer_handle()?;
        self.sync_layer_context(&active.layer_id)?;

        let semantics = self
            .semantic_runtime
            .board_semantics(self.semantic_context.clone());
        let session = self
            .board_runtime
            .begin_direct_session(
                active.frame,
                &entry_id,
                logical_cell_size.into(),
                touch_down.into(),
                at_ms,
                Box::new(semantics),
            )
            .map_err(ProfileV3PlatformError::board_runtime)?;

        Ok(Arc::new(ProfileV3PlatformSession {
            inner: Mutex::new(session),
            profile: self.profile.clone(),
            semantic_runtime: self.semantic_runtime.clone(),
            semantic_context: self.semantic_context.clone(),
            layer_id: active.layer_id,
        }))
    }
}

impl ProfileV3PlatformRuntime {
    fn active_layer_handle(&self) -> Result<LayerFrameHandleV3, ProfileV3PlatformError> {
        self.layer_stack
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?
            .last()
            .cloned()
            .ok_or(ProfileV3PlatformError::StateLock)
    }

    fn sync_layer_context(&self, layer_id: &str) -> Result<(), ProfileV3PlatformError> {
        let mut context = self
            .semantic_context
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?;
        context.layer_id = layer_id.to_owned();
        Ok(())
    }
}

#[derive(uniffi::Object)]
pub struct ProfileV3PlatformSession {
    inner: Mutex<BoardSessionV3>,
    profile: Arc<ProfileBundleV3>,
    semantic_runtime: ProfileSemanticsRuntimeV3,
    semantic_context: RuntimeSemanticContextHandleV3,
    layer_id: String,
}

#[uniffi::export]
impl ProfileV3PlatformSession {
    pub fn snapshot(
        &self,
    ) -> Result<FfiProfileV3SessionSnapshot, ProfileV3PlatformError> {
        let session = self
            .inner
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?;
        session_snapshot(
            &session,
            &self.profile,
            &self.semantic_runtime,
            &self.semantic_context,
            &self.layer_id,
        )
    }

    pub fn move_to(
        &self,
        point: FfiPoint,
        at_ms: Option<i64>,
    ) -> Result<FfiProfileV3SessionSnapshot, ProfileV3PlatformError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?;
        session.move_to(point.into(), at_ms);
        session_snapshot(
            &session,
            &self.profile,
            &self.semantic_runtime,
            &self.semantic_context,
            &self.layer_id,
        )
    }

    pub fn advance_time(
        &self,
        to_ms: i64,
    ) -> Result<FfiProfileV3SessionSnapshot, ProfileV3PlatformError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?;
        session.advance_time(to_ms);
        session_snapshot(
            &session,
            &self.profile,
            &self.semantic_runtime,
            &self.semantic_context,
            &self.layer_id,
        )
    }

    pub fn touch_up(
        &self,
        at_ms: Option<i64>,
    ) -> Result<FfiProfileV3SessionSnapshot, ProfileV3PlatformError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?;
        session.touch_up(at_ms);
        session_snapshot(
            &session,
            &self.profile,
            &self.semantic_runtime,
            &self.semantic_context,
            &self.layer_id,
        )
    }

    pub fn cancel(
        &self,
        at_ms: Option<i64>,
    ) -> Result<FfiProfileV3SessionSnapshot, ProfileV3PlatformError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?;
        session.cancel(at_ms);
        session_snapshot(
            &session,
            &self.profile,
            &self.semantic_runtime,
            &self.semantic_context,
            &self.layer_id,
        )
    }

    pub fn invalidate(
        &self,
        at_ms: Option<i64>,
    ) -> Result<FfiProfileV3SessionSnapshot, ProfileV3PlatformError> {
        let mut session = self
            .inner
            .lock()
            .map_err(|_| ProfileV3PlatformError::StateLock)?;
        session.invalidate(at_ms);
        session_snapshot(
            &session,
            &self.profile,
            &self.semantic_runtime,
            &self.semantic_context,
            &self.layer_id,
        )
    }
}

fn session_snapshot(
    session: &BoardSessionV3,
    profile: &ProfileBundleV3,
    semantic_runtime: &ProfileSemanticsRuntimeV3,
    semantic_context: &RuntimeSemanticContextHandleV3,
    layer_id: &str,
) -> Result<FfiProfileV3SessionSnapshot, ProfileV3PlatformError> {
    let persistent_board_id = session
        .persistent_board_id()
        .ok_or(ProfileV3PlatformError::StateLock)?;
    let pinned = session.current_endpoint_behavior();

    let surface = build_surface(
        profile,
        semantic_runtime,
        semantic_context,
        layer_id,
        &session.current_board_id,
        session.context.into(),
        session.candidate_entry_id.clone(),
        session.current_endpoint_entry_id.clone(),
        pinned,
    )?;

    Ok(FfiProfileV3SessionSnapshot {
        terminal: session.terminal.map(Into::into),
        current_board_id: session.current_board_id.clone(),
        persistent_board_id,
        context: session.context.into(),
        anchor: session.anchor.into(),
        commit_anchors: session
            .commit_anchors
            .iter()
            .copied()
            .map(Into::into)
            .collect(),
        candidate_entry_id: session.candidate_entry_id.clone(),
        current_endpoint_entry_id: session.current_endpoint_entry_id.clone(),
        committed_entry_ids: session.committed_entry_ids.clone(),
        board_transition_count: session.transition_count as i64,
        transition_limit_hit: session.transition_limit_hit,
        surface,
        runtime_dispatches: session
            .runtime_dispatches
            .iter()
            .map(Into::into)
            .collect(),
    })
}

#[allow(clippy::too_many_arguments)]
fn build_surface(
    profile: &ProfileBundleV3,
    semantic_runtime: &ProfileSemanticsRuntimeV3,
    semantic_context: &RuntimeSemanticContextHandleV3,
    layer_id: &str,
    board_id: &str,
    context: FfiProfileV3BoardContext,
    candidate_entry_id: Option<String>,
    current_endpoint_entry_id: Option<String>,
    pinned_behavior: Option<EndpointBehaviorV3>,
) -> Result<FfiProfileV3BoardSurface, ProfileV3PlatformError> {
    let board = profile
        .boards
        .iter()
        .find(|board| board.id == board_id)
        .ok_or_else(|| ProfileV3PlatformError::MissingBoard {
            board_id: board_id.to_owned(),
        })?;

    let mut semantics = semantic_runtime.board_semantics(semantic_context.clone());
    let mut entries = Vec::with_capacity(board.entries.len());

    for entry in &board.entries {
        let behavior = if current_endpoint_entry_id.as_deref() == Some(entry.id.as_str()) {
            pinned_behavior
                .clone()
                .unwrap_or_else(|| semantics.resolve_endpoint(entry))
        } else {
            semantics.resolve_endpoint(entry)
        };
        let presentation = behavior.presentation;

        entries.push(FfiProfileV3SurfaceEntry {
            id: entry.id.clone(),
            rect: entry.rect.clone().into(),
            text: presentation
                .as_ref()
                .and_then(|value| value.text.as_ref())
                .map(|text| text.base.clone()),
            accessibility_label: presentation
                .and_then(|value| value.accessibility_label),
        });
    }

    Ok(FfiProfileV3BoardSurface {
        layer_id: layer_id.to_owned(),
        board_id: board_id.to_owned(),
        context,
        bounds: board_bounds(board),
        entries,
        candidate_entry_id,
        current_endpoint_entry_id,
    })
}

fn board_bounds(board: &crate::profile_v3::BoardV3) -> Option<FfiProfileV3Bounds> {
    let mut min_x: Option<i64> = None;
    let mut min_y: Option<i64> = None;
    let mut max_x: Option<i64> = None;
    let mut max_y: Option<i64> = None;

    for entry in &board.entries {
        let rect = entry.rect.clone();
        let rect_max_x = rect.max_x()?;
        let rect_max_y = rect.max_y()?;
        min_x = Some(min_x.map_or(rect.x, |value| value.min(rect.x)));
        min_y = Some(min_y.map_or(rect.y, |value| value.min(rect.y)));
        max_x = Some(max_x.map_or(rect_max_x, |value| value.max(rect_max_x)));
        max_y = Some(max_y.map_or(rect_max_y, |value| value.max(rect_max_y)));
    }

    Some(FfiProfileV3Bounds {
        min_x: min_x?,
        min_y: min_y?,
        max_x: max_x?,
        max_y: max_y?,
    })
}
