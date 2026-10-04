use gesture_ime_core::{
    ActionInvocationV3, BoardSemanticsV3, CompositionTailTransformV3, ProfileBundleV3,
    ProfileSemanticsRuntimeV3, ProfileV3Codec, RuntimeDispatchV3, RuntimeSemanticContextV3,
};
use serde_json::{json, Value};

fn profile_json() -> Value {
    json!({
        "schema":"gesture-ime.profile.v3",
        "id":"profile.a2",
        "name":"A2 Semantics",
        "version":1,
        "gesturePolicy":{
            "deadZone":0.15,
            "initialCellCommitDistance":0.55,
            "subsequentCellCommitDistance":0.45,
            "angularHysteresisDegrees":8
        },
        "initialLayerRef":"layer.base",
        "layers":[
            {"id":"layer.base","rootBoardRef":"board.root"},
            {"id":"layer.symbol","rootBoardRef":"board.root"}
        ],
        "boards":[
            {
                "id":"board.root",
                "entries":[
                    {
                        "id":"key.main",
                        "rect":{"x":-1,"y":-1,"width":2,"height":2},
                        "resolver":{
                            "cases":[],
                            "default":{
                                "presentation":{
                                    "text":{"base":"a","transforms":[]}
                                },
                                "onRelease":[]
                            }
                        }
                    }
                ]
            }
        ],
        "states":[
            {"id":"shiftEnabled","type":"boolean","default":false},
            {
                "id":"latinCase",
                "type":"enum",
                "values":["lower","upper"],
                "default":"lower"
            }
        ],
        "transformTables":[
            {
                "id":"latin.shift",
                "entries":[
                    {"from":"a","to":"A"},
                    {"from":"b","to":"B"}
                ]
            },
            {
                "id":"latin.second",
                "entries":[
                    {"from":"A","to":"α"}
                ]
            },
            {
                "id":"kana.small",
                "entries":[
                    {"from":"つ","to":"っ"}
                ]
            },
            {
                "id":"kana.dakuten",
                "entries":[
                    {"from":"か","to":"が"},
                    {"from":"は","to":"ば"}
                ]
            },
            {
                "id":"kana.handakuten",
                "entries":[
                    {"from":"は","to":"ぱ"}
                ]
            },
            {
                "id":"suffix.longest",
                "entries":[
                    {"from":"a","to":"SHORT"},
                    {"from":"ba","to":"LONG"},
                    {"from":"𛀀ba","to":"HENTAIGANA_LONG"}
                ]
            },
            {
                "id":"hentaigana",
                "entries":[
                    {"from":"𛀀","to":"𛀁"}
                ]
            },
            {
                "id":"precomposed.only",
                "entries":[
                    {"from":"が","to":"X"}
                ]
            },
            {
                "id":"emoji.zwj",
                "entries":[
                    {"from":"👩‍💻","to":"TECH"}
                ]
            },
            {
                "id":"variation.selector",
                "entries":[
                    {"from":"✈️","to":"PLANE"}
                ]
            }
        ],
        "macros":[
            {
                "id":"macro.shifted",
                "actions":[
                    {
                        "actionID":"text.insert",
                        "arguments":{
                            "text":{
                                "base":"a",
                                "transforms":[
                                    {
                                        "when":{
                                            "eq":[
                                                {"state":"latinCase"},
                                                {"literal":"upper"}
                                            ]
                                        },
                                        "tableRef":"latin.shift"
                                    }
                                ]
                            }
                        }
                    }
                ]
            }
        ]
    })
}

fn profile() -> ProfileBundleV3 {
    let bytes = serde_json::to_vec(&profile_json()).unwrap();
    ProfileV3Codec::decode_and_validate(&bytes).unwrap()
}

fn main_entry(profile: &ProfileBundleV3) -> gesture_ime_core::BoardEntryV3 {
    profile.boards[0].entries[0].clone()
}

fn label(
    semantics: &mut impl BoardSemanticsV3,
    entry: &gesture_ime_core::BoardEntryV3,
) -> String {
    semantics
        .resolve_endpoint(entry)
        .presentation
        .and_then(|presentation| presentation.text)
        .map(|text| text.base)
        .unwrap_or_default()
}

fn action(id: &str, arguments: Value) -> ActionInvocationV3 {
    serde_json::from_value(json!({
        "actionID":id,
        "arguments":arguments
    }))
    .unwrap()
}

fn dispatched_text(dispatch: &RuntimeDispatchV3) -> Option<&str> {
    let RuntimeDispatchV3::Action(action) = dispatch else {
        return None;
    };
    action.arguments.get("text")?.as_str()
}

#[test]
fn a2_boolean_enum_eq_in_all_any_not_and_ordered_first_match_execute() {
    let mut value = profile_json();
    value["boards"][0]["entries"][0]["resolver"] = json!({
        "cases":[
            {
                "when":{
                    "all":[
                        {"not":{"state":"shiftEnabled"}},
                        {
                            "in":[
                                {"state":"latinCase"},
                                ["lower","upper"]
                            ]
                        },
                        {
                            "any":[
                                {
                                    "eq":[
                                        {"fact":"layer.id"},
                                        {"literal":"layer.base"}
                                    ]
                                },
                                {"literal":false}
                            ]
                        }
                    ]
                },
                "behavior":{
                    "presentation":{"text":{"base":"first","transforms":[]}}
                }
            },
            {
                "when":{"literal":true},
                "behavior":{
                    "presentation":{"text":{"base":"second","transforms":[]}}
                }
            }
        ],
        "default":{
            "presentation":{"text":{"base":"default","transforms":[]}}
        }
    });

    let bytes = serde_json::to_vec(&value).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.base"),
    );
    let mut semantics = runtime.board_semantics(context);

    assert_eq!(label(&mut semantics, &main_entry(&profile)), "first");
}

#[test]
fn a2_runtime_facts_and_default_fallback_execute() {
    let mut value = profile_json();
    value["boards"][0]["entries"][0]["resolver"] = json!({
        "cases":[
            {
                "when":{"fact":"composition.empty"},
                "behavior":{
                    "presentation":{"text":{"base":"empty","transforms":[]}}
                }
            },
            {
                "when":{
                    "all":[
                        {"fact":"conversion.active"},
                        {"fact":"conversion.hasCandidates"}
                    ]
                },
                "behavior":{
                    "presentation":{"text":{"base":"conversion","transforms":[]}}
                }
            }
        ],
        "default":{
            "presentation":{"text":{"base":"fallback","transforms":[]}}
        }
    });

    let bytes = serde_json::to_vec(&value).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3 {
            composition:"x".into(),
            conversion_active:true,
            conversion_has_candidates:true,
            layer_id:"layer.base".into(),
        },
    );
    let mut semantics = runtime.board_semantics(context.clone());
    assert_eq!(label(&mut semantics, &main_entry(&profile)), "conversion");

    {
        let mut context = context.lock().unwrap();
        context.conversion_active = false;
        context.conversion_has_candidates = false;
    }
    assert_eq!(label(&mut semantics, &main_entry(&profile)), "fallback");

    context.lock().unwrap().composition.clear();
    assert_eq!(label(&mut semantics, &main_entry(&profile)), "empty");
}

#[test]
fn a2_state_set_uses_whole_batch_snapshot_then_changes_future_resolution() {
    let profile = profile();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.base"),
    );
    let mut semantics = runtime.board_semantics(context);

    let batch = vec![
        action(
            "state.set",
            json!({"state":"latinCase","value":"upper"}),
        ),
        action(
            "text.insert",
            json!({
                "text":{
                    "base":"a",
                    "transforms":[
                        {
                            "when":{
                                "eq":[
                                    {"state":"latinCase"},
                                    {"literal":"upper"}
                                ]
                            },
                            "tableRef":"latin.shift"
                        }
                    ]
                }
            }),
        ),
    ];

    let first = semantics.resolve_dispatch_batch(&batch);
    assert_eq!(first.len(), 1);
    assert_eq!(dispatched_text(&first[0]), Some("a"));
    assert_eq!(
        runtime.state_value("latinCase"),
        Some(Value::String("upper".into()))
    );

    let second = semantics.resolve_dispatch_batch(&[batch[1].clone()]);
    assert_eq!(dispatched_text(&second[0]), Some("A"));
}

#[test]
fn a2_state_is_shared_across_sessions_and_new_runtime_resets_defaults() {
    let profile = profile();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();

    let context_one = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.base"),
    );
    let mut first = runtime.board_semantics(context_one);
    first.resolve_dispatch_batch(&[action(
        "state.set",
        json!({"state":"shiftEnabled","value":true}),
    )]);

    let context_two = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.symbol"),
    );
    let mut second = runtime.board_semantics(context_two);
    let state_sensitive = {
        let mut entry = main_entry(&profile);
        entry.resolver.cases = vec![
            serde_json::from_value(json!({
                "when":{"state":"shiftEnabled"},
                "behavior":{
                    "presentation":{"text":{"base":"shared","transforms":[]}}
                }
            }))
            .unwrap(),
        ];
        entry.resolver.default.presentation = Some(
            serde_json::from_value(json!({
                "text":{"base":"default","transforms":[]}
            }))
            .unwrap(),
        );
        entry
    };
    assert_eq!(label(&mut second, &state_sensitive), "shared");

    let reset = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    assert_eq!(reset.state_value("shiftEnabled"), Some(Value::Bool(false)));
}

#[test]
fn a2_resolved_string_applies_ordered_whole_string_transforms() {
    let mut value = profile_json();
    value["boards"][0]["entries"][0]["resolver"]["default"] = json!({
        "presentation":{
            "text":{
                "base":"a",
                "transforms":[
                    {"when":{"literal":true},"tableRef":"latin.shift"},
                    {"when":{"literal":true},"tableRef":"latin.second"}
                ]
            }
        },
        "onRelease":[
            {
                "actionID":"text.insert",
                "arguments":{
                    "text":{
                        "base":"a",
                        "transforms":[
                            {"when":{"literal":true},"tableRef":"latin.shift"},
                            {"when":{"literal":true},"tableRef":"latin.second"}
                        ]
                    }
                }
            }
        ]
    });

    let bytes = serde_json::to_vec(&value).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.base"),
    );
    let mut semantics = runtime.board_semantics(context);
    let resolved = semantics.resolve_endpoint(&main_entry(&profile));

    assert_eq!(
        resolved
            .presentation
            .as_ref()
            .and_then(|presentation| presentation.text.as_ref())
            .map(|text| text.base.as_str()),
        Some("α")
    );

    let dispatch = semantics.resolve_dispatch_batch(&resolved.on_release);
    assert_eq!(dispatched_text(&dispatch[0]), Some("α"));
}

#[test]
fn a2_resolved_string_miss_is_exact_passthrough() {
    let mut value = profile_json();
    value["boards"][0]["entries"][0]["resolver"]["default"]["presentation"] = json!({
        "text":{
            "base":"z",
            "transforms":[
                {"when":{"literal":true},"tableRef":"latin.shift"}
            ]
        }
    });

    let bytes = serde_json::to_vec(&value).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.base"),
    );
    let mut semantics = runtime.board_semantics(context);
    assert_eq!(label(&mut semantics, &main_entry(&profile)), "z");
}

#[test]
fn a2_transform_match_and_text_transform_share_longest_suffix_semantics() {
    let mut value = profile_json();
    value["boards"][0]["entries"][0]["resolver"] = json!({
        "cases":[
            {
                "when":{
                    "transformMatch":{
                        "tableRef":"suffix.longest",
                        "target":"compositionTail"
                    }
                },
                "behavior":{
                    "presentation":{"text":{"base":"hit","transforms":[]}}
                }
            }
        ],
        "default":{
            "presentation":{"text":{"base":"miss","transforms":[]}}
        }
    });

    let bytes = serde_json::to_vec(&value).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3 {
            composition:"prefix𛀀ba".into(),
            conversion_active:false,
            conversion_has_candidates:false,
            layer_id:"layer.base".into(),
        },
    );
    let mut semantics = runtime.board_semantics(context.clone());

    assert_eq!(label(&mut semantics, &main_entry(&profile)), "hit");

    let dispatch = semantics.resolve_dispatch_batch(&[action(
        "text.transform",
        json!({"table":"suffix.longest"}),
    )]);
    assert_eq!(
        dispatch,
        vec![RuntimeDispatchV3::CompositionTailTransform(
            CompositionTailTransformV3 {
                table_id:"suffix.longest".into(),
                matched_source:"𛀀ba".into(),
                replacement:"HENTAIGANA_LONG".into(),
            }
        )]
    );

    context.lock().unwrap().composition = "prefix?".into();
    assert_eq!(label(&mut semantics, &main_entry(&profile)), "miss");
    assert!(semantics
        .resolve_dispatch_batch(&[action(
            "text.transform",
            json!({"table":"suffix.longest"}),
        )])
        .is_empty());
}

#[test]
fn a2_transform_replacement_is_single_nonrecursive_operation() {
    let mut value = profile_json();
    value["transformTables"].as_array_mut().unwrap().push(json!({
        "id":"nonrecursive",
        "entries":[
            {"from":"a","to":"aa"},
            {"from":"aa","to":"FINAL"}
        ]
    }));
    let bytes = serde_json::to_vec(&value).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3 {
            composition:"a".into(),
            conversion_active:false,
            conversion_has_candidates:false,
            layer_id:"layer.base".into(),
        },
    );
    let mut semantics = runtime.board_semantics(context);
    let dispatch = semantics.resolve_dispatch_batch(&[action(
        "text.transform",
        json!({"table":"nonrecursive"}),
    )]);

    assert_eq!(
        dispatch,
        vec![RuntimeDispatchV3::CompositionTailTransform(
            CompositionTailTransformV3 {
                table_id:"nonrecursive".into(),
                matched_source:"a".into(),
                replacement:"aa".into(),
            }
        )]
    );
}

#[test]
fn a2_unicode_exactness_distinguishes_normalization_and_handles_zwj_variation_selectors() {
    let profile = profile();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.base"),
    );
    let mut semantics = runtime.board_semantics(context.clone());

    context.lock().unwrap().composition = "か\u{3099}".into();
    assert!(semantics
        .resolve_dispatch_batch(&[action(
            "text.transform",
            json!({"table":"precomposed.only"}),
        )])
        .is_empty());

    context.lock().unwrap().composition = "が".into();
    assert!(!semantics
        .resolve_dispatch_batch(&[action(
            "text.transform",
            json!({"table":"precomposed.only"}),
        )])
        .is_empty());

    context.lock().unwrap().composition = "x👩‍💻".into();
    let emoji = semantics.resolve_dispatch_batch(&[action(
        "text.transform",
        json!({"table":"emoji.zwj"}),
    )]);
    assert!(matches!(
        emoji.as_slice(),
        [RuntimeDispatchV3::CompositionTailTransform(effect)]
            if effect.matched_source == "👩‍💻" && effect.replacement == "TECH"
    ));

    context.lock().unwrap().composition = "x✈️".into();
    let variation = semantics.resolve_dispatch_batch(&[action(
        "text.transform",
        json!({"table":"variation.selector"}),
    )]);
    assert!(matches!(
        variation.as_slice(),
        [RuntimeDispatchV3::CompositionTailTransform(effect)]
            if effect.matched_source == "✈️" && effect.replacement == "PLANE"
    ));
}

#[test]
fn a2_small_kana_dakuten_handakuten_and_hentaigana_are_generic_tables() {
    let profile = profile();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.base"),
    );
    let mut semantics = runtime.board_semantics(context.clone());

    for (composition, table, source, replacement) in [
        ("つ", "kana.small", "つ", "っ"),
        ("か", "kana.dakuten", "か", "が"),
        ("は", "kana.handakuten", "は", "ぱ"),
        ("𛀀", "hentaigana", "𛀀", "𛀁"),
    ] {
        context.lock().unwrap().composition = composition.into();
        let dispatch = semantics.resolve_dispatch_batch(&[action(
            "text.transform",
            json!({"table":table}),
        )]);
        assert!(matches!(
            dispatch.as_slice(),
            [RuntimeDispatchV3::CompositionTailTransform(effect)]
                if effect.matched_source == source
                    && effect.replacement == replacement
        ));
    }
}

#[test]
fn a2_macro_body_resolved_string_uses_dispatch_snapshot() {
    let profile = profile();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.base"),
    );
    let mut semantics = runtime.board_semantics(context);

    let macro_actions = profile.macros[0].actions.clone();
    let lower = semantics.resolve_dispatch_batch(&macro_actions);
    assert_eq!(dispatched_text(&lower[0]), Some("a"));

    semantics.resolve_dispatch_batch(&[action(
        "state.set",
        json!({"state":"latinCase","value":"upper"}),
    )]);
    let upper = semantics.resolve_dispatch_batch(&macro_actions);
    assert_eq!(dispatched_text(&upper[0]), Some("A"));
}

#[test]
fn a2_endpoint_snapshot_does_not_reinterpret_after_state_change() {
    let mut value = profile_json();
    value["boards"][0]["entries"][0]["resolver"]["default"]["onRelease"] = json!([
        {
            "actionID":"text.insert",
            "arguments":{
                "text":{
                    "base":"a",
                    "transforms":[
                        {
                            "when":{
                                "eq":[
                                    {"state":"latinCase"},
                                    {"literal":"upper"}
                                ]
                            },
                            "tableRef":"latin.shift"
                        }
                    ]
                }
            }
        }
    ]);
    let bytes = serde_json::to_vec(&value).unwrap();
    let profile = ProfileV3Codec::decode_and_validate(&bytes).unwrap();
    let runtime = ProfileSemanticsRuntimeV3::compile(&profile).unwrap();
    let context = ProfileSemanticsRuntimeV3::context_handle(
        RuntimeSemanticContextV3::new("layer.base"),
    );
    let mut semantics = runtime.board_semantics(context);

    let pinned = semantics.resolve_endpoint(&main_entry(&profile));
    semantics.resolve_dispatch_batch(&[action(
        "state.set",
        json!({"state":"latinCase","value":"upper"}),
    )]);

    let dispatch = semantics.resolve_dispatch_batch(&pinned.on_release);
    assert_eq!(dispatched_text(&dispatch[0]), Some("a"));

    let newly_resolved = semantics.resolve_endpoint(&main_entry(&profile));
    let future = semantics.resolve_dispatch_batch(&newly_resolved.on_release);
    assert_eq!(dispatched_text(&future[0]), Some("A"));
}
