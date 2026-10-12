use gesture_ime_core::{
    ProfileEditorV3, ProfileV3BoardRuntime, ProfileV3Codec,
    DefaultBoardSemanticsV3, GestureSize, GesturePoint,
};
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


// M3k: invisible empty directions have no runtime BoardEntry until explicitly
// authored. A directional Stage must remain one atomic Rust/Undo step.
#[test]
fn sparse_directional_stage_creates_only_one_hit_target_and_supports_multistage_undo() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original = value(&editor.export_json().unwrap());
    let parent_id = "board.base.kana.a.flick";
    let old_parent = original["boards"].as_array().unwrap().iter()
        .find(|b| b["id"] == parent_id).unwrap().clone();
    assert_eq!(old_parent["entries"].as_array().unwrap().len(), 5);

    let first = json!({"type":"createDirectionalStage","boardId":parent_id,
        "direction":"northWest","replaceExistingOutput":false}).to_string();
    assert!(editor.apply_command_json(&first, 0).unwrap());
    let doc = value(&editor.export_json().unwrap());
    let parent = doc["boards"].as_array().unwrap().iter()
        .find(|b| b["id"] == parent_id).unwrap();
    assert_eq!(parent["entries"].as_array().unwrap().len(), 6,
        "only the explicitly assigned NW direction becomes a semantic Entry");
    let northwest = parent["entries"].as_array().unwrap().iter()
        .find(|e| e["rect"]["x"] == -3 && e["rect"]["y"] == -3).unwrap();
    let stage = northwest["resolver"]["default"]["transition"]["targetBoardRef"]
        .as_str().unwrap().to_owned();
    assert_eq!(northwest["resolver"]["default"]["transition"]["lifetime"], "transient");
    for id in ["kana.a.tap", "kana.a.w", "kana.a.n", "kana.a.e", "kana.a.s"] {
        assert_eq!(parent["entries"].as_array().unwrap().iter()
            .find(|e| e["id"] == id).unwrap(),
            old_parent["entries"].as_array().unwrap().iter()
                .find(|e| e["id"] == id).unwrap(),
            "ordinary tap + cardinal actions must not change");
    }
    let stage_board = doc["boards"].as_array().unwrap().iter()
        .find(|b| b["id"] == stage).unwrap();
    assert_eq!(stage_board["entries"].as_array().unwrap().len(), 1,
        "new Stage must have center only and no phantom diagonal hits");
    assert_eq!(stage_board["entries"][0]["rect"]["x"], -1);
    assert_eq!(stage_board["entries"][0]["rect"]["y"], -1);
    assert!(stage_board["entries"][0]["resolver"]["default"]["onRelease"]
        .as_array().unwrap().is_empty());

    let second = json!({"type":"createDirectionalStage","boardId":stage,
        "direction":"northEast","replaceExistingOutput":false}).to_string();
    assert!(editor.apply_command_json(&second, editor.revision()).unwrap());
    let nested = value(&editor.export_json().unwrap());
    let stage_one = nested["boards"].as_array().unwrap().iter()
        .find(|b| b["id"] == stage).unwrap();
    assert_eq!(stage_one["entries"].as_array().unwrap().len(), 2);
    let stage_two_id = stage_one["entries"].as_array().unwrap().iter()
        .find(|e| e["rect"]["x"] == 1 && e["rect"]["y"] == -3).unwrap()
        ["resolver"]["default"]["transition"]["targetBoardRef"].as_str().unwrap();
    assert!(nested["boards"].as_array().unwrap().iter().any(|b| b["id"] == stage_two_id));
    assert!(ProfileEditorV3::open(&editor.export_json().unwrap()).is_ok());

    assert!(editor.undo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), doc);
    assert!(editor.undo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), original);
    assert!(editor.redo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), doc);
    assert!(editor.redo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), nested);
}

#[test]
fn stage_output_replacement_requires_explicit_confirmation_and_errors_are_atomic() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original = editor.export_json().unwrap();
    let base = "board.base.kana.a.flick";
    for command in [
        json!({"type":"createDirectionalStage","boardId":base,"direction":"west",
            "replaceExistingOutput":false}),
        json!({"type":"createDirectionalStage","boardId":base,"direction":"center",
            "replaceExistingOutput":false}),
        json!({"type":"createDirectionalStage","boardId":"board.unknown",
            "direction":"northWest","replaceExistingOutput":false}),
        json!({"type":"createDirectionalStage","boardId":base,"direction":"northWest"}),
        json!({"type":"createDirectionalStage","boardId":base,"direction":"northWest",
            "replaceExistingOutput":null}),
    ] {
        assert!(editor.apply_command_json(&command.to_string(), 0).is_err(),
            "invalid Stage command must reject: {command}");
        assert_eq!(editor.export_json().unwrap(), original);
        assert_eq!(editor.revision(), 0);
        assert!(!editor.can_undo());
    }
    let replace = json!({"type":"createDirectionalStage","boardId":base,
        "direction":"west","replaceExistingOutput":true}).to_string();
    assert!(editor.apply_command_json(&replace, 0).unwrap());
    let changed = value(&editor.export_json().unwrap());
    let board = changed["boards"].as_array().unwrap().iter()
        .find(|b| b["id"] == base).unwrap();
    let west = board["entries"].as_array().unwrap().iter()
        .find(|e| e["id"] == "kana.a.w").unwrap();
    assert!(west["resolver"]["default"]["onRelease"].as_array().unwrap().is_empty());
    assert_eq!(west["resolver"]["default"]["transition"]["lifetime"], "transient");
    assert_eq!(west["resolver"]["default"]["presentation"]["text"]["base"], "い",
        "existing presentation metadata is not silently stripped");
    let unchanged = value(&original);
    let old_board = unchanged["boards"].as_array().unwrap().iter()
        .find(|b| b["id"] == base).unwrap();
    for id in ["kana.a.tap", "kana.a.n", "kana.a.e", "kana.a.s"] {
        assert_eq!(board["entries"].as_array().unwrap().iter().find(|e| e["id"] == id),
                   old_board["entries"].as_array().unwrap().iter().find(|e| e["id"] == id));
    }
    let before_error = editor.export_json().unwrap();
    let revision = editor.revision();
    assert!(editor.apply_command_json(&replace, revision).is_err(),
        "existing transition is never silently replaced");
    assert_eq!(editor.export_json().unwrap(), before_error);
    assert_eq!(editor.revision(), revision);
}


// M3m: ordinary immediate root transitions must place Hold at the *reachable*
// relative origin, and each user-created Hold input surface is independent.
#[test]
fn reachable_hold_from_kana_and_latin_keeps_root_and_cardinal_outputs() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original = value(&editor.export_json().unwrap());
    for (root, source) in [("board.ja.root", "kana.a"), ("board.alpha.root", "alpha.abc")] {
        let command = json!({"type":"createReachableHoldSurface",
            "boardId":root,"entryId":source,"delayMs":480}).to_string();
        assert!(editor.apply_command_json(&command, editor.revision()).unwrap());
    }
    let changed = value(&editor.export_json().unwrap());
    assert_eq!(changed["boards"].as_array().unwrap().len(),
        original["boards"].as_array().unwrap().len() + 2);
    let mut target_ids = Vec::new();
    for (root_id, root_key, relative_id) in [
        ("board.ja.root", "kana.a", "board.base.kana.a.flick"),
        ("board.alpha.root", "alpha.abc", "board.alpha.alpha.abc.flick"),
    ] {
        let root_before = original["boards"].as_array().unwrap().iter()
            .find(|b| b["id"] == root_id).unwrap();
        let root_after = changed["boards"].as_array().unwrap().iter()
            .find(|b| b["id"] == root_id).unwrap();
        assert_eq!(root_after, root_before, "root key and direct transition must stay untouched");
        let source_entry = root_after["entries"].as_array().unwrap().iter()
            .find(|e| e["id"] == root_key).unwrap();
        assert_eq!(source_entry["resolver"]["default"]["transition"]["targetBoardRef"], relative_id);
        assert!(source_entry["resolver"]["default"].get("hold").is_none(),
            "Hold on root would not run after immediate touch-down transition");

        let relative_before = original["boards"].as_array().unwrap().iter()
            .find(|b| b["id"] == relative_id).unwrap();
        let relative = changed["boards"].as_array().unwrap().iter()
            .find(|b| b["id"] == relative_id).unwrap();
        for prev in relative_before["entries"].as_array().unwrap() {
            let current = relative["entries"].as_array().unwrap().iter()
                .find(|e| e["id"] == prev["id"]).unwrap();
            let mut expected = prev.clone();
            if prev["rect"]["x"] == -1 && prev["rect"]["y"] == -1 {
                expected["resolver"]["default"]["hold"] =
                    current["resolver"]["default"]["hold"].clone();
                let hold_target = current["resolver"]["default"]["hold"]["transition"]["targetBoardRef"].clone();
                if let Some(cases) = expected["resolver"]["cases"].as_array_mut() {
                    for (i, case) in cases.iter_mut().enumerate() {
                        case["behavior"]["hold"] =
                            current["resolver"]["cases"][i]["behavior"]["hold"].clone();
                        assert_eq!(case["behavior"]["hold"]["transition"]["targetBoardRef"],
                            hold_target,
                            "every conditional endpoint must lead to the same Hold surface");
                    }
                }
            }
            assert_eq!(*current, expected,
                "only the relative origin Hold is new, no flick output changed");
        }
        let origin = relative["entries"].as_array().unwrap().iter()
            .find(|e| e["rect"]["x"] == -1 && e["rect"]["y"] == -1).unwrap();
        let hold = &origin["resolver"]["default"]["hold"];
        assert_eq!(hold["delayMs"], 480);
        assert_eq!(hold["suppressOnReleaseAfterStart"], true);
        assert_eq!(hold["transition"]["lifetime"], "transient");
        assert!(hold["onStart"].as_array().unwrap().is_empty());
        let destination = hold["transition"]["targetBoardRef"].as_str().unwrap();
        assert!(!target_ids.contains(&destination.to_string()));
        target_ids.push(destination.to_string());
        let board = changed["boards"].as_array().unwrap().iter()
            .find(|b| b["id"] == destination).unwrap();
        assert_eq!(board["entries"].as_array().unwrap().len(), 1);
        assert_eq!(board["entries"][0]["rect"]["x"], -1);
        assert_eq!(board["entries"][0]["rect"]["y"], -1);
        assert!(board["entries"][0]["resolver"]["default"]["onRelease"]
            .as_array().unwrap().is_empty());
    }
    assert!(ProfileEditorV3::open(&editor.export_json().unwrap()).is_ok());
    assert!(editor.undo().unwrap());
    assert!(editor.undo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), original);
    assert!(editor.redo().unwrap());
    assert!(editor.redo().unwrap());
    assert_eq!(value(&editor.export_json().unwrap()), changed);
}

#[test]
fn reachable_hold_rejects_conflicts_atomically_and_supports_direct_endpoint() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let original = editor.export_json().unwrap();
    for command in [
        json!({"type":"createReachableHoldSurface","boardId":"board.ja.root",
            "entryId":"kana.a","delayMs":49}),
        json!({"type":"createReachableHoldSurface","boardId":"board.ja.root",
            "entryId":"kana.a","delayMs":5001}),
        json!({"type":"createReachableHoldSurface","boardId":"board.ja.root",
            "entryId":"kana.a"}),
        json!({"type":"createReachableHoldSurface","boardId":"missing",
            "entryId":"kana.a","delayMs":480}),
        json!({"type":"createReachableHoldSurface","boardId":"board.ja.root",
            "entryId":"text.enter","delayMs":480}),
        json!({"type":"createReachableHoldSurface","boardId":"board.ja.root",
            "entryId":"edit.delete","delayMs":480}),
    ] {
        assert!(editor.apply_command_json(&command.to_string(), 0).is_err(),
            "rejected invalid/advanced Hold must be atomic: {command}");
        assert_eq!(editor.export_json().unwrap(), original);
        assert_eq!(editor.revision(), 0);
        assert!(!editor.can_undo());
    }
    let direct = json!({"type":"createReachableHoldSurface",
        "boardId":"board.base.kana.a.flick","entryId":"kana.a.w","delayMs":300})
        .to_string();
    assert!(editor.apply_command_json(&direct, 0).unwrap());
    let after = value(&editor.export_json().unwrap());
    let relative = after["boards"].as_array().unwrap().iter()
        .find(|b| b["id"] == "board.base.kana.a.flick").unwrap();
    let west = relative["entries"].as_array().unwrap().iter()
        .find(|e| e["id"] == "kana.a.w").unwrap();
    assert_eq!(west["resolver"]["default"]["hold"]["delayMs"], 300);
    assert_eq!(west["resolver"]["default"]["onRelease"][0]["arguments"]["text"]["base"], "い",
        "original direct flick output must survive");
    let prev = editor.export_json().unwrap();
    let rev = editor.revision();
    assert!(editor.apply_command_json(&direct, rev).is_err(),
        "existing Hold must never be replaced implicitly");
    assert_eq!(editor.revision(), rev);
    assert_eq!(editor.export_json().unwrap(), prev);
    assert!(editor.undo().unwrap());
    assert_eq!(editor.export_json().unwrap(), original);
}


#[test]
fn authored_reachable_hold_transitions_in_actual_rust_board_session() {
    let mut editor = ProfileEditorV3::open(PRODUCT).unwrap();
    let create = json!({"type":"createReachableHoldSurface",
        "boardId":"board.ja.root","entryId":"kana.a","delayMs":480}).to_string();
    assert!(editor.apply_command_json(&create, 0).unwrap());
    let authored = editor.export_json().unwrap();
    let doc = value(&authored);
    let relative = doc["boards"].as_array().unwrap().iter()
        .find(|b| b["id"] == "board.base.kana.a.flick").unwrap();
    let origin = relative["entries"].as_array().unwrap().iter()
        .find(|e| e["id"] == "kana.a.tap").unwrap();
    let hold_board_id = origin["resolver"]["default"]["hold"]["transition"]["targetBoardRef"]
        .as_str().unwrap();

    let profile = ProfileV3Codec::decode_and_validate(authored.as_bytes()).unwrap();
    let runtime = ProfileV3BoardRuntime::compile(&profile, "hold-authored").unwrap();
    let frame = runtime.new_frame("layer.ja").unwrap();
    let mut session = runtime.begin_direct_session(
        frame, "kana.a",
        GestureSize { width:100.0, height:50.0 },
        GesturePoint { x:0.0, y:0.0 }, 0,
        Box::<DefaultBoardSemanticsV3>::default(),
    ).unwrap();

    assert_eq!(session.current_board_id, "board.base.kana.a.flick");
    session.advance_time(479);
    assert_eq!(session.current_board_id, "board.base.kana.a.flick",
        "Hold must not transition before configured delay");
    session.advance_time(480);
    assert_eq!(session.current_board_id, hold_board_id,
        "Hold belongs to reachable relative origin after root touch-down");
    session.touch_up(Some(520));
    assert!(session.dispatched_actions.is_empty(),
        "empty Hold Board must not invent ordinary tap output on release");

    let frame = runtime.new_frame("layer.ja").unwrap();
    let mut cancelled = runtime.begin_direct_session(
        frame, "kana.a",
        GestureSize { width:100.0, height:50.0 },
        GesturePoint { x:0.0, y:0.0 }, 0,
        Box::<DefaultBoardSemanticsV3>::default(),
    ).unwrap();
    cancelled.cancel(Some(100));
    cancelled.advance_time(600);
    assert!(cancelled.dispatched_actions.is_empty(),
        "cancelled input must not later emit Hold or tap");
}


#[test]
fn reachable_hold_does_not_change_another_key_sharing_the_same_relative_board() {
    let mut original = value(PRODUCT);
    let root = original["boards"].as_array_mut().unwrap().iter_mut()
        .find(|b| b["id"] == "board.ja.root").unwrap();
    let second = root["entries"].as_array_mut().unwrap().iter_mut()
        .find(|e| e["id"] == "kana.ka").unwrap();
    second["resolver"]["default"]["transition"]["targetBoardRef"] =
        json!("board.base.kana.a.flick");
    let json = original.to_string();
    let mut editor = ProfileEditorV3::open(&json).unwrap();
    let before = editor.export_json().unwrap();
    let cmd = json!({"type":"createReachableHoldSurface",
        "boardId":"board.ja.root","entryId":"kana.a","delayMs":480}).to_string();
    assert!(editor.apply_command_json(&cmd, 0).is_err(),
        "shared relative Board must not acquire Hold that changes another key");
    assert_eq!(editor.export_json().unwrap(), before);
    assert_eq!(editor.revision(), 0);
    assert!(!editor.can_undo());
}
