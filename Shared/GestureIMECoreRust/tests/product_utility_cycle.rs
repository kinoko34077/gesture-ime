//! #99 / frozen #95 §F3: built-in 小゛゜ tap cycles through the generic
//! `kana.utilityCycle` TransformTable; flick directions keep their tables.

use gesture_ime_core::{FfiPoint, FfiSize, ProfileV3PlatformRuntime};
use std::sync::Arc;

const PRODUCT_JSON: &str = include_str!("../../../App/KeyboardExtension/Resources/default-ja.json");

fn runtime() -> Arc<ProfileV3PlatformRuntime> {
    ProfileV3PlatformRuntime::new(PRODUCT_JSON.to_owned()).unwrap()
}

/// Tap 小゛゜ with `composition`; returns (table, replacement) or None.
fn tap(rt: &ProfileV3PlatformRuntime, composition: &str) -> Option<(String, String)> {
    rt.update_semantic_context(composition.into(), false, false).unwrap();
    let s = rt
        .begin_session("kana.transform".into(), FfiSize { width: 80.0, height: 80.0 }, FfiPoint { x: 0.0, y: 0.0 }, 0)
        .unwrap();
    let d = s.touch_up(Some(10)).unwrap().runtime_dispatches;
    let first = d.first()?;
    Some((first.table_id.clone()?, first.replacement.clone()?))
}

fn cycle(rt: &ProfileV3PlatformRuntime, start: &str, expected: &[&str]) {
    let mut current = start.to_owned();
    for next in expected {
        let (table, replacement) = tap(rt, &current).unwrap_or_else(|| panic!("no dispatch for {current}"));
        assert_eq!(table, "kana.utilityCycle");
        assert_eq!(&replacement, next, "after {current}");
        current = replacement;
    }
}

#[test]
fn repeated_taps_follow_frozen_family_cycles() {
    let rt = runtime();
    cycle(&rt, "は", &["ば", "ぱ", "は"]);
    cycle(&rt, "つ", &["っ", "づ", "つ"]);
    cycle(&rt, "う", &["ぅ", "ゔ", "う"]);
    cycle(&rt, "か", &["が", "か"]);
    cycle(&rt, "や", &["ゃ", "や"]);
    cycle(&rt, "わ", &["ゎ", "わ"]);
    // Tail-only: earlier characters are untouched.
    assert_eq!(tap(&rt, "ほんと"), Some(("kana.utilityCycle".into(), "ど".into())));
}

#[test]
fn unmatched_tail_dispatches_nothing() {
    let rt = runtime();
    for tail in ["", "ん", "ー", "a", "ゕ", "カ"] {
        assert_eq!(tap(&rt, tail), None, "{tail:?}");
    }
}

#[test]
fn flick_directions_keep_explicit_tables() {
    let rt = runtime();
    for (dx, dy, table, comp, out) in [
        (-80.0, 0.0, "kana.small", "つ", "っ"),
        (0.0, -80.0, "kana.dakuten", "か", "が"),
        (80.0, 0.0, "kana.handakuten", "は", "ぱ"),
    ] {
        rt.update_semantic_context(comp.into(), false, false).unwrap();
        let s = rt
            .begin_session("kana.transform".into(), FfiSize { width: 80.0, height: 80.0 }, FfiPoint { x: 0.0, y: 0.0 }, 0)
            .unwrap();
        s.move_to(FfiPoint { x: dx, y: dy }, Some(5)).unwrap();
        let d = s.touch_up(Some(10)).unwrap().runtime_dispatches;
        assert_eq!(d[0].table_id.as_deref(), Some(table));
        assert_eq!(d[0].replacement.as_deref(), Some(out));
    }
}

#[test]
fn utility_cycle_table_is_exactly_the_frozen_65_unique_rows() {
    let v: serde_json::Value = serde_json::from_str(PRODUCT_JSON).unwrap();
    let t = v["transformTables"].as_array().unwrap().iter()
        .find(|t| t["id"] == "kana.utilityCycle").unwrap();
    let entries = t["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 65);
    let mut seen = std::collections::HashSet::new();
    for e in entries { assert!(seen.insert(e["from"].as_str().unwrap().to_owned())); }
}
