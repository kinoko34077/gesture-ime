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
