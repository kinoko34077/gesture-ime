use gesture_ime_core::{
    ProfileV3Codec, ProfileValidationCode, ProfileValidationError,
};
use serde_json::{json, Value};

fn base_profile() -> Value {
    json!({
        "schema": "gesture-ime.profile.v3",
        "id": "profile.v3.validation",
        "name": "V3 Validation",
        "version": 1,
        "gesturePolicy": {
            "deadZone": 0.15,
            "initialCellCommitDistance": 0.55,
            "subsequentCellCommitDistance": 0.45,
            "angularHysteresisDegrees": 8
        },
        "initialLayerRef": "layer.base",
        "layers": [
            {
                "id": "layer.base",
                "name": "基本",
                "rootBoardRef": "board.root"
            }
        ],
        "boards": [
            {
                "id": "board.root",
                "entries": [
                    {
                        "id": "key.a",
                        "rect": {"x": -1, "y": -1, "width": 2, "height": 2},
                        "resolver": {
                            "cases": [
                                {
                                    "when": {
                                        "eq": [
                                            {"state": "latinCase"},
                                            {"literal": "upper"}
                                        ]
                                    },
                                    "behavior": {
                                        "presentation": {
                                            "text": {
                                                "base": "a",
                                                "transforms": [
                                                    {
                                                        "when": {"fact": "composition.empty"},
                                                        "tableRef": "latin.shift"
                                                    }
                                                ]
                                            }
                                        },
                                        "onRelease": [
                                            {
                                                "actionID": "text.insert",
                                                "arguments": {
                                                    "text": {
                                                        "base": "a",
                                                        "transforms": [
                                                            {
                                                                "when": {
                                                                    "eq": [
                                                                        {"state": "latinCase"},
                                                                        {"literal": "upper"}
                                                                    ]
                                                                },
                                                                "tableRef": "latin.shift"
                                                            }
                                                        ]
                                                    }
                                                }
                                            }
                                        ]
                                    }
                                }
                            ],
                            "default": {
                                "presentation": {
                                    "text": {"base": "𛀀が", "transforms": []},
                                    "accessibilityLabel": "変体仮名"
                                },
                                "onRelease": [
                                    {
                                        "actionID": "text.insert",
                                        "arguments": {
                                            "text": {"base": "𛀀が", "transforms": []}
                                        }
                                    }
                                ]
                            }
                        }
                    }
                ]
            }
        ],
        "states": [
            {
                "id": "shiftEnabled",
                "type": "boolean",
                "default": false
            },
            {
                "id": "latinCase",
                "type": "enum",
                "values": ["lower", "upper"],
                "default": "lower"
            }
        ],
        "transformTables": [
            {
                "id": "latin.shift",
                "entries": [
                    {"from": "a", "to": "A"},
                    {"from": "𛀀", "to": "𛀁"}
                ]
            },
            {
                "id": "kana.dakuten",
                "entries": [
                    {"from": "か", "to": "が"},
                    {"from": "が", "to": "が"}
                ]
            }
        ],
        "macros": [
            {
                "id": "macro.noop",
                "actions": [
                    {"actionID": "noop", "arguments": {}}
                ]
            }
        ]
    })
}

fn validate(value: &Value) -> Result<(), ProfileValidationError> {
    let bytes = serde_json::to_vec(value).unwrap();
    ProfileV3Codec::decode_and_validate(&bytes).map(|_| ())
}

fn expect_code(value: &Value, code: ProfileValidationCode) {
    let error = validate(value).unwrap_err();
    assert_eq!(error.code, code, "unexpected validation error: {error:?}");
}

#[test]
fn v3_valid_profile_passes_with_unicode_conditions_and_transforms() {
    validate(&base_profile()).unwrap();
}

#[test]
fn v3_initial_layer_and_board_references_fail_closed() {
    let mut missing_layer = base_profile();
    missing_layer["initialLayerRef"] = json!("layer.missing");
    expect_code(&missing_layer, ProfileValidationCode::MissingReference);

    let mut missing_board = base_profile();
    missing_board["layers"][0]["rootBoardRef"] = json!("board.missing");
    expect_code(&missing_board, ProfileValidationCode::MissingReference);
}

#[test]
fn v3_board_rect_overlap_origin_and_extent_are_distinct_errors() {
    let mut bad_rect = base_profile();
    bad_rect["boards"][0]["entries"][0]["rect"] =
        json!({"x": 20, "y": 0, "width": 1, "height": 1});
    expect_code(&bad_rect, ProfileValidationCode::BoardRect);

    let mut overlap = base_profile();
    overlap["boards"][0]["entries"] = json!([
        {
            "id":"left",
            "rect":{"x":-2,"y":-1,"width":2,"height":2},
            "resolver":{"cases":[],"default":{}}
        },
        {
            "id":"right",
            "rect":{"x":-1,"y":-1,"width":2,"height":2},
            "resolver":{"cases":[],"default":{}}
        }
    ]);
    expect_code(&overlap, ProfileValidationCode::BoardOverlap);

    let mut origin_overlap = base_profile();
    origin_overlap["boards"][0]["entries"] = json!([
        {
            "id":"one",
            "rect":{"x":-1,"y":-1,"width":2,"height":2},
            "resolver":{"cases":[],"default":{}}
        },
        {
            "id":"two",
            "rect":{"x":0,"y":0,"width":1,"height":1},
            "resolver":{"cases":[],"default":{}}
        }
    ]);
    expect_code(
        &origin_overlap,
        ProfileValidationCode::BoardOriginOverlap,
    );

    let mut extent = base_profile();
    extent["boards"][0]["entries"] = json!([
        {
            "id":"west",
            "rect":{"x":-20,"y":0,"width":1,"height":1},
            "resolver":{"cases":[],"default":{}}
        },
        {
            "id":"east",
            "rect":{"x":1,"y":0,"width":1,"height":1},
            "resolver":{"cases":[],"default":{}}
        }
    ]);
    expect_code(&extent, ProfileValidationCode::BoardExtent);
}

#[test]
fn v3_edge_touching_rectangles_are_valid() {
    let mut value = base_profile();
    value["boards"][0]["entries"] = json!([
        {
            "id":"left",
            "rect":{"x":-2,"y":-1,"width":1,"height":2},
            "resolver":{"cases":[],"default":{}}
        },
        {
            "id":"right",
            "rect":{"x":-1,"y":-1,"width":1,"height":2},
            "resolver":{"cases":[],"default":{}}
        }
    ]);
    validate(&value).unwrap();
}

#[test]
fn v3_state_declarations_and_condition_types_are_validated() {
    let mut invalid_default = base_profile();
    invalid_default["states"][1]["default"] = json!("missing");
    expect_code(&invalid_default, ProfileValidationCode::InvalidState);

    let mut unknown_fact = base_profile();
    unknown_fact["boards"][0]["entries"][0]["resolver"]["cases"][0]["when"] =
        json!({"fact":"unknown.fact"});
    expect_code(
        &unknown_fact,
        ProfileValidationCode::UnknownRuntimeFact,
    );

    let mut type_mismatch = base_profile();
    type_mismatch["boards"][0]["entries"][0]["resolver"]["cases"][0]["when"] =
        json!({
            "eq":[
                {"state":"shiftEnabled"},
                {"literal":"upper"}
            ]
        });
    expect_code(
        &type_mismatch,
        ProfileValidationCode::InvalidCondition,
    );

    let mut enum_literal_outside_domain = base_profile();
    enum_literal_outside_domain["boards"][0]["entries"][0]["resolver"]["cases"][0]["when"] =
        json!({
            "eq":[
                {"state":"latinCase"},
                {"literal":"sideways"}
            ]
        });
    expect_code(
        &enum_literal_outside_domain,
        ProfileValidationCode::InvalidCondition,
    );
}

#[test]
fn v3_condition_depth_is_bounded() {
    let mut nested = json!({"fact":"conversion.active"});
    for _ in 0..8 {
        nested = json!({"not": nested});
    }

    let mut value = base_profile();
    value["boards"][0]["entries"][0]["resolver"]["cases"][0]["when"] = nested;
    expect_code(&value, ProfileValidationCode::LimitConditions);
}

#[test]
fn v3_transform_sources_and_references_are_validated() {
    let mut duplicate = base_profile();
    duplicate["transformTables"][0]["entries"] = json!([
        {"from":"a","to":"A"},
        {"from":"a","to":"AA"}
    ]);
    expect_code(
        &duplicate,
        ProfileValidationCode::DuplicateTransformSource,
    );

    let mut missing_table = base_profile();
    missing_table["boards"][0]["entries"][0]["resolver"]["default"]["onRelease"] =
        json!([
            {
                "actionID":"text.transform",
                "arguments":{"table":"missing.table"}
            }
        ]);
    expect_code(
        &missing_table,
        ProfileValidationCode::InvalidTransformReference,
    );

    let mut transform_match_missing = base_profile();
    transform_match_missing["boards"][0]["entries"][0]["resolver"]["cases"][0]["when"] =
        json!({
            "transformMatch":{
                "tableRef":"missing.table",
                "target":"compositionTail"
            }
        });
    expect_code(
        &transform_match_missing,
        ProfileValidationCode::InvalidTransformReference,
    );
}

#[test]
fn v3_action_capabilities_and_macro_nesting_fail_closed() {
    let mut profile_switch = base_profile();
    profile_switch["boards"][0]["entries"][0]["resolver"]["default"]["onRelease"] =
        json!([
            {
                "actionID":"profile.switch",
                "arguments":{"profile":"other.profile"}
            }
        ]);
    expect_code(
        &profile_switch,
        ProfileValidationCode::UnavailableCapability,
    );

    let mut nested_macro = base_profile();
    nested_macro["macros"][0]["actions"] = json!([
        {
            "actionID":"macro.run",
            "arguments":{"macro":"macro.noop"}
        }
    ]);
    expect_code(&nested_macro, ProfileValidationCode::MacroNesting);
}

#[test]
fn v3_transition_cannot_share_release_with_layer_switch() {
    let mut value = base_profile();
    value["boards"][0]["entries"][0]["resolver"]["default"] = json!({
        "onRelease":[
            {
                "actionID":"layer.set",
                "arguments":{"layer":"layer.base"}
            }
        ],
        "transition":{
            "targetBoardRef":"board.root",
            "lifetime":"transient"
        }
    });
    expect_code(
        &value,
        ProfileValidationCode::ConflictingControlFlow,
    );
}

#[test]
fn v3_state_set_and_resolved_text_arguments_are_typed() {
    let mut valid_state_set = base_profile();
    valid_state_set["boards"][0]["entries"][0]["resolver"]["default"]["onRelease"] =
        json!([
            {
                "actionID":"state.set",
                "arguments":{"state":"latinCase","value":"upper"}
            }
        ]);
    validate(&valid_state_set).unwrap();

    let mut invalid_state_set = base_profile();
    invalid_state_set["boards"][0]["entries"][0]["resolver"]["default"]["onRelease"] =
        json!([
            {
                "actionID":"state.set",
                "arguments":{"state":"latinCase","value":true}
            }
        ]);
    expect_code(&invalid_state_set, ProfileValidationCode::InvalidState);

    let mut legacy_string_payload = base_profile();
    legacy_string_payload["boards"][0]["entries"][0]["resolver"]["default"]["onRelease"] =
        json!([
            {
                "actionID":"text.insert",
                "arguments":{"text":"legacy"}
            }
        ]);
    expect_code(
        &legacy_string_payload,
        ProfileValidationCode::InvalidActionArguments,
    );
}

#[test]
fn v3_hold_transition_control_flow_is_validated() {
    let mut conflict = base_profile();
    conflict["boards"][0]["entries"][0]["resolver"]["default"]["hold"] = json!({
        "delayMs":350,
        "onStart":[
            {
                "actionID":"layer.push",
                "arguments":{"layer":"layer.base"}
            }
        ],
        "transition":{
            "targetBoardRef":"board.root",
            "lifetime":"persistent"
        },
        "suppressOnReleaseAfterStart":true
    });
    expect_code(
        &conflict,
        ProfileValidationCode::ConflictingControlFlow,
    );

    let mut state_then_transition = base_profile();
    state_then_transition["boards"][0]["entries"][0]["resolver"]["default"] = json!({
        "onRelease":[
            {
                "actionID":"state.set",
                "arguments":{"state":"shiftEnabled","value":true}
            }
        ],
        "transition":{
            "targetBoardRef":"board.root",
            "lifetime":"persistent"
        }
    });
    validate(&state_then_transition).unwrap();
}


#[test]
fn v3_required_serialized_members_and_explicit_nulls_fail_closed() {
    let mut missing_cases = base_profile();
    if let Some(resolver) = missing_cases["boards"][0]["entries"][0]["resolver"].as_object_mut() {
        resolver.remove("cases");
    }
    expect_code(&missing_cases, ProfileValidationCode::UnsupportedSchema);

    let mut missing_transforms = base_profile();
    if let Some(text) = missing_transforms["boards"][0]["entries"][0]["resolver"]["default"]["presentation"]["text"].as_object_mut() {
        text.remove("transforms");
    }
    expect_code(&missing_transforms, ProfileValidationCode::UnsupportedSchema);

    let mut null_layer_name = base_profile();
    null_layer_name["layers"][0]["name"] = Value::Null;
    expect_code(&null_layer_name, ProfileValidationCode::UnsupportedSchema);

    let mut null_state_values = base_profile();
    null_state_values["states"][0]["values"] = Value::Null;
    expect_code(&null_state_values, ProfileValidationCode::UnsupportedSchema);

    let mut null_endpoint_transition = base_profile();
    null_endpoint_transition["boards"][0]["entries"][0]["resolver"]["default"]["transition"] =
        Value::Null;
    expect_code(
        &null_endpoint_transition,
        ProfileValidationCode::UnsupportedSchema,
    );
}
