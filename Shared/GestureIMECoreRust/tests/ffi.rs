use gesture_ime_core::{
    migrate_profile_to_v2_json, validate_profile_json, FfiBoardCoordinate, FfiDirection8,
    FfiPoint, FfiSize, SharedCoreRuntime,
};
use std::fs;
use std::path::PathBuf;

fn fixture(name: &str) -> String {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .join("spec/conformance/fixtures")
        .join(name);
    fs::read_to_string(path).expect("fixture")
}

#[test]
fn ffi_validation_preserves_canonical_error_code() {
    let result = validate_profile_json(fixture("profile-duplicate-path.invalid.json"));
    assert!(!result.valid);
    assert_eq!(
        result.error_code.as_deref(),
        Some("E_DUPLICATE_BINDING_PATH")
    );
}

#[test]
fn ffi_validation_rejects_v2_board_entry_without_meaningful_member() {
    let mut profile: serde_json::Value =
        serde_json::from_str(&fixture("profile-v2-board-cardinal.valid.json"))
            .expect("v2 fixture JSON");
    profile["boards"][0]["entries"][0] = serde_json::json!({
        "coordinate": {"x": 0, "y": 0}
    });

    let result = validate_profile_json(profile.to_string());
    assert!(!result.valid, "schema-invalid BoardEntry must fail activation");
    assert_eq!(result.error_code.as_deref(), Some("E_UNSUPPORTED_SCHEMA"));
}

#[test]
fn ffi_validation_rejects_v2_coordinate_unknown_member() {
    let mut profile: serde_json::Value =
        serde_json::from_str(&fixture("profile-v2-board-cardinal.valid.json"))
            .expect("v2 fixture JSON");
    profile["boards"][0]["entries"][0]["coordinate"]["z"] = serde_json::json!(0);

    let result = validate_profile_json(profile.to_string());
    assert!(!result.valid, "coordinate additionalProperties must fail activation");
    assert_eq!(result.error_code.as_deref(), Some("E_UNSUPPORTED_SCHEMA"));
}

#[test]
fn ffi_validation_rejects_v2_explicit_null_for_non_nullable_optional_members() {
    let base: serde_json::Value =
        serde_json::from_str(&fixture("profile-v2-board-cardinal.valid.json"))
            .expect("v2 fixture JSON");

    let reject = |profile: serde_json::Value, context: &str| {
        let result = validate_profile_json(profile.to_string());
        assert!(!result.valid, "{context} must fail canonical schema validation");
        assert_eq!(
            result.error_code.as_deref(),
            Some("E_UNSUPPORTED_SCHEMA"),
            "{context}"
        );
    };

    let mut theme = base.clone();
    theme["theme"] = serde_json::Value::Null;
    reject(theme, "theme:null");

    let mut key_presentation = base.clone();
    key_presentation["keyDefinitions"][0]["presentation"] = serde_json::Value::Null;
    reject(key_presentation, "key presentation:null");

    let mut presentation_text = base.clone();
    presentation_text["keyDefinitions"][0]["presentation"] =
        serde_json::json!({"text": null});
    reject(presentation_text, "presentation.text:null");

    let mut placement_width = base.clone();
    placement_width["layouts"][0]["placements"][0]["width"] = serde_json::Value::Null;
    reject(placement_width, "placement.width:null");

    let mut entry_transition = base.clone();
    entry_transition["boards"][0]["entries"][0]["transition"] = serde_json::Value::Null;
    reject(entry_transition, "board entry transition:null");

    let mut entry_hold_repeat = base.clone();
    entry_hold_repeat["boards"][0]["entries"][0]["hold"] = serde_json::json!({
        "delayMs": 450,
        "onStart": [],
        "repeat": null,
        "suppressOnReleaseAfterStart": false
    });
    reject(entry_hold_repeat, "board entry hold.repeat:null");

    let mut trigger_delay = base;
    let board_id = trigger_delay["boards"][0]["id"]
        .as_str()
        .expect("board id")
        .to_owned();
    trigger_delay["boards"][0]["triggers"] = serde_json::json!([{
        "type": "hold",
        "delayMs": null,
        "transition": {
            "targetBoardRef": board_id,
            "lifetime": "transient"
        }
    }]);
    reject(trigger_delay, "board trigger delayMs:null");
}

#[test]
fn ffi_runtime_exposes_precommit_candidate_and_hysteresis_before_distance_commit() {
    let runtime = SharedCoreRuntime::new(fixture("profile-diagonal-two-stage.valid.json"))
        .expect("runtime");
    let session = runtime
        .create_session(
            "base".into(),
            "kana.a".into(),
            runtime.profile_revision(),
            FfiSize {
                width: 100.0,
                height: 100.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
            None,
        )
        .expect("session");

    let east = session
        .move_to(
            FfiPoint {
                x: 18.793852,
                y: -6.840403,
            },
            None,
        )
        .expect("east precommit candidate");
    assert!(east.path.is_empty());
    assert_eq!(east.candidate_direction, Some(FfiDirection8::E));
    assert_eq!(
        east.candidate_coordinate,
        Some(FfiBoardCoordinate { x: 1, y: 0 })
    );

    let retained = session
        .move_to(
            FfiPoint {
                x: 18.270909,
                y: -8.134733,
            },
            None,
        )
        .expect("hysteresis retain");
    assert!(retained.path.is_empty());
    assert_eq!(retained.candidate_direction, Some(FfiDirection8::E));

    let switched = session
        .move_to(
            FfiPoint {
                x: 17.320508,
                y: -10.0,
            },
            None,
        )
        .expect("hysteresis switch");
    assert!(switched.path.is_empty());
    assert_eq!(switched.candidate_direction, Some(FfiDirection8::Ne));

    let committed = session
        .move_to(
            FfiPoint {
                x: 38.971143,
                y: -22.5,
            },
            None,
        )
        .expect("distance commit");
    assert_eq!(committed.path, vec![FfiDirection8::Ne]);
    assert_eq!(
        committed.committed_coordinates,
        vec![FfiBoardCoordinate { x: 1, y: -1 }]
    );
}

#[test]
fn ffi_runtime_drives_two_stage_session_without_platform_semantics() {
    let runtime = SharedCoreRuntime::new(fixture("profile-diagonal-two-stage.valid.json"))
        .expect("runtime");
    assert_eq!(runtime.profile_id(), "fixture.diagonal-two-stage");

    let session = runtime
        .create_session(
            "base".into(),
            "kana.a".into(),
            runtime.profile_revision(),
            FfiSize {
                width: 100.0,
                height: 100.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
            None,
        )
        .expect("session");

    let first = session
        .move_to(FfiPoint { x: 40.0, y: 0.0 }, None)
        .expect("stage 1");
    assert_eq!(first.path, vec![FfiDirection8::E]);

    let second = session
        .move_to(FfiPoint { x: 80.0, y: 0.0 }, None)
        .expect("stage 2");
    assert_eq!(
        second.path,
        vec![FfiDirection8::E, FfiDirection8::E]
    );

    let final_state = session.touch_up(None).expect("touch up");
    assert_eq!(
        final_state.path,
        vec![FfiDirection8::E, FfiDirection8::E]
    );
    assert_eq!(final_state.dispatched_actions.len(), 1);
    assert_eq!(final_state.dispatched_actions[0].action_id, "cursor.move");
}


#[test]
fn ffi_runtime_exposes_profile_owned_layout_and_direction_hints() {
    let runtime = SharedCoreRuntime::new(fixture("profile-diagonal-two-stage.valid.json"))
        .expect("runtime");

    let layout = runtime.compile_layout("base".into()).expect("layout");
    assert_eq!(layout.layer_id, "base");
    assert_eq!(layout.keys.len(), 1);

    let key = &layout.keys[0];
    assert_eq!(key.id, "kana.a");
    assert_eq!(key.row, 0);
    assert_eq!(key.column, 0);
    assert_eq!(key.width, 1.0);
    assert_eq!(key.height, 1.0);
    assert!(key.eligible_directions.contains(&FfiDirection8::E));
    assert!(key.eligible_directions.contains(&FfiDirection8::Ne));

    let e = key
        .first_stage_presentations
        .iter()
        .find(|presentation| presentation.direction == FfiDirection8::E)
        .expect("east presentation");
    assert_eq!(e.text.as_deref(), Some("え"));
}


#[test]
fn ffi_validation_accepts_profile_v2_and_migrates_v1() {
    let v2 = fixture("profile-v2-board-chain.valid.json");
    let validation = validate_profile_json(v2.clone());
    assert!(validation.valid, "{:?}", validation.detail);

    let migrated = migrate_profile_to_v2_json(fixture("profile-diagonal-two-stage.valid.json"))
        .expect("migrate v1");
    assert!(migrated.contains("\"schema\": \"gesture-ime.profile.v2\""));
    let migrated_validation = validate_profile_json(migrated);
    assert!(migrated_validation.valid, "{:?}", migrated_validation.detail);
}

#[test]
fn ffi_v2_snapshot_exposes_board_state_and_local_origin_reset() {
    let runtime = SharedCoreRuntime::new(fixture("profile-v2-board-chain.valid.json"))
        .expect("v2 runtime");
    let session = runtime
        .create_session(
            "base".into(),
            "key.test".into(),
            runtime.profile_revision(),
            FfiSize {
                width: 100.0,
                height: 100.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
            None,
        )
        .expect("v2 session");

    let first = session
        .move_to(FfiPoint { x: 50.0, y: 0.0 }, Some(10))
        .expect("first board transition");
    assert_eq!(first.current_board_id, "board.e");
    assert_eq!(first.persistent_board_id, "board.root");
    assert_eq!(
        first.committed_coordinates,
        vec![FfiBoardCoordinate { x: 1, y: 0 }]
    );
    assert_eq!(first.board_transition_count, 1);
    assert_eq!(first.anchor, FfiPoint { x: 50.0, y: 0.0 });

    let second = session
        .move_to(FfiPoint { x: 50.0, y: -50.0 }, Some(20))
        .expect("second board selection");
    assert_eq!(
        second.selected_coordinate,
        Some(FfiBoardCoordinate { x: 0, y: -1 })
    );

    let final_state = session.touch_up(Some(30)).expect("touch up");
    assert_eq!(final_state.current_board_id, "board.root");
    assert_eq!(final_state.dispatched_actions.len(), 1);
    assert_eq!(final_state.dispatched_actions[0].action_id, "text.insert");
}


#[test]
fn ffi_layout_projection_tracks_persistent_board_baseline() {
    let runtime = SharedCoreRuntime::new(fixture("profile-v2-board-lifetime.valid.json"))
        .expect("runtime");

    let initial = runtime.compile_layout("base".into()).expect("initial layout");
    let initial_key = &initial.keys[0];
    assert!(initial_key.eligible_directions.contains(&FfiDirection8::E));

    let session = runtime
        .create_session(
            "base".into(),
            "key.test".into(),
            runtime.profile_revision(),
            FfiSize {
                width: 100.0,
                height: 100.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
            None,
        )
        .expect("session");

    let transitioned = session
        .move_to(FfiPoint { x: 50.0, y: 0.0 }, Some(10))
        .expect("persistent transition");
    assert_eq!(transitioned.persistent_board_id, "board.persistent");
    session.touch_up(Some(20)).expect("touch up");

    let updated = runtime.compile_layout("base".into()).expect("updated layout");
    let updated_key = &updated.keys[0];
    assert_eq!(updated_key.title.as_deref(), Some("T"));
    assert!(updated_key.eligible_directions.contains(&FfiDirection8::N));
    assert!(!updated_key.eligible_directions.contains(&FfiDirection8::E));
}


#[test]
fn ffi_runtime_expands_v2_macro_release_into_ordered_actions() {
    let mut profile: serde_json::Value =
        serde_json::from_str(&fixture("profile-v2-board-cardinal.valid.json"))
            .expect("v2 fixture JSON");
    profile["macros"] = serde_json::json!([{
        "id": "macro.sample",
        "actions": [
            {"actionID": "text.insert", "arguments": {"text": "A"}},
            {"actionID": "cursor.move", "arguments": {"offset": 1}}
        ]
    }]);
    profile["boards"][0]["entries"][0]["onRelease"] = serde_json::json!([
        {"actionID": "macro.run", "arguments": {"macro": "macro.sample"}}
    ]);

    let runtime = SharedCoreRuntime::new(profile.to_string()).expect("runtime");
    let session = runtime
        .create_session(
            "base".into(),
            "key.a".into(),
            runtime.profile_revision(),
            FfiSize { width: 100.0, height: 100.0 },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
            None,
        )
        .expect("session");

    let final_state = session.touch_up(Some(10)).expect("touch up");
    let ids = final_state
        .dispatched_actions
        .iter()
        .map(|action| action.action_id.as_str())
        .collect::<Vec<_>>();
    assert_eq!(ids, vec!["text.insert", "cursor.move"]);
    assert!(!ids.contains(&"macro.run"));
}

#[test]
fn ffi_runtime_expands_normalized_v1_macro_release() {
    let mut profile: serde_json::Value =
        serde_json::from_str(&fixture("profile-diagonal-two-stage.valid.json"))
            .expect("v1 fixture JSON");
    profile["macros"] = serde_json::json!([{
        "id": "macro.sample",
        "actions": [
            {"actionID": "text.insert", "arguments": {"text": "V"}},
            {"actionID": "cursor.move", "arguments": {"offset": -1}}
        ]
    }]);
    profile["bindingSets"][0]["bindings"][0]["behavior"]["onRelease"] = serde_json::json!([
        {"actionID": "macro.run", "arguments": {"macro": "macro.sample"}}
    ]);

    let runtime = SharedCoreRuntime::new(profile.to_string()).expect("runtime");
    let session = runtime
        .create_session(
            "base".into(),
            "kana.a".into(),
            runtime.profile_revision(),
            FfiSize { width: 100.0, height: 100.0 },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
            None,
        )
        .expect("session");

    let final_state = session.touch_up(Some(10)).expect("touch up");
    let ids = final_state
        .dispatched_actions
        .iter()
        .map(|action| action.action_id.as_str())
        .collect::<Vec<_>>();
    assert_eq!(ids, vec!["text.insert", "cursor.move"]);
    assert!(!ids.contains(&"macro.run"));
}

#[test]
fn ffi_runtime_expands_v2_macro_for_hold_start_and_repeat() {
    let mut profile: serde_json::Value =
        serde_json::from_str(&fixture("profile-v2-board-cardinal.valid.json"))
            .expect("v2 fixture JSON");
    profile["macros"] = serde_json::json!([{
        "id": "macro.timed",
        "actions": [
            {"actionID": "text.insert", "arguments": {"text": "H"}},
            {"actionID": "cursor.move", "arguments": {"offset": 1}}
        ]
    }]);
    profile["boards"][0]["entries"][0]["hold"] = serde_json::json!({
        "delayMs": 100,
        "onStart": [
            {"actionID": "macro.run", "arguments": {"macro": "macro.timed"}}
        ],
        "repeat": {
            "intervalMs": 50,
            "actions": [
                {"actionID": "macro.run", "arguments": {"macro": "macro.timed"}}
            ]
        },
        "suppressOnReleaseAfterStart": true
    });

    let runtime = SharedCoreRuntime::new(profile.to_string()).expect("runtime");
    let session = runtime
        .create_session(
            "base".into(),
            "key.a".into(),
            runtime.profile_revision(),
            FfiSize { width: 100.0, height: 100.0 },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
            None,
        )
        .expect("session");

    let started = session.advance_time(100).expect("hold start");
    let started_ids = started
        .dispatched_actions
        .iter()
        .map(|action| action.action_id.as_str())
        .collect::<Vec<_>>();
    assert_eq!(started_ids, vec!["text.insert", "cursor.move"]);

    let repeated = session.advance_time(150).expect("repeat");
    let repeated_ids = repeated
        .dispatched_actions
        .iter()
        .map(|action| action.action_id.as_str())
        .collect::<Vec<_>>();
    assert_eq!(
        repeated_ids,
        vec!["text.insert", "cursor.move", "text.insert", "cursor.move"]
    );
    assert!(!repeated_ids.contains(&"macro.run"));
}
