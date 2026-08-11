---
sidebar_position: 3
---

# SDK Reference

The HMG public SDK provides Python / TypeScript clients. The interfaces mirror the [MCP tools](mcp-reference.md), plus two SDK-only additions: `history` and `export`. The final source of truth for the HTTP contract is `openapi/hmg-server.yaml`.

## SDK layers

| Layer | Class | Coverage |
|---|---|---|
| Public SDK | `HMGClient` in Python `hmg-sdk` / TypeScript `@hmg_ai/sdk-ts` | 8 public interfaces: memorize, recall, correct, govern, handoff, stats, history, export |
| Source-level HTTP helper | `HmgClient` in `sdk/python/hmg.py` / `sdk/typescript/hmg.ts` | Full HTTP contract (account, secret vault, observation, cloud, team, control plane, etc.), see [Source-level helper](#source-level-hmgclient-advanced) |

Capabilities not exposed publicly: `agent_brief` (internal to the SessionStart hook), `observation_*` (not activated in agent integration).

## Installation and connection

```bash
pip install hmg-sdk            # Python
npm install @hmg_ai/sdk-ts     # TypeScript
```

```python
from hmg import HMGClient

client = HMGClient(base_url="http://127.0.0.1:7654")
```

```typescript
import { HMGClient } from "@hmg_ai/sdk-ts";

const client = new HMGClient({ baseUrl: "http://127.0.0.1:7654" });
```

| Constructor arg | Python | TypeScript | Description |
|---|---|---|---|
| HMG HTTP address | `base_url` | `baseUrl` | Default `http://127.0.0.1:7654` (server default; change with `HMG_HTTP_ADDR`) |
| API key | `api_key` | `apiKey` | Sent as `x-api-key` when an auth gateway is present |

## Common response envelope

HTTP APIs return a unified envelope:

```json
{ "ok": true,  "data": {},   "error": null }
{ "ok": false, "data": null, "error": { "code": "policy.denied", "message": "...", "details": {} } }
```

The public SDK deserializes responses into objects; most source-level `HmgClient` methods return the envelope directly.

## ScopeInput

All interfaces share the same optional `scope` field structure:

```typescript
interface ScopeInput {
  tenant_id?: string;   // defaults to the OS username from the store config; usually not passed
  workspace?: string;   // usually the git remote owner
  repository?: string;  // repository name
  branch?: string;      // branch
}
```

- **MCP path**: the agent never passes it — hooks inject it mechanically
- **SDK / HTTP path**: callers may pass it explicitly; defaults or runtime-directory inference apply otherwise

---

## Public API list

### Python `HMGClient`

| Method | Returns | Description |
|---|---|---|
| `memorize(content, **kwargs)` | `MemorizeResponse` | Write one memory |
| `recall(query, **kwargs)` | `RecallResponse` | Recall memories by query |
| `correct(target_atom, action, reason, **kwargs)` | `CorrectResponse` | Correct one memory |
| `govern(target_atom, action, reason, **kwargs)` | `GovernanceResponse` | Govern one memory |
| `handoff(summary, **kwargs)` | `HandoffResponse` | Write a session handoff summary |
| `stats()` | `StatsResponse` | Store overview |
| `history(atom_id)` | `HistoryResponse` | Full evolution of one memory (audit) |
| `export(**kwargs)` | `ExportResponse` | Export all atoms and edges |

### TypeScript `HMGClient`

| Method | Returns | Description |
|---|---|---|
| `memorize(req)` | `Promise<MemorizeResponse>` | Write one memory |
| `recall(req)` | `Promise<RecallResponse>` | Recall memories by query |
| `correct(req)` | `Promise<CorrectResponse>` | Correct one memory |
| `govern(req)` | `Promise<GovernanceResponse>` | Govern one memory |
| `handoff(req)` | `Promise<HandoffResponse>` | Write a session handoff summary |
| `stats()` | `Promise<StatsResponse>` | Store overview |
| `history(atomId)` | `Promise<HistoryResponse>` | Full evolution of one memory (audit) |
| `export(req?)` | `Promise<ExportResponse>` | Export all atoms and edges |
| `bulkMemorize(req, onEvent?)` | `Promise<BulkMemorizeSummary>` | TypeScript only: SSE bulk write with progress events |

---

## Interface schemas

Field semantics match the MCP tools; only the structure is listed here. For notes see the corresponding tool in [MCP Reference](mcp-reference.md).

### memorize

```typescript
// Input
interface MemorizeInput {
  content: string;          // required. One self-contained sentence
  source?: string;          // "user" / "agent" / custom
  scope?: ScopeInput;       // optional
}
// Output
interface MemorizeOutput {
  atom_id: string;          // atom ULID (no_op returns the existing atom)
  effect: "applied" | "no_op" | "rejected";
  reason?: string;          // reason for no_op / rejected
  deduped_with?: string;    // no_op only: the matched existing atom ID
}
```

### recall

```typescript
// Input
interface RecallInput {
  query: string;            // required. Noun phrases work best
  max_results?: number;     // default 10
  include_negated?: boolean; // default false
  scope?: ScopeInput;
}
// Output
interface RecallOutput {
  atoms: {
    atom_id: string;
    content: string;
    score: number;          // 0.0 ~ 1.0, descending
    created_at: string;     // RFC 3339
    source?: string;
  }[];
  meta: object;             // recall metadata
}
```

### correct

```typescript
// Input
interface CorrectInput {
  target_atom: string;      // required
  action: "negate" | "confirm_actual" | "confirm_necessary" | "demote" | "replace";
  reason: string;           // required, written to the audit chain
  new_content?: string;     // required for replace only
  scope?: ScopeInput;       // inherits from the target atom by default
}
// Output
interface CorrectOutput {
  effect: "applied" | "rejected";
  target_atom: string;
  new_atom_id?: string;     // replace only
  reason?: string;          // rejected only
}
```

> `negate` is not precisely reversible; recover with `replace`.

### govern

```typescript
// Input
interface GovernInput {
  target_atom: string;      // required
  action: "quarantine" | "seal" | "tombstone" | "derive_lesson";
  reason: string;           // required, written to the audit chain
  lesson_content?: string;  // required for derive_lesson only
  scope?: ScopeInput;       // inherits from the target atom by default
}
// Output
interface GovernOutput {
  effect: "applied" | "rejected";
  target_atom: string;
  lesson_atom_id?: string;  // derive_lesson only
  reason?: string;          // rejected only
}
```

> `tombstone` destroys content by default — no caller flag needed.

### handoff

```typescript
// Input
interface HandoffInput {
  summary: string;          // required. Recommended: what/why/validation/risks/next
  source?: string;
  scope?: ScopeInput;
}
// Output
interface HandoffOutput {
  atom_id: string;
  effect: "applied" | "rejected";
  reason?: string;
}
```

### stats

```typescript
// Input: none
// Output
interface StatsOutput {
  atoms: number;
  edges: number;
  indexes: { semantic: number; keyword: number; temporal: number; categorical: number };
  snapshot_version: number; // increments on every write
}
```

### history (SDK only)

```typescript
// Input
interface HistoryInput {
  atom_id: string;          // required
}
// Output
interface HistoryOutput {
  current: {
    atom_id: string;
    content: string;
    polarity: "positive" | "negative" | "conditional";
    epistemic: "possible" | "actual" | "necessary";
    exposure_state: "visible" | "quarantined" | "sealed" | "tombstoned" | "lesson";
    created_at: string;
    source?: string;
  };
  polarity_history: HistoryTransition[];
  epistemic_history: HistoryTransition[];
  exposure_history: HistoryTransition[];
  relations: {
    derived_from: string[];
    supersedes: string[];
    related_lessons: string[];   // bidirectional: lesson ↔ original
  };
}
interface HistoryTransition {
  from: string;
  to: string;
  reason: string;
  at: string;               // RFC 3339
  by?: string;
}
```

### export (SDK only)

```typescript
// Input
interface ExportInput {
  format?: "json" | "csv";  // default "json"
  scope?: { workspace?: string; repository?: string; branch?: string }; // omitted exports everything
}
// Output
interface ExportOutput {
  nodes: {
    id: string;             // atom ULID
    label: string;          // content (truncated to first 200 chars)
    group: "necessary" | "actual" | "possible";
    epistemic: number;      // 0=possible, 1=actual, 2=necessary
    polarity: "positive" | "negative" | "conditional";
    certainty: number;      // 0.0 ~ 1.0
    created_at: string;
  }[];
  edges: {
    id: string;
    from: string;
    to: string;
    relation: string;       // "supersedes" | "derived_lesson_from" | "supports" | ...
    weight: number;         // 0.0 ~ 1.0
    directed: boolean;
  }[];
  stats: { atom_count: number; edge_count: number; snapshot_version: number };
}
```

---

## End-to-end example

```python
from hmg import HMGClient

client = HMGClient(base_url="http://127.0.0.1:7654")

written = client.memorize(
    content="Always run database migrations before deploying this project",
    source="deploy-rule",
)

result = client.recall(query="pre-deployment checklist", max_results=5)
for atom in result.atoms:
    print(atom.atom_id, atom.score, atom.content)

if result.atoms:
    client.correct(
        target_atom=result.atoms[0].atom_id,
        action="replace",
        reason="migration tool switched from migrate to alembic",
        new_content="Always run alembic migrations before deploying",
    )

client.handoff(
    summary="Updated deployment docs: migration tool switched to alembic. Validated: staging deployment passed. Next: sync the CI scripts.",
    source="docs-update",
)
```

```typescript
import { HMGClient } from "@hmg_ai/sdk-ts";

const client = new HMGClient({ baseUrl: "http://127.0.0.1:7654" });

const written = await client.memorize({
  content: "Always run database migrations before deploying this project",
  source: "deploy-rule",
});

const result = await client.recall({ query: "pre-deployment checklist", max_results: 5 });

// Bulk write (SSE progress callback)
const summary = await client.bulkMemorize(
  {
    items: [
      { content: "Tests use vitest", source: "convention" },
      { content: "CI must run lint first", source: "convention" },
    ],
    stop_on_error: false,
  },
  (event) => {
    if (event.event === "progress") console.log(`${event.done}/${event.total}`);
  },
);
```

---

<a id="source-level-hmgclient-advanced"></a>

## Source-level HmgClient (advanced)

The source-level `HmgClient` maps the full HTTP contract directly, aimed at implementers of the website/account backend, ops control plane, Team Cloud, etc. Regular applications should use the public SDK.

### Basic memory / graph / audit

| Capability | Python | TypeScript | HTTP |
|---|---|---|---|
| Stats | `stats()` | `stats()` | `GET /api/stats` |
| Memorize | `memorize(MemorizeRequest)` | `memorize(request)` | `POST /api/memorize` |
| Recall | `recall(RecallRequest)` | `recall(request)` | `POST /api/recall` |
| Recall view | `recall_view(RecallViewRequest)` | `recallView(request)` | `POST /api/recall_view` |
| Noise feedback | `noise_feedback(phrase)` | `noiseFeedback(request)` | `POST /api/memory/noise_feedback` |
| Correct | `correct(CorrectRequest)` | `correct(request)` | `POST /api/correct` |
| Verify | `verify()` | `verify()` | `POST /api/verify` |
| Snapshot | `create_snapshot(reason)` | `createSnapshot(reason)` | `POST /api/snapshot` |
| Snapshot delta | `get_snapshot(version)` | `getSnapshot(version)` | `GET /api/snapshots/{version}` |
| Replay | `replay(from_version, to_version)` | `replay(fromVersion, toVersion)` | `GET /api/replay` |
| Governance | `quarantine` / `seal` / `tombstone` / `derive_lesson` | `quarantine` / `seal` / `tombstone` / `deriveLesson` | `POST /api/governance/*` |
| Graph export | `graph_export()` | `graphExport()` | `GET /api/graph/export` |
| Atom | `get_atom(atom_id)` | `getAtom(atomId)` | `GET /api/atom/{id}` |
| Atom history | `atom_history(atom_id)` | `atomHistory(atomId)` | `GET /api/atom/{id}/history` |
| Audit | `audit_access()` / `audit_verify()` | `auditAccess()` / `auditVerify()` | `GET /api/audit/*` |

The source-level helper also accepts a full `MemoryContext` (including `access_level`, `policy_tags`, `audit`, `references`, `governance`) plus software-engineering convenience functions (`software_engineering_scope` / `task_reference_filters`, etc.).

### Advanced route groups

| Route group | Capability | Python / TypeScript entry |
|---|---|---|
| `/api/account/*` | Account login (device code flow), entitlements, devices, quotas | `account_device_code*` / `account_activations` / `account_current_entitlement` |
| `/api/secrets/*` | Secret vault: store / lookup / use / reveal / rotate / revoke | `secret_store` / `secret_lookup` / ... |
| `/api/observations/*` | Observation capture, promotion, cleanup, config | `observation_capture` / `observation_promote` / ... |
| `/api/hooks/*`, `/api/panorama/*` | Integration event dispatch, panorama queries | `hook_dispatch` / `panorama_summary` / `panorama_query` |
| `/api/cloud/*` | Cloud sync, vault, federated recall, corrections, SSE events | `CloudSync` / `CloudVaults` / `CloudFederation` / `Corrections` |
| `/control/team/*` | Team Cloud: org, invite, memory space, audit, usage | `CloudTeam(client)` / `teamCloud*` |
| `/api/enterprise/*`, `/control/business/*` | Enterprise policy, DLP, break-glass, Business Governance | `Enterprise(client)` / `business*` |
| `/control/productization/*` | Private Cloud, Hybrid/Federation, Hub registry | `privateCloudReadiness` / `hub*` |

The complete schema for each route is defined in `openapi/hmg-server.yaml`.

## Maintenance rules

When updating this SDK reference, always verify:

1. `openapi/hmg-server.yaml` contains the corresponding route, schema, and envelope
2. `sdk/python/hmg.py` and `sdk/typescript/hmg.ts` expose the corresponding methods
3. The published packages `export/sdk-python` and `export/sdk-ts` implement what this doc says
4. `tests/contracts.rs` locks the key fields
5. Examples use the real class names: public `HMGClient`, source-level `HmgClient`

---

Previous: [MCP Reference](mcp-reference.md)
