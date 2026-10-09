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


// M3i: Key->Macro invocation is authored only by the common revisioned Rust
// Core. This is not iOS/Android host delivery or browser JS macro execution.
#[test]
fn key_macro_invocation_preserves_other_behavior_and_undo_redo() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let create = json!({"type":"createMacro","name":"あいさつ",
        "actions":[{"actionID":"text.insert",
            "arguments":{"text":{"base":"こんにちは！","transforms":[]}}}]});
    assert!(editor.apply_command_json(&create.to_string(), 0).unwrap());
    let macro_id = value(&editor.export_json().unwrap())["macros"]
        .as_array().unwrap().last().unwrap()["id"].as_str().unwrap().to_owned();

    let before = value(&editor.export_json().unwrap());
    let get_entry = |doc: &Value| {
        doc["boards"].as_array().unwrap().iter()
            .find(|board| board["id"] == "board.ja.root").unwrap()["entries"]
            .as_array().unwrap().iter()
            .find(|entry| entry["id"] == "kana.a").unwrap().clone()
    };
    let before_entry = get_entry(&before);
    let attach = json!({"type":"setEntryDefaultMacroInvocation",
        "boardId":"board.ja.root","entryId":"kana.a",
        "macroId":macro_id,"enabled":true}).to_string();
    assert!(editor.apply_command_json(&attach, editor.revision()).unwrap());
    let after = value(&editor.export_json().unwrap());
    let attached = get_entry(&after);
    let actions = attached["resolver"]["default"]["onRelease"].as_array().unwrap();
    assert_eq!(actions.len(), 1);
    assert_eq!(actions[0]["actionID"], "macro.run");
    assert_eq!(actions[0]["arguments"]["macro"], macro_id);
    let mut expected = before_entry.clone();
    expected["resolver"]["default"]["onRelease"] = attached["resolver"]["default"]["onRelease"].clone();
    assert_eq!(attached, expected, "key Theme/presentation/transition/Hold/conditions stay unchanged");
    assert!(!editor.apply_command_json(&attach, editor.revision()).unwrap(),
        "already attached Macro must not add a duplicate or extra Undo");

    let rename = json!({"type":"renameMacro","macroId":macro_id,"name":"挨拶"}).to_string();
    assert!(editor.apply_command_json(&rename, editor.revision()).unwrap());
    assert_eq!(get_entry(&value(&editor.export_json().unwrap()))
        ["resolver"]["default"]["onRelease"][0]["arguments"]["macro"], macro_id,
        "user-visible rename cannot break stable macro.run reference");
    assert!(editor.undo().unwrap()); // undo name change, not attachment
    assert_eq!(get_entry(&value(&editor.export_json().unwrap()))
        ["resolver"]["default"]["onRelease"][0]["arguments"]["macro"], macro_id);
    assert!(editor.undo().unwrap()); // undo attachment
    assert_eq!(get_entry(&value(&editor.export_json().unwrap())), before_entry);
    assert!(editor.redo().unwrap()); // redo attachment
    assert_eq!(get_entry(&value(&editor.export_json().unwrap())),
        attached);
    let remove = json!({"type":"setEntryDefaultMacroInvocation",
        "boardId":"board.ja.root","entryId":"kana.a",
        "macroId":macro_id,"enabled":false}).to_string();
    assert!(editor.apply_command_json(&remove, editor.revision()).unwrap());
    assert_eq!(get_entry(&value(&editor.export_json().unwrap())), before_entry);
    assert!(!editor.apply_command_json(&remove, editor.revision()).unwrap());
    assert!(editor.undo().unwrap());
    assert_eq!(get_entry(&value(&editor.export_json().unwrap())), attached);
    assert!(ProfileEditorV3::open(&editor.export_json().unwrap()).is_ok(),
        "complete Profile remains roundtrip validated");
}

#[test]
fn invalid_macro_assignment_never_mutates_profile_or_history() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let command = json!({"type":"createMacro","name":"valid",
        "actions":[{"actionID":"noop","arguments":{}}]}).to_string();
    assert!(editor.apply_command_json(&command, 0).unwrap());
    let before = editor.export_json().unwrap();
    let revision = editor.revision();
    let id = value(&before)["macros"].as_array().unwrap().last().unwrap()
        ["id"].as_str().unwrap().to_owned();
    let invalid = [
        json!({"type":"setEntryDefaultMacroInvocation","boardId":"missing",
            "entryId":"kana.a","macroId":id,"enabled":true}),
        json!({"type":"setEntryDefaultMacroInvocation","boardId":"board.ja.root",
            "entryId":"missing","macroId":id,"enabled":true}),
        json!({"type":"setEntryDefaultMacroInvocation","boardId":"board.ja.root",
            "entryId":"kana.a","macroId":"macro.missing","enabled":true}),
        json!({"type":"setEntryDefaultMacroInvocation","boardId":"board.ja.root",
            "entryId":"kana.a","macroId":id}),
        json!({"type":"setEntryDefaultMacroInvocation","boardId":"board.ja.root",
            "entryId":"kana.a","enabled":false}),
        json!({"type":"setEntryDefaultMacroInvocation","boardId":"board.ja.root",
            "entryId":"kana.a","macroId":id,"enabled":null}),
    ];
    for action in invalid {
        assert!(editor.apply_command_json(&action.to_string(), revision).is_err(), "{action}");
        assert_eq!(editor.revision(), revision);
        assert_eq!(editor.export_json().unwrap(), before);
        assert!(!editor.can_redo());
    }
}


#[test]
fn macro_binding_does_not_replace_existing_key_default_actions() {
    // Validated built-in Profile + a pre-existing non-Macro action. This proves
    // attach/removal touches only the selected macro.run entry.
    let mut source = value(PRODUCT);
    let board = source["boards"].as_array_mut().unwrap().iter_mut()
        .find(|b| b["id"] == "board.ja.root").unwrap();
    let entry = board["entries"].as_array_mut().unwrap().iter_mut()
        .find(|e| e["id"] == "kana.a").unwrap();
    entry["resolver"]["default"]["onRelease"] =
        json!([{"actionID":"noop","arguments":{}}]);
    let mut editor = ProfileEditorV3::open(&source.to_string()).unwrap();
    let create = json!({"type":"createMacro","name":"additional",
        "actions":[{"actionID":"noop","arguments":{}}]});
    assert!(editor.apply_command_json(&create.to_string(), editor.revision()).unwrap());
    let macro_id = value(&editor.export_json().unwrap())["macros"]
        .as_array().unwrap().last().unwrap()["id"].as_str().unwrap().to_owned();
    let before = value(&editor.export_json().unwrap());
    let attach = json!({"type":"setEntryDefaultMacroInvocation",
        "boardId":"board.ja.root","entryId":"kana.a",
        "macroId":macro_id,"enabled":true}).to_string();
    assert!(editor.apply_command_json(&attach, editor.revision()).unwrap());
    let after = value(&editor.export_json().unwrap());
    let locate = |profile: &Value| profile["boards"].as_array().unwrap().iter()
        .find(|b| b["id"] == "board.ja.root").unwrap()["entries"]
        .as_array().unwrap().iter().find(|e| e["id"] == "kana.a").unwrap().clone();
    let actions = locate(&after)["resolver"]["default"]["onRelease"].as_array().unwrap().clone();
    assert_eq!(actions.len(), 2);
    assert_eq!(actions[0]["actionID"], "noop");
    assert_eq!(actions[1]["actionID"], "macro.run");
    assert_eq!(actions[1]["arguments"]["macro"], macro_id);
    let remove = json!({"type":"setEntryDefaultMacroInvocation",
        "boardId":"board.ja.root","entryId":"kana.a",
        "macroId":macro_id,"enabled":false}).to_string();
    assert!(editor.apply_command_json(&remove, editor.revision()).unwrap());
    assert_eq!(locate(&value(&editor.export_json().unwrap())), locate(&before),
        "unassignment removes only the Macro while preserving existing onRelease action");
}
