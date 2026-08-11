# 集成

HMG 支持通过 MCP 协议和宿主原生 hooks 接入各类 Agent。本章描述 2026 年 8 月集成层设计确定后的接入形态。

## 集成后会得到什么

完成接入后，Agent 在日常对话里会自动进行精准的记忆管理，不需要你每次手动提醒“记住这个”或“先回忆一下历史上下文”。

具体来说：

- **会话启动时**，Agent 自动收到一份记忆简报：上次交接、关键决策、已知风险、下一步。
- **每轮对话时**，Agent 自动用你的消息预取相关记忆，补充到当前上下文。
- **作用域自动隔离**：项目 / 仓库 / 分支由会话所在目录机械推断并注入，Agent 不传、不会传错。
- **写入完全自主**：Agent 在做出决策、完成交换时自动调 `memorize` 增量存储；任务结束时调 `handoff` 写交接。
- 当新信息与旧记忆冲突时，Agent 会修正过期或错误的记忆（`correct`），而不是沿用旧结论。

这意味着 Agent 不再只依赖当前会话上下文，而是从此具备了可持续积累、可按需召回的长期记忆能力。同一个项目聊得越久，Agent 越了解你的代码库、约定和偏好。

## 工作机制

集成层由三部分组成：

1. **MCP server**：Agent 通过 MCP 工具读写记忆（`memory_memorize` / `memory_recall` / `memory_correct` / `memory_govern` / `memory_handoff` / `memory_stats`）。
2. **生命周期 hooks（3 个）**：在固定时机自动注入上下文或校准参数。

   | Hook | 时机 | 职责 |
   |---|---|---|
   | `SessionStart` | 会话启动 / 恢复 / 清理 / 压缩后 | 输出记忆简报 + 状态行 |
   | `UserPromptSubmit` | 每轮用户消息 | 用消息预取相关记忆；必要时提醒 Agent 存储 |
   | `PreToolUse` | Agent 调用 HMG MCP 工具前 | 从会话目录推断 scope，机械注入工具入参 |

3. **记忆策略文件**（`hmg.md` / rules / CLAUDE.md 注入）：指导 Agent 何时自主搜索、何时存储、如何判断来源、如何处理敏感信息。

设计上有两条硬性约定：

- **记忆写入只有两个通道**：`memorize`（增量）和 `handoff`（交接）。没有机械兜底——规则打分无法判断「这段对话里隐含了一个重要决策」，持久记忆完全依赖 Agent 主动性。
- **observation 管道不激活**：Agent 集成中不做原始对话/命令输出的机械捕获，避免低质量记忆污染。

## 通用接入流程

```bash
# 1. 准备本地运行时
hmg setup

# 2. 预览某个 Agent 会写入哪些文件
hmg init --agent codex --dry-run

# 3. 实际写入配置
hmg init --agent codex

# 4. 检查接入状态
hmg doctor --agent codex
```

`hmg init` 是当前推荐入口。它会按不同宿主写入对应的 MCP 配置、memory policy 和 lifecycle hooks。手动配置时应直接使用 `hmg-server`。

## 接入 Codex

Codex 的接入形态是：

- `~/.codex/config.toml`：注册 `hmg` MCP server
- `~/.codex/hooks.json`：注册 3 个生命周期 hooks
- `~/.codex/hooks/hmg-lifecycle.sh`：瘦适配器，把宿主事件透传给 `hmg hook dispatch`（所有逻辑在 HMG 二进制内部）
- `~/.codex/hmg.md`：注入自主记忆策略

### 预览配置

```bash
hmg init --agent codex --dry-run
```

### 应用配置

```bash
hmg init --global --agent codex

# 或仅更新当前项目上下文关联的配置
hmg init --agent codex
```

### MCP 配置示例

`hmg init` 会自动写入。形态类似：

```toml
[mcp_servers.hmg]
type = "stdio"
command = "/Users/<user>/.local/bin/hmg-server"
args = ["/Users/<user>/.local/share/hmg/stores/default"]
startup_timeout_sec = 30

[mcp_servers.hmg.env]
HMG_PROVIDER_BACKEND = "local"
HMG_USE_LOCAL_DAEMON = "1"
```

> 不要给 `mcp_servers.hmg` 配置固定的 `cwd`：MCP server 子进程需要继承会话的工作目录，HMG 依赖它推断 scope。

### hooks 行为

- **SessionStart**：HMG 组装记忆简报（最近交接、关键决策）+ 状态行（`HMG Active | scope=... | atoms=N`），作为上下文注入会话。
- **UserPromptSubmit**：用本轮用户消息作为 query 做一次预取召回；命中则 Agent 直接使用，未命中时 Agent 可按策略自主追加搜索。
- **PreToolUse**：Agent 调用任何 `mcp__hmg__*` 工具前，从会话目录推断 scope 并注入入参。Agent 传了错误的 scope 会被静默纠正。

### 验证

```bash
hmg doctor --agent codex
hmg doctor --agent codex --live-tool-smoke
```

接入成功后，Codex 会列出 `memory_memorize`、`memory_recall`、`memory_correct`、`memory_govern`、`memory_handoff`、`memory_stats` 等 HMG 工具。

## 接入 Cursor

Cursor 的接入文件通常位于当前项目目录下：

- `.cursor/mcp.json`
- `.cursor/rules/hmg-memory.mdc`
- `.cursor/hooks.json`
- `.cursor/hooks/hmg-lifecycle.sh`

### 预览与应用

```bash
hmg init --agent cursor --dry-run
hmg init --agent cursor
```

### MCP 配置示例

```json
{
  "mcpServers": {
    "hmg": {
      "command": "/Users/<user>/.local/bin/hmg-server",
      "args": ["/Users/<user>/.local/share/hmg/stores/default"],
      "env": {
        "HMG_DATA_DIR": "/Users/<user>/.local/share/hmg/stores/default",
        "HMG_PROVIDER_BACKEND": "local",
        "HMG_USE_LOCAL_DAEMON": "1"
      }
    }
  }
}
```

Cursor 的 hook 事件名与 Codex 不同（方言差异），适配层会自动映射：

| Codex 事件 | Cursor 事件 |
|---|---|
| `SessionStart` | `sessionStart` |
| `UserPromptSubmit` | `beforeSubmitPrompt` |
| `PreToolUse` | `preToolUse` |

`.cursor/rules/hmg-memory.mdc` 注入记忆使用规则，职责与 Codex 的 `hmg.md` 相同。

### 验证

```bash
hmg doctor --agent cursor
```

详见 [Agent 看不到 HMG 工具](troubleshooting.md#agent-cant-see-hmg-tools)。

## 接入 Claude Code

Claude Code 的接入文件通常包括：

- 当前项目下的 `.mcp.json`
- 当前项目下的 `CLAUDE.md`
- `~/.claude/settings.json`
- `~/.claude/hooks/hmg-lifecycle.sh`

### 配置

```bash
hmg init --agent claude --dry-run
hmg init --agent claude
```

### MCP 配置示例

```json
{
  "mcpServers": {
    "hmg": {
      "command": "/Users/<user>/.local/bin/hmg-server",
      "args": ["/Users/<user>/.local/share/hmg/stores/default"],
      "env": {
        "HMG_DATA_DIR": "/Users/<user>/.local/share/hmg/stores/default",
        "HMG_PROVIDER_BACKEND": "local",
        "HMG_USE_LOCAL_DAEMON": "1"
      }
    }
  }
}
```

Claude Code 的 hook 事件名与 Codex 完全一致（`SessionStart` / `UserPromptSubmit` / `PreToolUse`），配置写在 `~/.claude/settings.json` 的 hooks 段。行为与 Codex 相同：启动简报、每轮预取、scope 机械注入。

### 验证

```bash
hmg doctor --agent claude
```

## 临时会话的记忆归属

Codex 桌面端左下角 Chats 开启的临时会话不依附任何项目。这类会话统一共享固定 scope：

```
<本机用户名> / personal / chats / main
```

- 不同临时会话之间记忆互通（不会因会话目录不同而互相隔离）
- 临时会话与项目会话互相隔离：在临时会话里存的用户偏好，在项目会话里不会自动出现；如需要，在项目会话中重新 memorize 一次

## 导入已有记忆 {#importing-existing-memories}

如果你在使用 HMG 之前已经积累了历史对话或宿主原生记忆文件（Codex memories、CLAUDE.md、Cursor rules 等），可以用 `hmg-memory-import` skill 一次性导入：

对 Agent 说「**导入记忆至 HMG**」，它会：

1. 扫描历史对话和原生记忆文件，提取有长期价值的条目
2. 按归属分类：项目相关 → 当前项目 scope；跨项目用户偏好 → `personal/chats/main`
3. 列出清单供你确认后逐条写入，并汇报结果

该 skill 位于 `~/.codex/skills/hmg-memory-import/`（或 Claude Code 的 `~/.claude/skills/`），随 HMG 发行。

## 接入其他 MCP 客户端

HMG 支持的 Agent 不止上面三个。查看当前版本支持列表：

```bash
hmg integrations list
hmg integrations detect
hmg integrations explain codex cursor claude
```

### 通用 MCP 接入方法

任何兼容 MCP 的客户端都可以手动接入，但仍然优先推荐 `hmg init` 自动生成配置。

1. 在客户端的 MCP 配置里添加 server：
   ```json
   {
     "mcpServers": {
       "hmg": {
         "command": "/Users/<user>/.local/bin/hmg-server",
         "args": ["/Users/<user>/.local/share/hmg/stores/default"]
       }
     }
   }
   ```
2. 如需指定 store 或 daemon 形态，在环境变量里补充 `HMG_DATA_DIR`、`HMG_USE_LOCAL_DAEMON=1`。
3. 验证客户端能列出 `memory_memorize`、`memory_recall`、`memory_correct`、`memory_handoff` 等工具。

没有 hooks 能力的宿主也能用：MCP 读写完全可用，scope 由 HMG 从 MCP server 进程的工作目录推断；只是少了会话启动简报和每轮预取这两个自动注入点。

### 外部事件桥接

对不方便直接接 MCP 的宿主，也可以通过 lifecycle bridge 对接：

```bash
hmg agent-event --explain --payload '{"event":"pre_edit_recall","files":["src/lib.rs"]}'
```

---

下一章：[故障排查](troubleshooting.md)
