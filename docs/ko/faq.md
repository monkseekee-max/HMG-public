# FAQ

### Where is HMG's data stored?

In the **store directory** on your machine, by default `<user data dir>/hmg/stores/default` — on macOS / Linux usually `~/.local/share/hmg/stores/default`. Use `--store <path>` to override, or `hmg doctor --verbose` to see the actual path. Data stays local by default.

The store contains:

- long-term memories
- indexes
- observations
- local runtime state

Default location and layout: see [Configuration](settings.md#store-directory).

### How should I think about local data and privacy?

HMG is local-first by default:

- memories, indexes, and observations all live in the local store
- you decide where the store directory goes
- you can back up, migrate, isolate, or delete the store directly
- when several agents share one store, data boundaries come from scope, governance state, and local directories together

Two rules:

1. Don't put secrets, tokens, passwords, or sensitive customer data into regular memories.
2. For credentials that must persist, use `hmg secret store` — never plaintext in regular memories.

### Do I need to log in? How do plans work?

No forced login — basic memory features work without it. To unlock developer-edition features and higher memory capacity:

- **Upgrade your plan** in the user center on the website, then run `hmg login` locally
- Login requires network: HMG verifies the account with the remote service, identifies the plan, receives a signature, and unlocks after local verification
- Login performs **no migration and modifies no local memory data**: local reads/writes always use the OS username as tenant; the account is only for identity mapping in cloud sync
- Logging out or switching accounts only clears the linked-account field in the store config; local memories are untouched

### How is HMG different from chat history?

Chat history is a **complete running log** of conversations, piled up chronologically — hard to search. HMG memory is **information you'll use in the future**: decisions, root causes, constraints, preferences, verification results — structured, searchable, correctable, scoped. HMG is not "remembering what you said" but "remembering what stays useful".

### How is HMG different from a vector database?

A vector database only does **semantic similarity search**. On top of that HMG provides:

- **Scope** (tenant/workspace/repository/branch) — context isolation
- **Multi-route retrieval** (semantics + keywords + graph relations, etc.)
- **Correction and governance** (information goes stale: correct, demote, quarantine, tombstone — with audit kept)
- **Structured queries** (decision tracing, risk lists, impact analysis, knowledge graph exploration)

In short: a vector DB is "store + search"; HMG is "memory that expires, gets corrected, and carries context".

### Do I need to write memories manually?

Mostly no. With an agent integrated, memory writing is fully autonomous: the agent calls `memorize` incrementally as decisions and exchanges happen, writes a `handoff` at task end, and corrects stale information with `correct`. Manual writing fits what you want to deliberately deposit: project conventions, stable preferences, long-term constraints.

### Does the agent need to pass scope when calling HMG?

No — and it shouldn't. In agent integration, scope is mechanically inferred from the session directory and injected by hooks (all four levels: tenant / workspace / repository / branch); wrong values passed by the agent are silently corrected. Only manual CLI use may involve `--scope`. See [Scope](concepts.md#scope).

### Why can't project sessions see memories from ephemeral sessions?

That's scope isolation by design. Ephemeral sessions not attached to a project (e.g. Codex desktop Chats) all share the `personal/chats/main` scope, isolated from project scopes. If a user preference stored in an ephemeral session is also needed in a project, memorize it again inside the project session.

### Won't memories grow endless and messy?

HMG has multiple layers of denoising:

- **Write-source control**: in agent integration, durable memories only enter through the two active channels memorize / handoff — no mechanical capture of raw conversations or command output
- **Correction / demotion / governance**: stale info can be corrected or demoted; sensitive info governed
- **Exact dedup**: identical content is never stored twice
- **store hygiene**: `hmg store hygiene` cleans orphan edges/indexes
- **Scope isolation**: projects/branches never pollute each other

Combined with the writing guidance in [Best Practices](best-practices.md), memories stay concise.

### What workflows is HMG suited for?

Any workflow where the agent should keep remembering context. Typical:

- long-term collaboration on solo projects
- multi-session, multi-day tasks with continuous handoff
- experience accumulation across repos and branches
- several agents on one machine sharing long-term memory

### Can I migrate to another computer?

Yes. Two ways:

```bash
# 1. Copy the store directory to the new machine
# 2. Official migration command
hmg store migrate --from /old/store --to /new/store --backup --apply
```

The simplest backup is copying the whole store directory.

Or export first with `hmg export --format json` and import on the new machine. See [Backing up or migrating local data](troubleshooting.md#backup-or-migrate-local-data).

### How should sensitive information be handled?

- **Don't** write API keys, tokens, or passwords into regular memories.
- Credentials that must persist: use the **secret vault** — `hmg secret store <name> <value>`.
- Reveal on demand: `hmg secret reveal <name>`.
- At write time HMG auto-redacts structured sensitive info (connection strings, `password=xxx`, Bearer tokens, private key blocks); natural-language sensitive content is not auto-detected.
- Sensitive info written by mistake? Govern immediately: `hmg govern <atom-id> --action tombstone --destroy-payload --reason "sensitive info written by mistake"`.

Governance options: see [Removing or isolating sensitive information](daily-usage.md#sensitive-memory-governance).

### Can I delete memories?

Yes, but HMG recommends **governance over physical deletion** to keep the audit trail:

```bash
# Tombstone (logical deletion, payload optionally destroyed)
hmg govern <atom-id> --action tombstone --destroy-payload --reason "no longer needed"

# Quarantine (kept, hidden from recall)
hmg govern <atom-id> --action quarantine --reason "not needed for now"

# Demote (may no longer be needed)
hmg correct <atom-id> --action demote-possible --reason "no longer applicable"
```

Observations can be removed with `hmg obs forget`.

### Can I import existing conversation history and memory files?

Yes. Say "import memories into HMG" to your agent (the `hmg-memory-import` skill): it scans conversation history and host-native memory files, extracts items with long-term value, classifies them by project / personal, and writes them after your confirmation. See [Importing existing memories](integration.md#importing-existing-memories).
