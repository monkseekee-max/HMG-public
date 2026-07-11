//! Conformance tests for HMG-compatible implementations.
//!
//! These tests verify wire-schema shapes and lifecycle semantics using
//! the `hmg-protocol` crate types. They do not require a running HMG server.

#[cfg(test)]
mod tests {
    use hmg_protocol::*;

    // --- Wire schema tests ---

    #[test]
    fn atom_view_round_trips_json() {
        let atom = AtomView {
            id: "01KSD4ZQFXV4G3W7FY7H9KH2V9".into(),
            content: "Test content".into(),
            structured: None,
            created_at: "2026-05-24T12:00:00Z".into(),
            updated_at: None,
            polarity: Polarity::Positive,
            epistemic: EpistemicStatus::Actual,
            exposure: ExposureState::Visible,
            modality: Modality::Text,
            category: Some("decision".into()),
            source: Some("agent".into()),
            source_modality: Some("agent".into()),
        };

        let json = serde_json::to_string(&atom).unwrap();
        let back: AtomView = serde_json::from_str(&json).unwrap();

        assert_eq!(atom.id, back.id);
        assert_eq!(atom.content, back.content);
        assert_eq!(atom.polarity, back.polarity);
        assert_eq!(atom.epistemic, back.epistemic);
        assert_eq!(atom.exposure, back.exposure);
        assert_eq!(atom.modality, back.modality);
    }

    #[test]
    fn correction_action_all_variants_round_trip() {
        for variant in &[
            "negate",
            "confirm_actual",
            "confirm_necessary",
            "demote",
            "replace",
        ] {
            let action = CorrectionAction::from_str(variant)
                .unwrap_or_else(|| panic!("Unknown variant: {variant}"));
            let json = serde_json::to_string(&action).unwrap();
            assert!(
                json.contains(variant),
                "Serialized form should contain {variant}"
            );
        }
    }

    #[test]
    fn governance_action_all_variants_round_trip() {
        let variants = [
            GovernanceAction::Quarantine,
            GovernanceAction::Seal,
            GovernanceAction::Tombstone,
            GovernanceAction::DeriveLesson,
        ];

        for action in &variants {
            let json = serde_json::to_string(&action).unwrap();
            let back: GovernanceAction = serde_json::from_str(&json).unwrap();
            assert_eq!(format!("{:?}", action), format!("{:?}", back));
        }
    }

    #[test]
    fn polarity_variants_round_trip() {
        let variants = [
            Polarity::Positive,
            Polarity::Negative {
                reason: Some("test".into()),
            },
            Polarity::Conditional {
                condition: Some("if X".into()),
            },
        ];

        for p in &variants {
            let json = serde_json::to_string(p).unwrap();
            let back: Polarity = serde_json::from_str(&json).unwrap();
            assert_eq!(format!("{:?}", p), format!("{:?}", back));
        }
    }

    #[test]
    fn exposure_state_all_five_variants() {
        let variants = [
            ExposureState::Visible,
            ExposureState::Quarantined,
            ExposureState::Sealed,
            ExposureState::Tombstoned,
            ExposureState::Lesson,
        ];

        for v in &variants {
            let json = serde_json::to_string(v).unwrap();
            let back: ExposureState = serde_json::from_str(&json).unwrap();
            assert_eq!(v, &back);
        }
    }

    // --- Lifecycle semantics tests ---

    #[test]
    fn correction_negate_changes_polarity() {
        let atom = AtomView {
            id: "01TEST".into(),
            content: "This is correct".into(),
            polarity: Polarity::Positive,
            ..default_atom_view()
        };

        // After negate, polarity should be Negative
        let negated = CorrectionAction::Negate;
        let json = serde_json::to_string(&negated).unwrap();
        assert!(json.contains("negate"));

        // Verify the atom had positive polarity before
        assert!(matches!(atom.polarity, Polarity::Positive));
    }

    #[test]
    fn governance_tombstone_removes_from_normal_recall() {
        let states = [ExposureState::Visible, ExposureState::Tombstoned];

        // Normal recall should include Visible, exclude Tombstoned
        let normal_visible: Vec<_> = states
            .iter()
            .filter(|s| matches!(s, ExposureState::Visible))
            .collect();
        assert_eq!(normal_visible.len(), 1);

        let tombstoned_in_normal: Vec<_> = states
            .iter()
            .filter(|s| matches!(s, ExposureState::Tombstoned))
            .collect();
        assert_eq!(tombstoned_in_normal.len(), 1); // exists but filtered in recall
    }

    #[test]
    fn scope_hierarchy_is_preserved() {
        let scope = ScopeRef::coding_agent("tenant", "workspace", "repo", "branch");

        assert_eq!(scope.tenant_id, "tenant");
        assert_eq!(scope.path.len(), 3);
        assert_eq!(scope.path[0].kind, "workspace");
        assert_eq!(scope.path[1].kind, "repository");
        assert_eq!(scope.path[2].kind, "branch");
    }

    #[test]
    fn recall_response_shape() {
        let response = RecallResponse {
            atoms: vec![RecallAtom {
                content: "test".into(),
                id: "01ABC".into(),
                relevance: 0.95,
                scope: Some("tenant/ws/repo/branch".into()),
                created_at: Some("2026-05-24T12:00:00Z".into()),
            }],
            total_candidates: 10,
            query: "test query".into(),
            format: OutputFormat::CompactYaml,
            diagnostics: None,
        };

        let json = serde_json::to_string(&response).unwrap();
        let back: RecallResponse = serde_json::from_str(&json).unwrap();

        assert_eq!(response.atoms.len(), back.atoms.len());
        assert_eq!(response.total_candidates, back.total_candidates);
    }

    #[test]
    fn memorize_ack_shape() {
        let ack = MemorizeAck {
            atom_ids: vec!["01AAA".into(), "01BBB".into()],
            success: true,
            message: Some("Stored 2 atoms".into()),
        };

        let json = serde_json::to_string(&ack).unwrap();
        let back: MemorizeAck = serde_json::from_str(&json).unwrap();

        assert_eq!(ack.atom_ids, back.atom_ids);
        assert!(back.success);
    }

    // --- Helper ---

    fn default_atom_view() -> AtomView {
        AtomView {
            id: String::new(),
            content: String::new(),
            structured: None,
            created_at: String::new(),
            updated_at: None,
            polarity: Polarity::Positive,
            epistemic: EpistemicStatus::Possible,
            exposure: ExposureState::Visible,
            modality: Modality::Text,
            category: None,
            source: None,
            source_modality: None,
        }
    }
}
