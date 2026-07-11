//! HMG Protocol — Wire-safe public DTO types.
//!
//! This crate defines the public types that appear in HMG wire protocols
//! (HTTP, MCP, gRPC, SDK). It contains **no** ranking, scoring, or internal
//! algorithm types — only the data shapes that users and agents see.
//!
//! # Stability
//!
//! Types in this crate follow semantic versioning. Breaking changes to
//! wire-visible fields will result in a major version bump.

pub mod atom;
pub mod bulk;
pub mod context;
pub mod correction;
pub mod governance;
pub mod output;
pub mod scope;
pub mod scope_parsers;

#[cfg(test)]
mod tests;

pub use atom::*;
pub use bulk::*;
pub use context::{AccessLevel, MemoryContextView};
pub use correction::*;
pub use governance::*;
pub use output::*;
pub use scope::{ScopeRef, ScopeSegment};
