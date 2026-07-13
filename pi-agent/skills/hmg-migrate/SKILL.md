---
name: hmg-migrate
description: Execute a reviewed HMG migration plan with provenance, dry-run safety, and secret rejection.
---

# HMG Migrate

Use this workflow only after an import plan has been reviewed.

## Workflow

1. Confirm dry-run output, source provenance, scope mapping, and DLP result.
2. Execute through typed HMG CLI or MCP writes.
3. Keep imported atoms tagged with source/provenance.
4. Run scoped recall smoke after import.
5. Record a handoff with migration scope, validation, risks, and rollback notes.

Secrets and raw credentials remain rejected by default.

