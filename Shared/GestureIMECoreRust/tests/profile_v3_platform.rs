use gesture_ime_core::{
    FfiPoint, FfiProfileV3BoardContext, FfiProfileV3DispatchKind, FfiSize,
    ProfileV3PlatformError, ProfileV3PlatformRuntime,
};
use serde_json::{json, Value};

fn profile_value() -> Value {
    json!({
        "schema":"gesture-ime.profile.v3",
        "id":"profile.a3.platform",
        "name":"A3 Platform",
        "version":1,
        "gesturePolicy":{
            "deadZone":0.1,
            "initialCellCommitDistance":0.5,
            "subsequentCellCommitDistance":0.4,
            "angularHysteresisDegrees":8
        },
        "initialLayerRef":"layer.base",
        "layers":[
            {"id":"layer.base","rootBoardRef":"board.root"},
            {"id":"layer.other","rootBoardRef":"board.other"}
        ],
        "boards":[
            {
                "id":"board.root",
                "entries":[
                    {
                        "id":"persist",
                        "rect":{"x":-1,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{"text":{"base":"P","transforms":[]}},
                                "transition":{
                                    "targetBoardRef":"board.relative",
                                    "lifetime":"persistent"
                                }
                            }
                        }
                    },
                    {
                        "id":"toggle",
                        "rect":{"x":2,"y":0,"width":1,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{"text":{"base":"T","transforms":[]}},
                                "onRelease":[
                                    {
                                        "actionID":"state.set",
                                        "arguments":{"state":"upper","value":true}
                                    }
                                ]
                            }
                        }
                    },
                    {
                        "id":"conditional",
                        "rect":{"x":4,"y":0,"width":4,"height":2},
                        "resolver":{
                            "cases":[
                                {
                                    "when":{"state":"upper"},
                                    "behavior":{
                                        "presentation":{
                                            "text":{"base":"UP","transforms":[]}
                                        }
                                    }
                                },
                                {
                                    "when":{"not":{"fact":"composition.empty"}},
                                    "behavior":{
                                        "presentation":{
                                            "text":{"base":"COMPOSING","transforms":[]}
                                        }
                                    }
                                }
                            ],
                            "default":{
                                "presentation":{
                                    "text":{"base":"down","transforms":[]}
                                }
                            }
                        }
                    },
                    {
                        "id":"dispatch",
                        "rect":{"x":8,"y":0,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{"text":{"base":"D","transforms":[]}},
                                "onRelease":[
                                    {
                                        "actionID":"cursor.move",
                                        "arguments":{"offset":1}
                                    },
                                    {
                                        "actionID":"text.insert",
                                        "arguments":{
                                            "text":{"base":"a","transforms":[]}
                                        }
                                    }
                                ]
                            }
                        }
                    }
                ]
            },
            {
                "id":"board.relative",
                "entries":[
                    {
                        "id":"relative.origin",
                        "rect":{"x":-1,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"O","transforms":[]}
                                }
                            }
                        }
                    },
                    {
                        "id":"relative.diagonal",
                        "rect":{"x":2,"y":2,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"↘","transforms":[]}
                                },
                                "onRelease":[
                                    {
                                        "actionID":"text.transform",
                                        "arguments":{"table":"kana.dakuten"}
                                    }
                                ]
                            }
                        }
                    },
                    {
                        "id":"relative.far",
                        "rect":{"x":6,"y":0,"width":1,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"F","transforms":[]}
                                }
                            }
                        }
                    }
                ]
            },
            {
                "id":"board.other",
                "entries":[
                    {
                        "id":"other.key",
                        "rect":{"x":0,"y":0,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"OTHER","transforms":[]}
                                }
                            }
                        }
                    }
                ]
            }
        ],
        "states":[
            {"id":"upper","type":"boolean","default":false}
        ],
        "transformTables":[
            {
                "id":"kana.dakuten",
                "entries":[{"from":"か","to":"が"}]
            }
        ],
        "macros":[]
    })
}

fn runtime() -> std::sync::Arc<ProfileV3PlatformRuntime> {
    ProfileV3PlatformRuntime::new(
        serde_json::to_string(&profile_value()).unwrap(),
    )
    .unwrap()
}

fn entry_text<'a>(
    surface: &'a gesture_ime_core::FfiProfileV3BoardSurface,
    id: &str,
) -> Option<&'a str> {
    surface
        .entries
        .iter()
        .find(|entry| entry.id == id)?
        .text
        .as_deref()
}

#[test]
fn a3_platform_initial_surface_uses_initial_layer_and_exact_rects() {
    let runtime = runtime();
    assert_eq!(runtime.active_layer_id().unwrap(), "layer.base");

    let surface = runtime.direct_surface().unwrap();
    assert_eq!(surface.layer_id, "layer.base");
    assert_eq!(surface.board_id, "board.root");
    assert_eq!(surface.context, FfiProfileV3BoardContext::Direct);
    assert_eq!(surface.entries.len(), 4);

    let half = surface
        .entries
        .iter()
        .find(|entry| entry.id == "toggle")
        .unwrap();
    assert_eq!(half.rect.x, 2);
    assert_eq!(half.rect.y, 0);
    assert_eq!(half.rect.width, 1);
    assert_eq!(half.rect.height, 2);

    let span = surface
        .entries
        .iter()
        .find(|entry| entry.id == "conditional")
        .unwrap();
    assert_eq!(span.rect.width, 4);

    let bounds = surface.bounds.unwrap();
    assert_eq!((bounds.min_x, bounds.min_y), (-1, -1));
    assert_eq!((bounds.max_x, bounds.max_y), (10, 2));
}

#[test]
fn a3_platform_surface_contains_only_authored_entries() {
    let runtime = runtime();
    let surface = runtime.direct_surface().unwrap();

    let ids = surface
        .entries
        .iter()
        .map(|entry| entry.id.as_str())
        .collect::<Vec<_>>();
    assert_eq!(ids, vec!["persist", "toggle", "conditional", "dispatch"]);
    assert!(!ids.iter().any(|id| id.contains("empty")));
}

#[test]
fn a3_platform_semantic_context_changes_future_surface_resolution() {
    let runtime = runtime();

    assert_eq!(
        entry_text(&runtime.direct_surface().unwrap(), "conditional"),
        Some("down")
    );

    runtime
        .update_semantic_context("x".into(), false, false)
        .unwrap();
    assert_eq!(
        entry_text(&runtime.direct_surface().unwrap(), "conditional"),
        Some("COMPOSING")
    );

    runtime
        .update_semantic_context(String::new(), false, false)
        .unwrap();

    let session = runtime
        .begin_session(
            "toggle".into(),
            FfiSize {
                width:100.0,
                height:80.0,
            },
            FfiPoint { x:10.0, y:10.0 },
            0,
        )
        .unwrap();
    session.touch_up(Some(10)).unwrap();

    assert_eq!(
        entry_text(&runtime.direct_surface().unwrap(), "conditional"),
        Some("UP")
    );
}

#[test]
fn a3_platform_same_layer_push_has_independent_persistent_frame() {
    let runtime = runtime();

    runtime.push_layer("layer.base".into()).unwrap();
    assert_eq!(runtime.active_layer_id().unwrap(), "layer.base");

    let session = runtime
        .begin_session(
            "persist".into(),
            FfiSize {
                width:100.0,
                height:100.0,
            },
            FfiPoint { x:20.0, y:20.0 },
            0,
        )
        .unwrap();

    let after_down = session.snapshot().unwrap();
    assert_eq!(after_down.current_board_id, "board.relative");
    assert_eq!(after_down.persistent_board_id, "board.relative");
    assert_eq!(after_down.context, FfiProfileV3BoardContext::Relative);

    session.touch_up(Some(10)).unwrap();
    assert_eq!(runtime.direct_surface().unwrap().board_id, "board.relative");

    runtime.pop_layer().unwrap();
    assert_eq!(runtime.direct_surface().unwrap().board_id, "board.root");
}

#[test]
fn a3_platform_relative_surface_and_candidate_use_v3_entry_ids() {
    let runtime = runtime();
    let session = runtime
        .begin_session(
            "persist".into(),
            FfiSize {
                width:100.0,
                height:80.0,
            },
            FfiPoint { x:0.0, y:0.0 },
            0,
        )
        .unwrap();

    let initial = session.snapshot().unwrap();
    assert_eq!(initial.surface.board_id, "board.relative");
    assert_eq!(initial.surface.context, FfiProfileV3BoardContext::Relative);
    assert_eq!(
        initial.surface.entries.iter().map(|entry| entry.id.as_str()).collect::<Vec<_>>(),
        vec!["relative.origin", "relative.diagonal", "relative.far"]
    );

    let moved = session
        .move_to(
            FfiPoint { x:100.0, y:80.0 },
            Some(10),
        )
        .unwrap();

    assert_eq!(
        moved.candidate_entry_id.as_deref(),
        Some("relative.diagonal")
    );
    assert_eq!(
        moved.surface.candidate_entry_id.as_deref(),
        Some("relative.diagonal")
    );
    assert_eq!(
        moved.current_endpoint_entry_id.as_deref(),
        Some("relative.diagonal")
    );
}

#[test]
fn a3_platform_runtime_dispatch_order_and_transform_projection_are_lossless() {
    let runtime = runtime();

    let ordinary = runtime
        .begin_session(
            "dispatch".into(),
            FfiSize {
                width:100.0,
                height:100.0,
            },
            FfiPoint { x:0.0, y:0.0 },
            0,
        )
        .unwrap()
        .touch_up(Some(10))
        .unwrap();

    assert_eq!(ordinary.runtime_dispatches.len(), 2);
    assert_eq!(
        ordinary.runtime_dispatches[0].kind,
        FfiProfileV3DispatchKind::Action
    );
    assert_eq!(
        ordinary.runtime_dispatches[0].action_id.as_deref(),
        Some("cursor.move")
    );
    assert_eq!(
        ordinary.runtime_dispatches[1].action_id.as_deref(),
        Some("text.insert")
    );
    assert_eq!(
        ordinary.runtime_dispatches[1].arguments_json.as_deref(),
        Some("{\"text\":\"a\"}")
    );

    runtime
        .update_semantic_context("か".into(), false, false)
        .unwrap();
    let relative = runtime
        .begin_session(
            "persist".into(),
            FfiSize {
                width:100.0,
                height:80.0,
            },
            FfiPoint { x:0.0, y:0.0 },
            0,
        )
        .unwrap();
    relative
        .move_to(FfiPoint { x:100.0, y:80.0 }, Some(10))
        .unwrap();
    let transformed = relative.touch_up(Some(20)).unwrap();

    assert_eq!(transformed.runtime_dispatches.len(), 1);
    let effect = &transformed.runtime_dispatches[0];
    assert_eq!(
        effect.kind,
        FfiProfileV3DispatchKind::CompositionTailTransform
    );
    assert_eq!(effect.table_id.as_deref(), Some("kana.dakuten"));
    assert_eq!(effect.matched_source.as_deref(), Some("か"));
    assert_eq!(effect.replacement.as_deref(), Some("が"));
}

#[test]
fn a3_platform_layer_stack_set_push_pop_and_bound_are_deterministic() {
    let runtime = runtime();

    runtime.push_layer("layer.other".into()).unwrap();
    assert_eq!(runtime.active_layer_id().unwrap(), "layer.other");
    assert_eq!(runtime.direct_surface().unwrap().board_id, "board.other");

    runtime.pop_layer().unwrap();
    assert_eq!(runtime.active_layer_id().unwrap(), "layer.base");

    runtime.set_layer("layer.other".into()).unwrap();
    assert_eq!(runtime.active_layer_id().unwrap(), "layer.other");

    runtime.set_layer("layer.base".into()).unwrap();
    for _ in 0..15 {
        runtime.push_layer("layer.base".into()).unwrap();
    }
    let error = runtime.push_layer("layer.base".into()).unwrap_err();
    assert!(matches!(error, ProfileV3PlatformError::LayerStackLimit));

    runtime.pop_layer().unwrap();
    runtime.push_layer("layer.base".into()).unwrap();
}

#[test]
fn a3_platform_profile_switch_remains_unavailable_at_activation() {
    let mut value = profile_value();
    value["boards"][0]["entries"][1]["resolver"]["default"]["onRelease"] =
        json!([
            {
                "actionID":"profile.switch",
                "arguments":{"profile":"profile.other"}
            }
        ]);

    let error = match ProfileV3PlatformRuntime::new(
        serde_json::to_string(&value).unwrap(),
    ) {
        Ok(_) => panic!("profile.switch profile unexpectedly activated"),
        Err(error) => error,
    };

    match error {
        ProfileV3PlatformError::InvalidProfile { code, .. } => {
            assert_eq!(code, "E_UNAVAILABLE_CAPABILITY");
        }
        other => panic!("unexpected error: {other:?}"),
    }
}
