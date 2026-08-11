---
sidebar_position: 2
---

# MCP Reference

HMG exposes memory tools to agents via MCP (Model Context Protocol). Tool names in the host look like `mcp__hmg__memory_memorize` (`mcp__<server>__<tool>`).

## Overview

| Tool | Purpose | Required fields |
|---|---|---|
| `memory_memorize` | Write one memory | `content` |
| `memory_recall` | Search memories | `query` |
| `memory_correct` | Correct one memory | `target_atom`, `action`, `reason` |
| `memory_govern` | Govern the lifecycle of one memory | `target_atom`, `action`, `reason` |
| `memory_handoff` | Session handoff summary | `summary` |
| `memory_stats` | Store overview | (none) |

Capabilities not exposed as MCP tools: `agent_brief` (internal to the SessionStart hook), `observation_*` (not activated in agent integration), `history` / `export` (SDK layer only, see [SDK Reference](sdk-reference.md)).

## General conventions

- **The agent never passes scope.** For every tool, scope is mechanically inferred from the session directory and injected by the PreToolUse hook (or inferred by the MCP server from its process working directory); scope passed by the agent is overridden.
- **Certainty and polarity are inferred automatically.** `epistemic` (fact/constraint/guess) and `polarity` (positive/negative/conditional) are inferred from wording — not input parameters.
- **Automatic redaction on write.** Structured sensitive information (connection strings, `password=xxx`, Bearer tokens, private key blocks) is auto-redacted at memorize time; sensitive content in natural language is not auto-detected — avoid writing it.
- **Exact dedup.** Writing identical content never creates a second atom (`effect: "no_op"`).

## ScopeInput (shared)

All tools share the same optional `scope` field structure (the agent never passes it):

```json
{
  "tenant_id": "qiankun",
  "workspace": "HMG-AI",
  "repository": "HMG-DEV-brach",
  "branch": "main"
}
```

| Field | Description |
|---|---|
| `tenant_id` | Tenant, the OS username, read by HMG from the store config |
| `workspace` | Workspace, usually the git remote owner |
| `repository` | Repository name |
| `branch` | Branch |

---

## memory_memorize

Write one long-term memory.

**Input**

| Field | Type | Required | Description |
|---|---|---|---|
| `content` | string | yes | Memory content, one self-contained sentence |
| `source` | string | no | Source attribution: `user` (said by the user, more authoritative) / `agent` (concluded by the agent) / custom |
| `scope` | ScopeInput | no | Injected by hooks automatically — the agent doesn't pass it |

**Output**

| Field | Description |
|---|---|
| `atom_id` | ULID of the atom (dedup hits return the existing atom's ID) |
| `effect` | `applied` (created) / `no_op` (dedup hit) / `rejected` (admission blocked) |
| `reason` | Reason for dedup/rejection (not returned when `applied`) |
| `deduped_with` | Existing atom ID on dedup hit (`no_op` only) |

**Example**

```json
{
  "content": "This project uses PostgreSQL 16 as the primary database, not MongoDB, because we need transactions and complex queries",
  "source": "user"
}
```

**Notes**

- No need to recall for duplicates first — HMG deduplicates exactly, automatically
- If a semantically close memory is already visible in the current context, update it with `memory_correct` (`replace`) instead of adding a new one
- Memories are stored in the language of the current conversation

---

## memory_recall

Search memories in natural language.

**Input**

| Field | Type | Required | Description |
|---|---|---|---|
| `query` | string | yes | Search query; noun phrases work best |
| `max_results` | number | no | Maximum results, default 10 |
| `include_negated` | boolean | no | Include negated memories, default false |
| `scope` | ScopeInput | no | Injected by hooks automatically — the agent doesn't pass it |

**Output**

| Field | Description |
|---|---|
| `atoms` | Results sorted by relevance, descending |
| `atoms[].atom_id` | Atom unique identifier for correct / govern |
| `atoms[].content` | Memory content (quarantined/sealed return a placeholder) |
| `atoms[].score` | Relevance score, 0.0 ~ 1.0 |
| `atoms[].created_at` | Creation time (RFC 3339) |
| `atoms[].source` | Source attribution |

**Example**

```json
{ "query": "PostgreSQL connection pool configuration" }
```

**Notes**

- Use noun phrases with key names (people, projects, technologies, files); avoid conversational questions
- One recall is usually enough — HMG already retrieves from semantic, keyword, and graph angles internally

---

## memory_correct

Correct one memory. Append-only: old content stays in the audit chain, history is never lost.

**Input**

| Field | Type | Required | Description |
|---|---|---|---|
| `target_atom` | string | yes | Atom ID to correct (from recall results) |
| `action` | string | yes | See action table below |
| `reason` | string | yes | Correction reason, written to the audit chain |
| `new_content` | string | required for replace | New content |
| `scope` | ScopeInput | no | Inherits from the target atom by default — don't pass it |

**action values**

| Action | Meaning | Typical scenario |
|---|---|---|
| `negate` | Mark false and disable | "This memory is outdated/wrong" |
| `confirm_actual` | Confirm as fact | "Was uncertain, now confirmed" |
| `confirm_necessary` | Confirm as hard constraint | "Not just a fact — a rule that must be followed" |
| `demote` | Demote to possible | "Thought it was settled; it isn't" |
| `replace` | Replace with new content (new atom created, old kept in the evolution chain) | "Content needs updating" |

**Output**

| Field | Description |
|---|---|
| `effect` | `applied` / `rejected` |
| `target_atom` | The corrected atom ID |
| `new_atom_id` | New atom ID (`replace` only) |
| `reason` | Rejection reason (`rejected` only) |

**Example**

```json
{
  "target_atom": "01J9ZK8V3QX7N2M4R6T8W0YB1C",
  "action": "replace",
  "reason": "migrated to PostgreSQL in v3, old decision outdated",
  "new_content": "The primary database is PostgreSQL 16, replacing the old MongoDB plan"
}
```

**Notes**

- `negate` is not precisely reversible (no un-negate); recover from a wrong negate with `replace`
- Wrong replace? Replace again on that same atom — guarantees exactly one active memory at any time

---

## memory_govern

Govern the lifecycle of one memory (isolate, seal, retire, distill a lesson).

**Input**

| Field | Type | Required | Description |
|---|---|---|---|
| `target_atom` | string | yes | Atom ID to govern |
| `action` | string | yes | `quarantine` / `seal` / `tombstone` / `derive_lesson` |
| `reason` | string | yes | Governance reason, written to the audit chain |
| `lesson_content` | string | required for derive_lesson | Redacted lesson distilled from the original |
| `scope` | ScopeInput | no | Inherits from the target atom by default — don't pass it |

**action values**

| Action | Meaning |
|---|---|
| `quarantine` | Quarantine: hidden from recall, content kept, recoverable |
| `seal` | Seal: audit-only |
| `tombstone` | Tombstone: logical deletion, content destroyed by default |
| `derive_lesson` | Distill a redacted lesson (new atom), retire the original |

**Output**

| Field | Description |
|---|---|
| `effect` | `applied` / `rejected` |
| `target_atom` | The governed atom ID |
| `lesson_atom_id` | Lesson atom ID (`derive_lesson` only) |
| `reason` | Rejection reason (`rejected` only) |

**Example**

```json
{
  "target_atom": "01J9ZK8V3QX7N2M4R6T8W0YB1C",
  "action": "derive_lesson",
  "reason": "original contains a leaked API key",
  "lesson_content": "Never hardcode API keys in code or memory; use environment variables"
}
```

**Notes**

- Sensitive info written by mistake: `derive_lesson` when a lesson is worth keeping, otherwise `seal` or `tombstone`
- `tombstone` destroys content by default — no extra flag needed

---

## memory_handoff

Write a session handoff summary. A handoff is a special memory: the startup brief of the next session recalls it **with priority**.

**Input**

| Field | Type | Required | Description |
|---|---|---|---|
| `summary` | string | yes | Handoff summary; recommended coverage: what changed / why / validation / risks / next steps (format free) |
| `source` | string | no | Source attribution |
| `scope` | ScopeInput | no | Injected by hooks automatically — the agent doesn't pass it |

**Output**

| Field | Description |
|---|---|
| `atom_id` | ULID of the handoff atom |
| `effect` | `applied` / `rejected` |
| `reason` | Rejection reason (`rejected` only) |

**Example**

```json
{
  "summary": "Fixed the null pointer in login.py. Root cause: get_session() returns None when the session expires; added a validity check at line 38, pytest passes. Risk: possible race on session refresh under concurrency. Next: add integration tests for the session module.",
  "source": "agent"
}
```

**Notes**

- When to call: task end, milestone reached, session about to end
- Division of labor with memorize: memorize stores single incremental facts; handoff stores the whole-task handoff

---

## memory_stats

Store overview. Mostly used internally by the SessionStart hook (empty store → onboarding flow); agents rarely need it in normal workflows.

**Input**: none.

**Output**

| Field | Description |
|---|---|
| `atoms` | Total memory atoms |
| `edges` | Total graph edges |
| `indexes` | Coverage per index (semantic / keyword / temporal / categorical) |
| `snapshot_version` | Current snapshot version, increments on every write |

---

Previous: [CLI Reference](cli-reference.md) · Next: [SDK Reference](sdk-reference.md)
