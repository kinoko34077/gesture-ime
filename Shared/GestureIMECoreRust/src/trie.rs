use crate::model::{BindingBehavior, BindingSet, Direction8, GesturePath};
use crate::validation::{ProfileLimits, ProfileValidationCode, ProfileValidationError};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, PartialEq)]
pub struct BindingTrieNode {
    pub behavior: Option<BindingBehavior>,
    pub children: HashMap<Direction8, BindingTrieNode>,
}

impl BindingTrieNode {
    pub fn eligible_directions(&self) -> HashSet<Direction8> {
        self.children.keys().copied().collect()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct BindingTrie {
    pub root: BindingTrieNode,
}

impl BindingTrie {
    pub fn node(&self, path: &GesturePath) -> Option<&BindingTrieNode> {
        let mut node = &self.root;
        for token in &path.0 {
            node = node.children.get(&token.direction)?;
        }
        Some(node)
    }
}

#[derive(Default)]
struct BuilderNode {
    behavior: Option<BindingBehavior>,
    children: HashMap<Direction8, BuilderNode>,
}

pub struct BindingTrieCompiler;

impl BindingTrieCompiler {
    pub fn compile(
        binding_set: &BindingSet,
        key_id: &str,
    ) -> Result<BindingTrie, ProfileValidationError> {
        let mut root = BuilderNode::default();
        let mut seen = HashSet::<GesturePath>::new();

        for binding in binding_set
            .bindings
            .iter()
            .filter(|binding| binding.key_id == key_id)
        {
            if binding.path.0.len() > ProfileLimits::PATH_DEPTH {
                return Err(ProfileValidationError::simple(
                    ProfileValidationCode::PathDepth,
                ));
            }

            if !seen.insert(binding.path.clone()) {
                return Err(ProfileValidationError::new(
                    ProfileValidationCode::DuplicateBindingPath,
                    Some(format!("{}:{key_id}", binding_set.id)),
                ));
            }

            let mut node = &mut root;
            for token in &binding.path.0 {
                node = node.children.entry(token.direction).or_default();
            }
            node.behavior = Some(binding.behavior.clone());
        }

        Ok(BindingTrie {
            root: freeze(root),
        })
    }
}

fn freeze(node: BuilderNode) -> BindingTrieNode {
    BindingTrieNode {
        behavior: node.behavior,
        children: node
            .children
            .into_iter()
            .map(|(direction, child)| (direction, freeze(child)))
            .collect(),
    }
}