---
sidebar_position: 1
---

# CLI 参考

HMG 的全部能力均可通过 `hmg` 命令行访问。本文按类别列出公开命令的用法；与 Agent 会话内工具的对应关系见 [MCP 参考](mcp-reference.md)。

## 全局选项

多数命令支持：

| 选项 | 说明 |
|---|---|
| `--store <path>` | 指定 store 目录（默认 `~/.local/share/hmg/stores/default`） |
| `--scope <tenant/workspace/repository/branch>` | 显式指定作用域；不传时按当前目录推断 |
| `--format text\|json\|yaml` | 输出格式 |
| `--direct` | 绕过 daemon，直接在进程内打开 store |
| `--dry-run` | 预览将要做出的变更，不实际执行 |

运行 `hmg help <command>` 查看单个命令的示例，`hmg help commands` 查看完整命令清单。

## 命令总览

| 类别 | 命令 |
|---|---|
| 记忆读写 | `memorize`、`recall`、`correct`、`govern`、`history`、`stats`、`export` |
| 任务上下文 | `agent-brief`、`handoff` |
| 查询 | `query`、`suggest-query`、`query-templates`、`explain-query`、`schema`、`recall-view`、`noise-feedback`、`panorama`、`impact` |
| 安装与接入 | `setup`、`init`、`doctor`、`login`、`account status`、`onboard`、`integrations`、`update`、`uninstall` |
| 运行时 | `daemon`、`model`、`hook`、`agent-event`、`agent-timeline` |
| store 维护 | `store migrate`、`store hygiene`、`store repair-edges`、`verify` |
| 密钥保险库 | `secret store / lookup / use / reveal / rotate / revoke` |
| 观察层 | `obs capture / promote / forget / maintain / review-queue`、`observation config / scheduler` |
| 其他 | `tui`、`version`、`language`、`completions` |

---

## 记忆读写

### hmg memorize

写入一条长期记忆。

```
hmg memorize <content> [--source <src>] [--scope <t/w/r/b>] [--file <path>] [--dry-run]
```

| 参数 | 说明 |
|---|---|
| `--source` | 来源归属（如 `user`、`cli`、自定义标签） |
| `--file` | 从文件读取内容（内容含引号/多行时使用） |

```bash
hmg memorize "本项目用 PostgreSQL 16 做主数据库，不用 MongoDB" --source cli
```

> 相同内容不会重复写入（返回已有 atom）。scope 不传时按当前目录推断。

### hmg recall

按自然语言召回记忆。

```
hmg recall <query> [--max-results <n>] [--profile compact|summary|full|debug]
                   [--scope <t/w/r/b>] [--include-negated] [--precision]
```

```bash
hmg recall "数据库选型决策"
hmg recall "登录 500 根因" --profile full
```

| 参数 | 说明 |
|---|---|
| `--profile` | 输出详略：`compact`（默认）/ `summary` / `full`（含边）/ `debug`（含检索诊断） |
| `--include-negated` | 包含已被否定的记忆（查看「曾经以为对」的信息） |
| `--precision` | 更严格的召回门控 |

### hmg correct

纠正一条记忆。

```
hmg correct <atom_id> --action <action> --reason <text> [--new-content <text>]
```

`--action` 取值：`replace` / `confirm-actual` / `confirm-necessary` / `demote-possible`。

```bash
hmg correct 01J9ZK8... --action replace \
  --reason "v3 已迁移到 PostgreSQL" \
  --new-content "主数据库用 PostgreSQL 16，替换原 MongoDB 方案"
```

> 否定一条记忆请用 `govern quarantine`（CLI 层）；MCP/SDK 层对应 `negate`。`negate` 不可精确逆，恢复用 `replace`。

### hmg govern

治理一条记忆的生命周期。

```
hmg govern <atom_id> --action <action> --reason <text> [--lesson <text>] [--destroy-payload]
```

`--action` 取值：`quarantine` / `seal` / `tombstone` / `derive-lesson`。

```bash
# 误写敏感信息：彻底清除
hmg govern 01J9ZK8... --action tombstone --destroy-payload --reason "误写 API key"

# 提炼脱敏教训，原文作废
hmg govern 01J9ZK8... --action derive-lesson --reason "原文含密钥" \
  --lesson "凭证应存 secret vault，不进普通记忆"
```

### hmg history / stats / export

```
hmg history <atom_id>          # 一条记忆的完整纠正/治理演变
hmg stats                      # atom / edge / 索引 / 快照版本统计
hmg export [--format json|csv] [--output <path>]   # 导出全部 atom 和 edge
```

---

## 任务上下文

### hmg agent-brief

任务开始时的上下文摘要（上次交接、关键决策、已知问题、未完成事项）。

```
hmg agent-brief [<query>] [--profile compact|summary|full|debug] [--scope <t/w/r/b>]
```

```bash
hmg agent-brief --query "修复登录接口偶发 500"
```

> Agent 集成中简报由 SessionStart hook 自动注入，无需手动调用。

### hmg handoff

任务结束时写入交接摘要（下次会话启动简报优先召回）。

```
hmg handoff <summary> [--source <src>] [--scope <t/w/r/b>]
```

```bash
hmg handoff "修复登录 500: token 过期校验改 UTC。验证: 200 次并发无 500。风险: 旧客户端缓存 expiry。下一步: 查刷新 token 流程。"
```

> 建议覆盖五要素：做了什么 / 为什么 / 验证 / 风险 / 下一步。

---

## 查询

| 命令 | 用途 |
|---|---|
| `hmg query <intent-task> <query-text>` | 按结构化查询模板执行（如决策追溯） |
| `hmg query --sql <sql>` | 只读 MemoryQL 查询（高级） |
| `hmg query-templates` | 列出可用的查询模板 |
| `hmg suggest-query <text>` | 让 HMG 推荐该怎么问 |
| `hmg explain-query` | 解释查询计划 |
| `hmg schema` | 查看 MemoryQL 逻辑 schema |
| `hmg recall-view <query> --view <id>` | 通过命名视图召回（normal / governance / audit） |
| `hmg noise-feedback <content>` | 反馈噪声短语，检索时降权 |
| `hmg panorama <query>` | 探索更广的图上下文 |
| `hmg impact <query>` | 评估一个变更的影响面 |

```bash
hmg query-templates                 # 先看有哪些模板
hmg query <intent-task> "缓存选型决策"
hmg noise-feedback "npm install 成功"
```

---

## 安装与接入

### hmg setup / init / doctor

```
hmg setup [--dry-run] [--no-daemon] [--no-model] [--no-agent-adapters]
hmg init [--global] [--agent <id>] [--all-agents] [--dry-run]
hmg doctor [--agent <id>] [--all-agents] [--fix] [--live-tool-smoke] [--verbose]
```

| 命令 | 职责 |
|---|---|
| `setup` | 准备本地运行时（daemon、嵌入模型） |
| `init` | 写入 Agent 接入配置（MCP、hooks、记忆策略文件）。`--dry-run` 预览 |
| `doctor` | 体检：核心 / store / 集成 / 运行时；`--fix` 自动修复可修复项 |

```bash
hmg setup
hmg init --agent codex --dry-run
hmg init --agent codex
hmg doctor --agent codex
```

### hmg login / account status

```
hmg login
hmg account status
```

基础记忆功能无需登录。在官网用户中心升级套餐后，执行 `hmg login` 联网验证账号并解锁对应能力与容量。登录不迁移本地数据，tenant 始终是本机用户名。

### hmg onboard

导入已有的 agent 记忆并验证真实召回。

```
hmg onboard [--import <file>] [--memory-path <path>] [--all] [--dry-run] [--non-interactive]
```

> 对 Agent 说「导入记忆至 HMG」（`hmg-memory-import` skill）走的是对话式导入；`hmg onboard` 是 CLI 直接导入。

### 其他

```
hmg update [--installer-url <url>]    # 升级
hmg uninstall [--purge-data]          # 卸载（默认保留 store 数据）
hmg integrations list|detect|explain|remove   # Agent 集成管理
hmg version                           # 版本与 edition
```

---

## 运行时

```
hmg daemon start|status|stop|restart [--store <path>]
hmg daemon install-service            # 安装为用户服务（自启动）
hmg model status                      # 嵌入模型状态
```

hooks 与事件桥接：

```
hmg hook dispatch --host <id> --event <name> [--payload <json>]   # 宿主 hook 的统一入口
hmg hook status [--host <id>] [--session-id <id>]                 # 会话与回执诊断（无正文）
hmg agent-event --payload <json> [--explain] [--dry-run]          # 外部 agent 生命周期事件桥接
hmg agent-timeline --event-id <id>                                # 查询持久化的 agent 时间线
```

> `hmg hook dispatch` 由宿主 hook 脚本调用（见 [集成](integration.md)），一般不需要手动运行；排查 hook 链路时可手动执行验证。

---

## store 维护

```
hmg store migrate --from <path> --to <path> [--backup] [--apply|--dry-run]
hmg store hygiene [--scope <t/w/r/b>] [--dry-run] [--force]      # 清理孤儿边/索引
hmg store repair-edges [--backup] [--apply] [--dry-run]          # 修复损坏的边
hmg verify                                                        # 图与存储完整性校验
```

---

## 密钥保险库（secret vault）

凭证不进普通记忆，存保险库：

```
hmg secret store <name> <value>     # 存入
hmg secret lookup <name>            # 查元数据（不揭示明文）
hmg secret use <name>               # 服务端授权使用
hmg secret reveal <name>            # 必要时揭示明文
hmg secret rotate <name> <new>      # 轮换
hmg secret revoke <name>            # 吊销
```

---

## 观察层（可选）

Agent 集成中不启用观察层；以下面向 CLI / 自动化管道场景：

```
hmg obs capture <content> [--source <src>]   # 捕获一条观察
hmg obs review-queue                         # 看待晋升的观察
hmg obs promote [--dry-run]                  # 晋升为长期记忆
hmg obs forget [<id>|--query <text>] [--confirm]   # 删除观察
hmg obs maintain                             # 执行保留策略清理
hmg observation config get|set <field> <value>     # 观察配置
hmg observation scheduler status|run-once          # 合并调度器
```

---

## 其他

```
hmg tui [--theme <name>] [--language <lang>]   # 终端交互界面
hmg language show|list|set <lang>|reset        # CLI 语言
hmg completions <shell>                        # shell 补全脚本
```

---

下一章：[MCP 参考](mcp-reference.md)
