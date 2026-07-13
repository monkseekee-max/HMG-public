---
name: hmg-context-loader
description: Manually load scoped HMG context when SessionStart or prompt-time hooks are unavailable.
---

# HMG Context Loader

Use this fallback only when mechanical hooks are unavailable or a human asks for
manual context loading.

## Workflow

1. Determine tenant, workspace, repository, and git branch.
2. Call `memory_agent_brief` with a compact or summary response profile.
3. Keep a fixed token budget.
4. Include scope, source, confidence, and trace when available.
5. Exit quietly when no relevant memory is found.

## Boundaries

- Do not replace SessionStart or UserPromptSubmit hooks when they are installed.
- Do not inject raw observations into normal prompts.
- Do not bypass scope or governance filters.

