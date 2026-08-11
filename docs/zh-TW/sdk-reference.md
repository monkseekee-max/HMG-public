---
sidebar_position: 3
---

# SDK 參考

HMG 公開包 SDK 提供 Python / TypeScript 客戶端，介面與 [MCP 工具](mcp-reference.md) 同構，另加 `history` 和 `export` 兩個 SDK 專屬介面。HTTP 合同的最終真源是 `openapi/hmg-server.yaml`。

## SDK 分層

| 層 | 類 | 覆蓋面 |
|---|---|---|
| 公開包 SDK | Python `hmg-sdk` / TypeScript `@hmg_ai/sdk-ts` 中的 `HMGClient` | 8 個公開介面：memorize、recall、correct、govern、handoff、stats、history、export |
| 原始碼級 HTTP helper | `sdk/python/hmg.py` / `sdk/typescript/hmg.ts` 中的 `HmgClient` | 完整 HTTP 合同（account、secret vault、observation、cloud、team、控制面等），見 [原始碼級 helper](#hmgclient-advanced) |

不暴露為公開介面的能力：`agent_brief`（SessionStart hook 內部實現）、`observation_*`（Agent 整合不啟用）。

## 安裝和連線

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

| 構造引數 | Python | TypeScript | 說明 |
|---|---|---|---|
| HMG HTTP 地址 | `base_url` | `baseUrl` | 預設 `http://127.0.0.1:7654`（server 預設地址，可用 `HMG_HTTP_ADDR` 修改） |
| API key | `api_key` | `apiKey` | 有鑑權閘道器時傳送 `x-api-key` |

## 公共響應 envelope

HTTP API 返回統一 envelope：

```json
{ "ok": true,  "data": {},   "error": null }
{ "ok": false, "data": null, "error": { "code": "policy.denied", "message": "...", "details": {} } }
```

公開包 SDK 會把響應反序列化成物件；原始碼級 `HmgClient` 多數方法直接返回 envelope。

## ScopeInput

所有介面的可選 `scope` 欄位，結構相同：

```typescript
interface ScopeInput {
  tenant_id?: string;   // 預設取 store 配置的本機使用者名稱，一般不傳
  workspace?: string;   // 通常為 git remote owner
  repository?: string;  // 倉庫名
  branch?: string;      // 分支
}
```

- **MCP 路徑**：agent 不傳，由 hook 機械注入
- **SDK / HTTP 路徑**：呼叫者可顯式傳入；不傳時使用預設配置或按執行目錄推斷

---

## 公開 API 列表

### Python `HMGClient`

| 方法 | 返回 | 描述 |
|---|---|---|
| `memorize(content, **kwargs)` | `MemorizeResponse` | 寫入一條記憶 |
| `recall(query, **kwargs)` | `RecallResponse` | 按 query 召回記憶 |
| `correct(target_atom, action, reason, **kwargs)` | `CorrectResponse` | 糾正一條記憶 |
| `govern(target_atom, action, reason, **kwargs)` | `GovernanceResponse` | 治理一條記憶 |
| `handoff(summary, **kwargs)` | `HandoffResponse` | 寫入會話交接摘要 |
| `stats()` | `StatsResponse` | store 概況 |
| `history(atom_id)` | `HistoryResponse` | 一條記憶的完整演變（審計） |
| `export(**kwargs)` | `ExportResponse` | 匯出全部 atom 和 edge |

### TypeScript `HMGClient`

| 方法 | 返回 | 描述 |
|---|---|---|
| `memorize(req)` | `Promise<MemorizeResponse>` | 寫入一條記憶 |
| `recall(req)` | `Promise<RecallResponse>` | 按 query 召回記憶 |
| `correct(req)` | `Promise<CorrectResponse>` | 糾正一條記憶 |
| `govern(req)` | `Promise<GovernanceResponse>` | 治理一條記憶 |
| `handoff(req)` | `Promise<HandoffResponse>` | 寫入會話交接摘要 |
| `stats()` | `Promise<StatsResponse>` | store 概況 |
| `history(atomId)` | `Promise<HistoryResponse>` | 一條記憶的完整演變（審計） |
| `export(req?)` | `Promise<ExportResponse>` | 匯出全部 atom 和 edge |
| `bulkMemorize(req, onEvent?)` | `Promise<BulkMemorizeSummary>` | TypeScript 專有：SSE 批次寫入並接收進度事件 |

---

## 介面 schema

欄位的詳細語義與 MCP 工具一致，此處只列結構；注意事項見 [MCP 參考](mcp-reference.md) 對應工具。

### memorize

```typescript
// 入參
interface MemorizeInput {
  content: string;          // 必填。獨立自足的一句話
  source?: string;          // "user" / "agent" / 自定義
  scope?: ScopeInput;       // 可選
}
// 出參
interface MemorizeOutput {
  atom_id: string;          // atom ULID（no_op 時返回已有 atom）
  effect: "applied" | "no_op" | "rejected";
  reason?: string;          // no_op / rejected 的原因
  deduped_with?: string;    // 僅 no_op：命中的已有 atom ID
}
```

### recall

```typescript
// 入參
interface RecallInput {
  query: string;            // 必填。名詞短語效果最好
  max_results?: number;     // 預設 10
  include_negated?: boolean; // 預設 false
  scope?: ScopeInput;
}
// 出參
interface RecallOutput {
  atoms: {
    atom_id: string;
    content: string;
    score: number;          // 0.0 ~ 1.0，降序排列
    created_at: string;     // RFC 3339
    source?: string;
  }[];
  meta: object;             // 召回元資訊
}
```

### correct

```typescript
// 入參
interface CorrectInput {
  target_atom: string;      // 必填
  action: "negate" | "confirm_actual" | "confirm_necessary" | "demote" | "replace";
  reason: string;           // 必填，寫入審計鏈
  new_content?: string;     // 僅 replace 必填
  scope?: ScopeInput;       // 預設繼承目標 atom
}
// 出參
interface CorrectOutput {
  effect: "applied" | "rejected";
  target_atom: string;
  new_atom_id?: string;     // 僅 replace
  reason?: string;          // 僅 rejected
}
```

> `negate` 不可精確逆；恢復用 `replace`。

### govern

```typescript
// 入參
interface GovernInput {
  target_atom: string;      // 必填
  action: "quarantine" | "seal" | "tombstone" | "derive_lesson";
  reason: string;           // 必填，寫入審計鏈
  lesson_content?: string;  // 僅 derive_lesson 必填
  scope?: ScopeInput;       // 預設繼承目標 atom
}
// 出參
interface GovernOutput {
  effect: "applied" | "rejected";
  target_atom: string;
  lesson_atom_id?: string;  // 僅 derive_lesson
  reason?: string;          // 僅 rejected
}
```

> `tombstone` 預設銷燬內容，無需呼叫者指定。

### handoff

```typescript
// 入參
interface HandoffInput {
  summary: string;          // 必填。建議覆蓋：做了什麼/為什麼/驗證/風險/下一步
  source?: string;
  scope?: ScopeInput;
}
// 出參
interface HandoffOutput {
  atom_id: string;
  effect: "applied" | "rejected";
  reason?: string;
}
```

### stats

```typescript
// 入參：無
// 出參
interface StatsOutput {
  atoms: number;
  edges: number;
  indexes: { semantic: number; keyword: number; temporal: number; categorical: number };
  snapshot_version: number; // 每次寫入遞增
}
```

### history（僅 SDK）

```typescript
// 入參
interface HistoryInput {
  atom_id: string;          // 必填
}
// 出參
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
    related_lessons: string[];   // 雙向：教訓 ↔ 原文
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

### export（僅 SDK）

```typescript
// 入參
interface ExportInput {
  format?: "json" | "csv";  // 預設 "json"
  scope?: { workspace?: string; repository?: string; branch?: string }; // 不傳匯出全量
}
// 出參
interface ExportOutput {
  nodes: {
    id: string;             // atom ULID
    label: string;          // 內容（截斷至前 200 字元）
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

## 端到端示例

```python
from hmg import HMGClient

client = HMGClient(base_url="http://127.0.0.1:7654")

written = client.memorize(
    content="本專案部署前必須先跑資料庫遷移",
    source="deploy-rule",
)

result = client.recall(query="部署前檢查事項", max_results=5)
for atom in result.atoms:
    print(atom.atom_id, atom.score, atom.content)

if result.atoms:
    client.correct(
        target_atom=result.atoms[0].atom_id,
        action="replace",
        reason="遷移工具已從 migrate 換成 alembic",
        new_content="部署前必須先用 alembic 跑資料庫遷移",
    )

client.handoff(
    summary="更新部署文件：遷移工具改 alembic。驗證：staging 部署透過。下一步：同步 CI 指令碼。",
    source="docs-update",
)
```

```typescript
import { HMGClient } from "@hmg_ai/sdk-ts";

const client = new HMGClient({ baseUrl: "http://127.0.0.1:7654" });

const written = await client.memorize({
  content: "本專案部署前必須先跑資料庫遷移",
  source: "deploy-rule",
});

const result = await client.recall({ query: "部署前檢查事項", max_results: 5 });

// 批次寫入（SSE 進度回撥）
const summary = await client.bulkMemorize(
  {
    items: [
      { content: "測試用 vitest", source: "convention" },
      { content: "CI 必須先跑 lint", source: "convention" },
    ],
    stop_on_error: false,
  },
  (event) => {
    if (event.event === "progress") console.log(`${event.done}/${event.total}`);
  },
);
```

---

<a id="原始碼級-hmgclient高階"></a>

## 原始碼級 HmgClient（高階） {#hmgclient-advanced}

原始碼級 `HmgClient` 直接對映完整 HTTP 合同，面向網站/account backend、運維控制面、Team Cloud 等實現者。普通應用請使用公開包 SDK。

### 基礎 memory / graph / audit

| 能力 | Python | TypeScript | HTTP |
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

原始碼級 helper 還接受完整 `MemoryContext`（含 `access_level`、`policy_tags`、`audit`、`references`、`governance`）以及軟體工程領域便利函式（`software_engineering_scope` / `task_reference_filters` 等）。

### 高階路由組

| 路由組 | 能力 | Python / TypeScript 入口 |
|---|---|---|
| `/api/account/*` | 賬號登入（device code 流程）、entitlements、裝置、配額 | `account_device_code*` / `account_activations` / `account_current_entitlement` |
| `/api/secrets/*` | 金鑰保險庫：store / lookup / use / reveal / rotate / revoke | `secret_store` / `secret_lookup` / ... |
| `/api/observations/*` | observation 捕獲、晉升、清理、配置 | `observation_capture` / `observation_promote` / ... |
| `/api/hooks/*`、`/api/panorama/*` | 整合事件分發、panorama 查詢 | `hook_dispatch` / `panorama_summary` / `panorama_query` |
| `/api/cloud/*` | 雲同步、vault、聯邦召回、corrections、SSE 事件 | `CloudSync` / `CloudVaults` / `CloudFederation` / `Corrections` |
| `/control/team/*` | Team Cloud：org、invite、memory space、audit、usage | `CloudTeam(client)` / `teamCloud*` |
| `/api/enterprise/*`、`/control/business/*` | 企業策略、DLP、break-glass、Business Governance | `Enterprise(client)` / `business*` |
| `/control/productization/*` | Private Cloud、Hybrid/Federation、Hub registry | `privateCloudReadiness` / `hub*` |

各路由的完整 schema 以 `openapi/hmg-server.yaml` 為準。

## 維護規則

SDK 參考更新時必須同步核對：

1. `openapi/hmg-server.yaml` 是否包含對應 route、schema、envelope
2. `sdk/python/hmg.py` 和 `sdk/typescript/hmg.ts` 是否暴露對應方法
3. 公開匯出包 `export/sdk-python`、`export/sdk-ts` 是否實現文件所寫方法
4. `tests/contracts.rs` 是否鎖住關鍵欄位
5. 示例程式碼使用真實類名：公開包 `HMGClient`，原始碼級 `HmgClient`

---

上一章：[MCP 參考](mcp-reference.md)
