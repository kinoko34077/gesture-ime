//! #72 / #69 §3–4: reversible Stage Stack, provisional terminal retargeting,
//! two-origin normalization, dwell rollback and partial policy overrides.

use gesture_ime_core::{
    BoardContextV3, BoardSessionV3, DefaultBoardSemanticsV3, GesturePoint, GestureSize,
    ProfileLimits, ProfileV3BoardRuntime, ProfileV3Codec, ProfileValidationCode,
};
use serde_json::{json, Value};

const CELL: f64 = 100.0;
const SOURCE_CENTER: GesturePoint = GesturePoint { x: 50.0, y: 50.0 };
// Deliberately off-center inside the 100pt source key.
const TOUCH_DOWN: GesturePoint = GesturePoint { x: 37.0, y: 52.0 };

fn release(offset: i64) -> Value {
    json!({"onRelease":[{"actionID":"cursor.move","arguments":{"offset":offset}}]})
}

fn entry(id: &str, x: i64, y: i64, behavior: Value) -> Value {
    json!({
        "id":id,
        "rect":{"x":x,"y":y,"width":2,"height":2},
        "resolver":{"cases":[],"default":behavior}
    })
}

fn to_board(target: &str, offset: i64) -> Value {
    let mut behavior = release(offset);
    behavior["transition"] = json!({"targetBoardRef":target,"lifetime":"transient"});
    behavior
}

/// root.src -> s1 {origin, east, north, west->s2}
/// s2 {origin, east, north->s3}
/// s3 {origin, east, north->s2 (cycle, bounded by the transition budget)}
fn profile_json() -> Value {
    let mut source = to_board("board.s1", 1);
    source["presentation"] = json!({"text":{"base":"src","transforms":[]}});
    json!({
        "schema":"gesture-ime.profile.v3",
        "id":"profile.stage.stack",
        "name":"Stage Stack",
        "version":1,
        "gesturePolicy":{
            "deadZone":0.15,
            "initialCellCommitDistance":0.5,
            "subsequentCellCommitDistance":0.4,
            "angularHysteresisDegrees":8
        },
        "initialLayerRef":"layer.base",
        "layers":[{"id":"layer.base","rootBoardRef":"board.root"}],
        "boards":[
            {"id":"board.root","entries":[entry("src", -1, -1, source)]},
            {"id":"board.s1","entries":[
                entry("s1.origin", -1, -1, release(10)),
                entry("s1.east", 1, -1, release(11)),
                entry("s1.north", -1, -3, release(12)),
                entry("s1.west", -3, -1, to_board("board.s2", 13))
            ]},
            {"id":"board.s2","entries":[
                entry("s2.origin", -1, -1, release(20)),
                entry("s2.east", 1, -1, release(21)),
                entry("s2.north", -1, -3, to_board("board.s3", 22))
            ]},
            {"id":"board.s3","entries":[
                entry("s3.origin", -1, -1, release(30)),
                entry("s3.east", 1, -1, release(31)),
                entry("s3.north", -1, -3, to_board("board.s2", 32))
            ]}
        ],
        "states":[],
        "transformTables":[],
        "macros":[]
    })
}

fn runtime_from(value: &Value) -> ProfileV3BoardRuntime {
    let bytes = serde_json::to_vec(value).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    ProfileV3BoardRuntime::compile(&profile, "stage-stack").unwrap()
}

fn session_from(value: &Value) -> BoardSessionV3 {
    let runtime = runtime_from(value);
    let frame = runtime.new_frame("layer.base").unwrap();
    runtime
        .begin_direct_session_at(
            frame,
            "src",
            GestureSize { width: CELL, height: CELL },
            TOUCH_DOWN,
            Some(SOURCE_CENTER),
            0,
            Box::new(DefaultBoardSemanticsV3),
        )
        .unwrap()
}

fn session() -> BoardSessionV3 {
    session_from(&profile_json())
}

/// Physical point displaced from the active stage pointer origin by cells.
fn rel(session: &BoardSessionV3, dx_cells: f64, dy_cells: f64) -> GesturePoint {
    GesturePoint {
        x: session.anchor.x + dx_cells * CELL,
        y: session.anchor.y + dy_cells * CELL,
    }
}

fn offsets(session: &BoardSessionV3) -> Vec<i64> {
    session
        .dispatched_actions
        .iter()
        .filter_map(|action| action.arguments.get("offset").and_then(Value::as_i64))
        .collect()
}

fn endpoint(session: &BoardSessionV3) -> Option<&str> {
    session.current_endpoint_entry_id.as_deref()
}

/// Enters Stage 2 by committing s1.west at `at_ms`.
fn enter_stage_two(session: &mut BoardSessionV3, at_ms: i64) {
    let point = rel(session, -0.7, 0.0);
    session.move_to(point, Some(at_ms));
    assert_eq!(session.current_board_id, "board.s2");
    assert_eq!(session.stage_depth(), 2);
}

#[test]
fn stage_one_uses_source_center_visual_origin_and_physical_pointer_origin() {
    let session = session();
    assert_eq!(session.context, BoardContextV3::Relative);
    assert_eq!(session.stage_depth(), 1);
    assert_eq!(session.visual_origin, SOURCE_CENTER);
    assert_eq!(session.anchor, TOUCH_DOWN);
    assert_eq!(endpoint(&session), Some("s1.origin"));
}

#[test]
fn terminal_candidate_retargets_a_b_a_and_releases_only_final_endpoint() {
    let mut session = session();
    session.move_to(rel(&session, 0.7, 0.0), Some(10));
    assert_eq!(endpoint(&session), Some("s1.east"));

    session.move_to(rel(&session, 0.0, -0.7), Some(20));
    assert_eq!(endpoint(&session), Some("s1.north"));

    session.move_to(rel(&session, 0.7, 0.0), Some(30));
    assert_eq!(endpoint(&session), Some("s1.east"));
    assert!(offsets(&session).is_empty(), "nothing dispatches before touch-up");

    session.touch_up(Some(40));
    assert_eq!(offsets(&session), vec![11]);
}

#[test]
fn returning_to_center_restores_origin_endpoint() {
    let mut session = session();
    session.move_to(rel(&session, 0.7, 0.0), Some(10));
    session.move_to(rel(&session, 0.05, 0.0), Some(20));
    assert_eq!(endpoint(&session), Some("s1.origin"));
    session.touch_up(Some(30));
    assert_eq!(offsets(&session), vec![10]);
}

#[test]
fn unassigned_region_does_not_commit_stale_candidate() {
    let mut session = session();
    session.move_to(rel(&session, 0.7, 0.0), Some(10));
    assert_eq!(endpoint(&session), Some("s1.east"));

    // South is >45 degrees from every registered s1 entry.
    session.move_to(rel(&session, 0.0, 0.9), Some(20));
    assert_eq!(endpoint(&session), None);
    assert_eq!(session.candidate_entry_id, None);

    session.touch_up(Some(30));
    assert!(offsets(&session).is_empty());
}

#[test]
fn forward_transition_normalizes_visual_and_pointer_origins_at_every_stage() {
    let mut session = session();
    let stage_two_point = rel(&session, -0.7, 0.03);
    session.move_to(stage_two_point, Some(10));
    assert_eq!(session.current_board_id, "board.s2");
    // s1.west center is (-1, 0) cells from the Stage 1 visual origin.
    assert_eq!(session.visual_origin, GesturePoint { x: -50.0, y: 50.0 });
    assert_eq!(session.anchor, stage_two_point);
    assert_eq!(endpoint(&session), Some("s2.origin"));

    let stage_three_point = rel(&session, 0.02, -0.6);
    session.move_to(stage_three_point, Some(20));
    assert_eq!(session.current_board_id, "board.s3");
    assert_eq!(session.stage_depth(), 3);
    assert_eq!(session.visual_origin, GesturePoint { x: -50.0, y: -50.0 });
    assert_eq!(session.anchor, stage_three_point);

    let frames = session.stages();
    assert_eq!(frames[0].visual_origin, SOURCE_CENTER);
    assert_eq!(frames[0].pointer_origin, TOUCH_DOWN);
    assert_eq!(frames[1].entered_via_entry_id.as_deref(), Some("s1.west"));
    assert_eq!(frames[2].entered_via_entry_id.as_deref(), Some("s2.north"));
    // No source release Action fires merely because stages were entered.
    assert!(offsets(&session).is_empty());
}

#[test]
fn stage_two_center_dwell_pops_exactly_one_stage() {
    let mut session = session();
    enter_stage_two(&mut session, 10);
    // Leave center (arms rollback), come back and dwell.
    session.move_to(rel(&session, 0.7, 0.0), Some(20));
    let center = rel(&session, 0.0, 0.0);
    session.move_to(center, Some(100));
    assert_eq!(session.rollback_progress(), Some(0.0));

    session.advance_time(1099);
    assert_eq!(session.stage_depth(), 2);
    assert!(session.rollback_progress().unwrap() > 0.99);

    session.advance_time(1100);
    assert_eq!(session.stage_depth(), 1);
    assert_eq!(session.current_board_id, "board.s1");
    assert_eq!(session.visual_origin, SOURCE_CENTER);
    assert_eq!(session.anchor, center, "pointer origin resets to the current finger");
    assert_eq!(endpoint(&session), Some("s1.origin"));
    assert_eq!(session.rollback_count, 1);
    assert_eq!(session.rollback_progress(), None);
    assert!(offsets(&session).is_empty(), "rollback fires no release Action");
}

#[test]
fn stage_two_unassigned_region_dwell_pops_exactly_one_stage() {
    let mut session = session();
    enter_stage_two(&mut session, 10);
    session.move_to(rel(&session, -0.8, 0.0), Some(50));
    assert_eq!(endpoint(&session), Some("s2.origin"));
    assert_eq!(session.rollback_progress(), Some(0.0));

    session.advance_time(1050);
    assert_eq!(session.stage_depth(), 1);
    assert_eq!(session.current_board_id, "board.s1");
}

#[test]
fn registered_candidate_before_expiry_cancels_and_restarts_dwell() {
    let mut session = session();
    enter_stage_two(&mut session, 10);
    session.move_to(rel(&session, 0.7, 0.0), Some(20));
    let anchor = session.anchor;
    let at = |dx: f64, dy: f64| GesturePoint { x: anchor.x + dx * CELL, y: anchor.y + dy * CELL };

    session.move_to(at(0.0, 0.0), Some(100));
    session.move_to(at(0.7, 0.0), Some(600));
    assert_eq!(session.rollback_progress(), None);
    session.move_to(at(0.0, 0.0), Some(700));

    session.advance_time(1650);
    assert_eq!(session.stage_depth(), 2, "dwell restarted at 700");
    session.advance_time(1700);
    assert_eq!(session.stage_depth(), 1);
}

#[test]
fn passing_briefly_through_rollback_zone_does_not_pop() {
    let mut session = session();
    enter_stage_two(&mut session, 10);
    session.move_to(rel(&session, -0.8, 0.0), Some(50));
    session.move_to(rel(&session, 0.7, 0.0), Some(300));
    session.advance_time(5000);
    assert_eq!(session.stage_depth(), 2);
    assert_eq!(endpoint(&session), Some("s2.east"));
}

#[test]
fn stationary_finger_after_pop_neither_multi_pops_nor_reenters_child() {
    let mut session = session();
    enter_stage_two(&mut session, 10);
    session.move_to(rel(&session, 0.0, -0.6), Some(20));
    assert_eq!(session.stage_depth(), 3);
    session.move_to(rel(&session, 0.7, 0.0), Some(30));
    let anchor = session.anchor;
    let center = GesturePoint { x: anchor.x, y: anchor.y };
    session.move_to(center, Some(40));

    session.advance_time(1040);
    assert_eq!(session.stage_depth(), 2);
    assert_eq!(session.current_board_id, "board.s2");
    assert_eq!(session.visual_origin, GesturePoint { x: -50.0, y: 50.0 });

    // Same physical point, a long time: no second pop, no re-entry.
    for t in [1100, 2500, 6000] {
        session.move_to(center, Some(t));
        session.advance_time(t + 5);
    }
    assert_eq!(session.stage_depth(), 2);
    assert_eq!(session.current_board_id, "board.s2");
    assert_eq!(endpoint(&session), Some("s2.origin"));
    assert_eq!(session.rollback_count, 1);

    // Fresh movement may roll back again.
    session.move_to(GesturePoint { x: center.x - 80.0, y: center.y }, Some(6100));
    session.advance_time(7100);
    assert_eq!(session.stage_depth(), 1);
    assert_eq!(session.rollback_count, 2);
}

#[test]
fn stage_one_never_rolls_back() {
    let mut session = session();
    session.move_to(rel(&session, 0.7, 0.0), Some(10));
    session.move_to(rel(&session, 0.0, 0.0), Some(20));
    session.advance_time(10_000);
    assert_eq!(session.stage_depth(), 1);
    assert_eq!(session.rollback_count, 0);
    assert_eq!(session.rollback_progress(), None);
}

#[test]
fn transition_budget_bounds_forward_back_loops() {
    let mut session = session();
    enter_stage_two(&mut session, 10);
    let mut t = 20;
    for _ in 0..(ProfileLimits::BOARD_TRANSITIONS_PER_INTERACTION * 2) {
        session.move_to(rel(&session, 0.0, -0.6), Some(t));
        t += 10;
        if session.transition_limit_hit {
            break;
        }
    }
    assert!(session.transition_limit_hit);
    assert_eq!(session.transition_count, ProfileLimits::BOARD_TRANSITIONS_PER_INTERACTION);
    assert!(session.stage_depth() <= ProfileLimits::BOARD_TRANSITIONS_PER_INTERACTION);
    session.touch_up(Some(t));
    assert_eq!(session.terminal, Some(gesture_ime_core::BoardSessionTerminalV3::Committed));
    assert_eq!(session.stage_depth(), 0);
}

#[test]
fn changing_provisional_candidate_cancels_previous_endpoint_hold() {
    let mut value = profile_json();
    value["boards"][1]["entries"][1]["resolver"]["default"]["hold"] = json!({
        "delayMs":300,
        "onStart":[{"actionID":"cursor.move","arguments":{"offset":19}}],
        "suppressOnReleaseAfterStart":true
    });
    let mut session = session_from(&value);
    session.move_to(rel(&session, 0.7, 0.0), Some(0));
    session.move_to(rel(&session, 0.0, -0.7), Some(200));
    session.advance_time(600);
    assert!(offsets(&session).is_empty(), "east Hold was cancelled by retarget");

    session.move_to(rel(&session, 0.7, 0.0), Some(650));
    session.advance_time(949);
    assert!(offsets(&session).is_empty());
    session.advance_time(950);
    assert_eq!(offsets(&session), vec![19]);
    // A started Hold owns the interaction: no retarget, release suppressed.
    session.move_to(rel(&session, 0.0, -0.7), Some(960));
    assert_eq!(endpoint(&session), Some("s1.east"));
    session.touch_up(Some(970));
    assert_eq!(offsets(&session), vec![19]);
}

#[test]
fn cancel_and_invalidate_clear_stage_stack_without_dispatch() {
    for invalidate in [false, true] {
        let mut session = session();
        enter_stage_two(&mut session, 10);
        session.move_to(rel(&session, 0.7, 0.0), Some(20));
        if invalidate {
            session.invalidate(Some(30));
        } else {
            session.cancel(Some(30));
        }
        assert_eq!(session.stage_depth(), 0);
        assert!(offsets(&session).is_empty());
        session.advance_time(5000);
        assert!(offsets(&session).is_empty());
    }
}

#[test]
fn persistent_transition_is_restored_when_its_stage_pops() {
    let mut value = profile_json();
    value["boards"][1]["entries"][3]["resolver"]["default"]["transition"]["lifetime"] =
        json!("persistent");
    let runtime = runtime_from(&value);
    let frame = runtime.new_frame("layer.base").unwrap();
    let mut session = runtime
        .begin_direct_session_at(
            frame.clone(),
            "src",
            GestureSize { width: CELL, height: CELL },
            TOUCH_DOWN,
            Some(SOURCE_CENTER),
            0,
            Box::new(DefaultBoardSemanticsV3),
        )
        .unwrap();
    enter_stage_two(&mut session, 10);
    assert_eq!(frame.lock().unwrap().persistent_board_id, "board.s2");

    session.move_to(rel(&session, 0.0, 0.9), Some(20));
    session.advance_time(1020);
    assert_eq!(session.stage_depth(), 1);
    assert_eq!(frame.lock().unwrap().persistent_board_id, "board.root");
}

#[test]
fn source_entry_partial_override_inherits_unset_fields() {
    let mut value = profile_json();
    value["boards"][0]["entries"][0]["gesturePolicyOverride"] =
        json!({"initialCellCommitDistance":1.2});
    value["boards"][1]["entries"][3]["gesturePolicyOverride"] =
        json!({"stageBacktrackDwellMs":300});

    let mut session = session_from(&value);
    let stage_one = session.active_policy().clone();
    assert_eq!(stage_one.initial_cell_commit_distance, 1.2);
    assert_eq!(stage_one.dead_zone, 0.15, "inherits common deadZone");
    assert_eq!(stage_one.effective_stage_backtrack_dwell_ms(), 1000);

    session.move_to(rel(&session, 0.7, 0.0), Some(10));
    assert_eq!(endpoint(&session), Some("s1.origin"), "override raised the commit distance");
    session.move_to(rel(&session, 1.3, 0.0), Some(20));
    assert_eq!(endpoint(&session), Some("s1.east"));

    session.move_to(rel(&session, -1.3, 0.0), Some(30));
    assert_eq!(session.stage_depth(), 2);
    let stage_two = session.active_policy().clone();
    assert_eq!(stage_two.effective_stage_backtrack_dwell_ms(), 300);
    assert_eq!(stage_two.initial_cell_commit_distance, 0.5, "s2 does not inherit src override");

    session.move_to(rel(&session, 0.0, 0.9), Some(40));
    session.advance_time(339);
    assert_eq!(session.stage_depth(), 2);
    session.advance_time(340);
    assert_eq!(session.stage_depth(), 1);
}

#[test]
fn stage_backtrack_dwell_defaults_and_validates() {
    let runtime = runtime_from(&profile_json());
    assert_eq!(runtime.policy.stage_backtrack_dwell_ms, None);
    assert_eq!(runtime.policy.effective_stage_backtrack_dwell_ms(), 1000);

    let mut explicit = profile_json();
    explicit["gesturePolicy"]["stageBacktrackDwellMs"] = json!(750);
    let bytes = serde_json::to_vec(&explicit).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    assert_eq!(profile.gesture_policy.stage_backtrack_dwell_ms, Some(750));
    let round_trip = serde_json::to_value(&profile).unwrap();
    assert_eq!(round_trip["gesturePolicy"]["stageBacktrackDwellMs"], json!(750));

    for bad in [json!(0), json!(99), json!(10_001)] {
        let mut value = profile_json();
        value["gesturePolicy"]["stageBacktrackDwellMs"] = bad;
        let bytes = serde_json::to_vec(&value).unwrap();
        let error = ProfileV3Codec::decode_and_validate(&bytes).unwrap_err();
        assert_eq!(error.code, ProfileValidationCode::InvalidGesturePolicy);
    }
}

#[test]
fn invalid_partial_override_is_rejected_in_inherited_context() {
    for partial in [
        json!({"initialCellCommitDistance":0.1}), // < inherited deadZone 0.15
        json!({"deadZone":3.0}),
        json!({"angularHysteresisDegrees":45}),
        json!({"stageBacktrackDwellMs":20}),
    ] {
        let mut value = profile_json();
        value["boards"][1]["entries"][3]["gesturePolicyOverride"] = partial;
        let bytes = serde_json::to_vec(&value).unwrap();
        let error = ProfileV3Codec::decode_and_validate(&bytes).unwrap_err();
        assert_eq!(error.code, ProfileValidationCode::InvalidGesturePolicy);
        assert_eq!(error.detail.as_deref(), Some("board.s1:s1.west"));
    }
}

#[test]
fn legacy_begin_without_visual_origin_keeps_touch_down_visual_origin() {
    let runtime = runtime_from(&profile_json());
    let frame = runtime.new_frame("layer.base").unwrap();
    let session = runtime
        .begin_direct_session(
            frame,
            "src",
            GestureSize { width: CELL, height: CELL },
            TOUCH_DOWN,
            0,
            Box::new(DefaultBoardSemanticsV3),
        )
        .unwrap();
    assert_eq!(session.visual_origin, TOUCH_DOWN);
    assert_eq!(session.anchor, TOUCH_DOWN);
}

#[test]
fn ffi_snapshot_exposes_visual_origin_stage_depth_and_rollback_progress() {
    use gesture_ime_core::{FfiPoint, FfiSize, ProfileV3PlatformRuntime};

    let mut value = profile_json();
    value["gesturePolicy"]["stageBacktrackDwellMs"] = json!(400);
    let runtime = ProfileV3PlatformRuntime::new(value.to_string()).unwrap();
    assert_eq!(runtime.default_policy().stage_backtrack_dwell_ms, 400);

    let session = runtime
        .begin_session_at_visual_origin(
            "src".into(),
            FfiSize { width: CELL, height: CELL },
            FfiPoint { x: TOUCH_DOWN.x, y: TOUCH_DOWN.y },
            Some(FfiPoint { x: SOURCE_CENTER.x, y: SOURCE_CENTER.y }),
            0,
        )
        .unwrap();
    let initial = session.snapshot().unwrap();
    assert_eq!(initial.stage_depth, 1);
    assert_eq!(initial.visual_origin, FfiPoint { x: 50.0, y: 50.0 });
    assert_eq!(initial.anchor, FfiPoint { x: 37.0, y: 52.0 });

    let stage_two = session
        .move_to(FfiPoint { x: -33.0, y: 52.0 }, Some(10))
        .unwrap();
    assert_eq!(stage_two.stage_depth, 2);
    assert_eq!(stage_two.visual_origin, FfiPoint { x: -50.0, y: 50.0 });

    let dwelling = session
        .move_to(FfiPoint { x: -33.0, y: 142.0 }, Some(20))
        .unwrap();
    assert_eq!(dwelling.rollback_progress, Some(0.0));
    let half = session.advance_time(220).unwrap();
    assert_eq!(half.rollback_progress, Some(0.5));
    let popped = session.advance_time(420).unwrap();
    assert_eq!(popped.stage_depth, 1);
    assert_eq!(popped.rollback_count, 1);
    assert_eq!(popped.rollback_progress, None);
    assert_eq!(popped.visual_origin, FfiPoint { x: 50.0, y: 50.0 });
    assert_eq!(popped.current_board_id, "board.s1");
}
