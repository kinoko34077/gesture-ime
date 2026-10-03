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
