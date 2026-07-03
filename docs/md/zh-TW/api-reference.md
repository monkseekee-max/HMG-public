# HMG API 參考 — Community Edition

HTTP 基礎 URL：`http://localhost:7654`（預設）。

## MCP 工具

HMG 暴露 48 個 MCP 工具，涵蓋核心記憶、治理、MemoryQL、觀察、密鑰庫、panorama 與圖健康工作流。下面的核心工具接受可選的 `context` 物件，包含範圍欄位以實現分支感知記憶。

### `memory_memorize`

儲存持久資訊。

```json
{
  "content": "要記憶的文字",
  "source": "可選來源標籤",
  "modality": "text",
  "context": {
    "tenant_id": "tenant-acme",
    "workspace": "platform",
    "repository": "my-repo",
    "branch": "main"
  }
}
```

回應：

```json
{
  "success": true,
  "added_atom_count": 1,
  "added_atoms": ["01KSEFSC29QX8RQ78N3110ATC9"],
  "snapshot_version": 8
}
```


### `memory_recall`

檢索相關記憶。

```json
{
  "query": "我們選擇了什麼資料庫？",
  "max_results": 10,
  "response_profile": "compact",
  "output_format": "yaml"
}
```

回應格式：`compact`（預設）、`summary`、`full`、`debug`。

輸出格式：`yaml`（預設）、`markdown`、`json`。


### `memory_correct`

糾錯、否定、確認、降權或取代原子。

```json
{
  "target_atom": "01KSEFSC29QX8RQ78N3110ATC9",
  "action": "replace",
  "reason": "為簡化改用 SQLite",
  "new_content": "決策：使用者資料使用 SQLite。"
}
```

動作：`negate`、`confirm_actual`、`confirm_necessary`、`demote`、`replace`。


### `memory_govern`

套用治理：隔離、密封、墓碑化或衍生教訓。

```json
{
  "target_atom": "01KSEFSC29QX8RQ78N3110ATC9",
  "action": "tombstone",
  "reason": "包含敏感 API 金鑰引用"
}
```

動作：`quarantine`、`seal`、`tombstone`、`derive_lesson`。


### `memory_history`

檢查原子的糾錯和治理歷史。

```json
{
  "atom_id": "01KSEFSC29QX8RQ78N3110ATC9"
}
```

### `memory_handoff`

撰寫跨工作階段交接摘要。

```json
{
  "summary": "實作了 X，用 Y 測試驗證，剩餘風險：Z。",
  "source": "session-end"
}
```

### `memory_agent_brief`

在工作開始時取得緊湊的分支感知簡報。

```json
{
  "query": "目前編碼工作的上下文",
  "brief_format": "compact_yaml"
}
```


### `memory_stats`

取得圖譜和索引統計資訊。

```json
{}
```


## HTTP API

### `POST /api/memorize`

與 `memory_memorize` 參數相同，作為 JSON 請求體。

### `POST /api/recall`

與 `memory_recall` 參數相同，作為 JSON 請求體。

### `POST /api/correct`

與 `memory_correct` 參數相同，作為 JSON 請求體。

### `POST /api/governance/{action}`

動作：`quarantine`、`seal`、`tombstone`、`derive_lesson`。

### `GET /api/stats`

返回原子數、邊數、索引統計。

### `GET /api/graph/export`

匯出完整記憶圖譜為 JSON。

### `GET /api/snapshot/{atom_id}`

返回特定原子的快照歷史。

### `GET /api/audit/{atom_id}`

返回完整審計追蹤（糾錯 + 治理歷史）。

## 範圍（分支感知記憶）

HMG 支援面向編碼 agent 的分層範圍：

```text
tenant_id → workspace → repository → branch
                                        ↳ task_id
                                        ↳ decision_id
```

當提供範圍欄位時，召回會自動優先返回分支特定的記憶，而非更廣泛的工作空間或租戶記憶。

## 回應格式

所有回應遵循一致的結構：

```json
{
  "success": true,
  "snapshot_version": 905,
  "..."
}
```

錯誤回應：

```json
{
  "success": false,
  "error": "錯誤描述"
}
```
