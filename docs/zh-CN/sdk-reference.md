---
sidebar_position: 3
---

# SDK 参考

HMG 公开包 SDK 提供 Python / TypeScript 客户端，接口与 [MCP 工具](mcp-reference.md) 同构，另加 `history` 和 `export` 两个 SDK 专属接口。HTTP 合同的最终真源是 `openapi/hmg-server.yaml`。

## SDK 分层

| 层 | 类 | 覆盖面 |
|---|---|---|
| 公开包 SDK | Python `hmg-sdk` / TypeScript `@hmg_ai/sdk-ts` 中的 `HMGClient` | 8 个公开接口：memorize、recall、correct、govern、handoff、stats、history、export |
| 源码级 HTTP helper | `sdk/python/hmg.py` / `sdk/typescript/hmg.ts` 中的 `HmgClient` | 完整 HTTP 合同（account、secret vault、observation、cloud、team、控制面等），见 [源码级 helper](#hmgclient-advanced) |

不暴露为公开接口的能力：`agent_brief`（SessionStart hook 内部实现）、`observation_*`（Agent 集成不激活）。

## 安装和连接

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

| 构造参数 | Python | TypeScript | 说明 |
|---|---|---|---|
| HMG HTTP 地址 | `base_url` | `baseUrl` | 默认 `http://127.0.0.1:7654`（server 默认地址，可用 `HMG_HTTP_ADDR` 修改） |
| API key | `api_key` | `apiKey` | 有鉴权网关时发送 `x-api-key` |

## 公共响应 envelope

HTTP API 返回统一 envelope：

```json
{ "ok": true,  "data": {},   "error": null }
{ "ok": false, "data": null, "error": { "code": "policy.denied", "message": "...", "details": {} } }
```

公开包 SDK 会把响应反序列化成对象；源码级 `HmgClient` 多数方法直接返回 envelope。

## ScopeInput

所有接口的可选 `scope` 字段，结构相同：

```typescript
interface ScopeInput {
  tenant_id?: string;   // 默认取 store 配置的本机用户名，一般不传
  workspace?: string;   // 通常为 git remote owner
  repository?: string;  // 仓库名
  branch?: string;      // 分支
}
```

- **MCP 路径**：agent 不传，由 hook 机械注入
- **SDK / HTTP 路径**：调用者可显式传入；不传时使用默认配置或按运行目录推断

---

## 公开 API 列表

### Python `HMGClient`

| 方法 | 返回 | 描述 |
|---|---|---|
| `memorize(content, **kwargs)` | `MemorizeResponse` | 写入一条记忆 |
| `recall(query, **kwargs)` | `RecallResponse` | 按 query 召回记忆 |
| `correct(target_atom, action, reason, **kwargs)` | `CorrectResponse` | 纠正一条记忆 |
| `govern(target_atom, action, reason, **kwargs)` | `GovernanceResponse` | 治理一条记忆 |
| `handoff(summary, **kwargs)` | `HandoffResponse` | 写入会话交接摘要 |
| `stats()` | `StatsResponse` | store 概况 |
| `history(atom_id)` | `HistoryResponse` | 一条记忆的完整演变（审计） |
| `export(**kwargs)` | `ExportResponse` | 导出全部 atom 和 edge |

### TypeScript `HMGClient`

| 方法 | 返回 | 描述 |
|---|---|---|
| `memorize(req)` | `Promise<MemorizeResponse>` | 写入一条记忆 |
| `recall(req)` | `Promise<RecallResponse>` | 按 query 召回记忆 |
| `correct(req)` | `Promise<CorrectResponse>` | 纠正一条记忆 |
| `govern(req)` | `Promise<GovernanceResponse>` | 治理一条记忆 |
| `handoff(req)` | `Promise<HandoffResponse>` | 写入会话交接摘要 |
| `stats()` | `Promise<StatsResponse>` | store 概况 |
| `history(atomId)` | `Promise<HistoryResponse>` | 一条记忆的完整演变（审计） |
| `export(req?)` | `Promise<ExportResponse>` | 导出全部 atom 和 edge |
| `bulkMemorize(req, onEvent?)` | `Promise<BulkMemorizeSummary>` | TypeScript 专有：SSE 批量写入并接收进度事件 |

---

## 接口 schema

字段的详细语义与 MCP 工具一致，此处只列结构；注意事项见 [MCP 参考](mcp-reference.md) 对应工具。

### memorize

```typescript
// 入参
interface MemorizeInput {
  content: string;          // 必填。独立自足的一句话
  source?: string;          // "user" / "agent" / 自定义
  scope?: ScopeInput;       // 可选
}
// 出参
interface MemorizeOutput {
  atom_id: string;          // atom ULID（no_op 时返回已有 atom）
  effect: "applied" | "no_op" | "rejected";
  reason?: string;          // no_op / rejected 的原因
  deduped_with?: string;    // 仅 no_op：命中的已有 atom ID
}
```

### recall

```typescript
// 入参
interface RecallInput {
  query: string;            // 必填。名词短语效果最好
  max_results?: number;     // 默认 10
  include_negated?: boolean; // 默认 false
  scope?: ScopeInput;
}
// 出参
interface RecallOutput {
  atoms: {
    atom_id: string;
    content: string;
    score: number;          // 0.0 ~ 1.0，降序排列
    created_at: string;     // RFC 3339
    source?: string;
  }[];
  meta: object;             // 召回元信息
}
```

### correct

```typescript
// 入参
interface CorrectInput {
  target_atom: string;      // 必填
  action: "negate" | "confirm_actual" | "confirm_necessary" | "demote" | "replace";
  reason: string;           // 必填，写入审计链
  new_content?: string;     // 仅 replace 必填
  scope?: ScopeInput;       // 默认继承目标 atom
}
// 出参
interface CorrectOutput {
  effect: "applied" | "rejected";
  target_atom: string;
  new_atom_id?: string;     // 仅 replace
  reason?: string;          // 仅 rejected
}
```

> `negate` 不可精确逆；恢复用 `replace`。

### govern

```typescript
// 入参
interface GovernInput {
  target_atom: string;      // 必填
  action: "quarantine" | "seal" | "tombstone" | "derive_lesson";
  reason: string;           // 必填，写入审计链
  lesson_content?: string;  // 仅 derive_lesson 必填
  scope?: ScopeInput;       // 默认继承目标 atom
}
// 出参
interface GovernOutput {
  effect: "applied" | "rejected";
  target_atom: string;
  lesson_atom_id?: string;  // 仅 derive_lesson
  reason?: string;          // 仅 rejected
}
```

> `tombstone` 默认销毁内容，无需调用者指定。

### handoff

```typescript
// 入参
interface HandoffInput {
  summary: string;          // 必填。建议覆盖：做了什么/为什么/验证/风险/下一步
  source?: string;
  scope?: ScopeInput;
}
// 出参
interface HandoffOutput {
  atom_id: string;
  effect: "applied" | "rejected";
  reason?: string;
}
```

### stats

```typescript
// 入参：无
// 出参
interface StatsOutput {
  atoms: number;
  edges: number;
  indexes: { semantic: number; keyword: number; temporal: number; categorical: number };
  snapshot_version: number; // 每次写入递增
}
```

### history（仅 SDK）

```typescript
// 入参
interface HistoryInput {
  atom_id: string;          // 必填
}
// 出参
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
    related_lessons: string[];   // 双向：教训 ↔ 原文
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

### export（仅 SDK）

```typescript
// 入参
interface ExportInput {
  format?: "json" | "csv";  // 默认 "json"
  scope?: { workspace?: string; repository?: string; branch?: string }; // 不传导出全量
}
// 出参
interface ExportOutput {
  nodes: {
    id: string;             // atom ULID
    label: string;          // 内容（截断至前 200 字符）
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
    content="本项目部署前必须先跑数据库迁移",
    source="deploy-rule",
)

result = client.recall(query="部署前检查事项", max_results=5)
for atom in result.atoms:
    print(atom.atom_id, atom.score, atom.content)

if result.atoms:
    client.correct(
        target_atom=result.atoms[0].atom_id,
        action="replace",
        reason="迁移工具已从 migrate 换成 alembic",
        new_content="部署前必须先用 alembic 跑数据库迁移",
    )

client.handoff(
    summary="更新部署文档：迁移工具改 alembic。验证：staging 部署通过。下一步：同步 CI 脚本。",
    source="docs-update",
)
```

```typescript
import { HMGClient } from "@hmg_ai/sdk-ts";

const client = new HMGClient({ baseUrl: "http://127.0.0.1:7654" });

const written = await client.memorize({
  content: "本项目部署前必须先跑数据库迁移",
  source: "deploy-rule",
});

const result = await client.recall({ query: "部署前检查事项", max_results: 5 });

// 批量写入（SSE 进度回调）
const summary = await client.bulkMemorize(
  {
    items: [
      { content: "测试用 vitest", source: "convention" },
      { content: "CI 必须先跑 lint", source: "convention" },
    ],
    stop_on_error: false,
  },
  (event) => {
    if (event.event === "progress") console.log(`${event.done}/${event.total}`);
  },
);
```

---

<a id="源码级-hmgclient高级"></a>

## 源码级 HmgClient（高级） {#hmgclient-advanced}

源码级 `HmgClient` 直接映射完整 HTTP 合同，面向网站/account backend、运维控制面、Team Cloud 等实现者。普通应用请使用公开包 SDK。

### 基础 memory / graph / audit

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

源码级 helper 还接受完整 `MemoryContext`（含 `access_level`、`policy_tags`、`audit`、`references`、`governance`）以及软件工程领域便利函数（`software_engineering_scope` / `task_reference_filters` 等）。

### 高级路由组

| 路由组 | 能力 | Python / TypeScript 入口 |
|---|---|---|
| `/api/account/*` | 账号登录（device code 流程）、entitlements、设备、配额 | `account_device_code*` / `account_activations` / `account_current_entitlement` |
| `/api/secrets/*` | 密钥保险库：store / lookup / use / reveal / rotate / revoke | `secret_store` / `secret_lookup` / ... |
| `/api/observations/*` | observation 捕获、晋升、清理、配置 | `observation_capture` / `observation_promote` / ... |
| `/api/hooks/*`、`/api/panorama/*` | 集成事件分发、panorama 查询 | `hook_dispatch` / `panorama_summary` / `panorama_query` |
| `/api/cloud/*` | 云同步、vault、联邦召回、corrections、SSE 事件 | `CloudSync` / `CloudVaults` / `CloudFederation` / `Corrections` |
| `/control/team/*` | Team Cloud：org、invite、memory space、audit、usage | `CloudTeam(client)` / `teamCloud*` |
| `/api/enterprise/*`、`/control/business/*` | 企业策略、DLP、break-glass、Business Governance | `Enterprise(client)` / `business*` |
| `/control/productization/*` | Private Cloud、Hybrid/Federation、Hub registry | `privateCloudReadiness` / `hub*` |

各路由的完整 schema 以 `openapi/hmg-server.yaml` 为准。

## 维护规则

SDK 参考更新时必须同步核对：

1. `openapi/hmg-server.yaml` 是否包含对应 route、schema、envelope
2. `sdk/python/hmg.py` 和 `sdk/typescript/hmg.ts` 是否暴露对应方法
3. 公开导出包 `export/sdk-python`、`export/sdk-ts` 是否实现文档所写方法
4. `tests/contracts.rs` 是否锁住关键字段
5. 示例代码使用真实类名：公开包 `HMGClient`，源码级 `HmgClient`

---

上一章：[MCP 参考](mcp-reference.md)
