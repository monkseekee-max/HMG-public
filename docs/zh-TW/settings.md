# 配置

## 配置檔案說明

HMG 涉及的配置主要分為三類：Agent 整合檔案、store 資料目錄、執行時環境變數。這裡只列使用者真正會碰到的部分。

| 檔案 | 作用 | 誰生成 |
|------|------|--------|
| `~/.codex/config.toml` / `.cursor/mcp.json` / `.mcp.json` | 告訴宿主如何啟動 HMG MCP server | `hmg init --agent <id>` |
| `~/.codex/hooks.json` / `.cursor/hooks.json` / `~/.claude/settings.json` | 宿主生命週期 hooks（SessionStart / UserPromptSubmit / PreToolUse 三個） | `hmg init --agent <id>` |
| `AGENTS.md` / `CLAUDE.md` / `.cursor/rules/hmg-memory.mdc` | Agent 的 memory policy 與使用約定 | `hmg init --agent <id>` |
| store 目錄 | 資料本體（記憶/索引/觀察） | 自動建立 |

### store path

- 預設 store：`<使用者資料目錄>/hmg/stores/default`
  - macOS/Linux：`~/.local/share/hmg/stores/default`
  - Windows：通常為 `%LOCALAPPDATA%\hmg\stores\default`
- 用 `--store <path>` 指定任意 store。
- 多數命令支援 `--store`，如 `hmg memorize "..." --store /my/store`。

### 身份與登入（store.toml）

store 目錄下的 `store.toml` 記錄本機身份：

```toml
# ~/.local/share/hmg/stores/default/store.toml

[identity]
local_tenant = "qiankun"              # 本機使用者名稱，hmg init 時寫入，永不變
linked_account = "userB"              # hmg login 登入後寫入，登出時清除
linked_at = "2026-07-28T10:00:00Z"    # 登入時間
```

- **local_tenant**：所有記憶的 tenant（scope 第一層）都用它，`hmg init` 時取本機使用者名稱寫入，之後不變。
- **linked_account**：在官網升級套餐後執行 `hmg login` 登入寫入的 HMG 使用者中心賬號。登入**不做任何資料遷移**——本地讀寫永遠用 `local_tenant`，賬號對映只在雲同步時使用。
- 登出 / 換賬號：只清除 `linked_account`，本地記憶零影響。

### 環境變數

見 [常用環境變數](#common-env-vars)。

## Store 目錄說明 {#store-directory}
store 是 HMG 資料的根目錄。

### 預設位置

見上文。`hmg doctor --verbose` 會列印實際使用的 data directory，優先以該輸出為準。

### 專案 store 怎麼選

- **預設 store + 作用域**：靠 repository/branch 區分專案（Agent 整合預設如此，scope 從會話目錄自動推斷），適合不想多目錄管理。
- **專案獨立 store**：`--store /path/to/proj`，物理隔離，避免汙染，推薦多專案。

### 備份遷移

```bash
# 方法 1: 直接複製 store 目錄
cp -r /old/store /backup/store

# 方法 2: 官方遷移 (帶備份)
hmg store migrate --from /old/store --to /new/store --backup --apply

# 先 dry-run 預覽
hmg store migrate --from /old/store --to /new/store --dry-run
```

### 維護命令

```bash
# 清理孤兒邊/索引
hmg store hygiene --dry-run
hmg store hygiene

# 修復損壞的邊
hmg store repair-edges --dry-run
hmg store repair-edges --backup --apply
```

## 常用環境變數 {#common-env-vars}
只列本地常用項。

| 變數 | 作用 |
|------|------|
| `HMG_STORE` | 預設 store 路徑 |
| `HMG_DATA_DIR` | 當前宿主使用的資料目錄 |
| `HMG_PROVIDER_BACKEND` | 當前 provider backend，常見為 `local` |
| `HMG_USE_LOCAL_DAEMON` | 是否優先走本地 daemon |
| `HMG_CONSOLIDATION_SCHEDULER` | 觀察合併排程器（如 `embedded`，僅 observation 場景） |
| `HMG_CAPTURE_MODE` | 觀察捕獲模式（如 `raw-with-retention`） |
| `HMG_PROMOTION_MODE` | 觀察晉升模式（如 `execute`） |
| `HMG_AUTOMATION_TIER` | 自動化等級（如 `remember-first-govern-later`） |
| `HMG_AGENT_ID` | 當前宿主標識，如 `codex` / `cursor` / `claude` |
| `HMG_HTTP_ADDR` | 啟用 HTTP fallback 時的本地地址 |

### observation 配置檢視與排程

> observation 管道在 Agent 整合中不啟用（持久記憶由 agent 主動 memorize/handoff 寫入）。以下命令面向手動 / 自動化管道場景。

```bash
hmg observation config get
hmg observation config set capture_mode raw-with-retention
hmg observation scheduler status
hmg observation scheduler run-once
```
