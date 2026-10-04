use gesture_ime_core::{
    BoardContextV3, DefaultBoardSemanticsV3, GesturePoint, GestureSize, ProfileV3BoardRuntime,
    ProfileV3Codec,
};
use serde_json::{json, Value};

fn profile_json() -> Value {
    json!({
        "schema":"gesture-ime.profile.v3",
        "id":"profile.a1b.test",
        "name":"A1b Test",
        "version":1,
        "gesturePolicy":{
            "deadZone":0.10,
            "initialCellCommitDistance":0.55,
            "subsequentCellCommitDistance":0.45,
            "angularHysteresisDegrees":8
        },
        "initialLayerRef":"layer.base",
        "layers":[
            {"id":"layer.base","rootBoardRef":"board.root"}
        ],
        "boards":[
            {
                "id":"board.root",
                "entries":[
                    {
                        "id":"direct.transition",
                        "rect":{"x":-1,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "onRelease":[
                                    {"actionID":"cursor.move","arguments":{"offset":9}}
                                ],
                                "transition":{
                                    "targetBoardRef":"board.flick",
                                    "lifetime":"transient"
                                }
                            }
                        }
                    },
                    {
                        "id":"direct.plain",
                        "rect":{"x":1,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "onRelease":[
                                    {"actionID":"cursor.move","arguments":{"offset":20}}
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
                                "onRelease":[
                                    {"actionID":"cursor.move","arguments":{"offset":10}}
                                ]
                            }
                        }
                    },
                    {
                        "id":"east",
                        "rect":{"x":1,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "onRelease":[
                                    {"actionID":"cursor.move","arguments":{"offset":11}}
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
                                "onRelease":[
                                    {"actionID":"cursor.move","arguments":{"offset":12}}
                                ]
                            }
                        }
                    },
                    {
                        "id":"far.east",
                        "rect":{"x":3,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "onRelease":[
                                    {"actionID":"cursor.move","arguments":{"offset":13}}
                                ]
                            }
                        }
                    },
                    {
                        "id":"half.west",
                        "rect":{"x":-3,"y":-1,"width":1,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "onRelease":[
                                    {"actionID":"cursor.move","arguments":{"offset":14}}
                                ]
                            }
                        }
                    }
                ]
            }
        ],
        "states":[],
        "transformTables":[],
        "macros":[]
    })
}

fn runtime() -> ProfileV3BoardRuntime {
    let bytes = serde_json::to_vec(&profile_json()).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    ProfileV3BoardRuntime::compile(&profile, "a1b-test").unwrap()
}

fn relative_session(cell_width: f64, cell_height: f64) -> gesture_ime_core::BoardSessionV3 {
    let runtime = runtime();
    let frame = runtime.new_frame("layer.base").unwrap();
    runtime
        .begin_direct_session(
            frame,
            "direct.transition",
            GestureSize {
                width: cell_width,
                height: cell_height,
            },
            GesturePoint { x: 0.0, y: 0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap()
}

fn action_offsets(session: &gesture_ime_core::BoardSessionV3) -> Vec<i64> {
    session
        .dispatched_actions
        .iter()
        .filter_map(|action| action.arguments.get("offset")?.as_i64())
        .collect()
}

fn assert_close(actual: f64, expected: f64) {
    assert!((actual - expected).abs() < 1e-9, "{actual} != {expected}");
}

#[test]
fn v3_candidates_derive_from_rect_centers() {
    let session = relative_session(100.0, 50.0);

    assert_eq!(session.context, BoardContextV3::Relative);
    assert_eq!(session.current_board_id, "board.flick");
    assert_eq!(session.current_endpoint_entry_id.as_deref(), Some("origin"));

    let candidates = session.eligible_candidates();
    assert_eq!(candidates.len(), 4);
    assert!(!candidates.iter().any(|candidate| candidate.entry_id == "origin"));

    let east = candidates.iter().find(|item| item.entry_id == "east").unwrap();
    assert_close(east.center_x, 1.0);
    assert_close(east.center_y, 0.0);
    assert_close(east.radius, 1.0);

    let ne = candidates.iter().find(|item| item.entry_id == "ne").unwrap();
    assert_close(ne.center_x, 1.0);
    assert_close(ne.center_y, -1.0);
    assert_close(ne.radius, 1.0);

    let far = candidates
        .iter()
        .find(|item| item.entry_id == "far.east")
        .unwrap();
    assert_close(far.center_x, 2.0);
    assert_close(far.center_y, 0.0);
    assert_close(far.radius, 2.0);

    let half = candidates
        .iter()
        .find(|item| item.entry_id == "half.west")
        .unwrap();
    assert_close(half.center_x, -1.25);
    assert_close(half.center_y, 0.0);
    assert_close(half.radius, 1.25);
}

#[test]
fn v3_non_square_cell_size_maps_physical_motion_to_logical_geometry() {
    let mut session = relative_session(100.0, 50.0);

    session.move_to(GesturePoint { x: 60.0, y: 0.0 }, Some(10));

    assert_eq!(session.committed_entry_ids, vec!["east"]);
    assert_eq!(session.current_endpoint_entry_id.as_deref(), Some("east"));

    session.touch_up(Some(20));
    assert_eq!(action_offsets(&session), vec![11]);
}

#[test]
fn v3_diagonal_candidate_uses_authored_rect_geometry() {
    let mut session = relative_session(100.0, 50.0);

    session.move_to(GesturePoint { x: 60.0, y: -30.0 }, Some(10));
    assert_eq!(session.committed_entry_ids, vec!["ne"]);

    session.touch_up(Some(20));
    assert_eq!(action_offsets(&session), vec![12]);
}

#[test]
fn v3_same_ray_reachable_tie_prefers_farthest_radius() {
    let mut session = relative_session(100.0, 50.0);

    // One sampled move jumps past both radius-1 and radius-2 thresholds.
    session.move_to(GesturePoint { x: 120.0, y: 0.0 }, Some(10));

    assert_eq!(session.committed_entry_ids, vec!["far.east"]);
    session.touch_up(Some(20));
    assert_eq!(action_offsets(&session), vec![13]);
}

#[test]
fn v3_precommit_highlight_does_not_replace_origin_release_endpoint() {
    let mut session = relative_session(100.0, 50.0);

    session.move_to(GesturePoint { x: 30.0, y: 0.0 }, Some(10));

    assert_eq!(session.candidate_entry_id.as_deref(), Some("east"));
    assert!(session.committed_entry_ids.is_empty());
    assert_eq!(session.current_endpoint_entry_id.as_deref(), Some("origin"));

    session.touch_up(Some(20));
    assert_eq!(action_offsets(&session), vec![10]);
}

#[test]
fn v3_direct_entry_without_transition_releases_normally() {
    let runtime = runtime();
    let frame = runtime.new_frame("layer.base").unwrap();
    let mut session = runtime
        .begin_direct_session(
            frame,
            "direct.plain",
            GestureSize {
                width: 100.0,
                height: 50.0,
            },
            GesturePoint { x: 0.0, y: 0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();

    assert_eq!(session.context, BoardContextV3::Direct);
    session.move_to(GesturePoint { x: 200.0, y: 0.0 }, Some(10));
    assert!(session.committed_entry_ids.is_empty());

    session.touch_up(Some(20));
    assert_eq!(action_offsets(&session), vec![20]);
}

#[test]
fn v3_direct_transition_suppresses_source_release_and_uses_target_origin() {
    let mut session = relative_session(100.0, 50.0);

    assert_eq!(session.transition_count, 1);
    assert_eq!(session.commit_anchors, vec![GesturePoint { x: 0.0, y: 0.0 }]);

    session.touch_up(Some(20));

    assert_eq!(action_offsets(&session), vec![10]);
    assert!(!action_offsets(&session).contains(&9));
}


fn runtime_from_value(value: &Value) -> ProfileV3BoardRuntime {
    let bytes = serde_json::to_vec(value).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    ProfileV3BoardRuntime::compile(&profile, "a1b-custom").unwrap()
}

fn add_origin_board(value: &mut Value, board_id: &str, origin_id: &str, offset: i64) {
    value["boards"]
        .as_array_mut()
        .unwrap()
        .push(json!({
            "id":board_id,
            "entries":[
                {
                    "id":origin_id,
                    "rect":{"x":-1,"y":-1,"width":2,"height":2},
                    "resolver":{
                        "cases":[],
                        "default":{
                            "onRelease":[
                                {"actionID":"cursor.move","arguments":{"offset":offset}}
                            ]
                        }
                    }
                }
            ]
        }));
}

#[test]
fn v3_transient_transition_returns_to_layer_persistent_baseline() {
    let mut value = profile_json();
    add_origin_board(&mut value, "board.second", "second.origin", 40);
    value["boards"][1]["entries"][1]["resolver"]["default"]["transition"] = json!({
        "targetBoardRef":"board.second",
        "lifetime":"transient"
    });

    let runtime = runtime_from_value(&value);
    let frame = runtime.new_frame("layer.base").unwrap();
    let mut session = runtime
        .begin_direct_session(
            frame,
            "direct.transition",
            GestureSize { width:100.0, height:50.0 },
            GesturePoint { x:0.0, y:0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();

    session.move_to(GesturePoint { x:60.0, y:0.0 }, Some(10));

    assert_eq!(session.current_board_id, "board.second");
    assert_eq!(session.persistent_board_id().as_deref(), Some("board.root"));
    assert_eq!(session.transition_count, 2);

    session.touch_up(Some(20));
    assert_eq!(session.current_board_id, "board.root");
    assert_eq!(session.context, BoardContextV3::Direct);
}

#[test]
fn v3_persistent_transition_replaces_layer_baseline() {
    let mut value = profile_json();
    add_origin_board(&mut value, "board.persist", "persist.origin", 41);
    value["boards"][1]["entries"][1]["resolver"]["default"]["transition"] = json!({
        "targetBoardRef":"board.persist",
        "lifetime":"persistent"
    });

    let runtime = runtime_from_value(&value);
    let frame = runtime.new_frame("layer.base").unwrap();
    let mut session = runtime
        .begin_direct_session(
            frame,
            "direct.transition",
            GestureSize { width:100.0, height:50.0 },
            GesturePoint { x:0.0, y:0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();

    session.move_to(GesturePoint { x:60.0, y:0.0 }, Some(10));

    assert_eq!(session.current_board_id, "board.persist");
    assert_eq!(session.persistent_board_id().as_deref(), Some("board.persist"));

    session.touch_up(Some(20));
    assert_eq!(session.current_board_id, "board.persist");
    assert_eq!(session.context, BoardContextV3::Direct);
}

#[test]
fn v3_persistent_transition_through_transient_chain_reanchors_each_stage() {
    let mut value = profile_json();

    value["boards"][1]["entries"][1]["resolver"]["default"]["transition"] = json!({
        "targetBoardRef":"board.second",
        "lifetime":"transient"
    });

    value["boards"]
        .as_array_mut()
        .unwrap()
        .push(json!({
            "id":"board.second",
            "entries":[
                {
                    "id":"second.origin",
                    "rect":{"x":-1,"y":-1,"width":2,"height":2},
                    "resolver":{"cases":[],"default":{"onRelease":[]}}
                },
                {
                    "id":"second.east",
                    "rect":{"x":1,"y":-1,"width":2,"height":2},
                    "resolver":{
                        "cases":[],
                        "default":{
                            "onRelease":[],
                            "transition":{
                                "targetBoardRef":"board.persist",
                                "lifetime":"persistent"
                            }
                        }
                    }
                }
            ]
        }));
    add_origin_board(&mut value, "board.persist", "persist.origin", 42);

    let runtime = runtime_from_value(&value);
    let frame = runtime.new_frame("layer.base").unwrap();
    let mut session = runtime
        .begin_direct_session(
            frame,
            "direct.transition",
            GestureSize { width:100.0, height:50.0 },
            GesturePoint { x:0.0, y:0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();

    session.move_to(GesturePoint { x:60.0, y:0.0 }, Some(10));
    assert_eq!(session.current_board_id, "board.second");
    assert_eq!(session.anchor, GesturePoint { x:60.0, y:0.0 });

    // Subsequent threshold is 0.45 after the relative transition/re-anchor.
    session.move_to(GesturePoint { x:110.0, y:0.0 }, Some(20));

    assert_eq!(session.current_board_id, "board.persist");
    assert_eq!(session.persistent_board_id().as_deref(), Some("board.persist"));
    assert_eq!(session.transition_count, 3);
    assert_eq!(
        session.commit_anchors,
        vec![
            GesturePoint { x:0.0, y:0.0 },
            GesturePoint { x:60.0, y:0.0 },
            GesturePoint { x:110.0, y:0.0 }
        ]
    );
}

#[test]
fn v3_origin_release_actions_run_before_release_transition_and_persist() {
    let mut value = profile_json();
    add_origin_board(&mut value, "board.persist", "persist.origin", 43);
    value["boards"][1]["entries"][0]["resolver"]["default"]["transition"] = json!({
        "targetBoardRef":"board.persist",
        "lifetime":"persistent"
    });

    let runtime = runtime_from_value(&value);
    let frame = runtime.new_frame("layer.base").unwrap();
    let mut session = runtime
        .begin_direct_session(
            frame,
            "direct.transition",
            GestureSize { width:100.0, height:50.0 },
            GesturePoint { x:0.0, y:0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();

    session.touch_up(Some(10));

    assert_eq!(action_offsets(&session), vec![10]);
    assert_eq!(session.persistent_board_id().as_deref(), Some("board.persist"));
    assert_eq!(session.current_board_id, "board.persist");
    assert_eq!(session.transition_count, 2);
}

#[test]
fn v3_hold_without_transition_locks_direction_and_repeats() {
    let mut value = profile_json();
    value["boards"][1]["entries"][0]["resolver"]["default"]["hold"] = json!({
        "delayMs":100,
        "onStart":[
            {"actionID":"cursor.move","arguments":{"offset":30}}
        ],
        "repeat":{
            "intervalMs":50,
            "actions":[
                {"actionID":"cursor.move","arguments":{"offset":31}}
            ]
        },
        "suppressOnReleaseAfterStart":true
    });

    let runtime = runtime_from_value(&value);
    let frame = runtime.new_frame("layer.base").unwrap();
    let mut session = runtime
        .begin_direct_session(
            frame,
            "direct.transition",
            GestureSize { width:100.0, height:50.0 },
            GesturePoint { x:0.0, y:0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();

    session.advance_time(100);
    session.move_to(GesturePoint { x:100.0, y:0.0 }, Some(120));
    assert!(session.committed_entry_ids.is_empty());

    session.advance_time(200);
    session.touch_up(Some(210));

    assert_eq!(action_offsets(&session), vec![30, 31, 31]);
}

#[test]
fn v3_hold_transition_dispatches_on_start_then_reanchors_and_stops_source_repeat() {
    let mut value = profile_json();
    add_origin_board(&mut value, "board.second", "second.origin", 40);
    value["boards"][1]["entries"][0]["resolver"]["default"]["hold"] = json!({
        "delayMs":100,
        "onStart":[
            {"actionID":"cursor.move","arguments":{"offset":30}}
        ],
        "transition":{
            "targetBoardRef":"board.second",
            "lifetime":"transient"
        },
        "repeat":{
            "intervalMs":50,
            "actions":[
                {"actionID":"cursor.move","arguments":{"offset":31}}
            ]
        },
        "suppressOnReleaseAfterStart":true
    });

    let runtime = runtime_from_value(&value);
    let frame = runtime.new_frame("layer.base").unwrap();
    let mut session = runtime
        .begin_direct_session(
            frame,
            "direct.transition",
            GestureSize { width:100.0, height:50.0 },
            GesturePoint { x:0.0, y:0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();

    // Highlight east without committing; Hold still belongs to the origin endpoint.
    session.move_to(GesturePoint { x:30.0, y:0.0 }, Some(50));
    session.advance_time(100);

    assert_eq!(action_offsets(&session), vec![30]);
    assert_eq!(session.current_board_id, "board.second");
    assert_eq!(session.anchor, GesturePoint { x:30.0, y:0.0 });

    session.advance_time(300);
    assert_eq!(action_offsets(&session), vec![30]);

    session.touch_up(Some(310));
    assert_eq!(action_offsets(&session), vec![30, 40]);
}

#[test]
fn v3_cancel_and_invalidate_dispatch_no_later_hold_or_release() {
    let mut value = profile_json();
    value["boards"][1]["entries"][0]["resolver"]["default"]["hold"] = json!({
        "delayMs":100,
        "onStart":[
            {"actionID":"cursor.move","arguments":{"offset":30}}
        ],
        "suppressOnReleaseAfterStart":false
    });

    let runtime = runtime_from_value(&value);

    let frame_cancel = runtime.new_frame("layer.base").unwrap();
    let mut cancelled = runtime
        .begin_direct_session(
            frame_cancel,
            "direct.transition",
            GestureSize { width:100.0, height:50.0 },
            GesturePoint { x:0.0, y:0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();
    cancelled.cancel(Some(50));
    cancelled.advance_time(200);
    cancelled.touch_up(Some(210));
    assert!(cancelled.dispatched_actions.is_empty());

    let frame_invalidate = runtime.new_frame("layer.base").unwrap();
    let mut invalidated = runtime
        .begin_direct_session(
            frame_invalidate,
            "direct.transition",
            GestureSize { width:100.0, height:50.0 },
            GesturePoint { x:0.0, y:0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();
    invalidated.invalidate(Some(50));
    invalidated.advance_time(200);
    invalidated.touch_up(Some(210));
    assert!(invalidated.dispatched_actions.is_empty());
}

#[test]
fn v3_transition_cycle_stops_at_sixteen_and_keeps_failed_source_as_release_endpoint() {
    let mut value = profile_json();
    value["boards"][0]["entries"][0]["resolver"]["default"]["transition"]["targetBoardRef"] =
        json!("board.a");

    value["boards"]
        .as_array_mut()
        .unwrap()
        .push(json!({
            "id":"board.a",
            "entries":[
                {
                    "id":"a.origin",
                    "rect":{"x":-1,"y":-1,"width":2,"height":2},
                    "resolver":{"cases":[],"default":{"onRelease":[]}}
                },
                {
                    "id":"a.east",
                    "rect":{"x":1,"y":-1,"width":2,"height":2},
                    "resolver":{
                        "cases":[],
                        "default":{
                            "onRelease":[
                                {"actionID":"cursor.move","arguments":{"offset":50}}
                            ],
                            "transition":{
                                "targetBoardRef":"board.b",
                                "lifetime":"transient"
                            }
                        }
                    }
                }
            ]
        }));
    value["boards"]
        .as_array_mut()
        .unwrap()
        .push(json!({
            "id":"board.b",
            "entries":[
                {
                    "id":"b.origin",
                    "rect":{"x":-1,"y":-1,"width":2,"height":2},
                    "resolver":{"cases":[],"default":{"onRelease":[]}}
                },
                {
                    "id":"b.east",
                    "rect":{"x":1,"y":-1,"width":2,"height":2},
                    "resolver":{
                        "cases":[],
                        "default":{
                            "onRelease":[
                                {"actionID":"cursor.move","arguments":{"offset":51}}
                            ],
                            "transition":{
                                "targetBoardRef":"board.a",
                                "lifetime":"transient"
                            }
                        }
                    }
                }
            ]
        }));

    let runtime = runtime_from_value(&value);
    let frame = runtime.new_frame("layer.base").unwrap();
    let mut session = runtime
        .begin_direct_session(
            frame,
            "direct.transition",
            GestureSize { width:100.0, height:50.0 },
            GesturePoint { x:0.0, y:0.0 },
            0,
            Box::<DefaultBoardSemanticsV3>::default(),
        )
        .unwrap();

    for step in 0..16 {
        let point = GesturePoint {
            x: session.anchor.x + 60.0,
            y: session.anchor.y,
        };
        session.move_to(point, Some((step + 1) as i64 * 10));
    }

    assert_eq!(session.transition_count, 16);
    assert!(session.transition_limit_hit);
    assert_eq!(session.committed_entry_ids.len(), 16);
    assert_eq!(session.commit_anchors.len(), 16);

    session.touch_up(Some(200));
    assert_eq!(action_offsets(&session).len(), 1);
    assert!(matches!(action_offsets(&session)[0], 50 | 51));
}

#[test]
fn v3_angular_hysteresis_prevents_precommit_candidate_chatter() {
    let mut session = relative_session(100.0, 100.0);

    session.move_to(
        GesturePoint {
            x: 28.19,
            y: -10.26,
        },
        Some(10),
    );
    assert_eq!(session.candidate_entry_id.as_deref(), Some("east"));

    // Around -24 degrees NE is slightly closer, but not by the 8-degree hysteresis margin.
    session.move_to(
        GesturePoint {
            x: 27.4,
            y: -12.2,
        },
        Some(20),
    );
    assert_eq!(session.candidate_entry_id.as_deref(), Some("east"));

    // A larger angular move crosses the hysteresis margin.
    session.move_to(
        GesturePoint {
            x: 24.57,
            y: -17.21,
        },
        Some(30),
    );
    assert_eq!(session.candidate_entry_id.as_deref(), Some("ne"));
}

#[test]
fn v3_equal_angle_distance_tie_uses_canonical_center_order() {
    let mut session = relative_session(100.0, 100.0);
    let angle = std::f64::consts::FRAC_PI_8;
    let distance = 80.0;

    session.move_to(
        GesturePoint {
            x: distance * angle.cos(),
            y: -distance * angle.sin(),
        },
        Some(10),
    );

    // E and NE are equally distant in angle and equal radius.
    // center y is the next canonical tie-break, so NE (-1) precedes E (0).
    assert_eq!(session.committed_entry_ids, vec!["ne"]);
}
