use crate::model::{GesturePoint, GestureSize};
use crate::profile_v3::{
    ActionInvocationV3, BoardEntryV3, BoardTransitionLifetimeV3, BoardTransitionV3, BoardV3,
    EndpointBehaviorV3, GesturePolicyV3, LayerV3, ProfileBundleV3,
};
use crate::profile_v3_semantics::RuntimeDispatchV3;
use crate::profile_v3_validation::ProfileV3Validator;
use crate::validation::{ProfileLimits, ProfileValidationCode, ProfileValidationError};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BoardContextV3 {
    Direct,
    Relative,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BoardSessionTerminalV3 {
    Committed,
    Cancelled,
    Invalidated,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BoardCandidateV3 {
    pub entry_id: String,
    pub center_x: f64,
    pub center_y: f64,
    pub radius: f64,
}

impl BoardCandidateV3 {
    pub fn from_entry(entry: &BoardEntryV3) -> Option<Self> {
        if entry.rect.contains_origin() {
            return None;
        }

        let center_x = (entry.rect.x as f64 + entry.rect.width as f64 / 2.0) / 2.0;
        let center_y = (entry.rect.y as f64 + entry.rect.height as f64 / 2.0) / 2.0;
        let radius = center_x.abs().max(center_y.abs());

        if !center_x.is_finite()
            || !center_y.is_finite()
            || !radius.is_finite()
            || radius <= 0.0
        {
            return None;
        }

        Some(Self {
            entry_id: entry.id.clone(),
            center_x,
            center_y,
            radius,
        })
    }

    pub fn angle_degrees(&self) -> f64 {
        angle_degrees(self.center_x, self.center_y)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BoardFrameV3 {
    pub layer_id: String,
    pub root_board_id: String,
    pub persistent_board_id: String,
}

impl BoardFrameV3 {
    fn new(layer: &LayerV3) -> Self {
        Self {
            layer_id: layer.id.clone(),
            root_board_id: layer.root_board_ref.clone(),
            persistent_board_id: layer.root_board_ref.clone(),
        }
    }
}

pub trait BoardSemanticsV3: Send {
    fn resolve_endpoint(&mut self, entry: &BoardEntryV3) -> EndpointBehaviorV3;

    fn apply_dispatched_actions(&mut self, _actions: &[ActionInvocationV3]) {}

    fn resolve_dispatch_batch(
        &mut self,
        actions: &[ActionInvocationV3],
    ) -> Vec<RuntimeDispatchV3> {
        self.apply_dispatched_actions(actions);
        actions
            .iter()
            .cloned()
            .map(RuntimeDispatchV3::Action)
            .collect()
    }
}

#[derive(Debug, Default)]
pub struct DefaultBoardSemanticsV3;

impl BoardSemanticsV3 for DefaultBoardSemanticsV3 {
    fn resolve_endpoint(&mut self, entry: &BoardEntryV3) -> EndpointBehaviorV3 {
        entry.resolver.default.clone()
    }
}

#[derive(Clone)]
pub struct ProfileV3BoardRuntime {
    pub profile_revision: String,
    pub policy: GesturePolicyV3,
    boards: Arc<HashMap<String, BoardV3>>,
    layers: HashMap<String, LayerV3>,
    macros: Arc<HashMap<String, Vec<ActionInvocationV3>>>,
}

impl ProfileV3BoardRuntime {
    pub fn compile(
        profile: &ProfileBundleV3,
        profile_revision: impl Into<String>,
    ) -> Result<Self, ProfileValidationError> {
        ProfileV3Validator::validate(profile, None)?;

        Ok(Self {
            profile_revision: profile_revision.into(),
            policy: profile.gesture_policy.clone(),
            boards: Arc::new(
                profile
                    .boards
                    .iter()
                    .cloned()
                    .map(|board| (board.id.clone(), board))
                    .collect(),
            ),
            layers: profile
                .layers
                .iter()
                .cloned()
                .map(|layer| (layer.id.clone(), layer))
                .collect(),
            macros: Arc::new(
                profile
                    .macros
                    .iter()
                    .map(|macro_item| {
                        (macro_item.id.clone(), macro_item.actions.clone())
                    })
                    .collect(),
            ),
        })
    }

    pub fn board(&self, board_id: &str) -> Option<&BoardV3> {
        self.boards.get(board_id)
    }

    pub fn layer(&self, layer_id: &str) -> Option<&LayerV3> {
        self.layers.get(layer_id)
    }

    pub fn new_frame(
        &self,
        layer_id: &str,
    ) -> Result<Arc<Mutex<BoardFrameV3>>, ProfileValidationError> {
        let layer = self.layers.get(layer_id).ok_or_else(|| {
            ProfileValidationError::new(
                ProfileValidationCode::MissingReference,
                Some(layer_id.to_owned()),
            )
        })?;

        if !self.boards.contains_key(&layer.root_board_ref) {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::MissingReference,
                Some(layer.root_board_ref.clone()),
            ));
        }

        Ok(Arc::new(Mutex::new(BoardFrameV3::new(layer))))
    }

    #[allow(clippy::too_many_arguments)]
    pub fn begin_direct_session(
        &self,
        frame: Arc<Mutex<BoardFrameV3>>,
        entry_id: &str,
        logical_cell_size: GestureSize,
        touch_down: GesturePoint,
        at_ms: i64,
        semantics: Box<dyn BoardSemanticsV3>,
    ) -> Result<BoardSessionV3, ProfileValidationError> {
        self.begin_direct_session_at(
            frame,
            entry_id,
            logical_cell_size,
            touch_down,
            None,
            at_ms,
            semantics,
        )
    }

    /// Begins a direct session whose first relative stage renders at
    /// `source_visual_origin` (the source key's canonical rendered center) while
    /// the physical touch-down point remains the stage pointer origin (#69 §4.3).
    #[allow(clippy::too_many_arguments)]
    pub fn begin_direct_session_at(
        &self,
        frame: Arc<Mutex<BoardFrameV3>>,
        entry_id: &str,
        logical_cell_size: GestureSize,
        touch_down: GesturePoint,
        source_visual_origin: Option<GesturePoint>,
        at_ms: i64,
        semantics: Box<dyn BoardSemanticsV3>,
    ) -> Result<BoardSessionV3, ProfileValidationError> {
        BoardSessionV3::new(
            self.profile_revision.clone(),
            self.policy.clone(),
            self.boards.clone(),
            self.macros.clone(),
            frame,
            entry_id,
            logical_cell_size,
            touch_down,
            source_visual_origin,
            at_ms,
            semantics,
        )
    }
}

#[derive(Debug, Clone)]
struct EndpointSnapshotV3 {
    entry_id: String,
    behavior: EndpointBehaviorV3,
    release_transition_on_touch_up: bool,
}

/// Where the pointer currently sits relative to the active stage (#69 §4.7).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StageRegionV3 {
    /// Inside the effective dead zone around the stage pointer origin.
    Center,
    /// Beyond the dead zone in a direction that no registered entry covers.
    Unassigned,
    /// Beyond the dead zone toward a registered entry.
    Assigned,
}

/// One relative stage of the interaction-scoped Stage Stack (#69 §4.1).
/// Interaction state only; never persisted into Profile data.
#[derive(Debug, Clone, PartialEq)]
pub struct StageFrameV3 {
    pub board_id: String,
    /// Where the stage Board origin is rendered.
    pub visual_origin: GesturePoint,
    /// Physical pointer point treated as zero displacement for this stage.
    pub pointer_origin: GesturePoint,
    pub entered_via_entry_id: Option<String>,
    /// Common policy resolved against the entering source entry's partial override.
    pub policy: GesturePolicyV3,
    uses_subsequent_commit_distance: bool,
    persistent_board_before_entry: Option<String>,
}

/// Angular half-width of the cone that a registered entry covers. Movement
/// further than this from every eligible entry is an unassigned direction.
pub const STAGE_ASSIGNED_CONE_DEGREES: f64 = 45.0;

pub struct BoardSessionV3 {
    pub profile_revision: String,
    pub policy: GesturePolicyV3,
    pub logical_cell_size: GestureSize,
    /// Pointer origin of the active stage (or the touch-down point when direct).
    pub anchor: GesturePoint,
    /// Visual origin of the active stage (or the source visual origin when direct).
    pub visual_origin: GesturePoint,
    pub last_point: GesturePoint,
    pub current_board_id: String,
    pub context: BoardContextV3,
    pub candidate_entry_id: Option<String>,
    pub current_endpoint_entry_id: Option<String>,
    /// Every spatial entry that became the current endpoint or a stage
    /// transition, in order. Retargeting appends; it is a feedback history,
    /// not the release semantics.
    pub committed_entry_ids: Vec<String>,
    pub transition_count: usize,
    pub transition_limit_hit: bool,
    pub rollback_count: usize,
    pub terminal: Option<BoardSessionTerminalV3>,
    pub dispatched_actions: Vec<ActionInvocationV3>,
    pub runtime_dispatches: Vec<RuntimeDispatchV3>,
    pub commit_anchors: Vec<GesturePoint>,

    frame: Arc<Mutex<BoardFrameV3>>,
    boards: Arc<HashMap<String, BoardV3>>,
    macros: Arc<HashMap<String, Vec<ActionInvocationV3>>>,
    semantics: Box<dyn BoardSemanticsV3>,
    stages: Vec<StageFrameV3>,
    source_policy: GesturePolicyV3,
    current_endpoint: Option<EndpointSnapshotV3>,
    current_time_ms: i64,
    hold_due_ms: Option<i64>,
    repeat_due_ms: Option<i64>,
    hold_started: bool,
    spatial_locked: bool,
    rollback_armed: bool,
    rollback_dwell_started_ms: Option<i64>,
}

impl BoardSessionV3 {
    #[allow(clippy::too_many_arguments)]
    fn new(
        profile_revision: String,
        policy: GesturePolicyV3,
        boards: Arc<HashMap<String, BoardV3>>,
        macros: Arc<HashMap<String, Vec<ActionInvocationV3>>>,
        frame: Arc<Mutex<BoardFrameV3>>,
        direct_entry_id: &str,
        logical_cell_size: GestureSize,
        touch_down: GesturePoint,
        source_visual_origin: Option<GesturePoint>,
        at_ms: i64,
        semantics: Box<dyn BoardSemanticsV3>,
    ) -> Result<Self, ProfileValidationError> {
        if !logical_cell_size.width.is_finite()
            || !logical_cell_size.height.is_finite()
            || logical_cell_size.width <= 0.0
            || logical_cell_size.height <= 0.0
        {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some("logical cell size must be finite and positive".into()),
            ));
        }
        let visual_origin = source_visual_origin.unwrap_or(touch_down);
        if !visual_origin.x.is_finite() || !visual_origin.y.is_finite() {
            return Err(ProfileValidationError::new(
                ProfileValidationCode::UnsupportedSchema,
                Some("source visual origin must be finite".into()),
            ));
        }

        let persistent_board_id = frame
            .lock()
            .map_err(|_| {
                ProfileValidationError::new(
                    ProfileValidationCode::UnsupportedSchema,
                    Some("BoardFrameV3 lock poisoned".into()),
                )
            })?
            .persistent_board_id
            .clone();

        let direct_entry = boards
            .get(&persistent_board_id)
            .and_then(|board| board.entries.iter().find(|entry| entry.id == direct_entry_id))
            .cloned()
            .ok_or_else(|| {
                ProfileValidationError::new(
                    ProfileValidationCode::MissingReference,
                    Some(format!("{persistent_board_id}:{direct_entry_id}")),
                )
            })?;

        let source_policy = policy.with_override(direct_entry.gesture_policy_override.as_ref());
        let mut session = Self {
            profile_revision,
            policy,
            logical_cell_size,
            anchor: touch_down,
            visual_origin,
            last_point: touch_down,
            current_board_id: persistent_board_id,
            context: BoardContextV3::Direct,
            candidate_entry_id: None,
            current_endpoint_entry_id: None,
            committed_entry_ids: Vec::new(),
            transition_count: 0,
            transition_limit_hit: false,
            rollback_count: 0,
            terminal: None,
            dispatched_actions: Vec::new(),
            runtime_dispatches: Vec::new(),
            commit_anchors: Vec::new(),
            frame,
            boards,
            macros,
            semantics,
            stages: Vec::new(),
            source_policy,
            current_endpoint: None,
            current_time_ms: at_ms,
            hold_due_ms: None,
            repeat_due_ms: None,
            hold_started: false,
            spatial_locked: true,
            rollback_armed: false,
            rollback_dwell_started_ms: None,
        };

        let behavior = session.semantics.resolve_endpoint(&direct_entry);
        let transition = behavior.transition.clone();
        session.set_current_endpoint(direct_entry.id.clone(), behavior, false, at_ms);

        if let Some(transition) = transition {
            session.cancel_timers();
            if session.apply_transition(transition, Some(&direct_entry), touch_down, at_ms, false) {
                // The direct source ceases to be the release/Hold endpoint.
            } else {
                session.spatial_locked = true;
            }
        }

        Ok(session)
    }

    pub fn persistent_board_id(&self) -> Option<String> {
        self.frame
            .lock()
            .ok()
            .map(|frame| frame.persistent_board_id.clone())
    }

    pub fn current_board(&self) -> Option<&BoardV3> {
        self.boards.get(&self.current_board_id)
    }

    pub fn current_endpoint_behavior(&self) -> Option<EndpointBehaviorV3> {
        self.current_endpoint
            .as_ref()
            .map(|snapshot| snapshot.behavior.clone())
    }

    /// Relative Stage Stack, bottom (Stage 1) first. Empty while direct.
    pub fn stages(&self) -> &[StageFrameV3] {
        &self.stages
    }

    pub fn stage_depth(&self) -> usize {
        self.stages.len()
    }

    /// Effective policy of the active stage (or of the direct source entry).
    pub fn active_policy(&self) -> &GesturePolicyV3 {
        self.stages
            .last()
            .map(|stage| &stage.policy)
            .unwrap_or(&self.source_policy)
    }

    /// Pending rollback dwell progress in `0.0..1.0`, when a dwell is running.
    pub fn rollback_progress(&self) -> Option<f64> {
        let started = self.rollback_dwell_started_ms?;
        let dwell = self.active_policy().effective_stage_backtrack_dwell_ms().max(1);
        let elapsed = (self.current_time_ms - started).max(0);
        Some((elapsed as f64 / dwell as f64).clamp(0.0, 1.0))
    }

    pub fn origin_entry(&self) -> Option<&BoardEntryV3> {
        self.current_board()?
            .entries
            .iter()
            .find(|entry| entry.rect.contains_origin())
    }

    pub fn eligible_candidates(&self) -> Vec<BoardCandidateV3> {
        let mut candidates = self
            .current_board()
            .map(|board| {
                board
                    .entries
                    .iter()
                    .filter_map(BoardCandidateV3::from_entry)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        candidates.sort_by(|lhs, rhs| {
            lhs.radius
                .total_cmp(&rhs.radius)
                .then_with(|| lhs.center_y.total_cmp(&rhs.center_y))
                .then_with(|| lhs.center_x.total_cmp(&rhs.center_x))
                .then_with(|| lhs.entry_id.cmp(&rhs.entry_id))
        });
        candidates
    }

    pub fn move_to(&mut self, point: GesturePoint, at_ms: Option<i64>) {
        if self.terminal.is_some() {
            return;
        }
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
            if self.terminal.is_some() {
                return;
            }
        }

        self.last_point = point;
        if self.context != BoardContextV3::Relative || self.spatial_locked {
            return;
        }

        let policy = self.active_policy().clone();
        let logical_dx = (point.x - self.anchor.x) / self.logical_cell_size.width;
        let logical_dy = (point.y - self.anchor.y) / self.logical_cell_size.height;
        let logical_distance = logical_dx.hypot(logical_dy);

        if !logical_distance.is_finite() || logical_distance < policy.dead_zone {
            // Returning to the stage center makes the origin the provisional
            // endpoint again (#69 §4.4).
            self.candidate_entry_id = None;
            self.select_origin_endpoint();
            self.enter_rollback_region();
            return;
        }

        // Leaving the center is a meaningful exit that re-arms rollback (#69 §4.8).
        self.rollback_armed = true;

        let movement_angle = angle_degrees(logical_dx, logical_dy);
        let base_commit = if self.stages.last().is_some_and(|stage| stage.uses_subsequent_commit_distance) {
            policy.subsequent_cell_commit_distance
        } else {
            policy.initial_cell_commit_distance
        };

        let candidates: Vec<BoardCandidateV3> = self
            .eligible_candidates()
            .into_iter()
            .filter(|candidate| {
                angular_distance(movement_angle, candidate.angle_degrees())
                    <= STAGE_ASSIGNED_CONE_DEGREES
            })
            .collect();

        let nearest = nearest_reachable_candidate(
            &candidates,
            movement_angle,
            logical_distance,
            base_commit,
        )
        .or_else(|| nearest_precommit_candidate(&candidates, movement_angle));

        let Some(nearest) = nearest else {
            // Unassigned direction: no stale spatial candidate survives (#69
            // §4.10). The stage's own neutral origin endpoint is not a stale
            // candidate and stays in effect (e.g. origin-only Hold Boards).
            self.candidate_entry_id = None;
            let origin_is_endpoint = self
                .origin_entry()
                .is_some_and(|origin| self.current_endpoint_entry_id.as_deref() == Some(origin.id.as_str()));
            if !origin_is_endpoint {
                self.clear_current_endpoint();
            }
            self.enter_rollback_region();
            return;
        };
        self.rollback_dwell_started_ms = None;

        let next_candidate_id = nearest.entry_id.clone();
        match self
            .candidate_entry_id
            .as_deref()
            .and_then(|entry_id| candidates.iter().find(|item| item.entry_id == entry_id))
        {
            Some(current) if current.entry_id != nearest.entry_id => {
                let current_angle = current.angle_degrees();
                let nearest_angle = nearest.angle_degrees();
                let current_distance = angular_distance(movement_angle, current_angle);
                let nearest_distance = angular_distance(movement_angle, nearest_angle);
                let same_ray = angular_distance(current_angle, nearest_angle) < f64::EPSILON;

                if same_ray
                    || nearest_distance + policy.angular_hysteresis_degrees < current_distance
                {
                    self.candidate_entry_id = Some(next_candidate_id);
                }
            }
            Some(_) => {}
            None => self.candidate_entry_id = Some(next_candidate_id),
        }

        let Some(candidate_id) = self.candidate_entry_id.clone() else {
            return;
        };
        let Some(candidate) = candidates
            .iter()
            .find(|candidate| candidate.entry_id == candidate_id)
        else {
            return;
        };

        let required_commit = base_commit * candidate.radius;
        if logical_distance < required_commit {
            return;
        }

        if self.current_endpoint_entry_id.as_deref() == Some(candidate.entry_id.as_str()) {
            // Already the provisional terminal endpoint; Hold timing continues.
            return;
        }

        let Some(entry) = self
            .current_board()
            .and_then(|board| board.entries.iter().find(|entry| entry.id == candidate.entry_id))
            .cloned()
        else {
            return;
        };

        let behavior = self.semantics.resolve_endpoint(&entry);
        let transition = behavior.transition.clone();

        self.committed_entry_ids.push(entry.id.clone());
        self.cancel_timers();

        if let Some(transition) = transition {
            self.set_current_endpoint(entry.id.clone(), behavior, false, self.current_time_ms);
            if self.apply_transition(
                transition,
                Some(&entry),
                point,
                self.current_time_ms,
                true,
            ) {
                return;
            }

            // A bounded/failed transition becomes the terminal endpoint for the
            // remainder of the interaction rather than accumulating retries.
            self.cancel_timers();
            self.spatial_locked = true;
            self.candidate_entry_id = Some(entry.id);
            self.current_endpoint_entry_id = self
                .current_endpoint
                .as_ref()
                .map(|snapshot| snapshot.entry_id.clone());
        } else {
            // Terminal candidates stay provisional until touch-up (#69 §4.4).
            self.set_current_endpoint(entry.id.clone(), behavior, false, self.current_time_ms);
        }
    }

    pub fn advance_time(&mut self, target_ms: i64) {
        if self.terminal.is_some() || target_ms < self.current_time_ms {
            return;
        }

        if let Some(rollback_due) = self.rollback_due_ms() {
            let hold_first = !self.hold_started
                && self.hold_due_ms.is_some_and(|hold_due| hold_due < rollback_due);
            if rollback_due <= target_ms && !hold_first {
                self.pop_stage(rollback_due);
                self.current_time_ms = rollback_due;
                self.advance_time(target_ms);
                return;
            }
        }

        if !self.hold_started {
            if let Some(due_ms) = self.hold_due_ms {
                if due_ms <= target_ms {
                    let hold = self
                        .current_endpoint
                        .as_ref()
                        .and_then(|snapshot| snapshot.behavior.hold.clone());

                    if let Some(hold) = hold {
                        self.dispatch_actions(&hold.on_start);
                        self.hold_started = true;
                        self.hold_due_ms = None;
                        self.rollback_dwell_started_ms = None;

                        if let Some(transition) = hold.transition {
                            self.cancel_timers();
                            let via = self.current_endpoint_entry();
                            if self.apply_transition(
                                transition,
                                via.as_ref(),
                                self.last_point,
                                due_ms,
                                true,
                            ) {
                                // The target endpoint becomes active at the transition
                                // deadline, not at the caller's later target time. Catch
                                // up again so target Hold/repeat deadlines inside the
                                // same advance_time window are processed in causal order.
                                self.current_time_ms = due_ms;
                                self.advance_time(target_ms);
                                return;
                            }

                            self.spatial_locked = true;
                            if let Some(repeat) = hold.repeat_behavior {
                                self.repeat_due_ms = Some(due_ms + repeat.interval_ms);
                            }
                        } else {
                            self.spatial_locked = true;
                            if let Some(repeat) = hold.repeat_behavior {
                                self.repeat_due_ms = Some(due_ms + repeat.interval_ms);
                            }
                        }
                    }
                }
            }
        }

        if self.hold_started {
            let repeating = self
                .current_endpoint
                .as_ref()
                .and_then(|snapshot| snapshot.behavior.hold.as_ref())
                .and_then(|hold| hold.repeat_behavior.clone());

            if let Some(repeating) = repeating {
                while let Some(due_ms) = self.repeat_due_ms {
                    if due_ms > target_ms || self.terminal.is_some() {
                        break;
                    }
                    self.dispatch_actions(&repeating.actions);
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

        let snapshot = self.current_endpoint.clone();
        if let Some(snapshot) = snapshot {
            let suppress_release = self.hold_started
                && snapshot
                    .behavior
                    .hold
                    .as_ref()
                    .is_some_and(|hold| hold.suppress_on_release_after_start);

            if !suppress_release {
                self.dispatch_actions(&snapshot.behavior.on_release);
            }

            if snapshot.release_transition_on_touch_up {
                if let Some(transition) = snapshot.behavior.transition {
                    let via = self.current_endpoint_entry();
                    let _ = self.apply_transition(
                        transition,
                        via.as_ref(),
                        self.last_point,
                        self.current_time_ms,
                        true,
                    );
                }
            }
        }

        self.terminal = Some(BoardSessionTerminalV3::Committed);
        self.restore_persistent_baseline();
        self.cancel_timers();
    }

    pub fn cancel(&mut self, at_ms: Option<i64>) {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        if self.terminal.is_some() {
            return;
        }

        self.terminal = Some(BoardSessionTerminalV3::Cancelled);
        self.restore_persistent_baseline();
        self.cancel_timers();
    }

    pub fn invalidate(&mut self, at_ms: Option<i64>) {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        if self.terminal.is_some() {
            return;
        }

        self.terminal = Some(BoardSessionTerminalV3::Invalidated);
        self.restore_persistent_baseline();
        self.cancel_timers();
    }

    fn set_current_endpoint(
        &mut self,
        entry_id: String,
        behavior: EndpointBehaviorV3,
        release_transition_on_touch_up: bool,
        at_ms: i64,
    ) {
        self.current_endpoint_entry_id = Some(entry_id.clone());
        self.current_endpoint = Some(EndpointSnapshotV3 {
            entry_id,
            behavior,
            release_transition_on_touch_up,
        });
        self.hold_started = false;
        self.repeat_due_ms = None;
        self.hold_due_ms = self
            .current_endpoint
            .as_ref()
            .and_then(|snapshot| snapshot.behavior.hold.as_ref())
            .map(|hold| at_ms + hold.delay_ms);
    }

    fn clear_current_endpoint(&mut self) {
        self.current_endpoint = None;
        self.current_endpoint_entry_id = None;
        self.hold_due_ms = None;
        self.repeat_due_ms = None;
        self.hold_started = false;
    }

    fn current_endpoint_entry(&self) -> Option<BoardEntryV3> {
        let entry_id = self.current_endpoint_entry_id.as_deref()?;
        self.current_board()?
            .entries
            .iter()
            .find(|entry| entry.id == entry_id)
            .cloned()
    }

    fn select_origin_endpoint(&mut self) {
        let origin_id = self.origin_entry().map(|entry| entry.id.clone());
        if origin_id.is_some() && origin_id == self.current_endpoint_entry_id {
            return;
        }
        self.activate_relative_origin(self.current_time_ms);
    }

    fn activate_relative_origin(&mut self, at_ms: i64) {
        let origin = self.origin_entry().cloned();

        if let Some(origin) = origin {
            let behavior = self.semantics.resolve_endpoint(&origin);
            self.set_current_endpoint(origin.id, behavior, true, at_ms);
        } else {
            self.clear_current_endpoint();
        }
    }

    fn enter_rollback_region(&mut self) {
        if self.stages.len() > 1
            && self.rollback_armed
            && self.rollback_dwell_started_ms.is_none()
        {
            self.rollback_dwell_started_ms = Some(self.current_time_ms);
        }
    }

    fn rollback_due_ms(&self) -> Option<i64> {
        let started = self.rollback_dwell_started_ms?;
        if self.stages.len() <= 1 || self.spatial_locked {
            return None;
        }
        Some(started + self.active_policy().effective_stage_backtrack_dwell_ms())
    }

    /// Pops exactly one StageFrame (#69 §4.8–4.9).
    fn pop_stage(&mut self, at_ms: i64) {
        if self.stages.len() <= 1 {
            self.rollback_dwell_started_ms = None;
            return;
        }
        let Some(popped) = self.stages.pop() else {
            return;
        };
        if let Some(previous_persistent) = popped.persistent_board_before_entry {
            if let Ok(mut frame) = self.frame.lock() {
                frame.persistent_board_id = previous_persistent;
            }
        }

        let restored_pointer = self.last_point;
        let Some(restored) = self.stages.last_mut() else {
            return;
        };
        restored.pointer_origin = restored_pointer;
        self.current_board_id = restored.board_id.clone();
        self.visual_origin = restored.visual_origin;
        self.anchor = restored_pointer;

        self.rollback_count += 1;
        self.rollback_armed = false;
        self.rollback_dwell_started_ms = None;
        self.candidate_entry_id = None;
        self.hold_started = false;
        self.cancel_timers();
        self.activate_relative_origin(at_ms);
    }

    fn apply_transition(
        &mut self,
        transition: BoardTransitionV3,
        via_entry: Option<&BoardEntryV3>,
        point: GesturePoint,
        at_ms: i64,
        consumes_initial_stage: bool,
    ) -> bool {
        if self.transition_count >= ProfileLimits::BOARD_TRANSITIONS_PER_INTERACTION {
            self.transition_limit_hit = true;
            return false;
        }
        if !self.boards.contains_key(&transition.target_board_ref) {
            return false;
        }

        self.transition_count += 1;
        let mut persistent_board_before_entry = None;
        if transition.lifetime == BoardTransitionLifetimeV3::Persistent {
            let Ok(mut frame) = self.frame.lock() else {
                return false;
            };
            persistent_board_before_entry = Some(std::mem::replace(
                &mut frame.persistent_board_id,
                transition.target_board_ref.clone(),
            ));
        }

        // Every forward transition normalizes origins (#69 §4.3, §4.6): the new
        // Board renders at the canonical center of the committed entry and the
        // physical pointer at transition time becomes zero displacement.
        let visual_origin = match (self.context, via_entry) {
            (BoardContextV3::Relative, Some(entry)) => {
                let (cx, cy) = relative_entry_center_cells(entry);
                GesturePoint {
                    x: self.visual_origin.x + cx * self.logical_cell_size.width,
                    y: self.visual_origin.y + cy * self.logical_cell_size.height,
                }
            }
            _ => self.visual_origin,
        };
        let policy = self
            .policy
            .with_override(via_entry.and_then(|entry| entry.gesture_policy_override.as_ref()));
        let uses_subsequent_commit_distance = consumes_initial_stage
            || self
                .stages
                .last()
                .is_some_and(|stage| stage.uses_subsequent_commit_distance);

        self.stages.push(StageFrameV3 {
            board_id: transition.target_board_ref.clone(),
            visual_origin,
            pointer_origin: point,
            entered_via_entry_id: via_entry.map(|entry| entry.id.clone()),
            policy,
            uses_subsequent_commit_distance,
            persistent_board_before_entry,
        });

        self.current_board_id = transition.target_board_ref;
        self.context = BoardContextV3::Relative;
        self.anchor = point;
        self.visual_origin = visual_origin;
        self.last_point = point;
        self.commit_anchors.push(point);
        self.candidate_entry_id = None;
        self.current_endpoint = None;
        self.current_endpoint_entry_id = None;
        self.hold_started = false;
        self.spatial_locked = false;
        self.rollback_armed = false;
        self.rollback_dwell_started_ms = None;
        self.cancel_timers();
        self.activate_relative_origin(at_ms);
        true
    }

    fn dispatch_actions(&mut self, actions: &[ActionInvocationV3]) {
        let mut expanded = Vec::new();

        for action in actions {
            if action.action_id == "macro.run" {
                let macro_id = action.arguments.get("macro").and_then(Value::as_str);
                let Some(macro_id) = macro_id else {
                    debug_assert!(false, "validated macro.run is missing macro argument");
                    continue;
                };
                let Some(actions) = self.macros.get(macro_id) else {
                    debug_assert!(false, "validated macro.run reference is missing");
                    continue;
                };
                expanded.extend(actions.iter().cloned());
            } else {
                expanded.push(action.clone());
            }
        }

        let resolved = self.semantics.resolve_dispatch_batch(&expanded);
        self.runtime_dispatches.extend(resolved);
        self.dispatched_actions.extend(expanded);
    }

    fn restore_persistent_baseline(&mut self) {
        if let Ok(frame) = self.frame.lock() {
            self.current_board_id = frame.persistent_board_id.clone();
        }
        self.context = BoardContextV3::Direct;
        self.stages.clear();
        self.candidate_entry_id = None;
        self.current_endpoint = None;
        self.current_endpoint_entry_id = None;
        self.spatial_locked = true;
        self.rollback_dwell_started_ms = None;
    }

    fn cancel_timers(&mut self) {
        self.hold_due_ms = None;
        self.repeat_due_ms = None;
    }
}

/// Canonical center of a relative-Board entry in logical cells. Relative rects
/// are authored in half-cell atoms, matching [`BoardCandidateV3::from_entry`].
fn relative_entry_center_cells(entry: &BoardEntryV3) -> (f64, f64) {
    (
        (entry.rect.x as f64 + entry.rect.width as f64 / 2.0) / 2.0,
        (entry.rect.y as f64 + entry.rect.height as f64 / 2.0) / 2.0,
    )
}

fn nearest_reachable_candidate<'a>(
    candidates: &'a [BoardCandidateV3],
    movement_angle: f64,
    logical_distance: f64,
    base_commit: f64,
) -> Option<&'a BoardCandidateV3> {
    candidates
        .iter()
        .filter(|candidate| logical_distance >= base_commit * candidate.radius)
        .min_by(|lhs, rhs| {
            angular_distance(movement_angle, lhs.angle_degrees())
                .total_cmp(&angular_distance(movement_angle, rhs.angle_degrees()))
                .then_with(|| rhs.radius.total_cmp(&lhs.radius))
                .then_with(|| lhs.center_y.total_cmp(&rhs.center_y))
                .then_with(|| lhs.center_x.total_cmp(&rhs.center_x))
                .then_with(|| lhs.entry_id.cmp(&rhs.entry_id))
        })
}

fn nearest_precommit_candidate<'a>(
    candidates: &'a [BoardCandidateV3],
    movement_angle: f64,
) -> Option<&'a BoardCandidateV3> {
    candidates.iter().min_by(|lhs, rhs| {
        angular_distance(movement_angle, lhs.angle_degrees())
            .total_cmp(&angular_distance(movement_angle, rhs.angle_degrees()))
            .then_with(|| lhs.radius.total_cmp(&rhs.radius))
            .then_with(|| lhs.center_y.total_cmp(&rhs.center_y))
            .then_with(|| lhs.center_x.total_cmp(&rhs.center_x))
            .then_with(|| lhs.entry_id.cmp(&rhs.entry_id))
    })
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
