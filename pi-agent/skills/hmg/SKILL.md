---
name: hmg
description: Use HMG durable coding-agent memory when a task benefits from branch-aware recall, prior decisions, correction history, governance, or an end-of-task handoff.
---

# HMG

HMG is the durable coding-agent memory kernel plus governance control plane.
This skill only tells the agent when and how to use HMG. It does not implement
memory behavior; core state changes must go through typed MCP tools, CLI
commands, hooks, and the runtime.

## Use When

- Starting a non-trivial coding task or switching context.
- Before risky edits, releases, migrations, refactors, or architecture choices.
- When prior decisions, root causes, rejected approaches, validation outcomes,
  customer/support learnings, or governance notes may affect the task.
- When the user explicitly asks to remember, correct, forget, quarantine, or
  govern memory.
- At the end of a substantial task, milestone, investigation, benchmark, or
  operational run.

## Skip When

- The request is a simple translation, formatting edit, current time lookup, or
  one-line command with no durable value.
- The only available content is a secret, raw token, credential, or noisy
  transient command output.
- Mechanical hooks already captured a lifecycle event and no durable outcome has
  emerged.

## Owner Layers

- Runtime owns scope enforcement, ranking, persistence, DLP, audit, correction,
  governance, and daemon fast paths.
- MCP owns typed memory operations such as `memory_agent_brief`,
  `memory_recall`, `memory_handoff`, `memory_correct`, and `memory_govern`.
- Hooks own session lifecycle, command/test/git summaries, prompt-time context
  injection, and fail-open automation.
- CLI owns local diagnostics, JSON output, doctor, daemon control, install/init,
  and reproducible eval commands.
- Skills own agent workflow guidance, diagnostics orchestration, onboarding,
  integration planning, migration planning, and scorecard interpretation.

## Scope Rule

Prefer the current task and git context. Use four distinct scope layers:

- `tenant_id`
- `workspace`
- `repository`
- `branch`

Do not reuse a tenant or workspace name as the branch. If the current git branch
cannot be determined, omit the branch and let HMG infer it.

## Default Workflow

1. At task start, call `memory_agent_brief` with branch-aware scope.
2. Before risky decisions or edits, call `memory_recall` for the affected files,
   symbols, products, workflows, or customer context.
3. Route lifecycle and low-value command/test/git summaries through
   `observation_capture`.
4. For durable outcomes, call `memory_handoff` or `memory_memorize`.
5. For wrong or stale memory, call `memory_correct`; for sensitive or audit-only
   content, call `memory_govern`.

## Fallbacks

- If MCP is available, use MCP first.
- If MCP is unavailable, use CLI JSON commands such as `hmg recall --format json`
  and `hmg agent-brief --format json`.
- If CLI is unavailable, tell the user the shortest recovery command:
  `hmg doctor --format json` followed by `hmg init --agent <id> --dry-run`.

## Public Contract

Use `docs/llms.txt` for the current agent-facing tool, CLI, and skill index.
Do not maintain a second exhaustive tool list inside this skill.
