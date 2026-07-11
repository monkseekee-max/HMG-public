//! Correction actions — the operations that modify a memory atom's epistemic state.
//!
//! Corrections are append-only: the original atom's history is preserved,
//! and a new state is appended to the polarity/epistemic history.

/// Actions that can be applied to correct a memory atom.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum CorrectionAction {
    /// Negate the atom — mark it as false.
    Negate,
    /// Elevate epistemic status to Actual (confirmed as true).
    ConfirmActual,
    /// Elevate epistemic status to Necessary (axiomatic).
    ConfirmNecessary,
    /// Demote epistemic status to Possible (uncertain / unverified).
    Demote,
    /// Replace the atom's content with new text.
    /// Creates a `Supersedes` edge from the new atom to the old one.
    Replace,
}

impl CorrectionAction {
    /// All valid correction action variants as wire strings.
    pub fn all_variants() -> &'static [&'static str] {
        &[
            "negate",
            "confirm_actual",
            "confirm_necessary",
            "demote",
            "replace",
        ]
    }

    /// Parse a wire string into a CorrectionAction.
    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "negate" => Some(Self::Negate),
            "confirm_actual" => Some(Self::ConfirmActual),
            "confirm_necessary" => Some(Self::ConfirmNecessary),
            "demote" => Some(Self::Demote),
            "replace" => Some(Self::Replace),
            _ => None,
        }
    }
}

/// Result of a correction operation.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct CorrectionResult {
    /// Whether the correction was applied successfully.
    pub success: bool,
    /// Human-readable description of what happened.
    pub message: String,
    /// If a replacement was made, the ID of the new atom.
    pub replacement_atom_id: Option<String>,
}
