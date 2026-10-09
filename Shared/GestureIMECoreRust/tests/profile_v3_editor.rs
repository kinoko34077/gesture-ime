use gesture_ime_core::ProfileEditorV3;
use serde_json::{Value, json};

const PRODUCT: &str = include_str!("../../../App/KeyboardExtension/Resources/default-ja.json");

fn value(json_text: &str) -> Value {
    serde_json::from_str(json_text).unwrap()
}

#[test]
fn key_presentation_rename_and_undo_redo_are_atomic() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original = value(&editor.export_json().unwrap());
    assert_eq!(editor.revision(), 0);
    assert!(!editor.can_undo());

    let command = json!({
        "type":"setEntryDefaultText",
        "boardId":"board.ja.root",
        "entryId":"kana.a",
        "text":"共通テスト"
    }).to_string();
    assert!(editor.apply_command_json(&command, 0).unwrap());
    let changed = value(&editor.export_json().unwrap());
    assert_ne!(original, changed);
    assert_eq!(editor.revision(), 1);
    assert!(editor.can_undo());
    assert!(!editor.can_redo());

    assert!(editor.undo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), original);
    assert_eq!(editor.revision(), 2);
    assert!(editor.can_redo());

    assert!(editor.redo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), changed);
    assert_eq!(editor.revision(), 3);
}

#[test]
fn invalid_and_stale_commands_do_not_mutate_or_add_history() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original = editor.export_json().unwrap();
    assert!(editor.apply_command_json(r#"{"type":"renameProfile","name":""}"#, 0).is_err());
    assert!(editor.apply_command_json(r#"{"type":"setEntryDefaultText","boardId":"missing","entryId":"kana.a","text":"x"}"#, 0).is_err());
    assert!(editor.apply_command_json(r#"{"type":"renameProfile","name":"X"}"#, 42).is_err());
    assert_eq!(editor.export_json().unwrap(), original);
    assert_eq!(editor.revision(), 0);
    assert!(!editor.can_undo());
}

#[test]
fn no_op_and_rename_are_revision_checked() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original: Value = value(&editor.export_json().unwrap());
    let name = original["name"].as_str().unwrap();
    let noop = json!({"type":"renameProfile","name":name}).to_string();
    assert!(!editor.apply_command_json(&noop, 0).unwrap());
    assert_eq!(editor.revision(), 0);
    let command = json!({"type":"renameProfile","name":"Web・iOS・Android共通"}).to_string();
    assert!(editor.apply_command_json(&command, 0).unwrap());
    assert_eq!(editor.revision(), 1);
    assert_eq!(value(&editor.export_json().unwrap())["name"], "Web・iOS・Android共通");
}
