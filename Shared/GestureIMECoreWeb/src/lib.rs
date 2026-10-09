//! Browser-facing *binding*, not a second source of Profile or gesture semantics.
//! JSON wire responses keep Web UI independent of Rust/UniFFI type layouts.
use gesture_ime_core::{ProfileV3BoardRuntime, ProfileV3Codec, ProfileV3PlatformRuntime};
use serde_json::{Value, json};
use wasm_bindgen::prelude::*;

mod trace;
pub use trace::trace_profile_json;
mod editor;
pub use editor::WebProfileEditor;

/// Inspect the validated initial Layer and Board from the canonical Rust runtime.
/// This first M1 slice deliberately does not claim browser input/session parity.
pub fn inspect_profile_json(profile_json: &str) -> String {
    let result = inspect(profile_json, None);
    match result {
        Ok(profile) => json!({"ok": true, "profile": profile}).to_string(),
        Err(error) => json!({"ok": false, "error": error}).to_string(),
    }
}

/// Inspect a chosen Board using exactly the platform runtime's existing
/// per-Layer default semantic context. Never synthesize Stage/Host state.
pub fn inspect_board_json(profile_json: &str, layer_id: &str, board_id: &str) -> String {
    match inspect(profile_json, Some((layer_id, board_id))) {
        Ok(profile) => json!({"ok": true, "profile": profile}).to_string(),
        Err(error) => json!({"ok": false, "error": error}).to_string(),
    }
}

fn inspect(profile_json: &str, selection: Option<(&str, &str)>) -> Result<Value, String> {
    // The existing codec enforces the byte cap, structural schema and semantic bounds.
    let profile = ProfileV3Codec::decode_and_validate(profile_json.as_bytes())
        .map_err(|error| format!("{error:?}"))?;
    let revision = format!("{}:{}", profile.id, profile.version);
    let runtime = ProfileV3BoardRuntime::compile(&profile, revision.clone())
        .map_err(|error| format!("{error:?}"))?;

    let layer_id = selection.map(|(layer, _)| layer)
        .unwrap_or(profile.initial_layer_ref.as_str());
    let layer = runtime.layer(layer_id)
        .ok_or_else(|| format!("Layer not found: {layer_id}"))?;
    let board_id = selection.map(|(_, board)| board)
        .unwrap_or(layer.root_board_ref.as_str());
    let board = runtime.board(board_id)
        .ok_or_else(|| format!("Board not found: {board_id}"))?;
    // The native platform preview resolves text, author overrides and flick guides.
    // Browser presentation never reimplements Profile transition semantics.
    let platform = ProfileV3PlatformRuntime::new(profile_json.to_owned())
        .map_err(|error| format!("{error:?}"))?;
    if layer_id != profile.initial_layer_ref {
        platform.set_layer(layer_id.to_owned())
            .map_err(|error| format!("{error:?}"))?;
    }
    let surface = if board_id == layer.root_board_ref {
        platform.direct_surface()
    } else {
        platform.preview_surface(board_id.to_owned())
    }.map_err(|error| format!("{error:?}"))?;
    if surface.board_id != board.id {
        return Err("selected Board differs from the platform surface".to_owned());
    }
    let entries: Vec<Value> = surface
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
                },
                "text": entry.text,
                "accessibilityLabel": entry.accessibility_label,
                "guides": entry.guides.iter().map(|guide| json!({
                    "targetEntryId": guide.target_entry_id,
                    "centerX": guide.center_x,
                    "centerY": guide.center_y,
                    "label": guide.label,
                    "overridden": guide.overridden,
                })).collect::<Vec<_>>()
            })
        })
        .collect();

    Ok(json!({
        "id": profile.id,
        "name": profile.name,
        "revision": revision,
        "initialLayerId": layer.id,
        "initialBoardId": runtime.layer(&profile.initial_layer_ref)
            .ok_or("validated initial Layer is missing")?.root_board_ref,
        "layerId": layer.id,
        "boardId": board.id,
        "layers": profile.layers.iter().map(|layer| json!({
            "id": layer.id, "name": layer.name, "rootBoardId": layer.root_board_ref
        })).collect::<Vec<_>>(),
        "boards": profile.boards.iter().map(|board| json!({
            "id": board.id, "entryCount": board.entries.len()
        })).collect::<Vec<_>>(),
        "entries": entries
    }))
}

/// JavaScript/Wasm entry point; both native and Wasm use inspect_profile_json.
#[wasm_bindgen]
pub fn inspect_profile(profile_json: &str) -> String {
    inspect_profile_json(profile_json)
}

/// Browser API to inspect an existing direct or internal Board; the native
/// platform resolver is the semantic authority for text and guides.
#[wasm_bindgen]
pub fn inspect_board(profile_json: &str, layer_id: &str, board_id: &str) -> String {
    inspect_board_json(profile_json, layer_id, board_id)
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
        // The native preview surface, not JavaScript, provides flick labels.
        let entries = value["profile"]["entries"].as_array().unwrap();
        let kana = entries.iter().find(|entry| entry["id"] == "kana.a").unwrap();
        let guides = kana["guides"].as_array().unwrap();
        assert!(!guides.is_empty(), "built-in Kana must have native guide labels");
        assert!(guides.iter().all(|guide| guide["label"].is_string()
            && guide["centerX"].is_number() && guide["centerY"].is_number()));
    }

    #[test]
    fn nonroot_board_matches_canonical_native_preview() {
        let value: Value = serde_json::from_str(
            &inspect_board_json(PRODUCT, "layer.ja", "board.base.kana.a.flick")
        ).unwrap();
        assert_eq!(value["ok"], true, "{value}");
        assert_eq!(value["profile"]["boardId"], "board.base.kana.a.flick");
        assert_eq!(value["profile"]["layerId"], "layer.ja");
        assert!(value["profile"]["entries"].as_array().unwrap().len() > 1);
        assert_eq!(value["profile"]["initialBoardId"], "board.ja.root");
        let missing: Value = serde_json::from_str(
            &inspect_board_json(PRODUCT, "layer.ja", "board.absent")
        ).unwrap();
        assert_eq!(missing["ok"], false);
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
