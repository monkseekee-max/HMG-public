//! Scope serialization helpers for MCP/HTTP wire format.

use crate::scope::{ScopeRef, ScopeSegment};

/// Parse a scope from a flat string map (as used in MCP tool parameters).
///
/// Expected keys depend on domain pack. For software-engineering:
/// `tenant_id`, `workspace`, `repository`, `branch`, `task_id`, etc.
pub fn parse_scope_from_map(map: &std::collections::HashMap<String, String>) -> Option<ScopeRef> {
    let tenant_id = map.get("tenant_id")?;
    let mut path = Vec::new();

    // Standard software-engineering scope segments
    for (kind, key) in [
        ("workspace", "workspace"),
        ("repository", "repository"),
        ("branch", "branch"),
        ("task", "task_id"),
        ("pull_request", "pull_request_id"),
        ("issue", "issue_id"),
    ] {
        if let Some(id) = map.get(key) {
            path.push(ScopeSegment {
                kind: kind.to_string(),
                id: id.clone(),
            });
        }
    }

    if path.is_empty() {
        return None;
    }

    Some(ScopeRef::new(tenant_id, path))
}

/// Serialize a scope into a flat string map (for MCP tool responses).
pub fn scope_to_map(scope: &ScopeRef) -> std::collections::HashMap<String, String> {
    let mut map = std::collections::HashMap::new();
    map.insert("tenant_id".to_string(), scope.tenant_id.clone());
    for seg in &scope.path {
        map.insert(seg.kind.clone(), seg.id.clone());
    }
    map
}
