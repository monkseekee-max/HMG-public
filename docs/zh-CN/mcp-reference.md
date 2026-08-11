---
sidebar_position: 2
---

# MCP 参考

HMG 通过 MCP（Model Context Protocol）向 Agent 暴露记忆工具。工具名在宿主中形如 `mcp__hmg__memory_memorize`（`mcp__<server>__<tool>`）。

## 总览

| 工具 | 用途 | 必填字段 |
|---|---|---|
| `memory_memorize` | 写入一条记忆 | `content` |
| `memory_recall` | 搜索记忆 | `query` |
| `memory_correct` | 纠正一条记忆 | `target_atom`、`action`、`reason` |
| `memory_govern` | 管控一条记忆的生命周期 | `target_atom`、`action`、`reason` |
| `memory_handoff` | 会话交接摘要 | `summary` |
| `memory_stats` | 查看 store 概况 | （无） |

不暴露为 MCP 工具的能力：`agent_brief`（SessionStart hook 内部实现）、`observation_*`（Agent 集成不激活）、`history` / `export`（仅 SDK 层，见 [SDK 参考](sdk-reference.md)）。

## 通用约定

- **scope 不需要 agent 传**。所有工具的作用域由 PreToolUse hook 从会话所在目录机械推断并注入（或 MCP server 从进程工作目录推断）；agent 传入的 scope 会被覆盖。
- **确定性、极性自动推断**。`epistemic`（事实/约束/猜测）和 `polarity`（肯定/否定/条件）由 HMG 从内容措辞推断，不是入参。
- **写入自动脱敏**。结构化敏感信息（连接串、`password=xxx`、Bearer token、私钥块）在 memorize 时被自动脱敏；自然语言描述的敏感内容不会被自动检测，需调用者自行避免。
- **精确去重**。内容完全相同的写入不会创建第二条 atom（`effect: "no_op"`）。

## ScopeInput（共用）

所有工具的可选 `scope` 字段结构相同（agent 不需要传）：

```json
{
  "tenant_id": "qiankun",
  "workspace": "HMG-AI",
  "repository": "HMG-DEV-brach",
  "branch": "main"
}
```

| 字段 | 说明 |
|---|---|
| `tenant_id` | 租户，本机用户名，HMG 从 store 配置读取 |
| `workspace` | 工作区，通常为 git remote owner |
| `repository` | 仓库名 |
| `branch` | 分支 |

---

## memory_memorize

写入一条长期记忆。

**入参**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `content` | string | 是 | 记忆内容，独立自足的一句话 |
| `source` | string | 否 | 来源归属：`user`（用户说的，更权威）/ `agent`（agent 总结的）/ 自定义 |
| `scope` | ScopeInput | 否 | hook 自动注入，agent 不传 |

**出参**

| 字段 | 说明 |
|---|---|
| `atom_id` | atom 的 ULID（去重命中时返回已有 atom 的 ID） |
| `effect` | `applied`（新建）/ `no_op`（去重命中）/ `rejected`（准入拦截） |
| `reason` | 去重或拒绝的原因（`applied` 时不返回） |
| `deduped_with` | 去重命中的已有 atom ID（仅 `no_op`） |

**示例**

```json
{
  "content": "本项目用 PostgreSQL 16 做主数据库，不用 MongoDB，因为需要事务和复杂查询",
  "source": "user"
}
```

**注意**

- 不需要先调 recall 查重，HMG 内部自动精确去重
- 如果当前上下文中已经看到语义相近的记忆，用 `memory_correct`（`replace`）更新它，而不是新增
- 记忆使用用户当前对话的语言存储

---

## memory_recall

按自然语言搜索记忆。

**入参**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `query` | string | 是 | 搜索查询，名词短语效果最好 |
| `max_results` | number | 否 | 最大返回条数，默认 10 |
| `include_negated` | boolean | 否 | 是否包含已被否定的记忆，默认 false |
| `scope` | ScopeInput | 否 | hook 自动注入，agent 不传 |

**出参**

| 字段 | 说明 |
|---|---|
| `atoms` | 按相关性降序排列的结果列表 |
| `atoms[].atom_id` | atom 唯一标识，供 correct / govern 使用 |
| `atoms[].content` | 记忆内容（被隔离/封存的返回占位说明） |
| `atoms[].score` | 相关性得分，0.0 ~ 1.0 |
| `atoms[].created_at` | 创建时间（RFC 3339） |
| `atoms[].source` | 来源归属 |

**示例**

```json
{ "query": "PostgreSQL 连接池配置" }
```

**注意**

- query 用名词短语、保留关键实体（人名、项目名、技术名、文件名），不要用口语化问句
- 一次召回通常够用，HMG 内部已从语义、关键词、图关系等多角度检索

---

## memory_correct

纠正一条记忆。追加式纠错：旧内容保留在审计链中，不会丢失历史。

**入参**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `target_atom` | string | 是 | 要纠正的 atom ID（从 recall 结果获取） |
| `action` | string | 是 | 见下方动作表 |
| `reason` | string | 是 | 纠错理由，写入审计链 |
| `new_content` | string | replace 时必填 | 替换后的新内容 |
| `scope` | ScopeInput | 否 | 默认继承目标 atom，不需要传 |

**action 取值**

| 动作 | 含义 | 典型场景 |
|---|---|---|
| `negate` | 标记为假并停用 | 「这条记忆已经过时/错误了」 |
| `confirm_actual` | 确认为事实 | 「之前不确定，现在确认了」 |
| `confirm_necessary` | 确认为硬约束 | 「这不只是事实，是必须遵守的约束」 |
| `demote` | 降级为可能 | 「之前以为确定了，其实还不确定」 |
| `replace` | 用新内容替换（创建新 atom，旧 atom 保留在演变链） | 「内容需要更新」 |

**出参**

| 字段 | 说明 |
|---|---|
| `effect` | `applied` / `rejected` |
| `target_atom` | 被纠正的原 atom ID |
| `new_atom_id` | 新 atom ID（仅 `replace`） |
| `reason` | 拒绝原因（仅 `rejected`） |

**示例**

```json
{
  "target_atom": "01J9ZK8V3QX7N2M4R6T8W0YB1C",
  "action": "replace",
  "reason": "v3 已迁移到 PostgreSQL，旧决策过时",
  "new_content": "主数据库用 PostgreSQL 16，替换原 MongoDB 方案"
}
```

**注意**

- `negate` 不可精确逆（没有 un-negate）；否定错了用 `replace` 写回正确内容
- `replace` 写错了就在那条 atom 上继续 `replace`，保证任何时刻只有一条生效记忆

---

## memory_govern

管控一条记忆的生命周期（隔离、封存、作废、提炼教训）。

**入参**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `target_atom` | string | 是 | 要治理的 atom ID |
| `action` | string | 是 | `quarantine` / `seal` / `tombstone` / `derive_lesson` |
| `reason` | string | 是 | 治理理由，写入审计链 |
| `lesson_content` | string | derive_lesson 时必填 | 从原内容提炼的脱敏教训 |
| `scope` | ScopeInput | 否 | 默认继承目标 atom，不需要传 |

**action 取值**

| 动作 | 含义 |
|---|---|
| `quarantine` | 隔离：召回不再出现，内容保留，可恢复 |
| `seal` | 封存：仅审计可见 |
| `tombstone` | 墓碑化：逻辑删除，默认销毁内容 |
| `derive_lesson` | 提炼一条脱敏教训（新 atom），原文封存 |

**出参**

| 字段 | 说明 |
|---|---|
| `effect` | `applied` / `rejected` |
| `target_atom` | 被治理的原 atom ID |
| `lesson_atom_id` | 教训 atom ID（仅 `derive_lesson`） |
| `reason` | 拒绝原因（仅 `rejected`） |

**示例**

```json
{
  "target_atom": "01J9ZK8V3QX7N2M4R6T8W0YB1C",
  "action": "derive_lesson",
  "reason": "原文包含泄露的 API key",
  "lesson_content": "不要在代码或记忆中硬编码 API key，使用环境变量"
}
```

**注意**

- 误写敏感信息：有教训可提炼用 `derive_lesson`，没有就 `seal` 或 `tombstone`
- `tombstone` 默认销毁内容，不需要调用者额外指定

---

## memory_handoff

写入会话交接摘要。handoff 是一种特殊记忆：会话启动时的简报会**优先召回**最近的 handoff。

**入参**

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `summary` | string | 是 | 交接摘要，建议覆盖：做了什么 / 为什么 / 验证 / 风险 / 下一步（格式不强制） |
| `source` | string | 否 | 来源归属 |
| `scope` | ScopeInput | 否 | hook 自动注入，agent 不传 |

**出参**

| 字段 | 说明 |
|---|---|
| `atom_id` | handoff atom 的 ULID |
| `effect` | `applied` / `rejected` |
| `reason` | 拒绝原因（仅 `rejected`） |

**示例**

```json
{
  "summary": "修复了 login.py 的空指针问题，根因是 session 过期时 get_session() 返回 None，在 line 38 加了有效性检查，pytest 全部通过。风险：并发场景下 session 刷新可能有竞态。下一步：给 session 模块补集成测试。",
  "source": "agent"
}
```

**注意**

- 调用时机：任务结束、里程碑完成、会话即将结束
- 与 memorize 的分工：memorize 存单条增量知识，handoff 存一次任务的整体交接

---

## memory_stats

查看 store 概况。主要供 SessionStart hook 内部使用（判断空 store 走引导流程），agent 正常工作流一般不需要调用。

**入参**：无。

**出参**

| 字段 | 说明 |
|---|---|
| `atoms` | 记忆 atom 总数 |
| `edges` | 图边总数 |
| `indexes` | 各索引覆盖数（semantic / keyword / temporal / categorical） |
| `snapshot_version` | 当前快照版本号，每次写入递增 |

---

上一章：[CLI 参考](cli-reference.md) · 下一章：[SDK 参考](sdk-reference.md)
