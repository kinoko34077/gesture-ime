//! #77 / #69 §§5.3–5.5, §14: ordinary-keyboard floor on the built-in Profile,
//! expressed only through generic state/Actions/conditions and host facts.

use gesture_ime_core::{FfiPoint, FfiProfileV3RuntimeDispatch, FfiSize, ProfileV3PlatformRuntime};
use std::sync::Arc;

const PRODUCT_JSON: &str = include_str!("../../../App/KeyboardExtension/Resources/default-ja.json");
const CELL: FfiSize = FfiSize { width: 80.0, height: 80.0 };
const ORIGIN: FfiPoint = FfiPoint { x: 0.0, y: 0.0 };

fn runtime() -> Arc<ProfileV3PlatformRuntime> {
    ProfileV3PlatformRuntime::new(PRODUCT_JSON.to_owned()).unwrap()
}

fn text_of(runtime: &ProfileV3PlatformRuntime, id: &str) -> Option<String> {
    runtime
        .direct_surface()
        .unwrap()
        .entries
        .into_iter()
        .find(|entry| entry.id == id)?
        .text
}

fn tap(runtime: &ProfileV3PlatformRuntime, id: &str) -> Vec<FfiProfileV3RuntimeDispatch> {
    let session = runtime.begin_session(id.into(), CELL, ORIGIN, 0).unwrap();
    session.touch_up(Some(10)).unwrap().runtime_dispatches
}

fn inserted(dispatches: &[FfiProfileV3RuntimeDispatch]) -> String {
    dispatches
        .iter()
        .filter(|d| matches!(d.action_id.as_deref(), Some("text.directInsert" | "text.insert")))
        .filter_map(|d| d.arguments_json.clone())
        .collect::<Vec<_>>()
        .join("|")
}

#[test]
fn shift_cycles_lower_oneshot_caps_and_oneshot_returns_to_lower() {
    let runtime = runtime();
    runtime.set_layer("layer.alpha".into()).unwrap();
    assert_eq!(text_of(&runtime, "alpha.shift").as_deref(), Some("⇧"));
    assert_eq!(text_of(&runtime, "alpha.abc").as_deref(), Some("abc"));

    tap(&runtime, "alpha.shift");
    assert_eq!(text_of(&runtime, "alpha.shift").as_deref(), Some("⬆︎"));
    assert_eq!(text_of(&runtime, "alpha.abc").as_deref(), Some("ABC"));

    // One-shot: first letter upper, then back to lower.
    let first = inserted(&tap(&runtime, "alpha.abc"));
    assert!(first.contains("\"A\""), "{first}");
    assert_eq!(text_of(&runtime, "alpha.shift").as_deref(), Some("⇧"));
    let second = inserted(&tap(&runtime, "alpha.abc"));
    assert!(second.contains("\"a\""), "{second}");

    // Double tap → Caps Lock stays until toggled off.
    tap(&runtime, "alpha.shift");
    tap(&runtime, "alpha.shift");
    assert_eq!(text_of(&runtime, "alpha.shift").as_deref(), Some("⇪"));
    for _ in 0..2 {
        assert!(inserted(&tap(&runtime, "alpha.abc")).contains("\"A\""));
    }
    tap(&runtime, "alpha.shift");
    assert_eq!(text_of(&runtime, "alpha.shift").as_deref(), Some("⇧"));
}

#[test]
fn host_autocapitalization_fact_capitalizes_without_mutating_state() {
    let runtime = runtime();
    runtime.set_layer("layer.alpha".into()).unwrap();
    runtime.update_host_facts("default".into(), "default".into(), true, true).unwrap();
    assert_eq!(text_of(&runtime, "alpha.abc").as_deref(), Some("ABC"));
    assert!(inserted(&tap(&runtime, "alpha.abc")).contains("\"A\""));
    assert_eq!(text_of(&runtime, "alpha.shift").as_deref(), Some("⇧"));

    runtime.update_host_facts("default".into(), "default".into(), false, true).unwrap();
    assert!(inserted(&tap(&runtime, "alpha.abc")).contains("\"a\""));
}

#[test]
fn return_label_follows_host_return_key_and_conversion_wins() {
    let runtime = runtime();
    assert_eq!(text_of(&runtime, "text.enter").as_deref(), Some("改行"));
    for (key, label) in [("search", "検索"), ("send", "送信"), ("next", "次へ"), ("done", "完了")] {
        runtime.update_host_facts(key.into(), "default".into(), false, true).unwrap();
        assert_eq!(text_of(&runtime, "text.enter").as_deref(), Some(label));
    }
    // Unknown native values normalize into the closed vocabulary.
    runtime.update_host_facts("vendorSpecial".into(), "???".into(), false, true).unwrap();
    assert_eq!(text_of(&runtime, "text.enter").as_deref(), Some("改行"));

    runtime.update_host_facts("search".into(), "default".into(), false, true).unwrap();
    runtime.update_semantic_context("か".into(), true, true).unwrap();
    assert_eq!(text_of(&runtime, "text.enter").as_deref(), Some("確定"));
}

#[test]
fn backspace_tap_deletes_once_and_hold_repeats_bounded() {
    let runtime = runtime();
    let deletes = |d: &[FfiProfileV3RuntimeDispatch]| {
        d.iter().filter(|x| x.action_id.as_deref() == Some("edit.delete")).count()
    };
    assert_eq!(deletes(&tap(&runtime, "edit.delete")), 1);

    let session = runtime.begin_session("edit.delete".into(), CELL, ORIGIN, 0).unwrap();
    session.advance_time(399).unwrap();
    assert_eq!(deletes(&session.snapshot().unwrap().runtime_dispatches), 0);
    session.advance_time(400 + 70 * 5).unwrap();
    let held = session.touch_up(Some(400 + 70 * 5 + 10)).unwrap();
    // Hold start + 5 repeats; release suppressed after Hold started.
    assert_eq!(deletes(&held.runtime_dispatches), 6);
}

#[test]
fn space_tap_inserts_space_and_horizontal_drag_moves_cursor() {
    let runtime = runtime();
    let spaced = inserted(&tap(&runtime, "text.space"));
    assert!(spaced.contains("\" \""), "{spaced}");

    let session = runtime.begin_session("text.space".into(), CELL, ORIGIN, 0).unwrap();
    session.move_to(FfiPoint { x: -60.0, y: 0.0 }, Some(10)).unwrap();
    let left = session.touch_up(Some(20)).unwrap();
    let moves: Vec<_> = left
        .runtime_dispatches
        .iter()
        .filter(|d| d.action_id.as_deref() == Some("cursor.move"))
        .collect();
    assert_eq!(moves.len(), 1);
    assert!(moves[0].arguments_json.as_deref().unwrap().contains("-1"));
    assert!(!inserted(&left.runtime_dispatches).contains("\" \""));

    let session = runtime.begin_session("text.space".into(), CELL, ORIGIN, 0).unwrap();
    session.move_to(FfiPoint { x: 60.0, y: 0.0 }, Some(10)).unwrap();
    session.advance_time(10 + 300 + 80 * 3).unwrap();
    let held = session.touch_up(Some(10 + 300 + 80 * 3 + 5)).unwrap();
    assert_eq!(
        held.runtime_dispatches
            .iter()
            .filter(|d| d.action_id.as_deref() == Some("cursor.move"))
            .count(),
        4
    );
}
