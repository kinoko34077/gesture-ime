use gesture_ime_core::{
    validate_profile_json, FfiDirection8, FfiPoint, FfiSize, SharedCoreRuntime,
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
