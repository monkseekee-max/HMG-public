//! Protocol sync tests — ensure public DTOs stay aligned with the service contract.
//!
//! These tests verify that the public DTO types in export/protocol/ stay
//! in sync with the corresponding wire shapes exposed by the service.
//!
//! Run: cargo test -p hmg-protocol protocol_sync

// NOTE: These tests run inside the export/protocol crate which is standalone.
// They work by re-declaring the expected wire shapes and checking enum variants
// match. Release CI runs a separate field-level conformance check against the
// service implementation.

/// All CorrectionAction variants must be representable as wire strings.
#[test]
fn correction_action_wire_variants() {
    let expected = &[
        "negate",
        "confirm_actual",
        "confirm_necessary",
        "demote",
        "replace",
    ];

    let all = crate::CorrectionAction::all_variants();
    assert_eq!(all.len(), expected.len(), "variant count mismatch");

    for (i, expected_str) in expected.iter().enumerate() {
        assert!(
            crate::CorrectionAction::from_str(expected_str).is_some(),
            "CorrectionAction::from_str({expected_str}) returned None"
        );
        assert_eq!(
            all[i], *expected_str,
            "variant at index {i}: expected {expected_str}, got {}",
            all[i]
        );
    }
}

/// CorrectionAction::from_str rejects unknown actions.
#[test]
fn correction_action_rejects_unknown() {
    assert!(crate::CorrectionAction::from_str("unknown").is_none());
    assert!(crate::CorrectionAction::from_str("").is_none());
    assert!(crate::CorrectionAction::from_str("replace_content").is_none());
}

/// Polarity enum serializes to expected wire format.
#[test]
fn polarity_wire_format() {
    let positive = crate::Polarity::Positive;
    let negative = crate::Polarity::Negative { reason: Some("test".into()) };
    let conditional = crate::Polarity::Conditional { condition: Some("if X".into()) };

    let json_pos = serde_json::to_string(&positive).unwrap();
    let json_neg = serde_json::to_string(&negative).unwrap();
    let json_cond = serde_json::to_string(&conditional).unwrap();

    assert!(json_pos.contains("\"positive\""), "Polarity::Positive should serialize to snake_case");
    assert!(json_neg.contains("\"negative\""), "Polarity::Negative should serialize to snake_case");
    assert!(json_cond.contains("\"conditional\""), "Polarity::Conditional should serialize to snake_case");
}

/// EpistemicStatus enum covers the three canonical states.
#[test]
fn epistemic_status_variants() {
    let variants = [
        crate::EpistemicStatus::Possible,
        crate::EpistemicStatus::Actual,
        crate::EpistemicStatus::Necessary,
    ];

    for v in &variants {
        let json = serde_json::to_string(v).unwrap();
        let back: crate::EpistemicStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(*v, back, "EpistemicStatus roundtrip failed for {json}");
    }
}

/// ExposureState covers all five governance states.
#[test]
fn exposure_state_variants() {
    let variants = [
        crate::ExposureState::Visible,
        crate::ExposureState::Quarantined,
        crate::ExposureState::Sealed,
        crate::ExposureState::Tombstoned,
        crate::ExposureState::Lesson,
    ];

    for v in &variants {
        let json = serde_json::to_string(v).unwrap();
        let back: crate::ExposureState = serde_json::from_str(&json).unwrap();
        assert_eq!(*v, back, "ExposureState roundtrip failed for {json}");
    }
}

/// Modality covers all six sensory modalities.
#[test]
fn modality_variants() {
    let variants = [
        crate::Modality::Text,
        crate::Modality::Code,
        crate::Modality::Observation,
        crate::Modality::System,
        crate::Modality::Dialogue,
        crate::Modality::MultiModal,
    ];

    for v in &variants {
        let json = serde_json::to_string(v).unwrap();
        let back: crate::Modality = serde_json::from_str(&json).unwrap();
        assert_eq!(*v, back, "Modality roundtrip failed for {json}");
    }
}

/// GovernanceAction covers all four governance operations.
#[test]
fn governance_action_variants() {
    let variants = [
        crate::GovernanceAction::Quarantine,
        crate::GovernanceAction::Seal,
        crate::GovernanceAction::Tombstone,
        crate::GovernanceAction::DeriveLesson,
    ];

    for v in &variants {
        let json = serde_json::to_string(v).unwrap();
        let back: crate::GovernanceAction = serde_json::from_str(&json).unwrap();
        assert_eq!(*v, back, "GovernanceAction roundtrip failed for {json}");
    }
}

/// AtomView round-trips through JSON.
#[test]
fn atom_view_json_roundtrip() {
    let atom = crate::AtomView {
        id: "01KSD4ZQFXV4G3W7FY7H9KH2V9".into(),
        content: "We chose PostgreSQL for the main database".into(),
        structured: None,
        created_at: "2026-05-24T12:00:00Z".into(),
        updated_at: None,
        polarity: crate::Polarity::Positive,
        epistemic: crate::EpistemicStatus::Actual,
        exposure: crate::ExposureState::Visible,
        modality: crate::Modality::Text,
        category: Some("decision".into()),
        source: Some("agent".into()),
        source_modality: Some("agent".into()),
    };

    let json = serde_json::to_string(&atom).unwrap();
    let back: crate::AtomView = serde_json::from_str(&json).unwrap();

    assert_eq!(atom.id, back.id);
    assert_eq!(atom.content, back.content);
    assert_eq!(atom.polarity, back.polarity);
    assert_eq!(atom.epistemic, back.epistemic);
    assert_eq!(atom.exposure, back.exposure);
    assert_eq!(atom.modality, back.modality);
}

/// ScopeRef coding_agent convenience constructor.
#[test]
fn scope_ref_coding_agent() {
    let scope = crate::ScopeRef::coding_agent("my-tenant", "platform", "my-repo", "main");

    assert_eq!(scope.tenant_id, "my-tenant");
    assert_eq!(scope.path.len(), 3);
    assert_eq!(scope.path[0].kind, "workspace");
    assert_eq!(scope.path[0].id, "platform");
    assert_eq!(scope.path[1].kind, "repository");
    assert_eq!(scope.path[1].id, "my-repo");
    assert_eq!(scope.path[2].kind, "branch");
    assert_eq!(scope.path[2].id, "main");
}

/// ScopeRef JSON round-trip.
#[test]
fn scope_ref_json_roundtrip() {
    let scope = crate::ScopeRef::coding_agent("t1", "ws1", "repo1", "branch1");
    let json = serde_json::to_string(&scope).unwrap();
    let back: crate::ScopeRef = serde_json::from_str(&json).unwrap();
    assert_eq!(scope, back);
}

/// RecallResponse JSON round-trip.
#[test]
fn recall_response_json_roundtrip() {
    let response = crate::RecallResponse {
        atoms: vec![
            crate::RecallAtom {
                content: "test memory".into(),
                id: "01ABC".into(),
                relevance: 0.95,
                scope: Some("tenant-acme/platform/repo/main".into()),
                created_at: Some("2026-05-24T12:00:00Z".into()),
            },
        ],
        total_candidates: 10,
        query: "test query".into(),
        format: crate::OutputFormat::CompactYaml,
        diagnostics: None,
    };

    let json = serde_json::to_string(&response).unwrap();
    let back: crate::RecallResponse = serde_json::from_str(&json).unwrap();

    assert_eq!(response.atoms.len(), back.atoms.len());
    assert_eq!(response.atoms[0].content, back.atoms[0].content);
    assert_eq!(response.format, back.format);
}

/// MemorizeAck JSON round-trip.
#[test]
fn memorize_ack_json_roundtrip() {
    let ack = crate::MemorizeAck {
        atom_ids: vec!["01AAA".into(), "01BBB".into()],
        success: true,
        message: Some("Stored 2 atoms".into()),
    };

    let json = serde_json::to_string(&ack).unwrap();
    let back: crate::MemorizeAck = serde_json::from_str(&json).unwrap();

    assert_eq!(ack.atom_ids, back.atom_ids);
    assert_eq!(ack.success, back.success);
}

/// OutputFormat variants round-trip.
#[test]
fn output_format_variants() {
    for fmt in [
        crate::OutputFormat::CompactYaml,
        crate::OutputFormat::Json,
        crate::OutputFormat::Markdown,
        crate::OutputFormat::Summary,
    ] {
        let json = serde_json::to_string(&fmt).unwrap();
        let back: crate::OutputFormat = serde_json::from_str(&json).unwrap();
        assert_eq!(fmt, back);
    }
}

/// AccessLevel variants round-trip.
#[test]
fn access_level_variants() {
    for level in [
        crate::AccessLevel::Internal,
        crate::AccessLevel::Shared,
        crate::AccessLevel::Restricted,
    ] {
        let json = serde_json::to_string(&level).unwrap();
        let back: crate::AccessLevel = serde_json::from_str(&json).unwrap();
        assert_eq!(level, back);
    }
}

/// Scope parsers: parse_scope_from_map and scope_to_map are inverse.
#[test]
fn scope_parser_roundtrip() {
    let mut map = std::collections::HashMap::new();
    map.insert("tenant_id".to_string(), "my-tenant".into());
    map.insert("workspace".to_string(), "platform".into());
    map.insert("repository".to_string(), "my-repo".into());
    map.insert("branch".to_string(), "main".into());

    let scope = crate::scope_parsers::parse_scope_from_map(&map).unwrap();
    assert_eq!(scope.tenant_id, "my-tenant");
    assert_eq!(scope.path.len(), 3);

    let back = crate::scope_parsers::scope_to_map(&scope);
    assert_eq!(back.get("tenant_id").unwrap(), "my-tenant");
    assert_eq!(back.get("workspace").unwrap(), "platform");
    assert_eq!(back.get("repository").unwrap(), "my-repo");
    assert_eq!(back.get("branch").unwrap(), "main");
}

/// Scope parser returns None for empty map.
#[test]
fn scope_parser_empty_map() {
    let map = std::collections::HashMap::<String, String>::new();
    assert!(crate::scope_parsers::parse_scope_from_map(&map).is_none());
}

/// Scope parser returns Some with tenant-only if no scope segments.
#[test]
fn scope_parser_tenant_only() {
    let mut map = std::collections::HashMap::new();
    map.insert("tenant_id".to_string(), "my-tenant".into());
    // No scope segments → returns None (path is empty)
    assert!(crate::scope_parsers::parse_scope_from_map(&map).is_none());
}
