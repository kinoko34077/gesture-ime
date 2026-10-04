//! #101 / frozen #95 §F6.3: reverse rows expand into the flat runtime map
//! deterministically; conflicts are rejected.

use gesture_ime_core::{FfiPoint, FfiSize, ProfileV3Codec, ProfileV3PlatformRuntime};
use serde_json::{json, Value};

fn profile(table: Value) -> Value {
    json!({"schema":"gesture-ime.profile.v3","id":"p.rev","name":"R","version":1,
      "gesturePolicy":{"deadZone":0.15,"initialCellCommitDistance":0.5,"subsequentCellCommitDistance":0.4,"angularHysteresisDegrees":8},
      "initialLayerRef":"l","layers":[{"id":"l","rootBoardRef":"b"}],
      "boards":[{"id":"b","entries":[{"id":"k","rect":{"x":-1,"y":-1,"width":2,"height":2},
        "resolver":{"cases":[],"default":{"onRelease":[{"actionID":"text.transform","arguments":{"table":"t"}}]}}}]}],
      "states":[],"transformTables":[table],"macros":[]})
}

fn tap(p: &Value, composition: &str) -> Option<String> {
    let rt = ProfileV3PlatformRuntime::new(p.to_string()).unwrap();
    rt.update_semantic_context(composition.into(), false, false).unwrap();
    let s = rt.begin_session("k".into(), FfiSize { width: 80.0, height: 80.0 }, FfiPoint { x: 0.0, y: 0.0 }, 0).unwrap();
    s.touch_up(Some(5)).unwrap().runtime_dispatches.first()?.replacement.clone()
}

fn validate(p: &Value) -> Result<(), String> {
    ProfileV3Codec::decode_and_validate(&serde_json::to_vec(p).unwrap())
        .map(|_| ())
        .map_err(|e| format!("{}:{}", e.code.as_str(), e.detail.unwrap_or_default()))
}

#[test]
fn row_reverse_generates_back_mapping() {
    let p = profile(json!({"id":"t","entries":[{"from":"a","to":"A","reverse":true},{"from":"b","to":"B"}]}));
    assert_eq!(tap(&p, "a"), Some("A".into()));
    assert_eq!(tap(&p, "A"), Some("a".into()));
    assert_eq!(tap(&p, "B"), None, "non-reversible row has no back mapping");
}

#[test]
fn reverse_all_applies_to_every_row_and_row_flags_are_irrelevant() {
    let p = profile(json!({"id":"t","reverseAll":true,"entries":[{"from":"a","to":"A","reverse":false},{"from":"b","to":"B"}]}));
    assert_eq!(tap(&p, "A"), Some("a".into()));
    assert_eq!(tap(&p, "B"), Some("b".into()));
}

#[test]
fn identical_generated_pair_merges() {
    let p = profile(json!({"id":"t","entries":[{"from":"a","to":"A","reverse":true},{"from":"A","to":"a"}]}));
    assert!(validate(&p).is_ok());
    assert_eq!(tap(&p, "A"), Some("a".into()));
}

#[test]
fn conflicting_reverse_source_is_rejected_with_table_and_source() {
    let p = profile(json!({"id":"t","entries":[{"from":"a","to":"A","reverse":true},{"from":"A","to":"x"}]}));
    assert_eq!(validate(&p).unwrap_err(), "E_DUPLICATE_TRANSFORM_SOURCE:t:A");
    let q = profile(json!({"id":"t","reverseAll":true,"entries":[{"from":"a","to":"X"},{"from":"b","to":"X"}]}));
    assert_eq!(validate(&q).unwrap_err(), "E_DUPLICATE_TRANSFORM_SOURCE:t:X");
}

#[test]
fn empty_reverse_target_is_invalid() {
    let p = profile(json!({"id":"t","entries":[{"from":"a","to":"","reverse":true}]}));
    assert!(validate(&p).unwrap_err().starts_with("E_INVALID_TRANSFORM_REFERENCE"));
}

#[test]
fn tables_without_reverse_are_unchanged() {
    let p = profile(json!({"id":"t","title":"表","entries":[{"from":"a","to":"A","groupPath":["g"]}]}));
    assert!(validate(&p).is_ok());
    assert_eq!(tap(&p, "a"), Some("A".into()));
    assert_eq!(tap(&p, "A"), None);
}
