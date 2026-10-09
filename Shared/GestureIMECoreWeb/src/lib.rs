//! Browser-facing *binding*, not a second source of Profile or gesture semantics.
//! JSON wire responses keep Web UI independent of Rust/UniFFI type layouts.
use gesture_ime_core::{ProfileV3BoardRuntime, ProfileV3Codec, ProfileV3Editor};
use serde_json::{Value, json};
use wasm_bindgen::prelude::*;

mod trace;
pub use trace::trace_profile_json;

/// Inspect the validated initial Layer and Board from the canonical Rust runtime.
/// This first M1 slice deliberately does not claim browser input/session parity.
pub fn inspect_profile_json(profile_json: &str) -> String {
    let result = inspect(profile_json);
    match result {
        Ok(profile) => json!({"ok": true, "profile": profile}).to_string(),
        Err(error) => json!({"ok": false, "error": error}).to_string(),
    }
}

fn inspect(profile_json: &str) -> Result<Value, String> {
    // The existing codec enforces the byte cap, structural schema and semantic bounds.
    let profile = ProfileV3Codec::decode_and_validate(profile_json.as_bytes())
        .map_err(|error| format!("{error:?}"))?;
    let revision = format!("{}:{}", profile.id, profile.version);
    let runtime = ProfileV3BoardRuntime::compile(&profile, revision.clone())
        .map_err(|error| format!("{error:?}"))?;

    let layer = runtime
        .layer(&profile.initial_layer_ref)
        .ok_or_else(|| "validated initial Layer is missing".to_owned())?;
    let board = runtime
        .board(&layer.root_board_ref)
        .ok_or_else(|| "validated initial Board is missing".to_owned())?;
    let entries: Vec<Value> = board
        .entries
        .iter()
        .map(|entry| {
            json!({
                "id": entry.id,
                "rect": {
                    "x": entry.rect.x,
                    "y": entry.rect.y,
                    "width": entry.rect.width,
                    "height": entry.rect.height
                }
            })
        })
        .collect();

    Ok(json!({
        "id": profile.id,
        "name": profile.name,
        "revision": revision,
        "initialLayerId": layer.id,
        "initialBoardId": board.id,
        "entries": entries
    }))
}

/// JavaScript/Wasm entry point; both native and Wasm use inspect_profile_json.
#[wasm_bindgen]
pub fn inspect_profile(profile_json: &str) -> String {
    inspect_profile_json(profile_json)
}

#[cfg(test)]
mod tests {
    use super::*;

    const PRODUCT: &str = include_str!("../../../App/KeyboardExtension/Resources/default-ja.json");

    #[test]
    fn real_product_profile_uses_canonical_runtime() {
        let value: Value = serde_json::from_str(&inspect_profile_json(PRODUCT)).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["profile"]["id"], "builtin.ja.product");
        assert_eq!(value["profile"]["initialLayerId"], "layer.ja");
        assert_eq!(value["profile"]["initialBoardId"], "board.ja.root");
        assert!(value["profile"]["entries"].as_array().unwrap().len() > 1);
    }

    #[test]
    fn malformed_document_is_bounded_failure() {
        let value: Value = serde_json::from_str(&inspect_profile_json("{")).unwrap();
        assert_eq!(value["ok"], false);
        assert!(value["error"].as_str().unwrap().len() > 1);
    }
}

/// Bounded event replay through the canonical Rust BoardSessionV3.
/// This M1 binding resolves the default endpoint only; conditional host facts
/// are a later explicit parity gate, not simulated by JavaScript.
#[wasm_bindgen]
pub fn trace_profile(profile_json: &str, event_trace_json: &str) -> String {
    trace_profile_json(profile_json, event_trace_json)
}

/// Shared editor session runs identically in Web/PWA and future native bridges.
/// JavaScript owns the UI, not validation, mutation or Undo meaning.
#[wasm_bindgen]
pub struct WebProfileEditor {
    inner: ProfileV3Editor,
}

#[wasm_bindgen]
impl WebProfileEditor {
    #[wasm_bindgen(constructor)]
    pub fn new(profile_json: &str) -> Result<WebProfileEditor, JsValue> {
        ProfileV3Editor::open(profile_json)
            .map(|inner| Self { inner })
            .map_err(|error| JsValue::from_str(&error.to_string()))
    }

    pub fn set_entry_default_text(
        &mut self,
        board_id: &str,
        entry_id: &str,
        text: String,
    ) -> Result<bool, JsValue> {
        self.inner.set_entry_default_text(board_id, entry_id, text)
            .map_err(|error| JsValue::from_str(&error.to_string()))
    }

    pub fn undo(&mut self) -> bool { self.inner.undo() }
    pub fn redo(&mut self) -> bool { self.inner.redo() }

    pub fn state_json(&self) -> Result<String, JsValue> {
        self.inner.state_json()
            .map_err(|error| JsValue::from_str(&error.to_string()))
    }

    pub fn export_json(&self) -> Result<String, JsValue> {
        self.inner.export_json()
            .map_err(|error| JsValue::from_str(&error.to_string()))
    }
}
