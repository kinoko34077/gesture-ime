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
    assert_eq!(updated_key.title.as_deref(), Some("P"));
    assert!(updated_key.eligible_directions.contains(&FfiDirection8::N));
    assert!(!updated_key.eligible_directions.contains(&FfiDirection8::E));
}
