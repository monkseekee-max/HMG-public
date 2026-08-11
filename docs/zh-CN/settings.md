# 配置

## 配置文件说明

HMG 涉及的配置主要分为三类：Agent 集成文件、store 数据目录、运行时环境变量。这里只列用户真正会碰到的部分。

| 文件 | 作用 | 谁生成 |
|------|------|--------|
| `~/.codex/config.toml` / `.cursor/mcp.json` / `.mcp.json` | 告诉宿主如何启动 HMG MCP server | `hmg init --agent <id>` |
| `~/.codex/hooks.json` / `.cursor/hooks.json` / `~/.claude/settings.json` | 宿主生命周期 hooks（SessionStart / UserPromptSubmit / PreToolUse 三个） | `hmg init --agent <id>` |
| `AGENTS.md` / `CLAUDE.md` / `.cursor/rules/hmg-memory.mdc` | Agent 的 memory policy 与使用约定 | `hmg init --agent <id>` |
| store 目录 | 数据本体（记忆/索引/观察） | 自动创建 |

### store path

- 默认 store：`<用户数据目录>/hmg/stores/default`
  - macOS/Linux：`~/.local/share/hmg/stores/default`
  - Windows：通常为 `%LOCALAPPDATA%\hmg\stores\default`
- 用 `--store <path>` 指定任意 store。
- 多数命令支持 `--store`，如 `hmg memorize "..." --store /my/store`。

### 身份与登录（store.toml）

store 目录下的 `store.toml` 记录本机身份：

```toml
# ~/.local/share/hmg/stores/default/store.toml

[identity]
local_tenant = "qiankun"              # 本机用户名，hmg init 时写入，永不变
linked_account = "userB"              # hmg login 登录后写入，登出时清除
linked_at = "2026-07-28T10:00:00Z"    # 登录时间
```

- **local_tenant**：所有记忆的 tenant（scope 第一层）都用它，`hmg init` 时取本机用户名写入，之后不变。
- **linked_account**：在官网升级套餐后执行 `hmg login` 登录写入的 HMG 用户中心账号。登录**不做任何数据迁移**——本地读写永远用 `local_tenant`，账号映射只在云同步时使用。
- 登出 / 换账号：只清除 `linked_account`，本地记忆零影响。

### 环境变量

见 [常用环境变量](#common-env-vars)。

## Store 目录说明 {#store-directory}
store 是 HMG 数据的根目录。

### 默认位置

见上文。`hmg doctor --verbose` 会打印实际使用的 data directory，优先以该输出为准。

### 项目 store 怎么选

- **默认 store + 作用域**：靠 repository/branch 区分项目（Agent 集成默认如此，scope 从会话目录自动推断），适合不想多目录管理。
- **项目独立 store**：`--store /path/to/proj`，物理隔离，避免污染，推荐多项目。

### 备份迁移

```bash
# 方法 1: 直接复制 store 目录
cp -r /old/store /backup/store

# 方法 2: 官方迁移 (带备份)
hmg store migrate --from /old/store --to /new/store --backup --apply

# 先 dry-run 预览
hmg store migrate --from /old/store --to /new/store --dry-run
```

### 维护命令

```bash
# 清理孤儿边/索引
hmg store hygiene --dry-run
hmg store hygiene

# 修复损坏的边
hmg store repair-edges --dry-run
hmg store repair-edges --backup --apply
```

## 常用环境变量 {#common-env-vars}
只列本地常用项。

| 变量 | 作用 |
|------|------|
| `HMG_STORE` | 默认 store 路径 |
| `HMG_DATA_DIR` | 当前宿主使用的数据目录 |
| `HMG_PROVIDER_BACKEND` | 当前 provider backend，常见为 `local` |
| `HMG_USE_LOCAL_DAEMON` | 是否优先走本地 daemon |
| `HMG_CONSOLIDATION_SCHEDULER` | 观察合并调度器（如 `embedded`，仅 observation 场景） |
| `HMG_CAPTURE_MODE` | 观察捕获模式（如 `raw-with-retention`） |
| `HMG_PROMOTION_MODE` | 观察晋升模式（如 `execute`） |
| `HMG_AUTOMATION_TIER` | 自动化等级（如 `remember-first-govern-later`） |
| `HMG_AGENT_ID` | 当前宿主标识，如 `codex` / `cursor` / `claude` |
| `HMG_HTTP_ADDR` | 启用 HTTP fallback 时的本地地址 |

### observation 配置查看与调度

> observation 管道在 Agent 集成中不激活（持久记忆由 agent 主动 memorize/handoff 写入）。以下命令面向手动 / 自动化管道场景。

```bash
hmg observation config get
hmg observation config set capture_mode raw-with-retention
hmg observation scheduler status
hmg observation scheduler run-once
```
