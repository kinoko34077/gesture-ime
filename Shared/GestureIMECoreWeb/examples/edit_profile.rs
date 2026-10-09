//! Native counterpart for the WebAssembly editor session parity check.
use gesture_ime_core::{ProfileV3Editor};
use serde_json::{Value, json};

fn snapshot(editor: &ProfileV3Editor) -> Result<Value, Box<dyn std::error::Error>> {
    Ok(serde_json::from_str(&editor.state_json()?)?)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let path = std::env::args().nth(1).ok_or("provide Profile JSON path")?;
    let profile = std::fs::read_to_string(path)?;
    let mut editor = ProfileV3Editor::open(&profile)?;
    let before = snapshot(&editor)?;
    let changed = editor.set_entry_default_text("board.ja.root", "text.enter", "共有編集テスト".into())?;
    let after = snapshot(&editor)?;
    let undone = editor.undo();
    let undo_state = snapshot(&editor)?;
    let redone = editor.redo();
    let redo_state = snapshot(&editor)?;
    println!("{}", json!({
        "changed": changed,
        "before": before,
        "after": after,
        "undone": undone,
        "undoState": undo_state,
        "redone": redone,
        "redoState": redo_state,
    }));
    Ok(())
}
