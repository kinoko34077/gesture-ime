//! Replays *real* canonical BoardSessionV3 operations for web and native tests.
//! The adapter parses bounded events; it does not implement gesture semantics.
use gesture_ime_core::{
    BoardSessionV3, DefaultBoardSemanticsV3, GesturePoint, GestureSize, ProfileV3BoardRuntime,
    ProfileV3Codec,
};
use serde::Deserialize;
use serde_json::{Value, json};

const MAX_TRACE_BYTES: usize = 64 * 1024;
const MAX_EVENTS: usize = 256;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReplayRequest {
    entry_id: String,
    cell_width: f64,
    cell_height: f64,
    touch_down: GesturePoint,
    start_ms: i64,
    events: Vec<ReplayEvent>,
}

#[derive(Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
enum ReplayEvent {
    Move {
        x: f64,
        y: f64,
        #[serde(rename = "atMs")]
        at_ms: i64,
    },
    Advance {
        #[serde(rename = "atMs")]
        at_ms: i64,
    },
    Up {
        #[serde(rename = "atMs")]
        at_ms: i64,
    },
    Cancel {
        #[serde(rename = "atMs")]
        at_ms: i64,
    },
}

impl ReplayEvent {
    fn at_ms(&self) -> i64 {
        match self {
            Self::Move { at_ms, .. }
            | Self::Advance { at_ms }
            | Self::Up { at_ms }
            | Self::Cancel { at_ms } => *at_ms,
        }
    }
}

pub fn trace_profile_json(profile_json: &str, trace_json: &str) -> String {
    match replay(profile_json, trace_json) {
        Ok(trace) => json!({"ok": true, "trace": trace}).to_string(),
        Err(error) => json!({"ok": false, "error": error}).to_string(),
    }
}

fn replay(profile_json: &str, trace_json: &str) -> Result<Value, String> {
    if trace_json.len() > MAX_TRACE_BYTES {
        return Err("event trace exceeds 64 KiB limit".to_owned());
    }
    let request: ReplayRequest =
        serde_json::from_str(trace_json).map_err(|e| format!("invalid event trace: {e}"))?;
    if request.events.len() > MAX_EVENTS {
        return Err("event trace exceeds 256 events".to_owned());
    }
    if request.start_ms < 0
        || !request.cell_width.is_finite()
        || !request.cell_height.is_finite()
        || request.cell_width <= 0.0
        || request.cell_height <= 0.0
        || !request.touch_down.x.is_finite()
        || !request.touch_down.y.is_finite()
    {
        return Err("invalid start time, cell size or touch-down coordinates".to_owned());
    }

    let profile = ProfileV3Codec::decode_and_validate(profile_json.as_bytes())
        .map_err(|error| format!("{error:?}"))?;
    let revision = format!("{}:{}", profile.id, profile.version);
    let runtime = ProfileV3BoardRuntime::compile(&profile, revision.clone())
        .map_err(|error| format!("{error:?}"))?;
    let frame = runtime
        .new_frame(&profile.initial_layer_ref)
        .map_err(|error| format!("{error:?}"))?;
    let mut session = runtime
        .begin_direct_session(
            frame,
            &request.entry_id,
            GestureSize {
                width: request.cell_width,
                height: request.cell_height,
            },
            request.touch_down,
            request.start_ms,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .map_err(|error| format!("{error:?}"))?;

    let mut samples = vec![session_snapshot(&session)];
    let mut last_time = request.start_ms;
    for event in request.events {
        let at_ms = event.at_ms();
        if at_ms < last_time {
            return Err("event time must be monotonic".to_owned());
        }
        if session.terminal.is_some() {
            return Err("event after terminal operation".to_owned());
        }
        match event {
            ReplayEvent::Move { x, y, at_ms } => {
                if !x.is_finite() || !y.is_finite() {
                    return Err("non-finite move position".to_owned());
                }
                session.move_to(GesturePoint { x, y }, Some(at_ms));
            }
            ReplayEvent::Advance { at_ms } => session.advance_time(at_ms),
            ReplayEvent::Up { at_ms } => session.touch_up(Some(at_ms)),
            ReplayEvent::Cancel { at_ms } => session.cancel(Some(at_ms)),
        }
        last_time = at_ms;
        samples.push(session_snapshot(&session));
    }

    Ok(json!({
        "profileRevision": revision,
        "entryId": request.entry_id,
        "samples": samples
    }))
}

fn session_snapshot(session: &BoardSessionV3) -> Value {
    json!({
        "boardId": session.current_board_id,
        "persistentBoardId": session.persistent_board_id(),
        "context": format!("{:?}", session.context),
        "stageDepth": session.stage_depth(),
        "rollbackCount": session.rollback_count,
        "candidateEntryId": session.candidate_entry_id,
        "currentEndpointEntryId": session.current_endpoint_entry_id,
        "committedEntryIds": session.committed_entry_ids,
        "terminal": session.terminal.map(|state| format!("{state:?}")),
        "dispatchedActions": session.dispatched_actions.iter().map(|action| {
            json!({"actionID": action.action_id, "arguments": action.arguments})
        }).collect::<Vec<_>>()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    const PRODUCT: &str = include_str!("../../../App/KeyboardExtension/Resources/default-ja.json");

    #[test]
    fn canonical_builtin_kana_a_move_and_release() {
        let events = r#"{"entryId":"kana.a","cellWidth":50,"cellHeight":50,"touchDown":{"x":0,"y":0},"startMs":0,"events":[{"kind":"move","x":65,"y":0,"atMs":90},{"kind":"up","atMs":120}]}"#;
        let value: Value = serde_json::from_str(&trace_profile_json(PRODUCT, events)).unwrap();
        assert_eq!(value["ok"], true, "{value}");
        assert_eq!(value["trace"]["entryId"], "kana.a");
        assert_eq!(value["trace"]["samples"].as_array().unwrap().len(), 3);
        assert_eq!(value["trace"]["samples"][2]["terminal"], "Committed");
    }

    #[test]
    fn rejects_nonmonotonic_time_and_unknown_entry() {
        let past = r#"{"entryId":"kana.a","cellWidth":50,"cellHeight":50,"touchDown":{"x":0,"y":0},"startMs":100,"events":[{"kind":"move","x":50,"y":0,"atMs":90}]}"#;
        let missing = r#"{"entryId":"no.such.key","cellWidth":50,"cellHeight":50,"touchDown":{"x":0,"y":0},"startMs":0,"events":[]}"#;
        for request in [past, missing] {
            let value: Value = serde_json::from_str(&trace_profile_json(PRODUCT, request)).unwrap();
            assert_eq!(value["ok"], false);
        }
    }
}
