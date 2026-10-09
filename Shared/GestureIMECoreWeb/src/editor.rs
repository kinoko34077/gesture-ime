//! Stateful wasm binding to the *same* Rust ProfileEditorV3 used by native hosts.
//! The UI receives serialized snapshots; editing meaning and Undo stay in Rust.
use gesture_ime_core::ProfileEditorV3;
use serde_json::{Value, json};
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub struct WebProfileEditor {
    inner: ProfileEditorV3,
}

#[wasm_bindgen]
impl WebProfileEditor {
    #[wasm_bindgen(constructor)]
    pub fn new(profile_json: &str) -> Result<WebProfileEditor, JsValue> {
        ProfileEditorV3::open(profile_json)
            .map(|inner| Self { inner })
            .map_err(|error| JsValue::from_str(&error))
    }

    pub fn snapshot(&self) -> String {
        match self.inner.snapshot_json() {
            Ok(snapshot) => json!({
                "ok": true,
                "snapshot": serde_json::from_str::<Value>(&snapshot).unwrap_or(Value::Null)
            }).to_string(),
            Err(error) => json!({"ok": false, "error": error}).to_string(),
        }
    }

    pub fn apply_command(&mut self, command_json: &str, expected_revision: u32) -> String {
        let result = self.inner.apply_command_json(command_json, expected_revision);
        self.format_change(result)
    }

    pub fn undo(&mut self) -> String {
        let result = self.inner.undo();
        self.format_change(result)
    }

    pub fn redo(&mut self) -> String {
        let result = self.inner.redo();
        self.format_change(result)
    }
}

impl WebProfileEditor {
    fn format_change(&self, result: Result<bool, String>) -> String {
        match result {
            Ok(changed) => {
                match self.inner.snapshot_json() {
                    Ok(snapshot) => json!({
                        "ok": true,
                        "changed": changed,
                        "snapshot": serde_json::from_str::<Value>(&snapshot)
                            .unwrap_or(Value::Null)
                    }).to_string(),
                    Err(error) => json!({"ok": false, "error": error}).to_string(),
                }
            }
            Err(error) => json!({"ok": false, "error": error}).to_string(),
        }
    }
}
