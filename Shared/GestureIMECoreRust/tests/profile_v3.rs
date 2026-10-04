use gesture_ime_core::ProfileBundleV3;
use serde_json::Value;

fn sample_v3() -> String {
    r#"{
      "schema":"gesture-ime.profile.v3",
      "id":"profile.v3.test",
      "name":"変体仮名𛀀",
      "version":1,
      "gesturePolicy":{
        "deadZone":0.15,
        "initialCellCommitDistance":0.55,
        "subsequentCellCommitDistance":0.45,
        "angularHysteresisDegrees":8,
        "futurePolicyField":"keep-policy"
      },
      "initialLayerRef":"layer.ja",
      "layers":[
        {
          "id":"layer.ja",
          "name":"かな",
          "rootBoardRef":"board.root",
          "futureLayerField":{"keep":true}
        }
      ],
      "boards":[
        {
          "id":"board.root",
          "entries":[
            {
              "id":"key.a",
              "rect":{"x":-1,"y":-1,"width":2,"height":2,"futureRectField":7},
              "resolver":{
                "cases":[],
                "default":{
                  "presentation":{
                    "text":{"base":"𛀀が","transforms":[],"futureStringField":"keep"},
                    "accessibilityLabel":"変体仮名"
                  },
                  "onRelease":[]
                },
                "futureResolverField":"keep-resolver"
              },
              "futureEntryField":[1,2,3]
            }
          ],
          "futureBoardField":"keep-board"
        }
      ],
      "states":[
        {
          "id":"latinCase",
          "type":"enum",
          "values":["lower","upper"],
          "default":"lower",
          "futureStateField":"keep-state"
        }
      ],
      "transformTables":[
        {
          "id":"kana.hentaigana",
          "entries":[
            {"from":"𛀀","to":"𛀁","futureTransformEntryField":"keep-entry"}
          ],
          "futureTableField":"keep-table"
        }
      ],
      "macros":[],
      "futureProfileField":{"nested":["keep",{"scalar":"𛀀"}]}
    }"#.to_owned()
}

#[test]
fn v3_model_round_trips_unicode_and_unknown_members() {
    let source = sample_v3();
    let profile = ProfileBundleV3::decode_unvalidated(source.as_bytes()).unwrap();

    assert_eq!(profile.schema, "gesture-ime.profile.v3");
    assert_eq!(profile.name, "変体仮名𛀀");
    assert_eq!(
        profile.extra.get("futureProfileField"),
        Some(&serde_json::json!({"nested":["keep",{"scalar":"𛀀"}]}))
    );
    assert_eq!(
        profile.boards[0].entries[0].rect.extra.get("futureRectField"),
        Some(&serde_json::json!(7))
    );

    let encoded = profile.encode().unwrap();
    let round_trip: Value = serde_json::from_slice(&encoded).unwrap();
    let original: Value = serde_json::from_str(&source).unwrap();

    assert_eq!(round_trip["futureProfileField"], original["futureProfileField"]);
    assert_eq!(
        round_trip["gesturePolicy"]["futurePolicyField"],
        original["gesturePolicy"]["futurePolicyField"]
    );
    assert_eq!(
        round_trip["layers"][0]["futureLayerField"],
        original["layers"][0]["futureLayerField"]
    );
    assert_eq!(
        round_trip["boards"][0]["entries"][0]["rect"]["futureRectField"],
        original["boards"][0]["entries"][0]["rect"]["futureRectField"]
    );
    assert_eq!(
        round_trip["boards"][0]["entries"][0]["resolver"]["futureResolverField"],
        original["boards"][0]["entries"][0]["resolver"]["futureResolverField"]
    );
    assert_eq!(
        round_trip["boards"][0]["entries"][0]["presentation"],
        Value::Null
    );
    assert_eq!(
        round_trip["boards"][0]["entries"][0]["resolver"]["default"]["presentation"]["text"]["base"],
        "𛀀が"
    );
    assert_eq!(
        round_trip["transformTables"][0]["entries"][0]["from"],
        "𛀀"
    );
    assert_eq!(
        round_trip["transformTables"][0]["entries"][0]["futureTransformEntryField"],
        "keep-entry"
    );
}

#[test]
fn v3_condition_json_is_preserved_as_authored_data() {
    let source = sample_v3();
    let mut value: Value = serde_json::from_str(&source).unwrap();

    value["boards"][0]["entries"][0]["resolver"]["cases"] = serde_json::json!([
      {
        "when": {
          "transformMatch": {
            "tableRef": "kana.hentaigana",
            "target": "compositionTail"
          }
        },
        "behavior": {
          "onRelease": []
        }
      }
    ]);

    let bytes = serde_json::to_vec(&value).unwrap();
    let profile = ProfileBundleV3::decode_unvalidated(&bytes).unwrap();
    let encoded: Value = serde_json::from_slice(&profile.encode().unwrap()).unwrap();

    assert_eq!(
        encoded["boards"][0]["entries"][0]["resolver"]["cases"][0]["when"],
        value["boards"][0]["entries"][0]["resolver"]["cases"][0]["when"]
    );
}
