//! #79 / #69 §11.4: authoring groupPath on transform entries never changes
//! runtime transform resolution.

use gesture_ime_core::{FfiPoint, FfiSize, ProfileV3PlatformRuntime};
use serde_json::Value;

const PRODUCT_JSON: &str = include_str!("../../../App/KeyboardExtension/Resources/default-ja.json");

fn small_tap(json: String, composition: &str) -> Option<String> {
    let rt = ProfileV3PlatformRuntime::new(json).unwrap();
    rt.update_semantic_context(composition.into(), false, false).unwrap();
    let s = rt
        .begin_session("kana.transform".into(), FfiSize { width: 80.0, height: 80.0 }, FfiPoint { x: 0.0, y: 0.0 }, 0)
        .unwrap();
    s.touch_up(Some(10)).unwrap().runtime_dispatches.first()?.replacement.clone()
}

#[test]
fn grouped_tables_resolve_identically_to_flat_tables() {
    let mut grouped: Value = serde_json::from_str(PRODUCT_JSON).unwrap();
    for table in grouped["transformTables"].as_array_mut().unwrap() {
        for (i, entry) in table["entries"].as_array_mut().unwrap().iter_mut().enumerate() {
            entry["groupPath"] = serde_json::json!(["グループ", format!("g{}", i % 3)]);
        }
    }
    let grouped = grouped.to_string();
    for input in ["つ", "や", "あ", "か", "x"] {
        assert_eq!(
            small_tap(PRODUCT_JSON.to_owned(), input),
            small_tap(grouped.clone(), input),
            "{input}"
        );
    }
}
