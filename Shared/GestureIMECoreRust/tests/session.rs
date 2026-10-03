use gesture_ime_core::{
    ActionInvocation, Binding, BindingBehavior, BindingSet, BindingTrieCompiler, Direction8,
    GesturePath, GesturePoint, GesturePolicy, GestureSession, GestureSize, GestureTerminal,
    GestureToken, HoldBehavior, RepeatBehavior,
};
use serde_json::{Map, Value};
use std::collections::HashSet;

fn token(direction: Direction8) -> GestureToken {
    GestureToken { direction }
}

fn action(id: &str, text: &str) -> ActionInvocation {
    ActionInvocation {
        action_id: id.into(),
        arguments: Map::from_iter([("text".into(), Value::String(text.into()))]),
    }
}

fn release_behavior(label: &str) -> BindingBehavior {
    BindingBehavior {
        presentation: None,
        on_release: vec![action("text.insert", label)],
        hold: None,
    }
}

fn binding(key_id: &str, path: Vec<Direction8>, behavior: BindingBehavior) -> Binding {
    Binding {
        key_id: key_id.into(),
        path: GesturePath(path.into_iter().map(token).collect()),
        behavior,
    }
}

fn policy() -> GesturePolicy {
    GesturePolicy {
        dead_zone: 0.05,
        stage1_commit_distance: 0.20,
        stage2_commit_distance: 0.20,
        angular_hysteresis_degrees: 4.0,
        max_directional_stages: 2,
    }
}

fn point_from(anchor: GesturePoint, direction: Direction8, distance: f64) -> GesturePoint {
    let radians = direction.center_degrees().to_radians();
    GesturePoint {
        x: anchor.x + radians.cos() * distance,
        y: anchor.y + radians.sin() * distance,
    }
}

fn all_two_stage_trie() -> gesture_ime_core::BindingTrie {
    let mut bindings = Vec::new();
    for first in Direction8::CANONICAL_ORDER {
        bindings.push(binding("key.test", vec![first], release_behavior("stage1")));
        for second in Direction8::CANONICAL_ORDER {
            bindings.push(binding(
                "key.test",
                vec![first, second],
                release_behavior("stage2"),
            ));
        }
    }
    BindingTrieCompiler::compile(
        &BindingSet {
            id: "bindings.all".into(),
            bindings,
        },
        "key.test",
    )
    .unwrap()
}

#[test]
fn every_direction_pair_can_commit_as_two_stage_path() {
    let trie = all_two_stage_trie();
    let start = GesturePoint { x: 50.0, y: 50.0 };

    for first in Direction8::CANONICAL_ORDER {
        for second in Direction8::CANONICAL_ORDER {
            let mut session = GestureSession::new(
                "key.test",
                "test",
                trie.clone(),
                policy(),
                GestureSize {
                    width: 100.0,
                    height: 100.0,
                },
                start,
                0,
            );

            let stage1 = point_from(start, first, 30.0);
            session.move_to(stage1, None);
            let stage2 = point_from(stage1, second, 30.0);
            session.move_to(stage2, None);
            let result = session.touch_up(None);

            assert_eq!(
                result.path,
                GesturePath(vec![token(first), token(second)]),
                "{first:?},{second:?}"
            );
            assert_eq!(result.terminal, GestureTerminal::Committed);
        }
    }
}

#[test]
fn first_commit_resets_virtual_anchor_for_second_stage() {
    let trie = all_two_stage_trie();
    let start = GesturePoint { x: 50.0, y: 50.0 };
    let mut session = GestureSession::new(
        "key.test",
        "test",
        trie,
        policy(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        start,
        0,
    );

    let east = GesturePoint { x: 80.0, y: 50.0 };
    session.move_to(east, None);
    assert_eq!(session.anchor, east);
    assert_eq!(session.commit_anchors, vec![east]);

    let north_from_new_anchor = GesturePoint { x: 80.0, y: 20.0 };
    session.move_to(north_from_new_anchor, None);

    assert_eq!(
        session.path,
        GesturePath(vec![token(Direction8::E), token(Direction8::N)])
    );
    assert_eq!(session.commit_anchors, vec![east, north_from_new_anchor]);
}

#[test]
fn eligible_directions_follow_current_trie_node() {
    let set = BindingSet {
        id: "bindings.eligible".into(),
        bindings: vec![
            binding("key.test", vec![Direction8::E], release_behavior("e")),
            binding(
                "key.test",
                vec![Direction8::E, Direction8::N],
                release_behavior("en"),
            ),
            binding(
                "key.test",
                vec![Direction8::E, Direction8::S],
                release_behavior("es"),
            ),
        ],
    };
    let trie = BindingTrieCompiler::compile(&set, "key.test").unwrap();
    let start = GesturePoint { x: 50.0, y: 50.0 };
    let mut session = GestureSession::new(
        "key.test",
        "test",
        trie,
        policy(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        start,
        0,
    );

    assert_eq!(
        session.eligible_directions(),
        HashSet::from([Direction8::E])
    );
    session.move_to(GesturePoint { x: 80.0, y: 50.0 }, None);
    assert_eq!(
        session.eligible_directions(),
        HashSet::from([Direction8::N, Direction8::S])
    );
}

#[test]
fn hysteresis_prevents_small_candidate_flip_before_commit() {
    let set = BindingSet {
        id: "bindings.hysteresis".into(),
        bindings: vec![
            binding("key.test", vec![Direction8::E], release_behavior("e")),
            binding("key.test", vec![Direction8::Se], release_behavior("se")),
        ],
    };
    let trie = BindingTrieCompiler::compile(&set, "key.test").unwrap();
    let mut p = policy();
    p.stage1_commit_distance = 0.8;
    p.angular_hysteresis_degrees = 10.0;

    let start = GesturePoint { x: 0.0, y: 0.0 };
    let mut session = GestureSession::new(
        "key.test",
        "test",
        trie,
        p,
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        start,
        0,
    );

    let angle20 = 20f64.to_radians();
    session.move_to(
        GesturePoint {
            x: angle20.cos() * 30.0,
            y: angle20.sin() * 30.0,
        },
        None,
    );
    assert_eq!(session.candidate_direction, Some(Direction8::E));

    let angle24 = 24f64.to_radians();
    session.move_to(
        GesturePoint {
            x: angle24.cos() * 30.0,
            y: angle24.sin() * 30.0,
        },
        None,
    );
    assert_eq!(session.candidate_direction, Some(Direction8::E));

    let angle34 = 34f64.to_radians();
    session.move_to(
        GesturePoint {
            x: angle34.cos() * 30.0,
            y: angle34.sin() * 30.0,
        },
        None,
    );
    assert_eq!(session.candidate_direction, Some(Direction8::Se));
}

#[test]
fn hold_start_locks_endpoint_and_can_suppress_release() {
    let hold_behavior = BindingBehavior {
        presentation: None,
        on_release: vec![action("text.insert", "release")],
        hold: Some(HoldBehavior {
            delay_ms: 100,
            on_start: vec![action("text.insert", "hold")],
            repeat_behavior: Some(RepeatBehavior {
                interval_ms: 50,
                actions: vec![action("text.insert", "repeat")],
            }),
            suppress_on_release_after_start: true,
        }),
    };
    let set = BindingSet {
        id: "bindings.hold".into(),
        bindings: vec![
            binding("key.test", vec![], hold_behavior),
            binding("key.test", vec![Direction8::E], release_behavior("east")),
        ],
    };
    let trie = BindingTrieCompiler::compile(&set, "key.test").unwrap();
    let mut session = GestureSession::new(
        "key.test",
        "test",
        trie,
        policy(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 50.0, y: 50.0 },
        0,
    );

    session.advance_time(100);
    session.move_to(GesturePoint { x: 90.0, y: 50.0 }, None);
    assert!(session.path.0.is_empty());

    session.advance_time(205);
    let result = session.touch_up(None);
    let texts: Vec<_> = result
        .dispatched_actions
        .iter()
        .map(|action| action.arguments["text"].as_str().unwrap())
        .collect();

    assert_eq!(texts, vec!["hold", "repeat", "repeat"]);
}

#[test]
fn cancel_before_hold_dispatches_nothing() {
    let hold_behavior = BindingBehavior {
        presentation: None,
        on_release: vec![action("text.insert", "release")],
        hold: Some(HoldBehavior {
            delay_ms: 100,
            on_start: vec![action("text.insert", "hold")],
            repeat_behavior: None,
            suppress_on_release_after_start: false,
        }),
    };
    let set = BindingSet {
        id: "bindings.cancel".into(),
        bindings: vec![binding("key.test", vec![], hold_behavior)],
    };
    let trie = BindingTrieCompiler::compile(&set, "key.test").unwrap();
    let mut session = GestureSession::new(
        "key.test",
        "test",
        trie,
        policy(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 50.0, y: 50.0 },
        0,
    );

    let result = session.cancel(Some(50));
    assert_eq!(result.terminal, GestureTerminal::Cancelled);
    assert!(result.dispatched_actions.is_empty());

    session.advance_time(500);
    assert!(session.dispatched_actions.is_empty());
}

#[test]
fn cancel_after_valid_hold_keeps_prior_dispatch_but_adds_no_release() {
    let hold_behavior = BindingBehavior {
        presentation: None,
        on_release: vec![action("text.insert", "release")],
        hold: Some(HoldBehavior {
            delay_ms: 100,
            on_start: vec![action("text.insert", "hold")],
            repeat_behavior: None,
            suppress_on_release_after_start: false,
        }),
    };
    let set = BindingSet {
        id: "bindings.cancel-after-hold".into(),
        bindings: vec![binding("key.test", vec![], hold_behavior)],
    };
    let trie = BindingTrieCompiler::compile(&set, "key.test").unwrap();
    let mut session = GestureSession::new(
        "key.test",
        "test",
        trie,
        policy(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 50.0, y: 50.0 },
        0,
    );

    let result = session.cancel(Some(120));
    let texts: Vec<_> = result
        .dispatched_actions
        .iter()
        .map(|action| action.arguments["text"].as_str().unwrap())
        .collect();

    assert_eq!(texts, vec!["hold"]);
    assert_eq!(result.terminal, GestureTerminal::Cancelled);
}

#[test]
fn invalidate_is_terminal_and_does_not_release_endpoint() {
    let set = BindingSet {
        id: "bindings.invalidate".into(),
        bindings: vec![binding("key.test", vec![], release_behavior("release"))],
    };
    let trie = BindingTrieCompiler::compile(&set, "key.test").unwrap();
    let mut session = GestureSession::new(
        "key.test",
        "rev-1",
        trie,
        policy(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 50.0, y: 50.0 },
        0,
    );

    let result = session.invalidate(None);
    assert_eq!(result.terminal, GestureTerminal::Invalidated);
    assert!(result.dispatched_actions.is_empty());

    let second = session.touch_up(None);
    assert_eq!(second.terminal, GestureTerminal::Invalidated);
    assert!(second.dispatched_actions.is_empty());
}

#[test]
fn touch_up_at_root_dispatches_tap_behavior() {
    let set = BindingSet {
        id: "bindings.tap".into(),
        bindings: vec![binding("key.test", vec![], release_behavior("tap"))],
    };
    let trie = BindingTrieCompiler::compile(&set, "key.test").unwrap();
    let mut session = GestureSession::new(
        "key.test",
        "test",
        trie,
        policy(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 50.0, y: 50.0 },
        0,
    );

    let result = session.touch_up(None);
    assert_eq!(result.terminal, GestureTerminal::Committed);
    assert_eq!(result.path, GesturePath::default());
    assert_eq!(
        result.dispatched_actions[0].arguments["text"].as_str(),
        Some("tap")
    );
}