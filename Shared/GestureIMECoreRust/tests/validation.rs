use gesture_ime_core::{ProfileCodec, ProfileValidationCode, ProfileValidator};
use serde_json::{json, Value};

fn base_profile() -> Value {
    json!({
        "schema": "gesture-ime.profile.v1",
        "id": "test.profile",
        "name": "Test Profile",
        "version": 1,
        "gesturePolicy": {
            "deadZone": 0.1,
            "stage1CommitDistance": 0.35,
            "stage2CommitDistance": 0.35,
            "angularHysteresisDegrees": 8.0,
            "maxDirectionalStages": 2
        },
        "keyDefinitions": [
            {
                "id": "key.a",
                "presentation": {
                    "text": "あ",
                    "accessibilityLabel": "あ"
                }
            }
        ],
        "layouts": [
            {
                "id": "layout.base",
                "placements": [
                    {
                        "keyID": "key.a",
                        "row": 0,
                        "column": 0,
                        "width": 1,
                        "height": 1
                    }
                ]
            }
        ],
        "bindingSets": [
            {
                "id": "bindings.base",
                "bindings": [
                    {
                        "keyID": "key.a",
                        "path": [],
                        "behavior": {
                            "onRelease": [
                                {
                                    "actionID": "text.insert",
                                    "arguments": {
                                        "text": "あ"
                                    }
                                }
                            ]
                        }
                    },
                    {
                        "keyID": "key.a",
                        "path": [{"direction": "e"}],
                        "behavior": {
                            "onRelease": [
                                {
                                    "actionID": "text.insert",
                                    "arguments": {
                                        "text": "い"
                                    }
                                }
                            ]
                        }
                    }
                ]
            }
        ],
        "layers": [
            {
                "id": "base",
                "layoutRef": "layout.base",
                "bindingSetRef": "bindings.base"
            }
        ],
        "macros": [],
        "futureField": {
            "ignoredByRuntimeV1": true
        }
    })
}

fn decode(value: &Value) -> Result<gesture_ime_core::ProfileBundle, gesture_ime_core::ProfileValidationError> {
    ProfileCodec::decode_and_validate(&serde_json::to_vec(value).unwrap())
}

#[test]
fn valid_profile_decodes_and_ignores_unknown_members() {
    let profile = decode(&base_profile()).expect("valid profile");
    assert_eq!(profile.id, "test.profile");
    assert_eq!(profile.binding_sets[0].bindings.len(), 2);
}

#[test]
fn duplicate_binding_path_is_rejected() {
    let mut profile = base_profile();
    let bindings = profile["bindingSets"][0]["bindings"].as_array_mut().unwrap();
    bindings.push(bindings[1].clone());

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::DuplicateBindingPath);
}

#[test]
fn unknown_action_is_rejected() {
    let mut profile = base_profile();
    profile["bindingSets"][0]["bindings"][0]["behavior"]["onRelease"][0]["actionID"] =
        json!("platform.ios.magic");

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::UnknownAction);
}

#[test]
fn macro_nesting_is_rejected() {
    let mut profile = base_profile();
    profile["macros"] = json!([
        {
            "id": "macro.a",
            "actions": [
                {
                    "actionID": "macro.run",
                    "arguments": {
                        "macro": "macro.a"
                    }
                }
            ]
        }
    ]);

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::MacroNesting);
}

#[test]
fn path_depth_over_two_is_rejected() {
    let mut profile = base_profile();
    profile["bindingSets"][0]["bindings"][1]["path"] = json!([
        {"direction": "e"},
        {"direction": "n"},
        {"direction": "w"}
    ]);

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::PathDepth);
}

#[test]
fn macro_resource_limit_is_rejected() {
    let mut profile = base_profile();
    profile["macros"] = Value::Array(
        (0..129)
            .map(|index| {
                json!({
                    "id": format!("macro.{index}"),
                    "actions": []
                })
            })
            .collect(),
    );

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::LimitMacros);
}

#[test]
fn invalid_gesture_policy_is_rejected() {
    let mut profile = base_profile();
    profile["gesturePolicy"]["stage1CommitDistance"] = json!(0.05);

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::InvalidGesturePolicy);
}

#[test]
fn missing_layer_reference_is_rejected() {
    let mut profile = base_profile();
    profile["layers"][0]["layoutRef"] = json!("layout.missing");

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::MissingReference);
}

#[test]
fn known_action_requires_exact_argument_shape() {
    let mut profile = base_profile();
    profile["bindingSets"][0]["bindings"][0]["behavior"]["onRelease"][0]["arguments"] =
        json!({
            "text": "あ",
            "extra": true
        });

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::InvalidActionArguments);
}

#[test]
fn oversized_string_argument_is_rejected() {
    let mut profile = base_profile();
    profile["bindingSets"][0]["bindings"][0]["behavior"]["onRelease"][0]["arguments"]["text"] =
        json!("x".repeat(4097));

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::ArgumentTooLarge);
}

#[test]
fn layer_set_must_reference_loaded_layer() {
    let mut profile = base_profile();
    profile["bindingSets"][0]["bindings"][0]["behavior"]["onRelease"] = json!([
        {
            "actionID": "layer.set",
            "arguments": {
                "layer": "missing"
            }
        }
    ]);

    let error = decode(&profile).unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::MissingReference);
}

#[test]
fn validator_accepts_model_after_decode() {
    let bytes = serde_json::to_vec(&base_profile()).unwrap();
    let profile: gesture_ime_core::ProfileBundle = serde_json::from_slice(&bytes).unwrap();
    ProfileValidator::validate(&profile, Some(bytes.len())).expect("model validates");
}