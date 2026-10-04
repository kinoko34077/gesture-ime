use gesture_ime_core::{
    FfiPoint, FfiProfileV3BoardContext, FfiProfileV3DispatchKind, FfiSize,
    ProfileV3PlatformError, ProfileV3PlatformRuntime,
};
use serde_json::{json, Value};

fn profile_json() -> Value {
    json!({
        "schema":"gesture-ime.profile.v3",
        "id":"profile.a3.ffi",
        "name":"A3 FFI",
        "version":1,
        "gesturePolicy":{
            "deadZone":0.10,
            "initialCellCommitDistance":0.55,
            "subsequentCellCommitDistance":0.45,
            "angularHysteresisDegrees":8
        },
        "initialLayerRef":"layer.base",
        "layers":[
            {"id":"layer.base","rootBoardRef":"board.root"},
            {"id":"layer.alt","rootBoardRef":"board.alt"}
        ],
        "boards":[
            {
                "id":"board.root",
                "entries":[
                    {
                        "id":"key.persist",
                        "rect":{"x":-4,"y":0,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"P","transforms":[]},
                                    "accessibilityLabel":"persistent"
                                },
                                "transition":{
                                    "targetBoardRef":"board.flick",
                                    "lifetime":"persistent"
                                }
                            }
                        }
                    },
                    {
                        "id":"key.conditional",
                        "rect":{"x":0,"y":0,"width":4,"height":2},
                        "resolver":{
                            "cases":[
                                {
                                    "when":{"fact":"conversion.active"},
                                    "behavior":{
                                        "presentation":{
                                            "text":{"base":"確定","transforms":[]}
                                        },
                                        "onRelease":[
                                            {"actionID":"conversion.commit","arguments":{}}
                                        ]
                                    }
                                }
                            ],
                            "default":{
                                "presentation":{
                                    "text":{"base":"改行","transforms":[]}
                                },
                                "onRelease":[
                                    {
                                        "actionID":"text.insert",
                                        "arguments":{
                                            "text":{"base":"\\n","transforms":[]}
                                        }
                                    }
                                ]
                            }
                        }
                    },
                    {
                        "id":"key.dispatch",
                        "rect":{"x":6,"y":0,"width":1,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"D","transforms":[]}
                                },
                                "onRelease":[
                                    {
                                        "actionID":"text.insert",
                                        "arguments":{
                                            "text":{"base":"A","transforms":[]}
                                        }
                                    },
                                    {
                                        "actionID":"text.transform",
                                        "arguments":{"table":"kana.dakuten"}
                                    },
                                    {
                                        "actionID":"cursor.move",
                                        "arguments":{"offset":1}
                                    }
                                ]
                            }
                        }
                    }
                ]
            },
            {
                "id":"board.flick",
                "entries":[
                    {
                        "id":"origin",
                        "rect":{"x":-1,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"央","transforms":[]}
                                }
                            }
                        }
                    },
                    {
                        "id":"east",
                        "rect":{"x":1,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"東","transforms":[]}
                                },
                                "onRelease":[
                                    {
                                        "actionID":"text.insert",
                                        "arguments":{
                                            "text":{"base":"東","transforms":[]}
                                        }
                                    }
                                ]
                            }
                        }
                    },
                    {
                        "id":"ne",
                        "rect":{"x":1,"y":-3,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"北東","transforms":[]}
                                }
                            }
                        }
                    },
                    {
                        "id":"far.east",
                        "rect":{"x":3,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"遠東","transforms":[]}
                                }
                            }
                        }
                    }
                ]
            },
            {
                "id":"board.alt",
                "entries":[
                    {
                        "id":"alt.key",
                        "rect":{"x":0,"y":0,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"ALT","transforms":[]}
                                }
                            }
                        }
                    }
                ]
            }
        ],
        "states":[],
        "transformTables":[
            {
                "id":"kana.dakuten",
                "entries":[
                    {"from":"か","to":"が"}
                ]
            }
        ],
        "macros":[]
    })
}

fn profile_text() -> String {
    serde_json::to_string(&profile_json()).unwrap()
}

fn runtime() -> std::sync::Arc<ProfileV3PlatformRuntime> {
    ProfileV3PlatformRuntime::new(profile_text()).unwrap()
}

fn entry_text(
    surface: &gesture_ime_core::FfiProfileV3BoardSurface,
    entry_id: &str,
) -> Option<&str> {
    surface
        .entries
        .iter()
        .find(|entry| entry.id == entry_id)
        .and_then(|entry| entry.text.as_deref())
}

#[test]
fn a3_v3_platform_constructor_accepts_v3_and_rejects_invalid_profile() {
    let runtime = runtime();
    assert_eq!(runtime.profile_id(), "profile.a3.ffi");
    assert_eq!(runtime.active_layer_id().unwrap(), "layer.base");

    let mut invalid = profile_json();
    invalid["initialLayerRef"] = json!("layer.missing");
    let error = ProfileV3PlatformRuntime::new(
        serde_json::to_string(&invalid).unwrap(),
    )
    .unwrap_err();

    match error {
        ProfileV3PlatformError::InvalidProfile { code, .. } => {
            assert_eq!(code, "E_MISSING_REFERENCE");
        }
        other => panic!("unexpected error: {other:?}"),
    }
}

#[test]
fn a3_direct_surface_preserves_authored_rects_sparse_gaps_and_bounds() {
    let runtime = runtime();
    let surface = runtime.direct_surface().unwrap();

    assert_eq!(surface.layer_id, "layer.base");
    assert_eq!(surface.board_id, "board.root");
    assert_eq!(surface.context, FfiProfileV3BoardContext::Direct);
    assert_eq!(surface.entries.len(), 3);

    let persist = surface
        .entries
        .iter()
        .find(|entry| entry.id == "key.persist")
        .unwrap();
    assert_eq!((persist.rect.x, persist.rect.y), (-4, 0));
    assert_eq!((persist.rect.width, persist.rect.height), (2, 2));

    let conditional = surface
        .entries
        .iter()
        .find(|entry| entry.id == "key.conditional")
        .unwrap();
    assert_eq!((conditional.rect.x, conditional.rect.y), (0, 0));
    assert_eq!((conditional.rect.width, conditional.rect.height), (4, 2));

    let half = surface
        .entries
        .iter()
        .find(|entry| entry.id == "key.dispatch")
        .unwrap();
    assert_eq!((half.rect.x, half.rect.y), (6, 0));
    assert_eq!((half.rect.width, half.rect.height), (1, 2));

    let bounds = surface.bounds.unwrap();
    assert_eq!(
        (bounds.min_x, bounds.min_y, bounds.max_x, bounds.max_y),
        (-4, 0, 7, 2)
    );

    // Sparse space is represented only by absence: no synthetic filler entries.
    assert!(!surface.entries.iter().any(|entry| entry.id.starts_with("empty")));
}

#[test]
fn a3_semantic_context_changes_future_surface_resolution() {
    let runtime = runtime();

    assert_eq!(
        entry_text(&runtime.direct_surface().unwrap(), "key.conditional"),
        Some("改行")
    );

    runtime
        .update_semantic_context("かな".into(), true, true)
        .unwrap();

    assert_eq!(
        entry_text(&runtime.direct_surface().unwrap(), "key.conditional"),
        Some("確定")
    );

    runtime
        .update_semantic_context("かな".into(), false, false)
        .unwrap();

    assert_eq!(
        entry_text(&runtime.direct_surface().unwrap(), "key.conditional"),
        Some("改行")
    );
}

#[test]
fn a3_session_snapshot_exposes_relative_surface_candidate_and_anchor() {
    let runtime = runtime();
    let session = runtime
        .begin_session(
            "key.persist".into(),
            FfiSize {
                width: 100.0,
                height: 50.0,
            },
            FfiPoint { x: 10.0, y: 20.0 },
            0,
        )
        .unwrap();

    let initial = session.snapshot().unwrap();
    assert_eq!(initial.context, FfiProfileV3BoardContext::Relative);
    assert_eq!(initial.current_board_id, "board.flick");
    assert_eq!(initial.persistent_board_id, "board.flick");
    assert_eq!(initial.current_endpoint_entry_id.as_deref(), Some("origin"));
    assert_eq!(initial.surface.board_id, "board.flick");
    assert_eq!(initial.surface.entries.len(), 4);
    assert_eq!((initial.anchor.x, initial.anchor.y), (10.0, 20.0));

    let precommit = session
        .move_to(FfiPoint { x: 40.0, y: 20.0 }, Some(10))
        .unwrap();

    assert_eq!(precommit.candidate_entry_id.as_deref(), Some("east"));
    assert_eq!(precommit.surface.candidate_entry_id.as_deref(), Some("east"));
    assert_eq!(
        precommit.current_endpoint_entry_id.as_deref(),
        Some("origin")
    );
    assert!(precommit.committed_entry_ids.is_empty());
}

#[test]
fn a3_same_layer_push_creates_independent_board_frame() {
    let runtime = runtime();

    let first_session = runtime
        .begin_session(
            "key.persist".into(),
            FfiSize {
                width: 100.0,
                height: 50.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
        )
        .unwrap();
    first_session.touch_up(Some(1)).unwrap();

    assert_eq!(runtime.direct_surface().unwrap().board_id, "board.flick");

    // A second push of the same Layer gets a fresh BoardFrame rooted at board.root.
    assert_eq!(
        runtime.push_layer("layer.base".into()).unwrap().board_id,
        "board.root"
    );

    // Popping exposes the original frame and its independently persisted baseline.
    assert_eq!(runtime.pop_layer().unwrap().board_id, "board.flick");
}

#[test]
fn a3_layer_set_push_pop_and_stack_limit_are_runtime_owned() {
    let runtime = runtime();

    assert_eq!(
        runtime.push_layer("layer.alt".into()).unwrap().layer_id,
        "layer.alt"
    );
    assert_eq!(runtime.active_layer_id().unwrap(), "layer.alt");

    assert_eq!(
        runtime.pop_layer().unwrap().layer_id,
        "layer.base"
    );

    assert_eq!(
        runtime.set_layer("layer.alt".into()).unwrap().board_id,
        "board.alt"
    );
    assert_eq!(runtime.active_layer_id().unwrap(), "layer.alt");

    // Reset to one base frame, then fill the bounded stack to 16.
    runtime.set_layer("layer.base".into()).unwrap();
    for _ in 0..15 {
        runtime.push_layer("layer.base".into()).unwrap();
    }
    let error = runtime.push_layer("layer.base".into()).unwrap_err();
    assert!(matches!(error, ProfileV3PlatformError::LayerStackLimit));
}

#[test]
fn a3_runtime_dispatch_log_preserves_resolved_order_and_transform_effect() {
    let runtime = runtime();
    runtime
        .update_semantic_context("か".into(), false, false)
        .unwrap();

    let session = runtime
        .begin_session(
            "key.dispatch".into(),
            FfiSize {
                width: 100.0,
                height: 50.0,
            },
            FfiPoint { x: 0.0, y: 0.0 },
            0,
        )
        .unwrap();

    let before = session.snapshot().unwrap();
    assert!(before.runtime_dispatches.is_empty());

    let after = session.touch_up(Some(10)).unwrap();
    assert_eq!(after.runtime_dispatches.len(), 3);

    assert_eq!(
        after.runtime_dispatches[0].kind,
        FfiProfileV3DispatchKind::Action
    );
    assert_eq!(
        after.runtime_dispatches[0].action_id.as_deref(),
        Some("text.insert")
    );
    let first_args: Value = serde_json::from_str(
        after.runtime_dispatches[0]
            .arguments_json
            .as_deref()
            .unwrap(),
    )
    .unwrap();
    assert_eq!(first_args["text"], "A");

    assert_eq!(
        after.runtime_dispatches[1].kind,
        FfiProfileV3DispatchKind::CompositionTailTransform
    );
    assert_eq!(
        after.runtime_dispatches[1].table_id.as_deref(),
        Some("kana.dakuten")
    );
    assert_eq!(
        after.runtime_dispatches[1].matched_source.as_deref(),
        Some("か")
    );
    assert_eq!(
        after.runtime_dispatches[1].replacement.as_deref(),
        Some("が")
    );

    assert_eq!(
        after.runtime_dispatches[2].kind,
        FfiProfileV3DispatchKind::Action
    );
    assert_eq!(
        after.runtime_dispatches[2].action_id.as_deref(),
        Some("cursor.move")
    );

    // Snapshot exposes a monotonic log; adapters can consume only the suffix
    // after their previous count without reinterpreting semantics.
    assert_eq!(session.snapshot().unwrap().runtime_dispatches, after.runtime_dispatches);
}

#[test]
fn a3_profile_switch_remains_unavailable_at_constructor_boundary() {
    let mut value = profile_json();
    value["boards"][0]["entries"][2]["resolver"]["default"]["onRelease"] = json!([
        {
            "actionID":"profile.switch",
            "arguments":{"profile":"profile.other"}
        }
    ]);

    let error = ProfileV3PlatformRuntime::new(
        serde_json::to_string(&value).unwrap(),
    )
    .unwrap_err();

    match error {
        ProfileV3PlatformError::InvalidProfile { code, .. } => {
            assert_eq!(code, "E_UNAVAILABLE_CAPABILITY");
        }
        other => panic!("unexpected error: {other:?}"),
    }
}
