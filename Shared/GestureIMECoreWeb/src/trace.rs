//! Deterministic browser replay of the exact native Profile v3 platform runtime.
//! The browser owns no gesture or condition semantics: every event reaches Rust.
use gesture_ime_core::{
    FfiPoint, FfiProfileV3SessionSnapshot, FfiSize, ProfileV3PlatformRuntime,
};
use serde_json::{Value, json};

const MAX_SCRIPT_BYTES: usize = 16 * 1024;
const MAX_EVENTS: usize = 64;
const MAX_TIME_MS: i64 = 1_000_000_000;
const MAX_COORDINATE: f64 = 100_000.0;

pub fn trace_profile_json(profile_json: &str, script_json: &str) -> String {
    match trace(profile_json, script_json) {
        Ok(trace) => json!({"ok": true, "trace": trace}).to_string(),
        Err(error) => json!({"ok": false, "error": error}).to_string(),
    }
}

fn trace(profile_json: &str, script_json: &str) -> Result<Value, String> {
    if script_json.len() > MAX_SCRIPT_BYTES {
        return Err("trace script exceeds 16 KiB".into());
    }
    let script: Value = serde_json::from_str(script_json)
        .map_err(|error| format!("invalid trace JSON: {error}"))?;
    let obj = script.as_object().ok_or("trace must be an object")?;
    let entry_id = obj.get("entryId").and_then(Value::as_str)
        .filter(|value| !value.is_empty()).ok_or("entryId is required")?;
    let events = obj.get("events").and_then(Value::as_array)
        .ok_or("events must be an array")?;
    if events.len() > MAX_EVENTS {
        return Err("too many trace events (max 64)".into());
    }
    let width = bounded_coordinate(obj.get("cellWidth"), 80.0, "cellWidth")?;
    let height = bounded_coordinate(obj.get("cellHeight"), 80.0, "cellHeight")?;
    if width <= 0.0 || height <= 0.0 {
        return Err("cell dimensions must be positive".into());
    }
    let x = bounded_coordinate(obj.get("touchX"), 0.0, "touchX")?;
    let y = bounded_coordinate(obj.get("touchY"), 0.0, "touchY")?;
    let mut at_ms = event_time(obj.get("atMs"), "initial atMs")?.unwrap_or(0);

    let runtime = ProfileV3PlatformRuntime::new(profile_json.to_owned())
        .map_err(|error| format!("invalid Profile: {error}"))?;
    let profile_id = runtime.profile_id();
    let session = runtime.begin_session(
        entry_id.to_owned(),
        FfiSize { width, height },
        FfiPoint { x, y },
        at_ms,
    ).map_err(|error| format!("begin session: {error}"))?;

    let first = session.snapshot().map_err(|error| format!("initial snapshot: {error}"))?;
    let mut snapshots = vec![serialize_snapshot("down", &first)];
    let mut terminated = first.terminal.is_some();

    for event in events {
        if terminated {
            return Err("trace event after terminal event".into());
        }
        let event_obj = event.as_object().ok_or("each event must be an object")?;
        let event_type = event_obj.get("type").and_then(Value::as_str)
            .ok_or("event type is required")?;
        let next_time = event_time(event_obj.get("atMs"), "event atMs")?
            .ok_or("event atMs is required")?;
        if next_time < at_ms {
            return Err("event time must be monotonic".into());
        }
        at_ms = next_time;
        let snapshot = match event_type {
            "move" => {
                let x = bounded_coordinate(event_obj.get("x"), 0.0, "move.x")?;
                let y = bounded_coordinate(event_obj.get("y"), 0.0, "move.y")?;
                session.move_to(FfiPoint { x, y }, Some(at_ms))
            }
            "wait" => session.advance_time(at_ms),
            "up" => session.touch_up(Some(at_ms)),
            "cancel" => session.cancel(Some(at_ms)),
            "invalidate" => session.invalidate(Some(at_ms)),
            _ => return Err(format!("unknown event type: {event_type}")),
        }.map_err(|error| format!("{event_type} event: {error}"))?;
        terminated = snapshot.terminal.is_some();
        snapshots.push(serialize_snapshot(event_type, &snapshot));
    }

    Ok(json!({"profileId": profile_id, "entryId": entry_id, "snapshots": snapshots}))
}

fn bounded_coordinate(value: Option<&Value>, default: f64, name: &str) -> Result<f64, String> {
    let number = match value {
        Some(value) => value.as_f64().ok_or_else(|| format!("{name} must be a number"))?,
        None => default,
    };
    if !number.is_finite() || number.abs() > MAX_COORDINATE {
        return Err(format!("{name} out of bounds"));
    }
    Ok(number)
}

fn event_time(value: Option<&Value>, name: &str) -> Result<Option<i64>, String> {
    let Some(value) = value else { return Ok(None) };
    let time = value.as_i64().ok_or_else(|| format!("{name} must be integer milliseconds"))?;
    if !(0..=MAX_TIME_MS).contains(&time) {
        return Err(format!("{name} out of range"));
    }
    Ok(Some(time))
}

fn serialize_snapshot(event_type: &str, snapshot: &FfiProfileV3SessionSnapshot) -> Value {
    let entries: Vec<_> = snapshot.surface.entries.iter().map(|entry| json!({
        "id": entry.id,
        "text": entry.text,
        "accessibilityLabel": entry.accessibility_label,
        "rect": {
            "x": entry.rect.x,
            "y": entry.rect.y,
            "width": entry.rect.width,
            "height": entry.rect.height,
        },
        "guides": entry.guides.iter().map(|guide| json!({
            "entryId": guide.target_entry_id,
            "label": guide.label,
            "centerX": guide.center_x,
            "centerY": guide.center_y,
            "overridden": guide.overridden,
        })).collect::<Vec<_>>(),
    })).collect();
    let dispatches: Vec<_> = snapshot.runtime_dispatches.iter().map(|dispatch| json!({
        "kind": format!("{:?}", dispatch.kind),
        "actionId": dispatch.action_id,
        "arguments": dispatch.arguments_json.as_ref()
            .and_then(|arguments| serde_json::from_str::<Value>(arguments).ok()),
        "tableId": dispatch.table_id,
        "matchedSource": dispatch.matched_source,
        "replacement": dispatch.replacement,
    })).collect();
    json!({
        "event": event_type,
        "terminal": snapshot.terminal.as_ref().map(|value| format!("{value:?}")),
        "boardId": snapshot.current_board_id,
        "persistentBoardId": snapshot.persistent_board_id,
        "context": format!("{:?}", snapshot.context),
        "stageDepth": snapshot.stage_depth,
        "rollbackCount": snapshot.rollback_count,
        "rollbackProgress": snapshot.rollback_progress,
        "candidateId": snapshot.candidate_entry_id,
        "endpointId": snapshot.current_endpoint_entry_id,
        "committedEntryIds": snapshot.committed_entry_ids,
        "transitionCount": snapshot.board_transition_count,
        "transitionLimitHit": snapshot.transition_limit_hit,
        "surface": {
            "layerId": snapshot.surface.layer_id,
            "boardId": snapshot.surface.board_id,
            "entries": entries,
        },
        "runtimeDispatches": dispatches,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const PRODUCT: &str = include_str!("../../../App/KeyboardExtension/Resources/default-ja.json");

    fn run(script: &str) -> Value {
        serde_json::from_str(&trace_profile_json(PRODUCT, script)).unwrap()
    }

    #[test]
    fn real_product_return_key_dispatches_from_native_semantic_runtime() {
        let value = run(r#"{"entryId":"text.enter","events":[{"type":"up","atMs":10}]}"#);
        assert_eq!(value["ok"], true, "{value}");
        assert_eq!(value["trace"]["snapshots"][1]["terminal"], "Committed");
        assert_eq!(value["trace"]["snapshots"][1]["runtimeDispatches"][0]["actionId"], "text.insert");
        assert_eq!(value["trace"]["snapshots"][1]["runtimeDispatches"][0]["arguments"]["text"], "\n");
    }

    #[test]
    fn stage_is_the_actual_native_board_transition() {
        let value = run(r#"{"entryId":"kana.transform","events":[{"type":"move","x":0,"y":-80,"atMs":10},{"type":"up","atMs":20}]}"#);
        assert_eq!(value["ok"], true, "{value}");
        assert_eq!(value["trace"]["snapshots"][0]["boardId"], "board.ja.transform");
        assert_eq!(value["trace"]["snapshots"][0]["context"], "Relative");
        assert_eq!(value["trace"]["snapshots"][2]["terminal"], "Committed");
    }

    #[test]
    fn cancelled_sessions_are_not_commits() {
        let value = run(r#"{"entryId":"text.enter","events":[{"type":"cancel","atMs":10}]}"#);
        assert_eq!(value["ok"], true, "{value}");
        assert_eq!(value["trace"]["snapshots"][1]["terminal"], "Cancelled");
    }

    #[test]
    fn rejects_invalid_script_before_claiming_success() {
        for script in [
            "{",
            r#"{"entryId":"text.enter","events":[{"type":"up","atMs":10},{"type":"move","x":1,"y":2,"atMs":20}]}"#,
            r#"{"entryId":"text.enter","events":[{"type":"move","x":1,"y":2,"atMs":10},{"type":"up","atMs":5}]}"#,
            r#"{"entryId":"text.enter","events":[{"type":"invalid","atMs":1}]}"#,
        ] {
            assert_eq!(run(script)["ok"], false);
        }
    }
}
