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


#[test]
fn board_transition_change_preserves_key_behavior_and_supports_undo_redo() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original = value(&editor.export_json().unwrap());
    let root = original["boards"].as_array().unwrap()
        .iter().find(|board| board["id"] == "board.ja.root").unwrap();
    let before = root["entries"].as_array().unwrap()
        .iter().find(|entry| entry["id"] == "kana.a").unwrap().clone();
    let command = json!({
        "type": "setEntryDefaultTransition",
        "boardId": "board.ja.root",
        "entryId": "kana.a",
        "targetBoardId": "board.base.kana.ka.flick",
        "lifetime": "persistent"
    }).to_string();
    assert!(editor.apply_command_json(&command, 0).unwrap());
    let changed = value(&editor.export_json().unwrap());
    let changed_root = changed["boards"].as_array().unwrap()
        .iter().find(|board| board["id"] == "board.ja.root").unwrap();
    let after = changed_root["entries"].as_array().unwrap()
        .iter().find(|entry| entry["id"] == "kana.a").unwrap();
    assert_eq!(after["resolver"]["default"]["transition"]["targetBoardRef"], "board.base.kana.ka.flick");
    assert_eq!(after["resolver"]["default"]["transition"]["lifetime"], "persistent");
    let mut expected = before.clone();
    expected["resolver"]["default"]["transition"] = after["resolver"]["default"]["transition"].clone();
    assert_eq!(*after, expected, "do not alter presentation, action, hold or cases");

    assert!(editor.undo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), original);
    assert!(editor.redo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), changed);
    assert!(!editor.apply_command_json(&command, editor.revision()).unwrap());

    let remove = json!({
        "type":"setEntryDefaultTransition",
        "boardId":"board.ja.root", "entryId":"kana.a",
        "targetBoardId":null,"lifetime":null
    }).to_string();
    assert!(editor.apply_command_json(&remove, editor.revision()).unwrap());
    let cleared = value(&editor.export_json().unwrap());
    let entry = cleared["boards"].as_array().unwrap()
        .iter().find(|board| board["id"] == "board.ja.root").unwrap()["entries"].as_array().unwrap()
        .iter().find(|entry| entry["id"] == "kana.a").unwrap();
    assert!(entry["resolver"]["default"].get("transition").is_none());
}

#[test]
fn invalid_transition_reference_or_lifetime_is_atomic() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original = editor.export_json().unwrap();
    for command in [
        json!({"type":"setEntryDefaultTransition","boardId":"board.ja.root","entryId":"kana.a","targetBoardId":"board.absent","lifetime":"transient"}),
        json!({"type":"setEntryDefaultTransition","boardId":"board.absent","entryId":"kana.a","targetBoardId":"board.base.kana.a.flick","lifetime":"transient"}),
        json!({"type":"setEntryDefaultTransition","boardId":"board.ja.root","entryId":"absent","targetBoardId":"board.base.kana.a.flick","lifetime":"transient"}),
        json!({"type":"setEntryDefaultTransition","boardId":"board.ja.root","entryId":"kana.a"}),
        json!({"type":"setEntryDefaultTransition","boardId":"board.ja.root","entryId":"kana.a","targetBoardId":"board.base.kana.a.flick"}),
        json!({"type":"setEntryDefaultTransition","boardId":"board.ja.root","entryId":"kana.a","targetBoardId":null,"lifetime":"transient"}),
        json!({"type":"setEntryDefaultTransition","boardId":"board.ja.root","entryId":"kana.a","targetBoardId":"board.base.kana.a.flick","lifetime":"random"}),
    ] {
        assert!(editor.apply_command_json(&command.to_string(), 0).is_err(), "{command}");
        assert_eq!(editor.export_json().unwrap(), original);
        assert_eq!(editor.revision(), 0);
        assert!(!editor.can_undo());
    }
}


// M3g: macro IDs are internal/stable; user names are distinct and unique.
#[test]
fn macro_create_rename_actions_and_undo_roundtrip() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original = value(&editor.export_json().unwrap());
    let create = json!({
        "type":"createMacro",
        "name":"  あいさつ  ",
        "actions":[{"actionID":"noop","arguments":{}}]
    });
    assert!(editor.apply_command_json(&create.to_string(), 0).unwrap());
    let first = value(&editor.export_json().unwrap());
    let macros = first["macros"].as_array().unwrap();
    assert_eq!(macros.len(), original["macros"].as_array().unwrap().len() + 1);
    let created = macros.last().unwrap();
    let macro_id = created["id"].as_str().unwrap().to_owned();
    assert_eq!(created["name"], "あいさつ");
    assert_eq!(created["actions"][0]["actionID"], "noop");

    let rename = json!({"type":"renameMacro","macroId":macro_id,"name":"挨拶"});
    assert!(editor.apply_command_json(&rename.to_string(), editor.revision()).unwrap());
    let update = json!({
        "type":"setMacroActions",
        "macroId":macro_id,
        "actions":[{"actionID":"system.dismissKeyboard","arguments":{}}]
    });
    assert!(editor.apply_command_json(&update.to_string(), editor.revision()).unwrap());
    let changed = value(&editor.export_json().unwrap());
    let macro_after = changed["macros"].as_array().unwrap().last().unwrap();
    assert_eq!(macro_after["id"], created["id"], "rename/action edits never rewrite stable IDs");
    assert_eq!(macro_after["name"], "挨拶");
    assert_eq!(macro_after["actions"][0]["actionID"], "system.dismissKeyboard");
    assert_eq!(ProfileEditorV3::open(&editor.export_json().unwrap()).unwrap()
        .export_json().unwrap(), editor.export_json().unwrap());

    assert!(editor.undo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap())["macros"].as_array().unwrap()
        .last().unwrap()["actions"][0]["actionID"], "noop");
    assert!(editor.undo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap())["macros"].as_array().unwrap()
        .last().unwrap()["name"], "あいさつ");
    assert!(editor.undo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), original);
    assert!(editor.redo().unwrap());
    assert!(editor.redo().unwrap());
    assert!(editor.redo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), changed);
}

#[test]
fn macro_duplicate_names_bad_actions_stale_revision_are_atomic() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let create = json!({"type":"createMacro","name":"Sample","actions":[]});
    assert!(editor.apply_command_json(&create.to_string(), 0).unwrap());
    let before = editor.export_json().unwrap();
    let rev = editor.revision();
    let id = value(&before)["macros"].as_array().unwrap().last().unwrap()["id"]
        .as_str().unwrap().to_owned();

    let rejected = [
        json!({"type":"createMacro","name":" sample ","actions":[]}),
        json!({"type":"createMacro","name":"   ","actions":[]}),
        json!({"type":"createMacro","name":"X".repeat(101),"actions":[]}),
        json!({"type":"renameMacro","macroId":"missing","name":"Another"}),
        json!({"type":"setMacroActions","macroId":id,"actions":[
            {"actionID":"macro.run","arguments":{"macro":id}}
        ]}),
        json!({"type":"setMacroActions","macroId":id,"actions":[
            {"actionID":"missing.action","arguments":{}}
        ]}),
        json!({"type":"setMacroActions","macroId":id}),
    ];
    for command in rejected {
        assert!(editor.apply_command_json(&command.to_string(), rev).is_err(), "{command}");
        assert_eq!(editor.revision(), rev);
        assert_eq!(editor.export_json().unwrap(), before);
    }
    assert!(editor.apply_command_json(&json!({"type":"renameMacro","macroId":id,"name":"sample"}).to_string(), rev).unwrap());
    assert!(!editor.apply_command_json(&json!({"type":"renameMacro","macroId":id,"name":"sample"}).to_string(), editor.revision()).unwrap());
    let err = editor.apply_command_json(&create.to_string(), rev);
    assert!(err.is_err(), "stale revision must reject even valid command");
}
