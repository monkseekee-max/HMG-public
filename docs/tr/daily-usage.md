# Daily Usage Guide

HMG is a local memory system. It gives your AI agent memory across sessions — what was decided in this conversation can still be recalled in the next one.

This guide walks you through HMG's core operations using one complete project scenario. The examples use the TypeScript SDK; if you prefer the command line, every operation has a matching `hmg` command (see [CLI Reference](cli-reference.md)). Once an agent is integrated, most of these operations happen automatically — you just need to follow the ideas.

---

## Start with "remembering one thing"

You are starting a new project. The team just finished a meeting and made a technical decision. You want the agent to remember it so you never have to repeat yourself.

```typescript
const result = await client.memorize({
  content: "The project uses PostgreSQL 16 as the primary database, not MongoDB",
});

console.log(result.atom_id);  // "01HKX2ABCDEF..."
console.log(result.effect);   // "applied"
```

That's it. One memory stored. HMG calls it an **atom** — the smallest unit of memory.

You don't need to tell HMG "how certain" this memory is or "positive or negative" — it infers that from the text itself. You just write natural language.

### What if I store it twice?

```typescript
await client.memorize({ content: "The project uses PostgreSQL 16 as the primary database, not MongoDB" });
// → effect: "no_op" (dedup hit, no second copy created)
```

HMG deduplicates automatically. Identical content is never stored twice.

---

## Stored it — how do I find it again?

Three days later, new session. You ask the agent: "what database are we using again?"

Internally the agent calls recall:

```typescript
const result = await client.recall({
  query: "database selection",
});

// result.atoms:
// [
//   {
//     atom_id: "01HKX2ABCDEF...",
//     content: "The project uses PostgreSQL 16 as the primary database, not MongoDB",
//     score: 0.92,
//     created_at: "2026-07-25T14:00:00Z",
//     source: "user"
//   }
// ]
```

Queries work best as **noun phrases**. "database selection" beats "what database did we decide on again".

### Scope: where does a memory belong?

Every memory is automatically bound to a scope (tenant / workspace / repository / branch). You usually don't pass it — HMG infers it from the git information of the current working directory.

A memory stored on the `main` branch of the `mem0ai/mem0` repo is only recalled under that scope by default. Switch to another project and you won't see unrelated memories.

---

## What if a memory goes stale?

Two months later the project upgraded the database. The old memory still says "PostgreSQL 16", but you are on 17 now.

### Recommended: replace

```typescript
await client.correct({
  target_atom: "01HKX2ABCDEF...",
  action: "replace",
  reason: "upgraded to PostgreSQL 17",
  new_content: "The project uses PostgreSQL 17 as the primary database",
});
// → result.new_atom_id: "01NEW..."
```

Done in one step. The old atom is kept (linked to the new atom via a Supersedes edge); searches return only the new version.

Three months later, `history("01NEW...")` shows: this memory was upgraded from the "PostgreSQL 16" one, with the reason "upgraded to PostgreSQL 17". The audit chain is complete.

### When negate instead of replace?

negate fits "this no longer holds, and there is no replacement".

For example, half a year later you abandoned the MongoDB-based caching scheme entirely:

```typescript
// Previously stored: "Use MongoDB for session caching"
// Now the whole scheme is retired — no "new version", just gone
await client.correct({
  target_atom: "01MONGO...",
  action: "negate",
  reason: "MongoDB caching scheme retired, switched to Redis",
});
```

After negate, this memory disappears from default searches. The agent will never see it again.

Note: negate does not rewrite the text to "don't use MongoDB". It marks "this memory is no longer valid" — the original text stays, it just stops being recalled.

### How to choose?

| Situation | Use | Example |
|---|---|---|
| Same thing got a new version | `replace` | "use PostgreSQL 16" → "use PostgreSQL 17" |
| The decision itself changed (changed your mind) | `replace` | "considering K8s" → "deploy on ECS" |
| Retired entirely, no replacement | `negate` | "use MongoDB for caching" → retired |
| Content unchanged, "heard" becomes "confirmed" | `confirm_actual` | "API gateway uses Kong" (was uncertain, now confirmed in config) |
| Content unchanged, fact becomes hard constraint | `confirm_necessary` | "all APIs require auth" (upgraded from convention to compliance) |
| Content unchanged, "settled" downgraded to "still evaluating" | `demote` | "deploy on K8s" (thought it was settled; it isn't) |

One line: **content changes → replace; only certainty changes → confirm/demote; fully retired → negate.**

Note that `confirm_actual` does not change content — it confirms "what the content says is true". If the decision itself changed ("consider X" → "use Y"), that's a content change — use replace.

### Certainty levels (epistemic)

Every memory has a certainty level; confirm/demote change exactly that:

```
possible  →  "possibly true" (heard, evaluating, uncertain)
actual    →  "confirmed true" (verified, confirmed)
necessary →  "must be true" (hard constraint, compliance, non-negotiable)
```

Transitions:

```
possible ──confirm_actual──→ actual ──confirm_necessary──→ necessary
    ↑                          |                               |
    └──────────── demote ──────┘                               |
    ↑                                                          |
    └──────────────────── demote ──────────────────────────────┘
```

Caveats:

- `demote` goes straight to the bottom (possible), not one level down. Demoting necessary lands on possible, not actual.
- `confirm_actual` only upgrades; it cannot be applied to an atom that is already necessary (it errors).
- Want necessary back to actual? No single step. `demote` first (to possible), then `confirm_actual`.
- `confirm_actual` and `demote` are reversible between possible ↔ actual. But anything involving necessary is not (demote skips actual and lands on possible).

### Does correct lose information?

No. correct never destroys content. Old atoms are never deleted; `history` can always show them.

But negate and replace have no "one-click undo". If you got it wrong, recover like this:

### How to recover from a wrong operation?

There is no "un-negate" and no "undo replace". The universal recovery: **replace again on the problematic atom**.

**Wrong negate**: you negated "use MongoDB for caching" thinking it was retired. A week later you find it is still in use.

```typescript
await client.correct({
  target_atom: "01MONGO...",  // the negated atom
  action: "replace",
  reason: "negate was wrong, MongoDB caching is still in use",
  new_content: "MongoDB is used for session caching and is still in use",
});
```

**Wrong replace**: yesterday you replaced "use PG 16" → "use PG 17". Today the upgrade was cancelled — it's still 16.

```typescript
await client.correct({
  target_atom: "01NEW...",  // the wrong "use PG 17" atom
  action: "replace",
  reason: "upgrade cancelled, rolling back to 16",
  new_content: "The project uses PostgreSQL 16 as the primary database",
});
```

Why not memorize a new one? Because replace builds a Supersedes edge between old and new, guaranteeing exactly one active memory at any time. With memorize, the negated or superseded old atom may linger in recall results and contradict the new one.

The audit chain stays complete too: every step has a reason, and history shows the full evolution.

---

## Some memories must disappear {#sensitive-memory-governance}

One day you notice the agent once stored a database password into memory:

```typescript
// This memory should not exist
// atom_id: "01SECRET..."
// content: "The DB password is pg_admin_123, connection string is postgres://..."
```

### Doesn't HMG auto-redact already?

Partly. Connection strings (`postgres://user:pass@host/db`), `password=xxx` patterns, Bearer tokens, private key blocks — these are replaced with `[REDACTED:...]` at memorize time.

But "the DB password is pg_admin_123" in natural language slips through. So manual govern is still needed.

---

Now correct is not enough — you don't want to "fix the knowledge", you want "this memory must disappear".

Use govern:

### Safest: extract the lesson, retire the original

```typescript
await client.govern({
  target_atom: "01SECRET...",
  action: "derive_lesson",
  reason: "content contains a plaintext database password and must be removed",
  lesson_content: "Never store database passwords or connection strings in memory; use environment variables",
});
// → result.lesson_atom_id: "01LESSON..."
```

What happened:

```
original atom (01SECRET): "The DB password is pg_admin_123..."
  → sealed. Content permanently unrecoverable. No API can return the original text.

new atom (01LESSON): "Never store database passwords or connection strings in memory; use environment variables"
  → normally recallable. This lesson is worth keeping.
```

When derive_lesson instead of seal? **The old content holds concrete values nobody should see, but the "don't do this" experience itself is safe and reusable.** If there's no lesson worth keeping, use seal or tombstone directly.

A `derived_lesson_from` edge connects the two. If you later inspect the lesson atom's history, `related_lessons` points to the original atom (though its text is no longer readable). Querying the original atom's history likewise shows the lesson derived from it.

### Other governance actions

| Action | Effect | Reversible? |
|---|---|---|
| `quarantine` | Hidden from search, content kept, pending human review | ✅ recoverable |
| `seal` | Hidden permanently, content unrecoverable | ❌ |
| `tombstone` | Fully deleted, only ID and timestamps remain | ❌ |
| `derive_lesson` | Extract lesson → seal original | ❌ (original unrecoverable) |

### correct or govern?

One line: **correct changes what we believe; govern changes whether it exists.**

- "This memory is outdated" → correct (negate / replace)
- "This memory should not exist" → govern (seal / tombstone / derive_lesson)
- "This memory looks suspicious — hide it while we check" → govern (quarantine)

---

## End of session: hand off to the next one

The day's work is done. You fixed a bug, made decisions, and some things remain unfinished.

Call handoff to pass the context to the next session:

```typescript
await client.handoff({
  summary: "Fixed the null pointer in login.py. Root cause: get_session() returns None when the session expires; added a validity check at line 38, pytest passes. Risk: possible race on session refresh under concurrency. Next: add integration tests for the session module.",
});
```

Next time you open this project, the new session shows this handoff summary automatically at startup. No need to explain "where we left off" again.

### handoff vs memorize

| | memorize | handoff |
|---|---|---|
| What it stores | A single fact ("use PostgreSQL 17") | Full context (what + why + risks + next) |
| How many per session | Several (as you go) | Usually 1 (summary at the end) |
| How the next session uses it | Returned when searches match | Shown with priority at session start |

---

## Want the full history of a memory?

When you need "how many times was this memory changed, by whom, and why", use history:

```typescript
const result = await client.history({
  atom_id: "01LESSON...",
});

// result.current:
//   { content: "Never store database passwords...", exposure_state: "visible", ... }
//
// result.relations:
//   { related_lessons: ["01SECRET..."] }   ← which original atom it derives from
//
// result.exposure_history:
//   []   ← this lesson atom itself was never governed
```

Querying the original atom (01SECRET) instead:

```typescript
const result = await client.history({
  atom_id: "01SECRET...",
});

// result.current:
//   { content: "[governed payload hidden: sealed]", exposure_state: "sealed", ... }
//
// result.relations:
//   { related_lessons: ["01LESSON..."] }   ← the lesson atom derived from it
//
// result.exposure_history:
//   [{ from: "visible", to: "sealed", reason: "content contains a plaintext DB password", at: "2026-07-28T...", by: "agent" }]
```

`related_lessons` is bidirectional: from the lesson you see its origin; from the original you see the lesson it produced. Even when the original text is sealed and unreadable, the relation remains.

history is an audit tool. Agents don't need it in normal workflows — use it when you (the human) want to trace "what this memory has been through".

---

## See what's in the store

```typescript
const stats = await client.stats();

// {
//   atoms: 42,
//   edges: 306,
//   indexes: { semantic: 42, keyword: 42, temporal: 42, categorical: 42 },
//   snapshot_version: 64
// }
```

---

## Cheat sheet

| I want to... | Call | Required |
|---|---|---|
| Remember something | `memorize` | content |
| Find a past memory | `recall` | query |
| Mark a memory outdated | `correct` (negate) | target_atom, action, reason |
| Update a memory's content | `correct` (replace) | target_atom, action, reason, new_content |
| Make a memory disappear | `govern` (seal/tombstone) | target_atom, action, reason |
| Extract the lesson, retire the original | `govern` (derive_lesson) | target_atom, action, reason, lesson_content |
| Hand off to the next session | `handoff` | summary |
| Trace a memory's history | `history` | atom_id |
| Store overview | `stats` | (none) |
