use gesture_ime_core::{ProfileV3Codec, ProfileV3Editor};
use serde_json::Value;

const PRODUCT: &str = include_str!("../../../App/KeyboardExtension/Resources/default-ja.json");

fn entry<'a>(editor: &'a ProfileV3Editor) -> &'a gesture_ime_core::BoardEntryV3 {
    editor.profile().boards.iter()
        .find(|board| board.id == "board.ja.root").unwrap()
        .entries.iter().find(|entry| entry.id == "text.enter").unwrap()
}

fn state(editor: &ProfileV3Editor) -> Value {
    serde_json::from_str(&editor.state_json().unwrap()).unwrap()
}

#[test]
fn editing_real_product_preserves_nonpresentation_behavior_and_can_undo_redo() {
    let mut editor = ProfileV3Editor::open(PRODUCT).unwrap();
    let original = state(&editor);
    let before = entry(&editor).clone();

    assert!(editor.set_entry_default_text("board.ja.root", "text.enter", "テスト".into()).unwrap());
    let after = entry(&editor);
    assert_eq!(after.resolver.default.presentation.as_ref().unwrap().text.as_ref().unwrap().base, "テスト");
    assert_eq!(after.resolver.default.on_release, before.resolver.default.on_release);
    assert_eq!(after.resolver.default.transition, before.resolver.default.transition);
    assert_eq!(after.resolver.default.hold, before.resolver.default.hold);
    assert_eq!(after.resolver.cases, before.resolver.cases);
    assert_eq!(after.guide_label_overrides, before.guide_label_overrides);
    assert!(editor.can_undo());
    assert!(!editor.can_redo());
    let edited = state(&editor);

    assert!(!editor.set_entry_default_text("board.ja.root", "text.enter", "テスト".into()).unwrap());
    assert_eq!(state(&editor), edited);

    assert!(editor.undo());
    assert_eq!(state(&editor)["profile"], original["profile"]);
    assert!(editor.can_redo());
    assert!(editor.redo());
    assert_eq!(state(&editor), edited);
    assert!(!editor.can_redo());

    // Importing exported edited JSON must meet canonical validation.
    let exported = editor.export_json().unwrap();
    let restored = ProfileV3Codec::decode_and_validate(exported.as_bytes()).unwrap();
    assert_eq!(restored, *editor.profile());
}

#[test]
fn failed_edit_does_not_mutate_document_or_undo_stack() {
    let mut editor = ProfileV3Editor::open(PRODUCT).unwrap();
    let original = state(&editor);
    assert!(editor.set_entry_default_text("missing", "text.enter", "x".into()).is_err());
    assert!(editor.set_entry_default_text("board.ja.root", "missing", "x".into()).is_err());
    assert_eq!(state(&editor), original);
    assert!(!editor.undo());
}

#[test]
fn invalid_document_is_rejected_before_session_creation() {
    assert!(ProfileV3Editor::open("{").is_err());
}
