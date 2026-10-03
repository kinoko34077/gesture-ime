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
