//! Native reference sequence used for exact Wasm-vs-native editor parity.
use gesture_ime_core::ProfileEditorV3;
use serde_json::{Value, json};

fn snapshot(editor: &ProfileEditorV3, changed: bool) -> Result<Value, Box<dyn std::error::Error>> {
    let value: Value = serde_json::from_str(&editor.snapshot_json()?)?;
    Ok(json!({"ok": true, "changed": changed, "snapshot": value}))
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let profile_path = std::env::args().nth(1).ok_or("provide Profile JSON path")?;
    let command_path = std::env::args().nth(2).ok_or("provide command JSON path")?;
    let profile = std::fs::read_to_string(profile_path)?;
    let command = std::fs::read_to_string(command_path)?;
    let mut editor = ProfileEditorV3::open(&profile)?;
    let changed = editor.apply_command_json(&command, editor.revision())?;
    let after_apply = snapshot(&editor, changed)?;
    let changed = editor.undo()?;
    let after_undo = snapshot(&editor, changed)?;
    let changed = editor.redo()?;
    let after_redo = snapshot(&editor, changed)?;
    println!("{}", json!({
        "afterApply": after_apply,
        "afterUndo": after_undo,
        "afterRedo": after_redo
    }));
    Ok(())
}
