---
sidebar_position: 3
---

# SDK リファレンス

HMG の公開パッケージ SDK は Python / TypeScript クライアントを提供します。インターフェースは [MCP ツール](mcp-reference.md) と同構で、さらに `history` と `export` の 2 つの SDK 専用インターフェースが加わります。HTTP コントラクトの最終的な真源は `openapi/hmg-server.yaml` です。

## SDK のレイヤー

| レイヤー | クラス | カバー範囲 |
|---|---|---|
| 公開パッケージ SDK | Python `hmg-sdk` / TypeScript `@hmg_ai/sdk-ts` の `HMGClient` | 8 つの公開インターフェース：memorize、recall、correct、govern、handoff、stats、history、export |
| ソースレベル HTTP helper | `sdk/python/hmg.py` / `sdk/typescript/hmg.ts` の `HmgClient` | 完全な HTTP コントラクト（account、secret vault、observation、cloud、team、制御プレーンなど）。[ソースレベル helper](#ソースレベル-hmgclient上級) を参照 |

公開インターフェースとして公開されない機能：`agent_brief`（SessionStart hook の内部実装）、`observation_*`（Agent 統合では起動しない）。

## インストールと接続

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

| コンストラクタ引数 | Python | TypeScript | 説明 |
|---|---|---|---|
| HMG HTTP アドレス | `base_url` | `baseUrl` | 既定 `http://127.0.0.1:7654`（server の既定アドレス、`HMG_HTTP_ADDR` で変更可） |
| API key | `api_key` | `apiKey` | 認証ゲートウェイがある場合に `x-api-key` を送信 |

## 共通レスポンス envelope

HTTP API は統一 envelope を返します：

```json
{ "ok": true,  "data": {},   "error": null }
{ "ok": false, "data": null, "error": { "code": "policy.denied", "message": "...", "details": {} } }
```

公開パッケージ SDK はレスポンスをオブジェクトに逆シリアライズします。ソースレベル `HmgClient` の多くのメソッドは envelope を直接返します。

## ScopeInput

すべてのインターフェースの任意 `scope` フィールドは同じ構造です：

```typescript
interface ScopeInput {
  tenant_id?: string;   // 既定は store 設定の OS ユーザー名。通常は渡さない
  workspace?: string;   // 通常は git remote の owner
  repository?: string;  // リポジトリ名
  branch?: string;      // ブランチ
}
```

- **MCP パス**：agent は渡さず、hook が機械的に注入
- **SDK / HTTP パス**：呼び出し側が明示的に渡せる。未指定時は既定設定を使うか実行ディレクトリから推論

---

## 公開 API 一覧

### Python `HMGClient`

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `memorize(content, **kwargs)` | `MemorizeResponse` | 記憶を 1 件書き込む |
| `recall(query, **kwargs)` | `RecallResponse` | query で記憶をリコール |
| `correct(target_atom, action, reason, **kwargs)` | `CorrectResponse` | 記憶を 1 件訂正 |
| `govern(target_atom, action, reason, **kwargs)` | `GovernanceResponse` | 記憶を 1 件ガバナンス |
| `handoff(summary, **kwargs)` | `HandoffResponse` | セッション引き継ぎ要約を書き込む |
| `stats()` | `StatsResponse` | store の概況 |
| `history(atom_id)` | `HistoryResponse` | ある記憶の完全な変遷（監査） |
| `export(**kwargs)` | `ExportResponse` | すべての atom と edge をエクスポート |

### TypeScript `HMGClient`

| メソッド | 戻り値 | 説明 |
|---|---|---|
| `memorize(req)` | `Promise<MemorizeResponse>` | 記憶を 1 件書き込む |
| `recall(req)` | `Promise<RecallResponse>` | query で記憶をリコール |
| `correct(req)` | `Promise<CorrectResponse>` | 記憶を 1 件訂正 |
| `govern(req)` | `Promise<GovernanceResponse>` | 記憶を 1 件ガバナンス |
| `handoff(req)` | `Promise<HandoffResponse>` | セッション引き継ぎ要約を書き込む |
| `stats()` | `Promise<StatsResponse>` | store の概況 |
| `history(atomId)` | `Promise<HistoryResponse>` | ある記憶の完全な変遷（監査） |
| `export(req?)` | `Promise<ExportResponse>` | すべての atom と edge をエクスポート |
| `bulkMemorize(req, onEvent?)` | `Promise<BulkMemorizeSummary>` | TypeScript 専用：SSE で一括書き込みし進捗イベントを受信 |

---

## インターフェース schema

フィールドの詳細な意味は MCP ツールと同一で、ここでは構造のみ記載します。注意事項は [MCP リファレンス](mcp-reference.md) の対応ツールを参照。

### memorize

```typescript
// 入力
interface MemorizeInput {
  content: string;          // 必須。独立した一文
  source?: string;          // "user" / "agent" / カスタム
  scope?: ScopeInput;       // 任意
}
// 出力
interface MemorizeOutput {
  atom_id: string;          // atom の ULID（no_op 時は既存 atom を返す）
  effect: "applied" | "no_op" | "rejected";
  reason?: string;          // no_op / rejected の理由
  deduped_with?: string;    // no_op のみ：ヒットした既存 atom の ID
}
```

### recall

```typescript
// 入力
interface RecallInput {
  query: string;            // 必須。名詞句が最も効果的
  max_results?: number;     // 既定 10
  include_negated?: boolean; // 既定 false
  scope?: ScopeInput;
}
// 出力
interface RecallOutput {
  atoms: {
    atom_id: string;
    content: string;
    score: number;          // 0.0 ~ 1.0、降順
    created_at: string;     // RFC 3339
    source?: string;
  }[];
  meta: object;             // リコールのメタ情報
}
```

### correct

```typescript
// 入力
interface CorrectInput {
  target_atom: string;      // 必須
  action: "negate" | "confirm_actual" | "confirm_necessary" | "demote" | "replace";
  reason: string;           // 必須、監査チェーンに書き込まれる
  new_content?: string;     // replace のとき必須
  scope?: ScopeInput;       // 既定で対象 atom から継承
}
// 出力
interface CorrectOutput {
  effect: "applied" | "rejected";
  target_atom: string;
  new_atom_id?: string;     // replace のみ
  reason?: string;          // rejected のみ
}
```

> `negate` は正確に元に戻せない。復旧は `replace` を使う。

### govern

```typescript
// 入力
interface GovernInput {
  target_atom: string;      // 必須
  action: "quarantine" | "seal" | "tombstone" | "derive_lesson";
  reason: string;           // 必須、監査チェーンに書き込まれる
  lesson_content?: string;  // derive_lesson のとき必須
  scope?: ScopeInput;       // 既定で対象 atom から継承
}
// 出力
interface GovernOutput {
  effect: "applied" | "rejected";
  target_atom: string;
  lesson_atom_id?: string;  // derive_lesson のみ
  reason?: string;          // rejected のみ
}
```

> `tombstone` は既定で内容を破棄する。呼び出し側の指定は不要。

### handoff

```typescript
// 入力
interface HandoffInput {
  summary: string;          // 必須。カバー推奨：何をしたか/なぜ/検証/リスク/次のステップ
  source?: string;
  scope?: ScopeInput;
}
// 出力
interface HandoffOutput {
  atom_id: string;
  effect: "applied" | "rejected";
  reason?: string;
}
```

### stats

```typescript
// 入力：なし
// 出力
interface StatsOutput {
  atoms: number;
  edges: number;
  indexes: { semantic: number; keyword: number; temporal: number; categorical: number };
  snapshot_version: number; // 書き込みごとに増加
}
```

### history（SDK のみ）

```typescript
// 入力
interface HistoryInput {
  atom_id: string;          // 必須
}
// 出力
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
    related_lessons: string[];   // 双方向：教訓 ↔ 原文
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

### export（SDK のみ）

```typescript
// 入力
interface ExportInput {
  format?: "json" | "csv";  // 既定 "json"
  scope?: { workspace?: string; repository?: string; branch?: string }; // 未指定時は全量エクスポート
}
// 出力
interface ExportOutput {
  nodes: {
    id: string;             // atom ULID
    label: string;          // 内容（先頭 200 文字に切り詰め）
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

## エンドツーエンドの例

```python
from hmg import HMGClient

client = HMGClient(base_url="http://127.0.0.1:7654")

written = client.memorize(
    content="このプロジェクトはデプロイ前に必ずデータベースマイグレーションを実行する",
    source="deploy-rule",
)

result = client.recall(query="デプロイ前のチェック項目", max_results=5)
for atom in result.atoms:
    print(atom.atom_id, atom.score, atom.content)

if result.atoms:
    client.correct(
        target_atom=result.atoms[0].atom_id,
        action="replace",
        reason="マイグレーションツールを migrate から alembic に変更",
        new_content="デプロイ前に必ず alembic でデータベースマイグレーションを実行する",
    )

client.handoff(
    summary="デプロイドキュメントを更新：マイグレーションツールを alembic に変更。検証：staging デプロイ通過。次：CI スクリプトを同期。",
    source="docs-update",
)
```

```typescript
import { HMGClient } from "@hmg_ai/sdk-ts";

const client = new HMGClient({ baseUrl: "http://127.0.0.1:7654" });

const written = await client.memorize({
  content: "このプロジェクトはデプロイ前に必ずデータベースマイグレーションを実行する",
  source: "deploy-rule",
});

const result = await client.recall({ query: "デプロイ前のチェック項目", max_results: 5 });

// 一括書き込み（SSE 進捗コールバック）
const summary = await client.bulkMemorize(
  {
    items: [
      { content: "テストは vitest を使う", source: "convention" },
      { content: "CI は必ず先に lint を実行する", source: "convention" },
    ],
    stop_on_error: false,
  },
  (event) => {
    if (event.event === "progress") console.log(`${event.done}/${event.total}`);
  },
);
```

---

<a id="ソースレベル-hmgclient上級"></a>

## ソースレベル HmgClient（上級）

ソースレベル `HmgClient` は完全な HTTP コントラクトを直接マップし、ウェブサイト/account backend、運用制御プレーン、Team Cloud などの実装者向けです。通常のアプリケーションは公開パッケージ SDK を使ってください。

### 基本 memory / graph / audit

| 機能 | Python | TypeScript | HTTP |
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

ソースレベル helper は完全な `MemoryContext`（`access_level`、`policy_tags`、`audit`、`references`、`governance` を含む）とソフトウェアエンジニアリング領域の便利関数（`software_engineering_scope` / `task_reference_filters` など）も受け付けます。

### 上級ルートグループ

| ルートグループ | 機能 | Python / TypeScript エントリー |
|---|---|---|
| `/api/account/*` | アカウントログイン（device code フロー）、entitlements、デバイス、クォータ | `account_device_code*` / `account_activations` / `account_current_entitlement` |
| `/api/secrets/*` | secret vault：store / lookup / use / reveal / rotate / revoke | `secret_store` / `secret_lookup` / ... |
| `/api/observations/*` | observation の捕捉、昇格、クリーンアップ、設定 | `observation_capture` / `observation_promote` / ... |
| `/api/hooks/*`、`/api/panorama/*` | 統合イベントの配信、panorama クエリ | `hook_dispatch` / `panorama_summary` / `panorama_query` |
| `/api/cloud/*` | クラウド同期、vault、フェデレーションリコール、corrections、SSE イベント | `CloudSync` / `CloudVaults` / `CloudFederation` / `Corrections` |
| `/control/team/*` | Team Cloud：org、invite、memory space、audit、usage | `CloudTeam(client)` / `teamCloud*` |
| `/api/enterprise/*`、`/control/business/*` | エンタープライズポリシー、DLP、break-glass、Business Governance | `Enterprise(client)` / `business*` |
| `/control/productization/*` | Private Cloud、Hybrid/Federation、Hub registry | `privateCloudReadiness` / `hub*` |

各ルートの完全な schema は `openapi/hmg-server.yaml` に準じます。

## メンテナンスルール

SDK リファレンスを更新するときは必ず同時に確認してください：

1. `openapi/hmg-server.yaml` に対応する route、schema、envelope が含まれているか
2. `sdk/python/hmg.py` と `sdk/typescript/hmg.ts` が対応するメソッドを公開しているか
3. 公開エクスポートパッケージ `export/sdk-python`、`export/sdk-ts` がドキュメントに書かれたメソッドを実装しているか
4. `tests/contracts.rs` が重要なフィールドを固定しているか
5. サンプルコードは実際のクラス名を使う：公開パッケージ `HMGClient`、ソースレベル `HmgClient`

---

前：[MCP リファレンス](mcp-reference.md)
