//! #74 / #69 §6: flick-guide labels derive from target presentation;
//! source-scoped overrides change display only.

use gesture_ime_core::{FfiPoint, FfiSize, ProfileV3Codec, ProfileV3PlatformRuntime};
use serde_json::{json, Value};

fn text(t: &str, offset: i64) -> Value {
    json!({"presentation":{"text":{"base":t,"transforms":[]}},
           "onRelease":[{"actionID":"cursor.move","arguments":{"offset":offset}}]})
}
fn entry(id: &str, x: i64, y: i64, b: Value) -> Value {
    json!({"id":id,"rect":{"x":x,"y":y,"width":2,"height":2},"resolver":{"cases":[],"default":b}})
}
fn source(id: &str, x: i64, overrides: Option<Value>) -> Value {
    let mut e = entry(id, x, -1, json!({"presentation":{"text":{"base":id,"transforms":[]}},
        "transition":{"targetBoardRef":"board.flick","lifetime":"transient"}}));
    if let Some(o) = overrides { e["guideLabelOverrides"] = o; }
    e
}
fn profile(overrides: Option<Value>) -> Value {
    json!({"schema":"gesture-ime.profile.v3","id":"p.guides","name":"G","version":1,
      "gesturePolicy":{"deadZone":0.15,"initialCellCommitDistance":0.5,"subsequentCellCommitDistance":0.4,"angularHysteresisDegrees":8},
      "initialLayerRef":"l","layers":[{"id":"l","rootBoardRef":"board.root"}],
      "boards":[
        {"id":"board.root","entries":[source("a", -3, overrides), source("b", 1, None)]},
        {"id":"board.flick","entries":[
          entry("c", -1, -1, text("C", 1)), entry("e", 1, -1, text("E", 2)),
          entry("ne", 1, -3, text("NE", 3)), entry("far", 3, -1, text("FAR", 4))]}],
      "states":[],"transformTables":[],"macros":[]})
}

fn guides(rt: &ProfileV3PlatformRuntime, id: &str) -> Vec<(String, f64, f64, String, bool)> {
    let s = rt.direct_surface().unwrap();
    let e = s.entries.into_iter().find(|e| e.id == id).unwrap();
    e.guides.into_iter().map(|g| (g.target_entry_id, g.center_x, g.center_y, g.label, g.overridden)).collect()
}

#[test]
fn auto_labels_come_from_immediate_target_entries_including_diagonals() {
    let rt = ProfileV3PlatformRuntime::new(profile(None).to_string()).unwrap();
    let g = guides(&rt, "a");
    assert_eq!(g, vec![
        ("e".into(), 1.0, 0.0, "E".into(), false),
        ("ne".into(), 1.0, -1.0, "NE".into(), false),
    ], "origin and far entries are not keytop guides");
}

#[test]
fn override_is_source_scoped_and_display_only() {
    let rt = ProfileV3PlatformRuntime::new(profile(Some(json!({"e":"え"}))).to_string()).unwrap();
    assert_eq!(guides(&rt, "a")[0].3, "え");
    assert!(guides(&rt, "a")[0].4);
    // Reused target Board on another source keeps AUTO.
    assert_eq!(guides(&rt, "b")[0].3, "E");

    // Output unchanged: flicking east from "a" still dispatches offset 2.
    let s = rt.begin_session("a".into(), FfiSize{width:100.0,height:100.0}, FfiPoint{x:0.0,y:0.0}, 0).unwrap();
    s.move_to(FfiPoint{x:70.0,y:0.0}, Some(10)).unwrap();
    let done = s.touch_up(Some(20)).unwrap();
    assert!(done.runtime_dispatches[0].arguments_json.as_deref().unwrap().contains('2'));
}

#[test]
fn invalid_overrides_are_rejected() {
    for bad in [json!({"missing":"x"}), json!({"e":""}), json!({"e":"12345678901234567"})] {
        let bytes = serde_json::to_vec(&profile(Some(bad))).unwrap();
        let err = ProfileV3Codec::decode_and_validate(&bytes).unwrap_err();
        assert_eq!(err.code.as_str(), "E_INVALID_PRESENTATION");
    }
}
