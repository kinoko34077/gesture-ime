use gesture_ime_core::{
    FfiPoint, FfiProfileV3BoardContext, FfiProfileV3DispatchKind, FfiSize,
    ProfileV3Codec, ProfileV3PlatformRuntime,
};

const PRODUCT_JSON: &str = include_str!(
    "../../../App/KeyboardExtension/Resources/default-ja.json"
);

fn runtime() -> std::sync::Arc<ProfileV3PlatformRuntime> {
    ProfileV3PlatformRuntime::new(PRODUCT_JSON.to_owned()).unwrap()
}

fn entry_text<'a>(
    surface: &'a gesture_ime_core::FfiProfileV3BoardSurface,
    id: &str,
) -> Option<&'a str> {
    surface
        .entries
        .iter()
        .find(|entry| entry.id == id)?
        .text
        .as_deref()
}

#[test]
fn a5_builtin_profile_is_valid_canonical_v3_without_legacy_utility_panels() {
    let profile = ProfileV3Codec::decode_and_validate(PRODUCT_JSON.as_bytes()).unwrap();

    assert_eq!(profile.schema, "gesture-ime.profile.v3");
    assert_eq!(profile.id, "builtin.ja.product");
    assert_eq!(profile.initial_layer_ref, "layer.ja");

    let layer_ids = profile
        .layers
        .iter()
        .map(|layer| layer.id.as_str())
        .collect::<std::collections::HashSet<_>>();

    for id in [
        "layer.ja",
        "layer.numbers",
        "layer.alpha",
        "layer.symbols",
        "layer.utility.phrase",
        "layer.utility.emoji",
        "layer.utility.emoticon",
    ] {
        assert!(layer_ids.contains(id), "missing {id}");
    }

    assert!(!PRODUCT_JSON.contains("\"panel.open\""));
    assert!(!PRODUCT_JSON.contains("\"keyDefinitions\""));
    assert!(!PRODUCT_JSON.contains("\"layouts\""));
    assert!(!PRODUCT_JSON.contains("\"bindingSets\""));
}

#[test]
fn a5_builtin_return_resolves_newline_or_conversion_commit_from_runtime_fact() {
    let runtime = runtime();

    let idle = runtime.direct_surface().unwrap();
    assert_eq!(idle.layer_id, "layer.ja");
    assert_eq!(entry_text(&idle, "text.enter"), Some("改行"));

    let newline = runtime
        .begin_session(
            "text.enter".into(),
            FfiSize {
                width: 80.0,
                height: 80.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
        )
        .unwrap()
        .touch_up(Some(10))
        .unwrap();

    assert_eq!(newline.runtime_dispatches.len(), 1);
    assert_eq!(
        newline.runtime_dispatches[0].kind,
        FfiProfileV3DispatchKind::Action
    );
    assert_eq!(
        newline.runtime_dispatches[0].action_id.as_deref(),
        Some("text.insert")
    );
    assert_eq!(
        newline.runtime_dispatches[0].arguments_json.as_deref(),
        Some("{\"text\":\"\\n\"}")
    );

    runtime
        .update_semantic_context(String::new(), true, true)
        .unwrap();
    assert_eq!(
        entry_text(&runtime.direct_surface().unwrap(), "text.enter"),
        Some("確定")
    );

    let commit = runtime
        .begin_session(
            "text.enter".into(),
            FfiSize {
                width: 80.0,
                height: 80.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            20,
        )
        .unwrap()
        .touch_up(Some(30))
        .unwrap();

    assert_eq!(commit.runtime_dispatches.len(), 1);
    assert_eq!(
        commit.runtime_dispatches[0].action_id.as_deref(),
        Some("conversion.commit")
    );
}

#[test]
fn a5_builtin_kana_transform_board_uses_neutral_center_and_explicit_transforms() {
    let runtime = runtime();

    runtime
        .update_semantic_context("か".into(), false, false)
        .unwrap();

    let neutral = runtime
        .begin_session(
            "kana.transform".into(),
            FfiSize {
                width: 80.0,
                height: 80.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
        )
        .unwrap();

    let initial = neutral.snapshot().unwrap();
    assert_eq!(initial.current_board_id, "board.ja.transform");
    assert_eq!(initial.context, FfiProfileV3BoardContext::Relative);
    assert_eq!(
        entry_text(&initial.surface, "transform.center"),
        Some("小゛゜")
    );

    let neutral_result = neutral.touch_up(Some(10)).unwrap();
    assert!(neutral_result.runtime_dispatches.is_empty());

    let dakuten = runtime
        .begin_session(
            "kana.transform".into(),
            FfiSize {
                width: 80.0,
                height: 80.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            20,
        )
        .unwrap();
    dakuten
        .move_to(FfiPoint { x: 0.0, y: -80.0 }, Some(30))
        .unwrap();
    let voiced = dakuten.touch_up(Some(40)).unwrap();
    assert_eq!(voiced.runtime_dispatches.len(), 1);
    let effect = &voiced.runtime_dispatches[0];
    assert_eq!(
        effect.kind,
        FfiProfileV3DispatchKind::CompositionTailTransform
    );
    assert_eq!(effect.table_id.as_deref(), Some("kana.dakuten"));
    assert_eq!(effect.matched_source.as_deref(), Some("か"));
    assert_eq!(effect.replacement.as_deref(), Some("が"));

    runtime
        .update_semantic_context("つ".into(), false, false)
        .unwrap();
    let small = runtime
        .begin_session(
            "kana.transform".into(),
            FfiSize {
                width: 80.0,
                height: 80.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            50,
        )
        .unwrap();
    small
        .move_to(FfiPoint { x: -80.0, y: 0.0 }, Some(60))
        .unwrap();
    let small_result = small.touch_up(Some(70)).unwrap();
    assert_eq!(
        small_result.runtime_dispatches[0].table_id.as_deref(),
        Some("kana.small")
    );
    assert_eq!(
        small_result.runtime_dispatches[0].replacement.as_deref(),
        Some("っ")
    );

    runtime
        .update_semantic_context("は".into(), false, false)
        .unwrap();
    let handakuten = runtime
        .begin_session(
            "kana.transform".into(),
            FfiSize {
                width: 80.0,
                height: 80.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            80,
        )
        .unwrap();
    handakuten
        .move_to(FfiPoint { x: 80.0, y: 0.0 }, Some(90))
        .unwrap();
    let semi_voiced = handakuten.touch_up(Some(100)).unwrap();
    assert_eq!(
        semi_voiced.runtime_dispatches[0].table_id.as_deref(),
        Some("kana.handakuten")
    );
    assert_eq!(
        semi_voiced.runtime_dispatches[0].replacement.as_deref(),
        Some("ぱ")
    );
}

#[test]
fn a5_builtin_alpha_shift_uses_profile_state_and_resolved_string_table() {
    let runtime = runtime();
    runtime.set_layer("layer.alpha".into()).unwrap();

    let lower = runtime.direct_surface().unwrap();
    assert_eq!(entry_text(&lower, "alpha.abc"), Some("abc"));
    assert_eq!(entry_text(&lower, "alpha.shift"), Some("⇧"));

    let shift = runtime
        .begin_session(
            "alpha.shift".into(),
            FfiSize {
                width: 80.0,
                height: 80.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
        )
        .unwrap();
    let shifted = shift.touch_up(Some(10)).unwrap();
    assert!(shifted.runtime_dispatches.is_empty());

    let upper = runtime.direct_surface().unwrap();
    assert_eq!(entry_text(&upper, "alpha.abc"), Some("ABC"));
    assert_eq!(entry_text(&upper, "alpha.shift"), Some("⇪"));

    let abc = runtime
        .begin_session(
            "alpha.abc".into(),
            FfiSize {
                width: 80.0,
                height: 80.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            20,
        )
        .unwrap()
        .touch_up(Some(30))
        .unwrap();

    assert_eq!(abc.runtime_dispatches.len(), 1);
    assert_eq!(
        abc.runtime_dispatches[0].action_id.as_deref(),
        Some("text.directInsert")
    );
    assert_eq!(
        abc.runtime_dispatches[0].arguments_json.as_deref(),
        Some("{\"text\":\"ABC\"}")
    );
}

#[test]
fn a5_builtin_punctuation_has_real_diagonal_relative_destination() {
    let runtime = runtime();

    let flick = runtime
        .begin_session(
            "punctuation".into(),
            FfiSize {
                width: 80.0,
                height: 80.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
        )
        .unwrap();

    let initial = flick.snapshot().unwrap();
    assert_eq!(initial.context, FfiProfileV3BoardContext::Relative);
    assert!(initial
        .surface
        .entries
        .iter()
        .any(|entry| entry.id == "punctuation.ne"));

    let moved = flick
        .move_to(FfiPoint { x: 80.0, y: -80.0 }, Some(10))
        .unwrap();
    assert_eq!(
        moved.current_endpoint_entry_id.as_deref(),
        Some("punctuation.ne")
    );

    let released = flick.touch_up(Some(20)).unwrap();
    assert_eq!(
        released.runtime_dispatches[0].action_id.as_deref(),
        Some("text.insert")
    );
    assert_eq!(
        released.runtime_dispatches[0].arguments_json.as_deref(),
        Some("{\"text\":\"・\"}")
    );
}

#[test]
fn a5_builtin_utility_layers_are_full_profile_layers_and_pop_restores_previous_frame() {
    let runtime = runtime();

    runtime.push_layer("layer.utility.phrase".into()).unwrap();
    let phrase = runtime.direct_surface().unwrap();
    assert_eq!(phrase.layer_id, "layer.utility.phrase");
    assert_eq!(phrase.board_id, "board.utility.phrase");
    assert!(phrase.entries.iter().any(|entry| entry.id == "utility.back"));
    assert!(phrase
        .entries
        .iter()
        .any(|entry| entry.text.as_deref() == Some("ありがとう")));

    runtime.set_layer("layer.utility.emoji".into()).unwrap();
    let emoji = runtime.direct_surface().unwrap();
    assert_eq!(emoji.layer_id, "layer.utility.emoji");
    assert!(emoji
        .entries
        .iter()
        .any(|entry| entry.text.as_deref() == Some("😀")));

    runtime.set_layer("layer.utility.emoticon".into()).unwrap();
    let emoticon = runtime.direct_surface().unwrap();
    assert_eq!(emoticon.layer_id, "layer.utility.emoticon");
    assert!(emoticon
        .entries
        .iter()
        .any(|entry| entry.text.as_deref() == Some("(・ω・)")));

    runtime.pop_layer().unwrap();
    assert_eq!(runtime.active_layer_id().unwrap(), "layer.ja");
    assert_eq!(runtime.direct_surface().unwrap().board_id, "board.ja.root");
}
