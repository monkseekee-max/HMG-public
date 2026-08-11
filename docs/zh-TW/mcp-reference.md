---
sidebar_position: 2
---

# MCP 參考

HMG 透過 MCP（Model Context Protocol）向 Agent 暴露記憶工具。工具名在宿主中形如 `mcp__hmg__memory_memorize`（`mcp__<server>__<tool>`）。

## 總覽

| 工具 | 用途 | 必填欄位 |
|---|---|---|
| `memory_memorize` | 寫入一條記憶 | `content` |
| `memory_recall` | 搜尋記憶 | `query` |
| `memory_correct` | 糾正一條記憶 | `target_atom`、`action`、`reason` |
| `memory_govern` | 管控一條記憶的生命週期 | `target_atom`、`action`、`reason` |
| `memory_handoff` | 會話交接摘要 | `summary` |
| `memory_stats` | 檢視 store 概況 | （無） |

不暴露為 MCP 工具的能力：`agent_brief`（SessionStart hook 內部實現）、`observation_*`（Agent 整合不啟用）、`history` / `export`（僅 SDK 層，見 [SDK 參考](sdk-reference.md)）。

## 通用約定

- **scope 不需要 agent 傳**。所有工具的作用域由 PreToolUse hook 從會話所在目錄機械推斷並注入（或 MCP server 從程序工作目錄推斷）；agent 傳入的 scope 會被覆蓋。
- **確定性、極性自動推斷**。`epistemic`（事實/約束/猜測）和 `polarity`（肯定/否定/條件）由 HMG 從內容措辭推斷，不是入參。
- **寫入自動脫敏**。結構化敏感資訊（連線串、`password=xxx`、Bearer token、私鑰塊）在 memorize 時被自動脫敏；自然語言描述的敏感內容不會被自動檢測，需呼叫者自行避免。
- **精確去重**。內容完全相同的寫入不會建立第二條 atom（`effect: "no_op"`）。

## ScopeInput（共用）

所有工具的可選 `scope` 欄位結構相同（agent 不需要傳）：

```json
{
  "tenant_id": "qiankun",
  "workspace": "HMG-AI",
  "repository": "HMG-DEV-brach",
  "branch": "main"
}
```

| 欄位 | 說明 |
|---|---|
| `tenant_id` | 租戶，本機使用者名稱，HMG 從 store 配置讀取 |
| `workspace` | 工作區，通常為 git remote owner |
| `repository` | 倉庫名 |
| `branch` | 分支 |

---

## memory_memorize

寫入一條長期記憶。

**入參**

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `content` | string | 是 | 記憶內容，獨立自足的一句話 |
| `source` | string | 否 | 來源歸屬：`user`（使用者說的，更權威）/ `agent`（agent 總結的）/ 自定義 |
| `scope` | ScopeInput | 否 | hook 自動注入，agent 不傳 |

**出參**

| 欄位 | 說明 |
|---|---|
| `atom_id` | atom 的 ULID（去重命中時返回已有 atom 的 ID） |
| `effect` | `applied`（新建）/ `no_op`（去重命中）/ `rejected`（准入攔截） |
| `reason` | 去重或拒絕的原因（`applied` 時不返回） |
| `deduped_with` | 去重命中的已有 atom ID（僅 `no_op`） |

**示例**

```json
{
  "content": "本專案用 PostgreSQL 16 做主資料庫，不用 MongoDB，因為需要事務和複雜查詢",
  "source": "user"
}
```

**注意**

- 不需要先調 recall 查重，HMG 內部自動精確去重
- 如果當前上下文中已經看到語義相近的記憶，用 `memory_correct`（`replace`）更新它，而不是新增
- 記憶使用使用者當前對話的語言儲存

---

## memory_recall

按自然語言搜尋記憶。

**入參**

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `query` | string | 是 | 搜尋查詢，名詞短語效果最好 |
| `max_results` | number | 否 | 最大返回條數，預設 10 |
| `include_negated` | boolean | 否 | 是否包含已被否定的記憶，預設 false |
| `scope` | ScopeInput | 否 | hook 自動注入，agent 不傳 |

**出參**

| 欄位 | 說明 |
|---|---|
| `atoms` | 按相關性降序排列的結果列表 |
| `atoms[].atom_id` | atom 唯一標識，供 correct / govern 使用 |
| `atoms[].content` | 記憶內容（被隔離/封存的返回佔位說明） |
| `atoms[].score` | 相關性得分，0.0 ~ 1.0 |
| `atoms[].created_at` | 建立時間（RFC 3339） |
| `atoms[].source` | 來源歸屬 |

**示例**

```json
{ "query": "PostgreSQL 連線池配置" }
```

**注意**

- query 用名詞短語、保留關鍵實體（人名、專案名、技術名、檔名），不要用口語化問句
- 一次召回通常夠用，HMG 內部已從語義、關鍵詞、圖關係等多角度檢索

---

## memory_correct

糾正一條記憶。追加式糾錯：舊內容保留在審計鏈中，不會丟失歷史。

**入參**

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `target_atom` | string | 是 | 要糾正的 atom ID（從 recall 結果獲取） |
| `action` | string | 是 | 見下方動作表 |
| `reason` | string | 是 | 糾錯理由，寫入審計鏈 |
| `new_content` | string | replace 時必填 | 替換後的新內容 |
| `scope` | ScopeInput | 否 | 預設繼承目標 atom，不需要傳 |

**action 取值**

| 動作 | 含義 | 典型場景 |
|---|---|---|
| `negate` | 標記為假並停用 | 「這條記憶已經過時/錯誤了」 |
| `confirm_actual` | 確認為事實 | 「之前不確定，現在確認了」 |
| `confirm_necessary` | 確認為硬約束 | 「這不只是事實，是必須遵守的約束」 |
| `demote` | 降級為可能 | 「之前以為確定了，其實還不確定」 |
| `replace` | 用新內容替換（建立新 atom，舊 atom 保留在演變鏈） | 「內容需要更新」 |

**出參**

| 欄位 | 說明 |
|---|---|
| `effect` | `applied` / `rejected` |
| `target_atom` | 被糾正的原 atom ID |
| `new_atom_id` | 新 atom ID（僅 `replace`） |
| `reason` | 拒絕原因（僅 `rejected`） |

**示例**

```json
{
  "target_atom": "01J9ZK8V3QX7N2M4R6T8W0YB1C",
  "action": "replace",
  "reason": "v3 已遷移到 PostgreSQL，舊決策過時",
  "new_content": "主資料庫用 PostgreSQL 16，替換原 MongoDB 方案"
}
```

**注意**

- `negate` 不可精確逆（沒有 un-negate）；否定錯了用 `replace` 寫回正確內容
- `replace` 寫錯了就在那條 atom 上繼續 `replace`，保證任何時刻只有一條生效記憶

---

## memory_govern

管控一條記憶的生命週期（隔離、封存、作廢、提煉教訓）。

**入參**

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `target_atom` | string | 是 | 要治理的 atom ID |
| `action` | string | 是 | `quarantine` / `seal` / `tombstone` / `derive_lesson` |
| `reason` | string | 是 | 治理理由，寫入審計鏈 |
| `lesson_content` | string | derive_lesson 時必填 | 從原內容提煉的脫敏教訓 |
| `scope` | ScopeInput | 否 | 預設繼承目標 atom，不需要傳 |

**action 取值**

| 動作 | 含義 |
|---|---|
| `quarantine` | 隔離：召回不再出現，內容保留，可恢復 |
| `seal` | 封存：僅審計可見 |
| `tombstone` | 墓碑化：邏輯刪除，預設銷燬內容 |
| `derive_lesson` | 提煉一條脫敏教訓（新 atom），原文封存 |

**出參**

| 欄位 | 說明 |
|---|---|
| `effect` | `applied` / `rejected` |
| `target_atom` | 被治理的原 atom ID |
| `lesson_atom_id` | 教訓 atom ID（僅 `derive_lesson`） |
| `reason` | 拒絕原因（僅 `rejected`） |

**示例**

```json
{
  "target_atom": "01J9ZK8V3QX7N2M4R6T8W0YB1C",
  "action": "derive_lesson",
  "reason": "原文包含洩露的 API key",
  "lesson_content": "不要在程式碼或記憶中硬編碼 API key，使用環境變數"
}
```

**注意**

- 誤寫敏感資訊：有教訓可提煉用 `derive_lesson`，沒有就 `seal` 或 `tombstone`
- `tombstone` 預設銷燬內容，不需要呼叫者額外指定

---

## memory_handoff

寫入會話交接摘要。handoff 是一種特殊記憶：會話啟動時的簡報會**優先召回**最近的 handoff。

**入參**

| 欄位 | 型別 | 必填 | 說明 |
|---|---|---|---|
| `summary` | string | 是 | 交接摘要，建議覆蓋：做了什麼 / 為什麼 / 驗證 / 風險 / 下一步（格式不強制） |
| `source` | string | 否 | 來源歸屬 |
| `scope` | ScopeInput | 否 | hook 自動注入，agent 不傳 |

**出參**

| 欄位 | 說明 |
|---|---|
| `atom_id` | handoff atom 的 ULID |
| `effect` | `applied` / `rejected` |
| `reason` | 拒絕原因（僅 `rejected`） |

**示例**

```json
{
  "summary": "修復了 login.py 的空指標問題，根因是 session 過期時 get_session() 返回 None，在 line 38 加了有效性檢查，pytest 全部透過。風險：併發場景下 session 重新整理可能有競態。下一步：給 session 模組補整合測試。",
  "source": "agent"
}
```

**注意**

- 呼叫時機：任務結束、里程碑完成、會話即將結束
- 與 memorize 的分工：memorize 存單條增量知識，handoff 存一次任務的整體交接

---

## memory_stats

檢視 store 概況。主要供 SessionStart hook 內部使用（判斷空 store 走引導流程），agent 正常工作流一般不需要呼叫。

**入參**：無。

**出參**

| 欄位 | 說明 |
|---|---|
| `atoms` | 記憶 atom 總數 |
| `edges` | 圖邊總數 |
| `indexes` | 各索引覆蓋數（semantic / keyword / temporal / categorical） |
| `snapshot_version` | 當前快照版本號，每次寫入遞增 |

---

上一章：[CLI 參考](cli-reference.md) · 下一章：[SDK 參考](sdk-reference.md)
