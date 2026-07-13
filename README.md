<p align="center">
  <img src="docs/img/logovideo.gif" alt="HMG Logo" width="360" style="border-radius:12px;" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.7.6-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/license-Apache--2.0%20%7C%20Community-green.svg" alt="License">
  <img src="https://img.shields.io/badge/rust-1.85%2B-orange.svg" alt="Rust">
  <img src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/tools-48_MCP-purple.svg" alt="MCP Tools">
  <img src="https://img.shields.io/badge/adapters-19_agents-teal.svg" alt="Adapters">
</p>

<h1 align="center">HMG — Agent Memory That Actually Works</h1>

<p align="center">
  <strong>Holographic Memory Graph</strong> — branch-aware, auditable, governable long-term memory for AI coding agents.<br>
  Every session forgets. HMG makes sure the next one remembers.
</p>

<p align="center">
  <a href="https://hmg-ai.github.io/HMG-public/">🌐 Docs</a> ·
  <a href="https://github.com/HMG-AI/HMG-public/releases">📦 Releases</a> ·
  <a href="https://hmg1ai.com/">🏠 Website</a> ·
  <a href="#quick-start">🚀 Quick Start</a> ·
  <a href="#whats-new-in-v16">✨ What's New</a>
</p>

---

## The Problem

Your AI coding agent is brilliant — and amnesiac.

Every new session starts with a blank slate. It re-reads the same files, re-asks the same questions, **re-litigates decisions you already settled**. "Why are we using Postgres?" gets answered six times across six sessions. A bug fix from last week? Forgotten. The API key it shouldn't commit? Committed again.

The cost isn't just keystrokes — it's **trust**. You can't delegate to an agent that keeps losing the thread.

## Why HMG?

HMG gives an agent the one thing it's missing: **a durable, queryable, governable memory**.

| Without HMG | With HMG |
|---|---|
| Re-reads the whole repo to relearn context | Wakes up with a one-shot brief: status, decisions, risks, next steps |
| Re-argues settled architecture questions | Knows *why* a choice was made — and what was rejected |
| Silently overwrites the old answer when it's wrong | Keeps full correction history; the new answer is canonical, the old is never lost |
| Commits secrets and sensitive context | Governance quarantines, seals, or derives safe lessons |
| Forgets your branch the moment you switch | Memories are branch-scoped: `tenant → workspace → repository → branch` |

One tool call returns complete context. No prompt-stuffing. No context window limits. No forgetting.

## Quick Start

<a id="quick-start"></a>

```bash
# Install (Linux / macOS)
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh

# Initialize + start the daemon
hmg init -g
hmg daemon start
```

```powershell
# Install (Windows PowerShell)
irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex

# Initialize + start the daemon
hmg init -g
hmg daemon start
```

Store your first memory and pull it back — same works for any HTTP client:

```bash
# Store a decision
curl -s -X POST http://127.0.0.1:7654/api/memorize \
  -H 'Content-Type: application/json' \
  -d '{"content": "Decision: use Rust for performance-critical paths"}'

# Recall it later
curl -s http://127.0.0.1:7654/api/recall \
  -d '{"query": "what language for perf?"}'

# Verify your setup is healthy
hmg doctor
```

> **Community Edition is free** — 100,000 memory atoms, all core features, no license key. No account, no telemetry, no cloud. Data stays local.

## The Agent Memory Loop

```
capture → canonicalize → recall → correct → govern → consolidate → brief next session
```

Every session becomes context for the next. Decisions persist. Corrections leave a traceable history. Governance controls what gets remembered — and what gets forgotten.

```python
# Store a decision with rationale
memory_memorize(content="Use Rust for performance-critical paths", source="ADR-001")

# Next session: the agent wakes up with full context
memory_agent_brief(domain_pack_id="software-engineering")
# → scope, current status, prior decisions, unresolved risks, next steps

# Correct stale knowledge — the old version is kept in history
memory_correct(target_atom="01ABC...", action="replace", new_content="Use Rust + WASM")

# Govern sensitive data so it never leaks into recall
memory_govern(target_atom="01DEF...", action="seal", reason="contains API key")
```

## Core Capabilities

Not a vector database. Not a key-value store. HMG models memory as a **typed graph** — every atom carries polarity, epistemic state, governance tags, and a correction lineage.

- **🧲 One-Shot Recall** — A single MCP call returns complete context: current status, prior decisions, unresolved risks, and next steps. No re-reading, no re-asking.
- **🌿 Branch-Aware Scope** — `tenant → workspace → repository → branch`. Memories stay isolated per branch and become traceable on merge — your `feature/auth` work doesn't bleed into `feature/payments`.
- **🛡️ Governance Control Plane** — Quarantine, seal, tombstone, or derive lessons. Policy tags and audit context flow through every operation. Normal recall skips governed content; audit recall still sees it.
- **🏠 Local-First** — Embedded storage, zero external dependencies. Your memory lives on your machine, works offline, and never phones home.
- **🔌 49 MCP Tools** — Memorize, recall, correct, govern, history, handoff, agent-brief, MemoryQL, observation capture, vault, panorama, and graph-health workflows — all over a single standard interface.
- **📜 Open Protocol** — [`hmg-protocol`](protocol/) (Apache-2.0) is a standalone crate defining types and serialization for every memory operation. Implement it, verify against it, build on it.

## What's New in v1.6

<a id="whats-new-in-v16"></a>

- **🤝 Cross-Client Reliability** — Spec-correct MCP `ping` + capability probes, and a transparent daemon-proxy fallback when a direct server hits a store-lock collision. Works smoothly with strict clients like opencode and the Hermes gateway.
- **🧬 Agent-Native Extraction** — A dedicated `DomainLens` registry lets recall and anchoring lenses evolve independently of the coarser extraction profile. Caller-supplied entities and relations thread straight through the memorize pipeline.
- **🎯 Answer vs Context** — Recall now flags the top-ranked answer cluster as `primary`, distinct from same-scope supporting context — so agents surface the answer first instead of drowning in context.
- **🔐 Two-Tier Source License** — HMG is proprietary commercial software. The 19 core/product crates ship under the HMG Proprietary Source License; the 3 ecosystem-edge crates (`hmg-domain-packs`, `hmg-sdk`, `hmg-evals`) stay Apache-2.0.

See [CHANGELOG.md](CHANGELOG.md) and [Releases](https://github.com/HMG-AI/HMG-public/releases) for the full history.

## Editions

<!-- MANIFEST:START -->
| | Community (Free) | Developer ($9/mo) | Enterprise |
|---|---|---|---|
| Memory atoms | 100,000 | Unlimited | Unlimited |
| Semantic search | ✓ | ✓ | ✓ |
| One-Shot Recall | ✓ | ✓ | ✓ |
| Correction + Governance | ✓ | ✓ | ✓ |
| Observation capture | ✓ | ✓ | ✓ |
| Domain pack | software-engineering | software-engineering | All |
| Consolidation | — | ✓ (auto) | ✓ (full) |
| Intelligent lifecycle | — | ✓ | ✓ |
| SSO / RBAC | — | — | ✓ |
<!-- MANIFEST:END -->

One binary, runtime edition detection. No reinstall, no migration. Start free on Community and upgrade anytime with `hmg license apply <key>`.

## Agent Adapters

HMG works with the agent you already use. Wire any of the **19 supported adapters** — each is doctor-verifiable:

| Agent | Init command |
|-------|--------------|
| pi | `hmg init --agent pi` |
| Codex CLI | `hmg init --agent codex` |
| Cursor | `hmg init --agent cursor` |
| Claude Code | `hmg init --agent claude` |
| VS Code | `hmg init --agent vscode` |
| opencode | `hmg init --agent opencode` |
| Continue | `hmg init --agent continue` |
| Cline | `hmg init --agent cline` |
| Roo Code | `hmg init --agent roo-code` |
| Windsurf | `hmg init --agent windsurf` |
| Zed | `hmg init --agent zed` |
| Aider | `hmg init --agent aider` |
| OpenHands | `hmg init --agent openhands` |
| Goose | `hmg init --agent goose` |
| Gemini CLI | `hmg init --agent gemini-cli` |
| Qwen Code | `hmg init --agent qwen-code` |
| OpenClaw | `hmg init --agent openclaw` |
| Hermes | `hmg init --agent hermes` |
| Any MCP client | `hmg init --agent generic-mcp` |

Run `hmg doctor` to verify every adapter's lifecycle wiring, store path, and MCP readiness, or `hmg integrations detect` to see which agents are installed in your environment.

## SDKs

```bash
# Python
pip install hmg-sdk
```
```python
import hmg
client = hmg.HmgClient()
client.memorize("key decision: use Rust for perf")
```

```bash
# TypeScript
npm install @hmg_ai/sdk-ts
```
```typescript
import { HmgClient } from "@hmg_ai/sdk-ts";
const client = new HmgClient();
await client.memorize({ content: "decision noted" });
```

## What's in This Repository

This repository holds the **public artifacts** for HMG — everything you need to install, integrate, verify, and implement compatible protocols. The memory intelligence engine itself is proprietary.

| Path | What it is |
|------|-----------|
| [`protocol/`](protocol/) | `hmg-protocol` (Apache-2.0) — standalone crate defining all memory types & serialization |
| [`mcp/schemas/`](mcp/schemas/) | MCP tool definitions for all 49 public tools |
| [`openapi/`](openapi/) | HTTP API specification |
| [`sdk-python/`](sdk-python/) · [`sdk-ts/`](sdk-ts/) | Official Python and TypeScript SDKs |
| [`certification/`](certification/) | Conformance tests for compatible implementations |
| [`docs/`](docs/) | Multilingual documentation (10 languages) + live site |
| [`scripts/`](scripts/) | Installers — `install.sh`, `install.ps1` |

## Documentation

| | |
|---|---|
| [Getting Started](docs/md/getting-started.md) | Install → first memory in 5 minutes |
| [Concepts](docs/md/concepts.md) | Memory atoms, correction, governance, scope |
| [API Reference](docs/md/api-reference.md) | MCP tools and HTTP endpoints |
| [Architecture](docs/md/architecture.md) | System overview |
| [FAQ](docs/md/faq.md) | Common questions |
| [Upgrade Guide](docs/md/upgrade.md) | Version-to-version migration notes |

## Links

- **Website**: [hmg1ai.com](https://hmg1ai.com/)
- **Docs**: [hmg-ai.github.io/HMG-public](https://hmg-ai.github.io/HMG-public/)
- **Releases**: [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases)
- **Issues**: [GitHub Issues](https://github.com/HMG-AI/HMG-public/issues)
- **Security**: [GitHub Security](https://github.com/HMG-AI/HMG-public/security)
- **Contributing**: [CONTRIBUTING.md](CONTRIBUTING.md)

## License

HMG uses a **two-tier** license model:

- **Protocol & SDK artifacts** (this repo): [Apache-2.0](LICENSE) — open, implementable, verifiable
- **Community Edition binary**: [LICENSE-COMMUNITY](LICENSE-COMMUNITY) — free to use, no redistribution
- **Memory intelligence engine**: proprietary (HMG Proprietary Source License)

Copyright © HMG AI, Inc.
