---
name: hmg-onboard
description: Check and plan HMG MCP, hooks, scope identity, daemon, and doctor setup for an agent host without overwriting user configuration.
---

# HMG Onboard

Use this workflow to onboard or repair HMG for Codex, Claude Code, Cursor,
Pi Agent, OpenCode, or another supported agent host.

## Workflow

1. Identify the host and target repository.
2. Run or recommend `hmg integrations explain --agent <id> --format json`.
3. Run or recommend `hmg doctor --agent <id> --format json`.
4. Validate lifecycle mapping with
   `hmg agent-event explain --file event.json --format json`.
5. Check daemon readiness with `hmg daemon status --format json`.
6. Produce pass/warn/fail, evidence paths, and exact next commands.

## Safety

- Default to dry-run previews.
- Do not overwrite user config directly.
- Use `hmg init --agent <id> --dry-run` before any write.
- Do not store secrets in repository config.

