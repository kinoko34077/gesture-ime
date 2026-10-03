use crate::model::{
    ActionInvocation, Direction8, GesturePath, GesturePoint, GesturePolicy, GestureSize, GestureToken,
};
use crate::trie::{BindingTrie, BindingTrieNode};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum GestureTerminal {
    Committed,
    Cancelled,
    Invalidated,
}

#[derive(Debug, Clone, PartialEq)]
pub struct GestureSessionResult {
    pub terminal: GestureTerminal,
    pub path: GesturePath,
    pub dispatched_actions: Vec<ActionInvocation>,
}

#[derive(Debug, Clone)]
pub struct GestureSession {
    pub key_id: String,
    pub profile_revision: String,
    pub policy: GesturePolicy,
    pub key_size: GestureSize,

    pub path: GesturePath,
    pub anchor: GesturePoint,
    pub candidate_direction: Option<Direction8>,
    pub committed_directional_stages: i64,
    pub terminal: Option<GestureTerminal>,
    pub dispatched_actions: Vec<ActionInvocation>,
    pub commit_anchors: Vec<GesturePoint>,

    current_node: BindingTrieNode,
    current_time_ms: i64,
    hold_due_ms: Option<i64>,
    repeat_due_ms: Option<i64>,
    hold_started: bool,
    hold_locked: bool,
}

impl GestureSession {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        key_id: impl Into<String>,
        profile_revision: impl Into<String>,
        trie: BindingTrie,
        policy: GesturePolicy,
        key_size: GestureSize,
        touch_down: GesturePoint,
        at_ms: i64,
    ) -> Self {
        let mut session = Self {
            key_id: key_id.into(),
            profile_revision: profile_revision.into(),
            policy,
            key_size,
            path: GesturePath::default(),
            anchor: touch_down,
            candidate_direction: None,
            committed_directional_stages: 0,
            terminal: None,
            dispatched_actions: Vec::new(),
            commit_anchors: Vec::new(),
            current_node: trie.root,
            current_time_ms: at_ms,
            hold_due_ms: None,
            repeat_due_ms: None,
            hold_started: false,
            hold_locked: false,
        };
        session.schedule_current_hold(at_ms);
        session
    }

    pub fn eligible_directions(&self) -> HashSet<Direction8> {
        self.current_node.eligible_directions()
    }

    pub fn move_to(&mut self, point: GesturePoint, at_ms: Option<i64>) {
        if self.terminal.is_some() {
            return;
        }
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        if self.hold_locked
            || self.committed_directional_stages >= self.policy.max_directional_stages
        {
            return;
        }

        let scale = self.key_size.minimum_dimension();
        if !scale.is_finite() || scale <= 0.0 {
            return;
        }

        let dx = point.x - self.anchor.x;
        let dy = point.y - self.anchor.y;
        let normalized = dx.hypot(dy) / scale;

        if normalized < self.policy.dead_zone || self.current_node.children.is_empty() {
            self.candidate_direction = None;
            return;
        }

        let angle = Self::angle_degrees(dx, dy);
        let nearest = self
            .current_node
            .children
            .keys()
            .copied()
            .min_by(|lhs, rhs| {
                let lhs_distance = Self::angular_distance(angle, lhs.center_degrees());
                let rhs_distance = Self::angular_distance(angle, rhs.center_degrees());
                lhs_distance
                    .total_cmp(&rhs_distance)
                    .then_with(|| Self::rank(*lhs).cmp(&Self::rank(*rhs)))
            });

        let Some(nearest) = nearest else {
            return;
        };

        match self.candidate_direction {
            Some(current) if current != nearest => {
                let nearest_distance =
                    Self::angular_distance(angle, nearest.center_degrees());
                let current_distance =
                    Self::angular_distance(angle, current.center_degrees());
                if nearest_distance + self.policy.angular_hysteresis_degrees < current_distance {
                    self.candidate_direction = Some(nearest);
                }
            }
            None => {
                self.candidate_direction = Some(nearest);
            }
            _ => {}
        }

        let threshold = if self.committed_directional_stages == 0 {
            self.policy.stage1_commit_distance
        } else {
            self.policy.stage2_commit_distance
        };

        let Some(direction) = self.candidate_direction else {
            return;
        };
        if normalized < threshold {
            return;
        }
        let Some(child) = self.current_node.children.get(&direction).cloned() else {
            return;
        };

        self.cancel_hold_schedule();
        self.path.0.push(GestureToken { direction });
        self.current_node = child;
        self.committed_directional_stages += 1;
        self.anchor = point;
        self.commit_anchors.push(point);
        self.candidate_direction = None;
        self.schedule_current_hold(self.current_time_ms);
    }

    pub fn advance_time(&mut self, target_ms: i64) {
        if self.terminal.is_some() || target_ms < self.current_time_ms {
            return;
        }

        if let (Some(hold), Some(due_ms)) = (
            self.current_node.behavior.as_ref().and_then(|behavior| behavior.hold.as_ref()),
            self.hold_due_ms,
        ) {
            if !self.hold_started && due_ms <= target_ms {
                self.dispatched_actions.extend(hold.on_start.clone());
                self.hold_started = true;
                self.hold_locked = true;
                self.candidate_direction = None;
                if let Some(repeating) = &hold.repeat_behavior {
                    self.repeat_due_ms = Some(due_ms + repeating.interval_ms);
                }
            }
        }

        if self.hold_started {
            if let Some(repeating) = self
                .current_node
                .behavior
                .as_ref()
                .and_then(|behavior| behavior.hold.as_ref())
                .and_then(|hold| hold.repeat_behavior.as_ref())
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

    pub fn touch_up(&mut self, at_ms: Option<i64>) -> GestureSessionResult {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        if self.terminal.is_some() {
            return self.result();
        }

        if let Some(behavior) = &self.current_node.behavior {
            let suppress_release = self.hold_started
                && behavior
                    .hold
                    .as_ref()
                    .is_some_and(|hold| hold.suppress_on_release_after_start);
            if !suppress_release {
                self.dispatched_actions.extend(behavior.on_release.clone());
            }
        }

        self.terminal = Some(GestureTerminal::Committed);
        self.cancel_hold_schedule();
        self.result()
    }

    pub fn cancel(&mut self, at_ms: Option<i64>) -> GestureSessionResult {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        if self.terminal.is_some() {
            return self.result();
        }

        self.terminal = Some(GestureTerminal::Cancelled);
        self.cancel_hold_schedule();
        self.result()
    }

    pub fn invalidate(&mut self, at_ms: Option<i64>) -> GestureSessionResult {
        if let Some(at_ms) = at_ms {
            self.advance_time(at_ms);
        }
        if self.terminal.is_some() {
            return self.result();
        }

        self.terminal = Some(GestureTerminal::Invalidated);
        self.cancel_hold_schedule();
        self.result()
    }

    fn schedule_current_hold(&mut self, at_ms: i64) {
        self.hold_started = false;
        self.hold_locked = false;
        self.repeat_due_ms = None;
        self.hold_due_ms = self
            .current_node
            .behavior
            .as_ref()
            .and_then(|behavior| behavior.hold.as_ref())
            .map(|hold| at_ms + hold.delay_ms);
    }

    fn cancel_hold_schedule(&mut self) {
        self.hold_due_ms = None;
        self.repeat_due_ms = None;
    }

    fn result(&self) -> GestureSessionResult {
        GestureSessionResult {
            terminal: self.terminal.unwrap_or(GestureTerminal::Cancelled),
            path: self.path.clone(),
            dispatched_actions: self.dispatched_actions.clone(),
        }
    }

    fn rank(direction: Direction8) -> usize {
        Direction8::CANONICAL_ORDER
            .iter()
            .position(|candidate| *candidate == direction)
            .unwrap_or(usize::MAX)
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
}