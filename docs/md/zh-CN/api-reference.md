# HMG API 参考 — Community Edition

HTTP 基础 URL：`http://localhost:7654`（默认）。

## MCP 工具

HMG 暴露 48 个 MCP 工具，覆盖核心记忆、治理、MemoryQL、观察、密钥库、panorama 和图健康工作流。下面的核心工具接受可选的 `context` 对象，包含作用域字段以实现分支感知记忆。

### `memory_memorize`

存储持久信息。

```json
{
  "content": "要记忆的文本",
  "source": "可选来源标签",
  "modality": "text",
  "context": {
    "tenant_id": "tenant-acme",
    "workspace": "platform",
    "repository": "my-repo",
    "branch": "main"
  }
}
```

响应：

```json
{
  "success": true,
  "added_atom_count": 1,
  "added_atoms": ["01KSEFSC29QX8RQ78N3110ATC9"],
  "snapshot_version": 8
}
```


### `memory_recall`

检索相关记忆。

```json
{
  "query": "我们选择了什么数据库？",
  "max_results": 10,
  "response_profile": "compact",
  "output_format": "yaml"
}
```

响应格式：`compact`（默认）、`summary`、`full`、`debug`。

输出格式：`yaml`（默认）、`markdown`、`json`。


### `memory_correct`

纠错、否定、确认、降权或替换原子。

```json
{
  "target_atom": "01KSEFSC29QX8RQ78N3110ATC9",
  "action": "replace",
  "reason": "为简化改用 SQLite",
  "new_content": "决策：用户数据使用 SQLite。"
}
```

动作：`negate`、`confirm_actual`、`confirm_necessary`、`demote`、`replace`。


### `memory_govern`

应用治理：隔离、密封、墓碑化或派生教训。

```json
{
  "target_atom": "01KSEFSC29QX8RQ78N3110ATC9",
  "action": "tombstone",
  "reason": "包含敏感 API 密钥引用"
}
```

动作：`quarantine`、`seal`、`tombstone`、`derive_lesson`。


### `memory_history`

检查原子的纠错和治理历史。

```json
{
  "atom_id": "01KSEFSC29QX8RQ78N3110ATC9"
}
```

### `memory_handoff`

编写跨会话交接摘要。

```json
{
  "summary": "实现了 X，用 Y 测试验证，剩余风险：Z。",
  "source": "session-end"
}
```

### `memory_agent_brief`

在任务开始时获取紧凑的分支感知简报。

```json
{
  "query": "当前编码任务的上下文",
  "brief_format": "compact_yaml"
}
```


### `memory_stats`

获取图谱和索引统计信息。

```json
{}
```


## HTTP API

### `POST /api/memorize`

与 `memory_memorize` 参数相同，作为 JSON 请求体。

### `POST /api/recall`

与 `memory_recall` 参数相同，作为 JSON 请求体。

### `POST /api/correct`

与 `memory_correct` 参数相同，作为 JSON 请求体。

### `POST /api/governance/{action}`

动作：`quarantine`、`seal`、`tombstone`、`derive_lesson`。

### `GET /api/stats`

返回原子数、边数、索引统计。

### `GET /api/graph/export`

导出完整记忆图谱为 JSON。

### `GET /api/snapshot/{atom_id}`

返回特定原子的快照历史。

### `GET /api/audit/{atom_id}`

返回完整审计追踪（纠错 + 治理历史）。

## 作用域（分支感知记忆）

HMG 支持面向编码 agent 的层级作用域：

```text
tenant_id → workspace → repository → branch
                                        ↳ task_id
                                        ↳ decision_id
```

当提供作用域字段时，召回会自动优先返回分支特定的记忆，而非更广泛的工作空间或租户记忆。

## 响应格式

所有响应遵循一致的结构：

```json
{
  "success": true,
  "snapshot_version": 905,
  "..."
}
```

错误响应：

```json
{
  "success": false,
  "error": "错误描述"
}
```
