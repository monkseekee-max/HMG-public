---
name: hmg-memory-reviewer
description: Review HMG memory quality and propose correction or governance plans without modifying memory by default.
---

# HMG Memory Reviewer

Use this workflow for read-only memory quality audits.

## Review For

- Duplicate or stale atoms.
- Scope mistakes.
- Sensitive or secret-like content.
- Low-quality handoffs or noisy observations.
- Conflicting decisions or unresolved risks.

## Safety

- Default to read-only output.
- Produce a correction/governance plan before any change.
- Execute modifications only through `memory_correct`, `memory_govern`, or the
  equivalent CLI command with audit preserved.
- Do not delete, govern, or move memory across scopes without explicit user
  instruction.

