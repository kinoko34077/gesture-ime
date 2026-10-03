use gesture_ime_core::{
    ActionInvocation, Binding, BindingBehavior, BindingSet, BindingTrieCompiler, Direction8,
    GesturePath, GestureToken, ProfileValidationCode,
};
use serde_json::Map;
use std::collections::HashSet;

fn token(direction: Direction8) -> GestureToken {
    GestureToken { direction }
}

fn behavior(label: &str) -> BindingBehavior {
    BindingBehavior {
        presentation: None,
        on_release: vec![ActionInvocation {
            action_id: "text.insert".into(),
            arguments: Map::from_iter([("text".into(), label.into())]),
        }],
        hold: None,
    }
}

fn binding(key_id: &str, path: Vec<Direction8>, label: &str) -> Binding {
    Binding {
        key_id: key_id.into(),
        path: GesturePath(path.into_iter().map(token).collect()),
        behavior: behavior(label),
    }
}

#[test]
fn default_cardinal_key_exposes_only_cardinal_children() {
    let set = BindingSet {
        id: "bindings.base".into(),
        bindings: vec![
            binding("key.a", vec![], "あ"),
            binding("key.a", vec![Direction8::N], "う"),
            binding("key.a", vec![Direction8::E], "え"),
            binding("key.a", vec![Direction8::S], "お"),
            binding("key.a", vec![Direction8::W], "い"),
        ],
    };

    let trie = BindingTrieCompiler::compile(&set, "key.a").unwrap();

    assert_eq!(
        trie.root.eligible_directions(),
        HashSet::from([Direction8::N, Direction8::E, Direction8::S, Direction8::W])
    );
    assert!(trie.root.behavior.is_some());
}

#[test]
fn adding_diagonal_binding_exposes_diagonal_without_recognizer_change() {
    let set = BindingSet {
        id: "bindings.diagonal".into(),
        bindings: vec![
            binding("key.a", vec![Direction8::N], "う"),
            binding("key.a", vec![Direction8::Ne], "↗"),
            binding("key.a", vec![Direction8::E], "え"),
        ],
    };

    let trie = BindingTrieCompiler::compile(&set, "key.a").unwrap();

    assert_eq!(
        trie.root.eligible_directions(),
        HashSet::from([Direction8::N, Direction8::Ne, Direction8::E])
    );
}

#[test]
fn path_prefix_behavior_and_second_stage_children_coexist() {
    let set = BindingSet {
        id: "bindings.two-stage".into(),
        bindings: vec![
            binding("key.a", vec![Direction8::E], "え"),
            binding("key.a", vec![Direction8::E, Direction8::N], "→↑"),
            binding("key.a", vec![Direction8::E, Direction8::E], "→→"),
        ],
    };

    let trie = BindingTrieCompiler::compile(&set, "key.a").unwrap();
    let east = trie
        .node(&GesturePath(vec![token(Direction8::E)]))
        .expect("east node");

    assert!(east.behavior.is_some());
    assert_eq!(
        east.eligible_directions(),
        HashSet::from([Direction8::N, Direction8::E])
    );
    assert!(trie
        .node(&GesturePath(vec![token(Direction8::E), token(Direction8::N)]))
        .is_some());
    assert!(trie
        .node(&GesturePath(vec![token(Direction8::E), token(Direction8::E)]))
        .is_some());
}

#[test]
fn unrelated_key_bindings_are_not_compiled_into_target_trie() {
    let set = BindingSet {
        id: "bindings.multi".into(),
        bindings: vec![
            binding("key.a", vec![Direction8::N], "う"),
            binding("key.ka", vec![Direction8::Ne], "け"),
        ],
    };

    let trie = BindingTrieCompiler::compile(&set, "key.a").unwrap();

    assert_eq!(trie.root.eligible_directions(), HashSet::from([Direction8::N]));
    assert!(trie
        .node(&GesturePath(vec![token(Direction8::Ne)]))
        .is_none());
}

#[test]
fn duplicate_path_is_rejected_at_compile_boundary() {
    let set = BindingSet {
        id: "bindings.duplicate".into(),
        bindings: vec![
            binding("key.a", vec![Direction8::E], "え"),
            binding("key.a", vec![Direction8::E], "duplicate"),
        ],
    };

    let error = BindingTrieCompiler::compile(&set, "key.a").unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::DuplicateBindingPath);
}

#[test]
fn path_deeper_than_v1_limit_is_rejected_at_compile_boundary() {
    let set = BindingSet {
        id: "bindings.deep".into(),
        bindings: vec![binding(
            "key.a",
            vec![Direction8::E, Direction8::N, Direction8::W],
            "too-deep",
        )],
    };

    let error = BindingTrieCompiler::compile(&set, "key.a").unwrap_err();
    assert_eq!(error.code, ProfileValidationCode::PathDepth);
}