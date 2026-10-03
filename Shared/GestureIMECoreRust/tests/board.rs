use gesture_ime_core::{
    board_map, BoardCoordinate, BoardProfileCodec, BoardSession, BoardSessionTerminal,
    ProfileLimits, ProfileValidationCode, GesturePoint, GestureSize,
};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..").join("..")
}

fn fixture(name: &str) -> Vec<u8> {
    fs::read(
        repo_root()
            .join("spec")
            .join("conformance")
            .join("fixtures")
            .join(name),
    )
    .expect("fixture")
}

fn new_session(
    profile_name: &str,
) -> (
    gesture_ime_core::ProfileBundleV2,
    Arc<Mutex<HashMap<String, String>>>,
    BoardSession,
) {
    let profile = BoardProfileCodec::decode_and_validate(&fixture(profile_name)).expect("profile");
    let entry = profile.entry_points.first().expect("entry").clone();
    let state = Arc::new(Mutex::new(HashMap::new()));
    let session = BoardSession::new(
        &entry,
        format!("{}:{}", profile.id, profile.version),
        Arc::new(board_map(&profile)),
        state.clone(),
        profile.gesture_policy.clone(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 0.0, y: 0.0 },
        0,
    )
    .expect("session");
    (profile, state, session)
}

#[test]
fn v2_cardinal_profile_validates_and_exposes_sparse_coordinates() {
    let profile = BoardProfileCodec::decode_and_validate(&fixture(
        "profile-v2-board-cardinal.valid.json",
    ))
    .expect("v2 valid");
    let board = profile.boards.iter().find(|board| board.id == "board.a").unwrap();
    let coordinates = board
        .entries
        .iter()
        .map(|entry| entry.coordinate)
        .collect::<std::collections::HashSet<_>>();

    assert!(coordinates.contains(&BoardCoordinate { x: 0, y: 0 }));
    assert!(coordinates.contains(&BoardCoordinate { x: -1, y: 0 }));
    assert!(coordinates.contains(&BoardCoordinate { x: 0, y: -1 }));
    assert!(coordinates.contains(&BoardCoordinate { x: 1, y: 0 }));
    assert!(coordinates.contains(&BoardCoordinate { x: 0, y: 1 }));
}

#[test]
fn duplicate_board_coordinate_is_rejected() {
    let error = BoardProfileCodec::decode_and_validate(&fixture(
        "profile-v2-duplicate-coordinate.invalid.json",
    ))
    .expect_err("duplicate coordinate must fail");
    assert_eq!(error.code, ProfileValidationCode::DuplicateBoardCoordinate);
}

#[test]
fn chained_board_transition_resets_local_origin() {
    let (_profile, _state, mut session) =
        new_session("profile-v2-board-chain.valid.json");

    session.move_to(GesturePoint { x: 50.0, y: 0.0 }, Some(10));
    assert_eq!(session.current_board_id, "board.e");
    assert_eq!(session.anchor, GesturePoint { x: 50.0, y: 0.0 });
    assert_eq!(session.transition_count, 1);

    session.move_to(GesturePoint { x: 50.0, y: -50.0 }, Some(20));
    assert_eq!(
        session.selected_coordinate,
        Some(BoardCoordinate { x: 0, y: -1 })
    );

    session.touch_up(Some(30));
    assert_eq!(session.terminal, Some(BoardSessionTerminal::Committed));
    assert_eq!(session.dispatched_actions.len(), 1);
    assert_eq!(session.dispatched_actions[0].action_id, "text.insert");
    assert_eq!(
        session.dispatched_actions[0]
            .arguments
            .get("text")
            .and_then(|value| value.as_str()),
        Some("two")
    );
}

#[test]
fn persistent_and_transient_lifetimes_follow_entry_point_baseline() {
    let (profile, state, mut first) =
        new_session("profile-v2-board-lifetime.valid.json");
    let entry = profile.entry_points.first().unwrap().clone();
    let boards = Arc::new(board_map(&profile));

    first.move_to(GesturePoint { x: 50.0, y: 0.0 }, Some(10));
    assert_eq!(first.current_board_id, "board.persistent");
    assert_eq!(first.persistent_board_id, "board.persistent");
    first.touch_up(Some(20));

    let mut second = BoardSession::new(
        &entry,
        "second",
        boards.clone(),
        state.clone(),
        profile.gesture_policy.clone(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 0.0, y: 0.0 },
        100,
    )
    .expect("second session");
    assert_eq!(second.current_board_id, "board.persistent");

    second.move_to(GesturePoint { x: 0.0, y: -50.0 }, Some(110));
    assert_eq!(second.current_board_id, "board.transient");
    assert_eq!(second.persistent_board_id, "board.persistent");
    second.touch_up(Some(120));

    assert_eq!(second.current_board_id, "board.persistent");
    assert_eq!(second.persistent_board_id, "board.persistent");
    assert_eq!(
        second.dispatched_actions.last().unwrap().arguments["text"],
        "T"
    );
}

#[test]
fn hold_uses_the_same_transient_board_transition_mechanism() {
    let (_profile, _state, mut session) =
        new_session("profile-v2-board-lifetime.valid.json");

    session.advance_time(300);
    assert_eq!(session.current_board_id, "board.hold");
    assert_eq!(session.persistent_board_id, "board.root");
    assert_eq!(session.transition_count, 1);

    session.touch_up(Some(310));
    assert_eq!(session.current_board_id, "board.root");
    assert_eq!(
        session.dispatched_actions.last().unwrap().arguments["text"],
        "H"
    );
}

#[test]
fn accepted_v1_profile_normalizes_to_board_graph() {
    let profile = BoardProfileCodec::decode_and_validate(&fixture(
        "profile-diagonal-two-stage.valid.json",
    ))
    .expect("v1 should normalize");

    assert_eq!(profile.schema, "gesture-ime.profile.v2");
    assert!(!profile.boards.is_empty());
    assert!(!profile.entry_points.is_empty());

    let has_chained_transition = profile.boards.iter().any(|board| {
        board.entries.iter().any(|entry| entry.transition.is_some())
    });
    assert!(has_chained_transition);
}


#[test]
fn cyclic_board_graph_is_runtime_bounded_per_interaction() {
    let json = r#"
    {
      "schema":"gesture-ime.profile.v2",
      "id":"fixture.v2.cycle",
      "name":"Cycle",
      "version":1,
      "gesturePolicy":{
        "deadZone":0.1,
        "initialCellCommitDistance":0.3,
        "subsequentCellCommitDistance":0.3,
        "angularHysteresisDegrees":8
      },
      "keyDefinitions":[{"id":"key.test"}],
      "layouts":[{"id":"layout.base","placements":[{"keyID":"key.test","row":0,"column":0}]}],
      "layers":[{"id":"base","layoutRef":"layout.base"}],
      "boards":[
        {
          "id":"board.loop",
          "selectionPolicy":{"kind":"relativeCoordinate"},
          "entries":[
            {
              "coordinate":{"x":1,"y":0},
              "transition":{"targetBoardRef":"board.loop","lifetime":"transient"}
            }
          ]
        }
      ],
      "entryPoints":[
        {"id":"entry.loop","layerID":"base","keyID":"key.test","trigger":"press","boardRef":"board.loop"}
      ],
      "macros":[]
    }
    "#;

    let profile = BoardProfileCodec::decode_and_validate(json.as_bytes()).expect("cycle valid");
    let entry = profile.entry_points.first().unwrap().clone();
    let mut session = BoardSession::new(
        &entry,
        "cycle",
        Arc::new(board_map(&profile)),
        Arc::new(Mutex::new(HashMap::new())),
        profile.gesture_policy.clone(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 0.0, y: 0.0 },
        0,
    )
    .expect("session");

    for index in 1..=ProfileLimits::BOARD_TRANSITIONS_PER_INTERACTION + 4 {
        session.move_to(
            GesturePoint {
                x: index as f64 * 40.0,
                y: 0.0,
            },
            Some(index as i64),
        );
    }

    assert_eq!(
        session.transition_count,
        ProfileLimits::BOARD_TRANSITIONS_PER_INTERACTION
    );
    assert!(session.transition_limit_hit);
    assert!(session.selected_coordinate.is_some());
    assert!(
        session.committed_coordinates.len()
            <= ProfileLimits::BOARD_TRANSITIONS_PER_INTERACTION + 1
    );
}


#[test]
fn transient_chain_returns_directly_to_persistent_baseline() {
    let (_profile, _state, mut session) =
        new_session("profile-v2-board-transient-chain.valid.json");

    session.move_to(GesturePoint { x: 40.0, y: 0.0 }, Some(10));
    assert_eq!(session.current_board_id, "board.t1");
    assert_eq!(session.persistent_board_id, "board.root");

    session.move_to(GesturePoint { x: 40.0, y: -40.0 }, Some(20));
    assert_eq!(session.current_board_id, "board.t2");
    assert_eq!(session.persistent_board_id, "board.root");

    session.touch_up(Some(30));
    assert_eq!(session.current_board_id, "board.root");
    assert_eq!(
        session.dispatched_actions.last().unwrap().arguments["text"],
        "T2"
    );
}

#[test]
fn persistent_transition_from_transient_board_replaces_baseline() {
    let (profile, state, mut first) =
        new_session("profile-v2-board-transient-chain.valid.json");
    let entry = profile.entry_points.first().unwrap().clone();
    let boards = Arc::new(board_map(&profile));

    first.move_to(GesturePoint { x: 40.0, y: 0.0 }, Some(10));
    assert_eq!(first.current_board_id, "board.t1");
    assert_eq!(first.persistent_board_id, "board.root");

    first.move_to(GesturePoint { x: 40.0, y: 40.0 }, Some(20));
    assert_eq!(first.current_board_id, "board.p");
    assert_eq!(first.persistent_board_id, "board.p");
    first.touch_up(Some(30));
    assert_eq!(first.current_board_id, "board.p");

    let second = BoardSession::new(
        &entry,
        "after-promotion",
        boards,
        state,
        profile.gesture_policy,
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 0.0, y: 0.0 },
        100,
    )
    .expect("second session");
    assert_eq!(second.current_board_id, "board.p");
    assert_eq!(second.persistent_board_id, "board.p");
}


#[test]
fn precommit_candidate_preserves_wider_same_ray_reachability() {
    let json = r#"
    {
      "schema":"gesture-ime.profile.v2",
      "id":"fixture.v2.wider-ray",
      "name":"Wider ray",
      "version":1,
      "gesturePolicy":{
        "deadZone":0.1,
        "initialCellCommitDistance":0.4,
        "subsequentCellCommitDistance":0.4,
        "angularHysteresisDegrees":8
      },
      "keyDefinitions":[{"id":"key.test"}],
      "layouts":[{"id":"layout.base","placements":[{"keyID":"key.test","row":0,"column":0}]}],
      "layers":[{"id":"base","layoutRef":"layout.base"}],
      "boards":[
        {
          "id":"board.root",
          "selectionPolicy":{"kind":"relativeCoordinate"},
          "entries":[
            {"coordinate":{"x":0,"y":0},"onRelease":[]},
            {"coordinate":{"x":1,"y":0},"onRelease":[]},
            {"coordinate":{"x":2,"y":0},"onRelease":[]}
          ]
        }
      ],
      "entryPoints":[
        {"id":"entry.test","layerID":"base","keyID":"key.test","trigger":"press","boardRef":"board.root"}
      ],
      "macros":[]
    }
    "#;

    let profile = BoardProfileCodec::decode_and_validate(json.as_bytes()).expect("profile");
    let entry = profile.entry_points.first().expect("entry").clone();
    let boards = Arc::new(board_map(&profile));

    let mut gradual = BoardSession::new(
        &entry,
        "gradual",
        boards.clone(),
        Arc::new(Mutex::new(HashMap::new())),
        profile.gesture_policy.clone(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 0.0, y: 0.0 },
        0,
    )
    .expect("gradual session");
    gradual.move_to(GesturePoint { x: 20.0, y: 0.0 }, None);
    assert_eq!(
        gradual.candidate_coordinate,
        Some(BoardCoordinate { x: 1, y: 0 })
    );
    assert!(gradual.committed_coordinates.is_empty());

    let mut jump = BoardSession::new(
        &entry,
        "jump",
        boards,
        Arc::new(Mutex::new(HashMap::new())),
        profile.gesture_policy,
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 0.0, y: 0.0 },
        0,
    )
    .expect("jump session");
    jump.move_to(GesturePoint { x: 90.0, y: 0.0 }, None);
    assert_eq!(
        jump.committed_coordinates,
        vec![BoardCoordinate { x: 2, y: 0 }]
    );
}

#[test]
fn accepted_v1_duplicate_key_placements_normalize_once_per_layer() {
    let json = r#"
    {
      "schema":"gesture-ime.profile.v1",
      "id":"fixture.v1.duplicate-placement",
      "name":"Duplicate placement",
      "version":1,
      "gesturePolicy":{
        "deadZone":0.1,
        "stage1CommitDistance":0.3,
        "stage2CommitDistance":0.3,
        "angularHysteresisDegrees":8,
        "maxDirectionalStages":2
      },
      "keyDefinitions":[{"id":"key.test"}],
      "layouts":[
        {
          "id":"layout.base",
          "placements":[
            {"keyID":"key.test","row":0,"column":0},
            {"keyID":"key.test","row":0,"column":1}
          ]
        }
      ],
      "bindingSets":[
        {
          "id":"bindings.base",
          "bindings":[
            {
              "keyID":"key.test",
              "path":[],
              "behavior":{
                "onRelease":[{"actionID":"text.insert","arguments":{"text":"x"}}]
              }
            }
          ]
        }
      ],
      "layers":[
        {"id":"base","layoutRef":"layout.base","bindingSetRef":"bindings.base"}
      ],
      "macros":[]
    }
    "#;

    let profile = BoardProfileCodec::decode_and_validate(json.as_bytes())
        .expect("accepted v1 with duplicate placement must normalize");

    assert_eq!(profile.entry_points.len(), 1);
    assert_eq!(
        profile
            .boards
            .iter()
            .filter(|board| board.id == profile.entry_points[0].board_ref)
            .count(),
        1
    );
}


#[test]
fn center_release_uses_source_actions_before_persistent_transition() {
    let json = r#"
    {
      "schema":"gesture-ime.profile.v2",
      "id":"fixture.v2.center-transition",
      "name":"Center transition",
      "version":1,
      "gesturePolicy":{
        "deadZone":0.1,
        "initialCellCommitDistance":0.3,
        "subsequentCellCommitDistance":0.3,
        "angularHysteresisDegrees":8
      },
      "keyDefinitions":[{"id":"key.test","presentation":{"text":"K"}}],
      "layouts":[{"id":"layout.base","placements":[{"keyID":"key.test","row":0,"column":0}]}],
      "layers":[{"id":"base","layoutRef":"layout.base"}],
      "boards":[
        {
          "id":"board.root",
          "selectionPolicy":{"kind":"relativeCoordinate"},
          "entries":[
            {
              "coordinate":{"x":0,"y":0},
              "onRelease":[{"actionID":"text.insert","arguments":{"text":"source"}}],
              "transition":{"targetBoardRef":"board.target","lifetime":"persistent"}
            }
          ]
        },
        {
          "id":"board.target",
          "selectionPolicy":{"kind":"relativeCoordinate"},
          "entries":[
            {
              "coordinate":{"x":0,"y":0},
              "onRelease":[{"actionID":"text.insert","arguments":{"text":"target"}}]
            }
          ]
        }
      ],
      "entryPoints":[
        {"id":"entry.test","layerID":"base","keyID":"key.test","trigger":"press","boardRef":"board.root"}
      ],
      "macros":[]
    }
    "#;

    let profile = BoardProfileCodec::decode_and_validate(json.as_bytes()).expect("profile");
    let entry = profile.entry_points.first().unwrap().clone();
    let state = Arc::new(Mutex::new(HashMap::new()));
    let boards = Arc::new(board_map(&profile));

    let mut first = BoardSession::new(
        &entry,
        "first",
        boards.clone(),
        state.clone(),
        profile.gesture_policy.clone(),
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 0.0, y: 0.0 },
        0,
    )
    .expect("first");
    first.touch_up(Some(10));

    assert_eq!(first.persistent_board_id, "board.target");
    assert_eq!(first.dispatched_actions.len(), 1);
    assert_eq!(
        first.dispatched_actions[0].arguments["text"],
        "source"
    );

    let mut second = BoardSession::new(
        &entry,
        "second",
        boards,
        state,
        profile.gesture_policy,
        GestureSize {
            width: 100.0,
            height: 100.0,
        },
        GesturePoint { x: 0.0, y: 0.0 },
        20,
    )
    .expect("second");
    assert_eq!(second.current_board_id, "board.target");
    second.touch_up(Some(30));
    assert_eq!(
        second.dispatched_actions[0].arguments["text"],
        "target"
    );
}


#[test]
fn accepted_v1_shared_binding_set_reuses_compatibility_boards_across_layers() {
    let json = r#"
    {
      "schema":"gesture-ime.profile.v1",
      "id":"fixture.v1.shared-binding-set",
      "name":"Shared binding set",
      "version":1,
      "gesturePolicy":{
        "deadZone":0.1,
        "stage1CommitDistance":0.3,
        "stage2CommitDistance":0.3,
        "angularHysteresisDegrees":8,
        "maxDirectionalStages":2
      },
      "keyDefinitions":[{"id":"key.test"}],
      "layouts":[
        {"id":"layout.a","placements":[{"keyID":"key.test","row":0,"column":0}]},
        {"id":"layout.b","placements":[{"keyID":"key.test","row":0,"column":0}]}
      ],
      "bindingSets":[
        {
          "id":"bindings.shared",
          "bindings":[
            {
              "keyID":"key.test",
              "path":[],
              "behavior":{
                "onRelease":[{"actionID":"text.insert","arguments":{"text":"x"}}]
              }
            }
          ]
        }
      ],
      "layers":[
        {"id":"layer.a","layoutRef":"layout.a","bindingSetRef":"bindings.shared"},
        {"id":"layer.b","layoutRef":"layout.b","bindingSetRef":"bindings.shared"}
      ],
      "macros":[]
    }
    "#;

    let profile = BoardProfileCodec::decode_and_validate(json.as_bytes())
        .expect("accepted v1 must normalize");
    assert_eq!(profile.entry_points.len(), 2);
    assert_eq!(profile.boards.len(), 1);
    assert_eq!(
        profile.entry_points[0].board_ref,
        profile.entry_points[1].board_ref
    );
}

#[test]
fn v2_graph_limits_cover_the_accepted_v1_layer_key_envelope() {
    assert!(ProfileLimits::BOARDS >= ProfileLimits::TRIE_NODES);
    assert!(
        ProfileLimits::ENTRY_POINTS
            >= ProfileLimits::LAYERS * ProfileLimits::PLACEMENTS_PER_LAYOUT
    );
}
