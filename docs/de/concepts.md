# Core Concepts

This chapter explains what you need to know to use HMG: memory, atoms (with scope), edges, recall, correction and governance, handoff and brief.

## Memory {#memory}

HMG memory is **not a full chat log** — it is "information you will need later": decisions with reasons, stable preferences, project conventions, root causes, verification results, known risks, next steps.

There is one litmus test: **Will this information be reused? Will it affect future decisions?** Yes → worth remembering. Just a by-product of the moment (transient output, logs, one-off instructions) → don't store it.

For the full do/don't table and writing guidance see [Best Practices](best-practices.md).

## Atoms

An atom is HMG's smallest unit of memory. Every memory written via `memorize` becomes one atom.

- Each atom has a **unique ID**: returned on write; `correct`, `govern`, and `history` all use it for precise targeting
- The content is one **self-contained sentence** — a decision, a root cause, a verification result
- Metadata is attached automatically: creation time, source (`source`), scope (`scope`)

```bash
# The write returns an atom id — keep it
hmg memorize "Always run database migrations before deploying, otherwise startup fails on schema mismatch" --source deploy-rule

# Inspect the full evolution of one atom
hmg history <atom-id>
```

### Scope {#scope}

Scope marks **which context a memory belongs to and where it participates in recall**. Four levels:

```
tenant (who you are)
  └─ workspace (which organization)
       └─ repository (which repo)
            └─ branch (which branch)
```

- **tenant**: your OS username — a machine-level identity shared across all projects
- **workspace / repository**: usually the owner and repo name of the git remote
- **branch**: isolates experiment conclusions from stable decisions

Scope determines recall behavior. Say you decided "cache with SQLite" on `main` and are experimenting on `feature/redis-experiment`:

- In a session on main, recall returns the SQLite decision
- Experiment conclusions on the feature branch never pollute main

#### How scope is determined

**You don't manage scope manually.** HMG infers it in real time from the current working directory: tenant is your OS username; workspace / repository / branch come from the git remote and current branch; without git it falls back to directory names.

- **Agent integration**: scope is mechanically inferred from the session directory and injected — the agent never passes it and cannot get it wrong
- **CLI**: inferred from the current directory by default; use `--scope tenant/workspace/repository/branch` to override

#### Shared scope for ephemeral sessions

Sessions not attached to any project (e.g. Codex desktop Chats) all share one fixed scope:

```
<os-username> / personal / chats / main
```

Different ephemeral sessions share memories with each other; but ephemeral sessions are isolated from project sessions — a user preference stored in an ephemeral session will not automatically appear in a project session. If needed, memorize it again inside the project session.

## Edges

Edges connect atoms: a correction points at the memory it corrects, a handoff links to the decisions and risks of that task, a root cause links to a module or file.

You never maintain edges — their direct effect is: **recall returns not just one sentence but related context along the relations** — investigating a bug also brings back the decisions, verification, and follow-up risks from that time.

## Recall

Recall is searching past memories in natural language. HMG retrieves from multiple angles at once: semantics, keywords, graph relations.

**Write queries as noun phrases with key names** (people, projects, technologies, files) and drop conversational noise:

| ❌ Conversational | ✅ Noun phrase |
|---|---|
| what database did we decide on again | database selection decision |
| how did we handle that login error last time | login 500 root cause |

One recall is usually enough — no need to retry with rephrasings.

```bash
hmg recall "root cause of login endpoint 500"

# Not sure how to ask? Let HMG suggest a query
hmg suggest-query "intermittent login 500"
```

In agent integration the corresponding MCP tool is `memory_recall` — pass only the query (scope is handled automatically).

## Correction and Governance {#correct}

Information goes stale. When old information is wrong or superseded, **correct it instead of appending** — appending leaves old and new side by side, and recall may return the outdated one.

### correct: change content

| Action | Meaning |
|------|------|
| `replace` | Replace the old memory with new content |
| `confirm-actual` | Confirm this memory is an actual fact |
| `confirm-necessary` | Confirm this memory is a hard constraint |
| `demote-possible` | Demote a memory that may no longer be needed |
| `negate` (MCP/SDK) | Mark a memory false and disable it |

```bash
hmg correct <atom-id> --action replace \
  --reason "auth switched from session cookie to JWT" \
  --new-content "Auth uses JWT, not session cookies, because we need stateless cross-service validation"
```

Two caveats:

- `negate` is not precisely reversible (there is no "un-negate"); if you negated by mistake, `replace` the correct content back
- If a `replace` was wrong, `replace` again on that same atom — this guarantees exactly one active memory at any time

### govern: manage lifecycle

| Action | Meaning |
|------|------|
| `quarantine` | Quarantine: hidden from recall, content kept |
| `seal` | Seal: audit-only |
| `tombstone` | Tombstone: logical deletion |
| `derive-lesson` | Distill a redacted lesson from the content; retire the original |

All corrections and governance keep an audit trail — `hmg history <atom-id>` shows the full evolution. For the full sensitive-information workflow see [Removing or isolating sensitive information](daily-usage.md#sensitive-memory-governance).

## Handoff and Brief

A **handoff** is a document written for the next session at the end of a task, covering five elements: what changed / why / validation / risks / next steps. The brief at the start of the next session recalls it first.

```bash
hmg handoff "Fixed login 500: token expiry check switched to UTC. Validation: 200 concurrent logins, no 500. Risk: old clients cache expiry. Next: check the refresh token flow." --source bugfix-login-500
```

The **brief** (agent-brief) is a context summary at task start: last handoff, key decisions, known issues, open items. In agent integration it is injected automatically at session start; manually:

```bash
hmg agent-brief --query "fix intermittent 500 on the login endpoint"
```

## Observation layer (optional)

Observations are transient records: command output, logs, and test results land in the observation layer first, and only after filtering are promoted to durable memory — this prevents raw output from flooding memory with noise.

> The observation layer is **not enabled** in agent integration — durable memories are written only via the agent's own memorize / handoff calls. Observations are for CLI and automation pipelines.

```bash
hmg obs review-queue        # review observations pending promotion
hmg obs promote             # promote to durable memory
hmg obs forget --query "some transient record"
```

Next: [Daily Usage Guide](daily-usage.md)
