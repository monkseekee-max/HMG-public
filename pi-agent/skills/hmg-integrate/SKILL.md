---
name: hmg-integrate
description: Create a non-invasive HMG integration plan for a target repository using MCP, hooks, runtime, and smoke tests behind a feature flag.
---

# HMG Integrate

Use this workflow to plan HMG adoption in a third-party agent repository.

## Workflow

1. Scan language, framework, agent host, config paths, CI, and secrets patterns
   read-only.
2. Generate an integration plan.
3. Put behavior behind a feature flag or explicit init command.
4. Preview writes with `hmg init --agent <id> --dry-run`.
5. Add the smallest smoke test that proves MCP tools, hooks, scope identity, and
   recall without changing business logic.

## Safety

- Do not write secrets to the repo.
- Feature flag off must preserve existing behavior.
- Do not overwrite user config without a reviewed diff.

