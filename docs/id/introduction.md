---
sidebar_position: 1
---

# Introduction

## What is HMG?

HMG (Holographic Memory Graph) is a **long-term memory system for AI agents**. It lets coding assistants such as Codex, Cursor, and Claude Code remember across session boundaries:

- Project experience and architecture decisions
- User preferences and project conventions
- Root causes you have tracked down, with verification results
- Known risks and follow-up items

Traditional coding assistants start from scratch every session, forcing you to re-explain the project background and "why we wrote it this way" over and over. HMG distills "information you will need in the future" into structured memory and recalls it on demand in the right context (project, repository, branch), so you can:

- Cut down repeated explanations
- Keep decisions consistent
- Get new sessions up to speed quickly
- Reduce information loss when collaborating

HMG runs entirely on your machine: memory data, indexes, and the embedding model all stay local and never pass through any third-party service.

## What is HMG good for?

HMG keeps memory data on your machine. It fits individual developers or small local teams. Common scenarios:

| Scenario | Description |
|------|------|
| Personal development memory | Your project conventions, pitfalls you hit, why you chose a solution |
| Project conventions | Code style, test commands, deployment constraints, directory rules |
| Architecture decisions | Why A instead of B, alternatives, risks, verification results |
| Troubleshooting experience | The root cause, what you tried, how it was finally fixed |
| User preferences | Your stable coding preferences (e.g. "always indent with spaces", "use vitest for tests") |
| Task handoff | Multi-day tasks continue across sessions; on resume you know where you left off and what is next |
| Multi-branch context | Experiment conclusions on feature branches never pollute stable decisions on main |

> Note: HMG memory is not a dump of chat history — it is "information worth reusing". Transient output, full logs, and one-off instructions should never become long-term memory. See [Memory](concepts.md#memory).

## Quick integration and long-term memory

After installation, two steps:

```bash
hmg setup
hmg init --agent codex
```

Replace `codex` with `cursor` or `claude` as needed. Once integrated:

- **At session start**, the agent automatically receives a memory brief (last handoff, key decisions, risks, next steps)
- **On every turn**, your message is used to prefetch relevant memories
- **Scope isolation is automatic**: project / repository / branch are inferred mechanically from the session directory — the agent never passes them and cannot get them wrong
- **Writing is fully autonomous**: the agent stores memories with `memorize` as decisions happen, and writes a `handoff` when the task ends

From then on the agent has long-term memory: the longer you work on a project, the better it understands your codebase, conventions, and preferences.

To unlock the developer edition and higher memory capacity, upgrade your plan on the website first, then run `hmg login` locally (optional, requires network). For host differences, hooks, MCP configuration, and manual setup, see [Integration](integration.md).

Next: [Core Concepts](concepts.md)
