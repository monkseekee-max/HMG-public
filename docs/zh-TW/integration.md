# 整合

HMG 支援透過 MCP 協議和宿主原生 hooks 接入各類 Agent。本章描述 2026 年 8 月整合層設計確定後的接入形態。

## 整合後會得到什麼

完成接入後，Agent 在日常對話裡會自動進行精準的記憶管理，不需要你每次手動提醒“記住這個”或“先回憶一下歷史上下文”。

具體來說：

- **會話啟動時**，Agent 自動收到一份記憶簡報：上次交接、關鍵決策、已知風險、下一步。
- **每輪對話時**，Agent 自動用你的訊息預取相關記憶，補充到當前上下文。
- **作用域自動隔離**：專案 / 倉庫 / 分支由會話所在目錄機械推斷並注入，Agent 不傳、不會傳錯。
- **寫入完全自主**：Agent 在做出決策、完成交換時自動調 `memorize` 增量儲存；任務結束時調 `handoff` 寫交接。
- 當新資訊與舊記憶衝突時，Agent 會修正過期或錯誤的記憶（`correct`），而不是沿用舊結論。

這意味著 Agent 不再只依賴當前會話上下文，而是從此具備了可持續積累、可按需召回的長期記憶能力。同一個專案聊得越久，Agent 越瞭解你的程式碼庫、約定和偏好。

## 工作機制

整合層由三部分組成：

1. **MCP server**：Agent 透過 MCP 工具讀寫記憶（`memory_memorize` / `memory_recall` / `memory_correct` / `memory_govern` / `memory_handoff` / `memory_stats`）。
2. **生命週期 hooks（3 個）**：在固定時機自動注入上下文或校準引數。

   | Hook | 時機 | 職責 |
   |---|---|---|
   | `SessionStart` | 會話啟動 / 恢復 / 清理 / 壓縮後 | 輸出記憶簡報 + 狀態行 |
   | `UserPromptSubmit` | 每輪使用者訊息 | 用訊息預取相關記憶；必要時提醒 Agent 儲存 |
   | `PreToolUse` | Agent 呼叫 HMG MCP 工具前 | 從會話目錄推斷 scope，機械注入工具入參 |

3. **記憶策略檔案**（`hmg.md` / rules / CLAUDE.md 注入）：指導 Agent 何時自主搜尋、何時儲存、如何判斷來源、如何處理敏感資訊。

設計上有兩條硬性約定：

- **記憶寫入只有兩個通道**：`memorize`（增量）和 `handoff`（交接）。沒有機械兜底——規則打分無法判斷「這段對話裡隱含了一個重要決策」，持久記憶完全依賴 Agent 主動性。
- **observation 管道不啟用**：Agent 整合中不做原始對話/命令輸出的機械捕獲，避免低質量記憶汙染。

## 通用接入流程

```bash
# 1. 準備本地執行時
hmg setup

# 2. 預覽某個 Agent 會寫入哪些檔案
hmg init --agent codex --dry-run

# 3. 實際寫入配置
hmg init --agent codex

# 4. 檢查接入狀態
hmg doctor --agent codex
```

`hmg init` 是當前推薦入口。它會按不同宿主寫入對應的 MCP 配置、memory policy 和 lifecycle hooks。手動配置時應直接使用 `hmg-server`。

## 接入 Codex

Codex 的接入形態是：

- `~/.codex/config.toml`：註冊 `hmg` MCP server
- `~/.codex/hooks.json`：註冊 3 個生命週期 hooks
- `~/.codex/hooks/hmg-lifecycle.sh`：瘦介面卡，把宿主事件透傳給 `hmg hook dispatch`（所有邏輯在 HMG 二進位制內部）
- `~/.codex/hmg.md`：注入自主記憶策略

### 預覽配置

```bash
hmg init --agent codex --dry-run
```

### 應用配置

```bash
hmg init --global --agent codex

# 或僅更新當前專案上下文關聯的配置
hmg init --agent codex
```

### MCP 配置示例

`hmg init` 會自動寫入。形態類似：

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

> 不要給 `mcp_servers.hmg` 配置固定的 `cwd`：MCP server 子程序需要繼承會話的工作目錄，HMG 依賴它推斷 scope。

### hooks 行為

- **SessionStart**：HMG 組裝記憶簡報（最近交接、關鍵決策）+ 狀態行（`HMG Active | scope=... | atoms=N`），作為上下文注入會話。
- **UserPromptSubmit**：用本輪使用者訊息作為 query 做一次預取召回；命中則 Agent 直接使用，未命中時 Agent 可按策略自主追加搜尋。
- **PreToolUse**：Agent 呼叫任何 `mcp__hmg__*` 工具前，從會話目錄推斷 scope 並注入入參。Agent 傳了錯誤的 scope 會被靜默糾正。

### 驗證

```bash
hmg doctor --agent codex
hmg doctor --agent codex --live-tool-smoke
```

接入成功後，Codex 會列出 `memory_memorize`、`memory_recall`、`memory_correct`、`memory_govern`、`memory_handoff`、`memory_stats` 等 HMG 工具。

## 接入 Cursor

Cursor 的接入檔案通常位於當前專案目錄下：

- `.cursor/mcp.json`
- `.cursor/rules/hmg-memory.mdc`
- `.cursor/hooks.json`
- `.cursor/hooks/hmg-lifecycle.sh`

### 預覽與應用

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

Cursor 的 hook 事件名與 Codex 不同（方言差異），適配層會自動對映：

| Codex 事件 | Cursor 事件 |
|---|---|
| `SessionStart` | `sessionStart` |
| `UserPromptSubmit` | `beforeSubmitPrompt` |
| `PreToolUse` | `preToolUse` |

`.cursor/rules/hmg-memory.mdc` 注入記憶使用規則，職責與 Codex 的 `hmg.md` 相同。

### 驗證

```bash
hmg doctor --agent cursor
```

詳見 [Agent 看不到 HMG 工具](troubleshooting.md#agent-cant-see-hmg-tools)。

## 接入 Claude Code

Claude Code 的接入檔案通常包括：

- 當前專案下的 `.mcp.json`
- 當前專案下的 `CLAUDE.md`
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

Claude Code 的 hook 事件名與 Codex 完全一致（`SessionStart` / `UserPromptSubmit` / `PreToolUse`），配置寫在 `~/.claude/settings.json` 的 hooks 段。行為與 Codex 相同：啟動簡報、每輪預取、scope 機械注入。

### 驗證

```bash
hmg doctor --agent claude
```

## 臨時會話的記憶歸屬

Codex 桌面端左下角 Chats 開啟的臨時會話不依附任何專案。這類會話統一共享固定 scope：

```
<本機使用者名稱> / personal / chats / main
```

- 不同臨時會話之間記憶互通（不會因會話目錄不同而互相隔離）
- 臨時會話與專案會話互相隔離：在臨時會話裡存的使用者偏好，在專案會話裡不會自動出現；如需要，在專案會話中重新 memorize 一次

## 匯入已有記憶 {#importing-existing-memories}

如果你在使用 HMG 之前已經積累了歷史對話或宿主原生記憶檔案（Codex memories、CLAUDE.md、Cursor rules 等），可以用 `hmg-memory-import` skill 一次性匯入：

對 Agent 說「**匯入記憶至 HMG**」，它會：

1. 掃描歷史對話和原生記憶檔案，提取有長期價值的條目
2. 按歸屬分類：專案相關 → 當前專案 scope；跨專案使用者偏好 → `personal/chats/main`
3. 列出清單供你確認後逐條寫入，並彙報結果

該 skill 位於 `~/.codex/skills/hmg-memory-import/`（或 Claude Code 的 `~/.claude/skills/`），隨 HMG 發行。

## 接入其他 MCP 客戶端

HMG 支援的 Agent 不止上面三個。檢視當前版本支援列表：

```bash
hmg integrations list
hmg integrations detect
hmg integrations explain codex cursor claude
```

### 通用 MCP 接入方法

任何相容 MCP 的客戶端都可以手動接入，但仍然優先推薦 `hmg init` 自動生成配置。

1. 在客戶端的 MCP 配置裡新增 server：
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
2. 如需指定 store 或 daemon 形態，在環境變數裡補充 `HMG_DATA_DIR`、`HMG_USE_LOCAL_DAEMON=1`。
3. 驗證客戶端能列出 `memory_memorize`、`memory_recall`、`memory_correct`、`memory_handoff` 等工具。

沒有 hooks 能力的宿主也能用：MCP 讀寫完全可用，scope 由 HMG 從 MCP server 程序的工作目錄推斷；只是少了會話啟動簡報和每輪預取這兩個自動注入點。

### 外部事件橋接

對不方便直接接 MCP 的宿主，也可以透過 lifecycle bridge 對接：

```bash
hmg agent-event --explain --payload '{"event":"pre_edit_recall","files":["src/lib.rs"]}'
```

---

下一章：[故障排查](troubleshooting.md)
