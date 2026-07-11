//! Scope — hierarchical context for memory atoms.
//!
//! Scope defines where a memory lives: which tenant, workspace, repository,
//! branch, task, etc. The scope hierarchy is domain-specific and configured
//! via domain packs.

/// One segment in a hierarchical scope path.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize, PartialEq, Eq, Hash)]
pub struct ScopeSegment {
    /// The kind of scope segment (e.g., "workspace", "repository", "branch").
    pub kind: String,
    /// The identifier within that kind (e.g., "my-org", "my-repo", "main").
    pub id: String,
}

/// A hierarchical scope reference.
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize, PartialEq, Eq, Hash)]
pub struct ScopeRef {
    /// The tenant that owns this scope.
    pub tenant_id: String,
    /// The hierarchical path of scope segments.
    pub path: Vec<ScopeSegment>,
}

impl ScopeRef {
    /// Create a new scope reference.
    pub fn new(tenant_id: impl Into<String>, path: impl IntoIterator<Item = ScopeSegment>) -> Self {
        Self {
            tenant_id: tenant_id.into(),
            path: path.into_iter().collect(),
        }
    }

    /// Convenience: create a software-engineering style scope.
    ///
    /// ```ignore
    /// let scope = ScopeRef::coding_agent("my-tenant", "my-workspace", "my-repo", "main");
    /// ```
    pub fn coding_agent(tenant_id: &str, workspace: &str, repository: &str, branch: &str) -> Self {
        Self::new(
            tenant_id,
            vec![
                ScopeSegment {
                    kind: "workspace".into(),
                    id: workspace.into(),
                },
                ScopeSegment {
                    kind: "repository".into(),
                    id: repository.into(),
                },
                ScopeSegment {
                    kind: "branch".into(),
                    id: branch.into(),
                },
            ],
        )
    }
}
