//! Platform-neutral Profile v3 authoring session.
//! A command is validated atomically and contributes at most one Undo step.
use crate::profile_v3::{PresentationV3, ProfileBundleV3, ResolvedStringV3};
use crate::profile_v3_validation::ProfileV3Codec;
use serde_json::json;

const HISTORY_CAPACITY: usize = 32;

#[derive(Debug, thiserror::Error)]
pub enum ProfileV3EditError {
    #[error("invalid Profile or edit: {0}")]
    Invalid(String),
    #[error("board not found: {0}")]
    BoardNotFound(String),
    #[error("entry not found: {0}")]
    EntryNotFound(String),
}

#[derive(Debug)]
pub struct ProfileV3Editor {
    profile: ProfileBundleV3,
    undo: Vec<ProfileBundleV3>,
    redo: Vec<ProfileBundleV3>,
}

impl ProfileV3Editor {
    pub fn open(profile_json: &str) -> Result<Self, ProfileV3EditError> {
        let profile = ProfileV3Codec::decode_and_validate(profile_json.as_bytes())
            .map_err(|error| ProfileV3EditError::Invalid(format!("{error:?}")))?;
        Ok(Self { profile, undo: Vec::new(), redo: Vec::new() })
    }

    pub fn profile(&self) -> &ProfileBundleV3 { &self.profile }
    pub fn can_undo(&self) -> bool { !self.undo.is_empty() }
    pub fn can_redo(&self) -> bool { !self.redo.is_empty() }

    /// Updates only the default presentation text for one authored entry.
    /// All existing actions, conditional cases, transition, accessibility label,
    /// conditional text transforms and extra Profile fields are preserved.
    pub fn set_entry_default_text(
        &mut self,
        board_id: &str,
        entry_id: &str,
        text: String,
    ) -> Result<bool, ProfileV3EditError> {
        let mut next = self.profile.clone();
        let board = next.boards.iter_mut().find(|board| board.id == board_id)
            .ok_or_else(|| ProfileV3EditError::BoardNotFound(board_id.to_owned()))?;
        let entry = board.entries.iter_mut().find(|entry| entry.id == entry_id)
            .ok_or_else(|| ProfileV3EditError::EntryNotFound(entry_id.to_owned()))?;
        let presentation = entry.resolver.default.presentation
            .get_or_insert_with(PresentationV3::default);
        match &mut presentation.text {
            Some(resolved) => resolved.base = text,
            None => presentation.text = Some(ResolvedStringV3 {
                base: text,
                transforms: Vec::new(),
                extra: Default::default(),
            }),
        }

        if next == self.profile { return Ok(false); }

        // Re-decode through canonical structural/semantic validator before
        // committing; invalid edits preserve the prior document and history.
        let bytes = next.encode().map_err(|error|
            ProfileV3EditError::Invalid(error.to_string()))?;
        let validated = ProfileV3Codec::decode_and_validate(&bytes)
            .map_err(|error| ProfileV3EditError::Invalid(format!("{error:?}")))?;
        Self::push(&mut self.undo, std::mem::replace(&mut self.profile, validated));
        self.redo.clear();
        Ok(true)
    }

    pub fn undo(&mut self) -> bool {
        let Some(previous) = self.undo.pop() else { return false };
        let current = std::mem::replace(&mut self.profile, previous);
        Self::push(&mut self.redo, current);
        true
    }

    pub fn redo(&mut self) -> bool {
        let Some(next) = self.redo.pop() else { return false };
        let current = std::mem::replace(&mut self.profile, next);
        Self::push(&mut self.undo, current);
        true
    }

    pub fn export_json(&self) -> Result<String, ProfileV3EditError> {
        serde_json::to_string(&self.profile)
            .map_err(|error| ProfileV3EditError::Invalid(error.to_string()))
    }

    /// Common state contract used by the Wasm editor and native parity CLI.
    pub fn state_json(&self) -> Result<String, ProfileV3EditError> {
        let profile = serde_json::to_value(&self.profile)
            .map_err(|error| ProfileV3EditError::Invalid(error.to_string()))?;
        Ok(json!({
            "profile": profile,
            "canUndo": self.can_undo(),
            "canRedo": self.can_redo(),
        }).to_string())
    }

    fn push(stack: &mut Vec<ProfileBundleV3>, value: ProfileBundleV3) {
        stack.push(value);
        if stack.len() > HISTORY_CAPACITY {
            stack.remove(0);
        }
    }
}
