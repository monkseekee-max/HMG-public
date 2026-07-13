---
name: hmg-import
description: Plan safe dry-run imports from mem0, MEMORY.md, Claude memory banks, or project documents into HMG.
---

# HMG Import

Use this workflow to prepare external memory import.

## Workflow

1. Parse source data in dry-run mode.
2. Run DLP and secret detection.
3. Produce a scope mapping plan.
4. Preserve source and provenance.
5. Reject raw tokens and sensitive content by default.

No durable writes happen in this skill. Execution belongs to typed HMG import or
memorize paths after the user reviews the plan.

