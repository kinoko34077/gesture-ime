use gesture_ime_core::{
    ActionInvocation, Binding, BindingBehavior, BindingSet, BindingTrieCompiler, Direction8,
    GesturePath, GesturePoint, GesturePolicy, GestureSession, GestureSize, GestureTerminal,
    ProfileBundle, ProfileCodec,
};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Deserialize)]
struct Manifest {
    schema: String,
    fixtures: Vec<ManifestEntry>,
}

#[derive(Debug, Deserialize)]
struct ManifestEntry {
    file: String,
    kind: String,
    expect: String,
    #[serde(default)]
    error: Option<String>,
    #[serde(default)]
    assertions: Option<Value>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GestureTraceFixture {
    policy: GesturePolicy,
    key_size: [f64; 2],
    paths: Vec<GesturePath>,
    samples: Vec<GestureSample>,
    expected: GestureExpected,
}

#[derive(Debug, Deserialize)]
struct GestureSample {
    event: String,
    point: [f64; 2],
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct GestureExpected {
    path: GesturePath,
    commit_anchors: Vec<[f64; 2]>,
    terminal: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LifecycleFixture {
    endpoint_behavior: BindingBehavior,
    events: Vec<LifecycleEvent>,
    expected: LifecycleExpected,
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
enum LifecycleEvent {
    #[serde(rename = "touchDown", rename_all = "camelCase")]
    TouchDown {
        #[serde(default)]
        profile_revision: Option<String>,
        at_ms: i64,
    },
    #[serde(rename = "cancel", rename_all = "camelCase")]
    Cancel { at_ms: i64 },
    #[serde(rename = "advanceTime", rename_all = "camelCase")]
    AdvanceTime { to_ms: i64 },
    #[serde(rename = "profileReload", rename_all = "camelCase")]
    ProfileReload { new_revision: String, at_ms: i64 },
    #[serde(rename = "touchUp", rename_all = "camelCase")]
    TouchUp { at_ms: i64 },
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LifecycleExpected {
    terminal: String,
    dispatched_actions: Vec<ActionInvocation>,
    #[serde(default)]
    next_session_profile_revision: Option<String>,
}

fn repo_root() -> PathBuf {
    if let Ok(root) = std::env::var("GESTURE_IME_REPO_ROOT") {
        return PathBuf::from(root);
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
}

fn read_json<T: for<'de> Deserialize<'de>>(path: &Path) -> T {
    let data = fs::read(path).unwrap_or_else(|error| {
        panic!("failed to read {}: {error}", path.display());
    });
    serde_json::from_slice(&data).unwrap_or_else(|error| {
        panic!("failed to decode {}: {error}", path.display());
    })
}

fn profile_runtime(profile: &ProfileBundle) -> (&BindingSet, &str) {
    let layer = profile.layers.first().expect("profile layer");
    let layout = profile
        .layouts
        .iter()
        .find(|layout| layout.id == layer.layout_ref)
        .expect("layer layout");
    let binding_set = profile
        .binding_sets
        .iter()
        .find(|set| set.id == layer.binding_set_ref)
        .expect("layer binding set");
    let key_id = layout
        .placements
        .first()
        .expect("layout placement")
        .key_id
        .as_str();
    (binding_set, key_id)
}

fn direction_from_value(value: &Value) -> Direction8 {
    serde_json::from_value(value.clone()).expect("Direction8")
}

fn run_profile_fixture(path: &Path, entry: &ManifestEntry) {
    let data = fs::read(path).unwrap();
    match entry.expect.as_str() {
        "valid" => {
            let profile = ProfileCodec::decode_and_validate(&data)
                .unwrap_or_else(|error| panic!("{} unexpectedly invalid: {error}", entry.file));
            let (binding_set, key_id) = profile_runtime(&profile);
            let trie = BindingTrieCompiler::compile(binding_set, key_id)
                .unwrap_or_else(|error| panic!("{} trie compile failed: {error}", entry.file));

            if let Some(assertions) = &entry.assertions {
                if let Some(expected) = assertions.get("rootEligibleDirections") {
                    let expected = expected
                        .as_array()
                        .expect("rootEligibleDirections array")
                        .iter()
                        .map(direction_from_value)
                        .collect::<HashSet<_>>();
                    assert_eq!(
                        trie.root.eligible_directions(),
                        expected,
                        "{} root eligible directions",
                        entry.file
                    );
                }

                if let Some(expected) = assertions.get("rootIncludes") {
                    let direction = direction_from_value(expected);
                    assert!(
                        trie.root.eligible_directions().contains(&direction),
                        "{} root should include {direction:?}",
                        entry.file
                    );
                }

                if let Some(paths) = assertions.get("pathsInclude") {
                    for path_value in paths.as_array().expect("pathsInclude array") {
                        let directions = path_value
                            .as_array()
                            .expect("direction path array")
                            .iter()
                            .map(direction_from_value)
                            .map(|direction| gesture_ime_core::GestureToken { direction })
                            .collect();
                        let path = GesturePath(directions);
                        assert!(
                            trie.node(&path).is_some(),
                            "{} should contain path {:?}",
                            entry.file,
                            path
                        );
                    }
                }
            }
        }
        "invalid" => {
            let error = ProfileCodec::decode_and_validate(&data)
                .expect_err("invalid fixture must fail");
            assert_eq!(
                Some(error.code.as_str()),
                entry.error.as_deref(),
                "{} validation error",
                entry.file
            );
        }
        other => panic!("unsupported profile expectation: {other}"),
    }
}

fn empty_behavior() -> BindingBehavior {
    BindingBehavior {
        presentation: None,
        on_release: Vec::new(),
        hold: None,
    }
}

fn terminal_name(terminal: GestureTerminal) -> &'static str {
    match terminal {
        GestureTerminal::Committed => "committed",
        GestureTerminal::Cancelled => "cancelled",
        GestureTerminal::Invalidated => "invalidated",
    }
}

fn run_gesture_fixture(path: &Path, entry: &ManifestEntry) {
    let fixture: GestureTraceFixture = read_json(path);
    let bindings = fixture
        .paths
        .iter()
        .cloned()
        .map(|path| Binding {
            key_id: "fixture.key".into(),
            path,
            behavior: empty_behavior(),
        })
        .collect();
    let trie = BindingTrieCompiler::compile(
        &BindingSet {
            id: "fixture.bindings".into(),
            bindings,
        },
        "fixture.key",
    )
    .expect("gesture fixture trie");

    let first = fixture.samples.first().expect("touch down sample");
    assert_eq!(first.event, "down", "{} first sample", entry.file);
    let mut session = GestureSession::new(
        "fixture.key",
        "fixture",
        trie,
        fixture.policy,
        GestureSize {
            width: fixture.key_size[0],
            height: fixture.key_size[1],
        },
        GesturePoint {
            x: first.point[0],
            y: first.point[1],
        },
        0,
    );

    for sample in fixture.samples.iter().skip(1) {
        let point = GesturePoint {
            x: sample.point[0],
            y: sample.point[1],
        };
        match sample.event.as_str() {
            "move" => session.move_to(point, None),
            "up" => {
                session.move_to(point, None);
                session.touch_up(None);
            }
            other => panic!("{} unknown sample event {other}", entry.file),
        }
    }

    assert_eq!(session.path, fixture.expected.path, "{} path", entry.file);
    let anchors = session
        .commit_anchors
        .iter()
        .map(|point| [point.x, point.y])
        .collect::<Vec<_>>();
    assert_eq!(
        anchors, fixture.expected.commit_anchors,
        "{} commit anchors",
        entry.file
    );
    assert_eq!(
        session.terminal.map(terminal_name),
        Some(fixture.expected.terminal.as_str()),
        "{} terminal",
        entry.file
    );
}

fn lifecycle_policy() -> GesturePolicy {
    GesturePolicy {
        dead_zone: 0.15,
        stage1_commit_distance: 0.4,
        stage2_commit_distance: 0.4,
        angular_hysteresis_degrees: 8.0,
        max_directional_stages: 2,
    }
}

fn run_lifecycle_fixture(path: &Path, entry: &ManifestEntry) {
    let fixture: LifecycleFixture = read_json(path);
    let trie = BindingTrieCompiler::compile(
        &BindingSet {
            id: "fixture.lifecycle".into(),
            bindings: vec![Binding {
                key_id: "fixture.key".into(),
                path: GesturePath::default(),
                behavior: fixture.endpoint_behavior,
            }],
        },
        "fixture.key",
    )
    .expect("lifecycle fixture trie");

    let mut session: Option<GestureSession> = None;
    let mut next_session_profile_revision: Option<String> = None;

    for event in fixture.events {
        match event {
            LifecycleEvent::TouchDown {
                profile_revision,
                at_ms,
            } => {
                session = Some(GestureSession::new(
                    "fixture.key",
                    profile_revision.unwrap_or_else(|| "fixture".into()),
                    trie.clone(),
                    lifecycle_policy(),
                    GestureSize {
                        width: 100.0,
                        height: 100.0,
                    },
                    GesturePoint { x: 0.0, y: 0.0 },
                    at_ms,
                ));
            }
            LifecycleEvent::Cancel { at_ms } => {
                session
                    .as_mut()
                    .expect("session before cancel")
                    .cancel(Some(at_ms));
            }
            LifecycleEvent::AdvanceTime { to_ms } => {
                session
                    .as_mut()
                    .expect("session before advance")
                    .advance_time(to_ms);
            }
            LifecycleEvent::ProfileReload {
                new_revision,
                at_ms,
            } => {
                session
                    .as_mut()
                    .expect("session before profile reload")
                    .invalidate(Some(at_ms));
                next_session_profile_revision = Some(new_revision);
            }
            LifecycleEvent::TouchUp { at_ms } => {
                session
                    .as_mut()
                    .expect("session before touch up")
                    .touch_up(Some(at_ms));
            }
        }
    }

    let session = session.expect("lifecycle session");
    assert_eq!(
        session.terminal.map(terminal_name),
        Some(fixture.expected.terminal.as_str()),
        "{} terminal",
        entry.file
    );
    assert_eq!(
        session.dispatched_actions,
        fixture.expected.dispatched_actions,
        "{} dispatched actions",
        entry.file
    );
    assert_eq!(
        next_session_profile_revision,
        fixture.expected.next_session_profile_revision,
        "{} next session profile revision",
        entry.file
    );
}

#[test]
fn canonical_manifest_passes_against_rust_runtime() {
    let root = repo_root();
    let conformance = root.join("spec").join("conformance");
    let manifest: Manifest = read_json(&conformance.join("manifest.json"));

    assert_eq!(
        manifest.schema, "gesture-ime.conformance-manifest.v1",
        "manifest schema"
    );

    for entry in &manifest.fixtures {
        let path = conformance.join(&entry.file);
        match entry.kind.as_str() {
            "profile" => run_profile_fixture(&path, entry),
            "gesture-trace" => run_gesture_fixture(&path, entry),
            "lifecycle" => run_lifecycle_fixture(&path, entry),
            other => panic!("{} unsupported fixture kind {other}", entry.file),
        }
    }
}