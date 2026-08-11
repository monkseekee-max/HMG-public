---
sidebar_position: 1
---

# CLI 參考

HMG 的全部能力均可透過 `hmg` 命令列訪問。本文按類別列出公開命令的用法；與 Agent 會話內工具的對應關係見 [MCP 參考](mcp-reference.md)。

## 全域性選項

多數命令支援：

| 選項 | 說明 |
|---|---|
| `--store <path>` | 指定 store 目錄（預設 `~/.local/share/hmg/stores/default`） |
| `--scope <tenant/workspace/repository/branch>` | 顯式指定作用域；不傳時按當前目錄推斷 |
| `--format text\|json\|yaml` | 輸出格式 |
| `--direct` | 繞過 daemon，直接在程序內開啟 store |
| `--dry-run` | 預覽將要做出的變更，不實際執行 |

執行 `hmg help <command>` 檢視單個命令的示例，`hmg help commands` 檢視完整命令清單。

## 命令總覽

| 類別 | 命令 |
|---|---|
| 記憶讀寫 | `memorize`、`recall`、`correct`、`govern`、`history`、`stats`、`export` |
| 任務上下文 | `agent-brief`、`handoff` |
| 查詢 | `query`、`suggest-query`、`query-templates`、`explain-query`、`schema`、`recall-view`、`noise-feedback`、`panorama`、`impact` |
| 安裝與接入 | `setup`、`init`、`doctor`、`login`、`account status`、`onboard`、`integrations`、`update`、`uninstall` |
| 執行時 | `daemon`、`model`、`hook`、`agent-event`、`agent-timeline` |
| store 維護 | `store migrate`、`store hygiene`、`store repair-edges`、`verify` |
| 金鑰保險庫 | `secret store / lookup / use / reveal / rotate / revoke` |
| 觀察層 | `obs capture / promote / forget / maintain / review-queue`、`observation config / scheduler` |
| 其他 | `tui`、`version`、`language`、`completions` |

---

## 記憶讀寫

### hmg memorize

寫入一條長期記憶。

```
hmg memorize <content> [--source <src>] [--scope <t/w/r/b>] [--file <path>] [--dry-run]
```

| 引數 | 說明 |
|---|---|
| `--source` | 來源歸屬（如 `user`、`cli`、自定義標籤） |
| `--file` | 從檔案讀取內容（內容含引號/多行時使用） |

```bash
hmg memorize "本專案用 PostgreSQL 16 做主資料庫，不用 MongoDB" --source cli
```

> 相同內容不會重複寫入（返回已有 atom）。scope 不傳時按當前目錄推斷。

### hmg recall

按自然語言召回記憶。

```
hmg recall <query> [--max-results <n>] [--profile compact|summary|full|debug]
                   [--scope <t/w/r/b>] [--include-negated] [--precision]
```

```bash
hmg recall "資料庫選型決策"
hmg recall "登入 500 根因" --profile full
```

| 引數 | 說明 |
|---|---|
| `--profile` | 輸出詳略：`compact`（預設）/ `summary` / `full`（含邊）/ `debug`（含檢索診斷） |
| `--include-negated` | 包含已被否定的記憶（檢視「曾經以為對」的資訊） |
| `--precision` | 更嚴格的召回門控 |

### hmg correct

糾正一條記憶。

```
hmg correct <atom_id> --action <action> --reason <text> [--new-content <text>]
```

`--action` 取值：`replace` / `confirm-actual` / `confirm-necessary` / `demote-possible`。

```bash
hmg correct 01J9ZK8... --action replace \
  --reason "v3 已遷移到 PostgreSQL" \
  --new-content "主資料庫用 PostgreSQL 16，替換原 MongoDB 方案"
```

> 否定一條記憶請用 `govern quarantine`（CLI 層）；MCP/SDK 層對應 `negate`。`negate` 不可精確逆，恢復用 `replace`。

### hmg govern

治理一條記憶的生命週期。

```
hmg govern <atom_id> --action <action> --reason <text> [--lesson <text>] [--destroy-payload]
```

`--action` 取值：`quarantine` / `seal` / `tombstone` / `derive-lesson`。

```bash
# 誤寫敏感資訊：徹底清除
hmg govern 01J9ZK8... --action tombstone --destroy-payload --reason "誤寫 API key"

# 提煉脫敏教訓，原文作廢
hmg govern 01J9ZK8... --action derive-lesson --reason "原文含金鑰" \
  --lesson "憑證應存 secret vault，不進普通記憶"
```

### hmg history / stats / export

```
hmg history <atom_id>          # 一條記憶的完整糾正/治理演變
hmg stats                      # atom / edge / 索引 / 快照版本統計
hmg export [--format json|csv] [--output <path>]   # 匯出全部 atom 和 edge
```

---

## 任務上下文

### hmg agent-brief

任務開始時的上下文摘要（上次交接、關鍵決策、已知問題、未完成事項）。

```
hmg agent-brief [<query>] [--profile compact|summary|full|debug] [--scope <t/w/r/b>]
```

```bash
hmg agent-brief --query "修復登入介面偶發 500"
```

> Agent 整合中簡報由 SessionStart hook 自動注入，無需手動呼叫。

### hmg handoff

任務結束時寫入交接摘要（下次會話啟動簡報優先召回）。

```
hmg handoff <summary> [--source <src>] [--scope <t/w/r/b>]
```

```bash
hmg handoff "修復登入 500: token 過期校驗改 UTC。驗證: 200 次併發無 500。風險: 舊客戶端快取 expiry。下一步: 查重新整理 token 流程。"
```

> 建議覆蓋五要素：做了什麼 / 為什麼 / 驗證 / 風險 / 下一步。

---

## 查詢

| 命令 | 用途 |
|---|---|
| `hmg query <intent-task> <query-text>` | 按結構化查詢模板執行（如決策追溯） |
| `hmg query --sql <sql>` | 只讀 MemoryQL 查詢（高階） |
| `hmg query-templates` | 列出可用的查詢模板 |
| `hmg suggest-query <text>` | 讓 HMG 推薦該怎麼問 |
| `hmg explain-query` | 解釋查詢計劃 |
| `hmg schema` | 檢視 MemoryQL 邏輯 schema |
| `hmg recall-view <query> --view <id>` | 透過命名檢視召回（normal / governance / audit） |
| `hmg noise-feedback <content>` | 反饋噪聲短語，檢索時降權 |
| `hmg panorama <query>` | 探索更廣的圖上下文 |
| `hmg impact <query>` | 評估一個變更的影響面 |

```bash
hmg query-templates                 # 先看有哪些模板
hmg query <intent-task> "快取選型決策"
hmg noise-feedback "npm install 成功"
```

---

## 安裝與接入

### hmg setup / init / doctor

```
hmg setup [--dry-run] [--no-daemon] [--no-model] [--no-agent-adapters]
hmg init [--global] [--agent <id>] [--all-agents] [--dry-run]
hmg doctor [--agent <id>] [--all-agents] [--fix] [--live-tool-smoke] [--verbose]
```

| 命令 | 職責 |
|---|---|
| `setup` | 準備本地執行時（daemon、嵌入模型） |
| `init` | 寫入 Agent 接入配置（MCP、hooks、記憶策略檔案）。`--dry-run` 預覽 |
| `doctor` | 體檢：核心 / store / 整合 / 執行時；`--fix` 自動修復可修復項 |

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

基礎記憶功能無需登入。在官網使用者中心升級套餐後，執行 `hmg login` 聯網驗證賬號並解鎖對應能力與容量。登入不遷移本地資料，tenant 始終是本機使用者名稱。

### hmg onboard

匯入已有的 agent 記憶並驗證真實召回。

```
hmg onboard [--import <file>] [--memory-path <path>] [--all] [--dry-run] [--non-interactive]
```

> 對 Agent 說「匯入記憶至 HMG」（`hmg-memory-import` skill）走的是對話式匯入；`hmg onboard` 是 CLI 直接匯入。

### 其他

```
hmg update [--installer-url <url>]    # 升級
hmg uninstall [--purge-data]          # 解除安裝（預設保留 store 資料）
hmg integrations list|detect|explain|remove   # Agent 整合管理
hmg version                           # 版本與 edition
```

---

## 執行時

```
hmg daemon start|status|stop|restart [--store <path>]
hmg daemon install-service            # 安裝為使用者服務（自啟動）
hmg model status                      # 嵌入模型狀態
```

hooks 與事件橋接：

```
hmg hook dispatch --host <id> --event <name> [--payload <json>]   # 宿主 hook 的統一入口
hmg hook status [--host <id>] [--session-id <id>]                 # 會話與回執診斷（無正文）
hmg agent-event --payload <json> [--explain] [--dry-run]          # 外部 agent 生命週期事件橋接
hmg agent-timeline --event-id <id>                                # 查詢持久化的 agent 時間線
```

> `hmg hook dispatch` 由宿主 hook 指令碼呼叫（見 [整合](integration.md)），一般不需要手動執行；排查 hook 鏈路時可手動執行驗證。

---

## store 維護

```
hmg store migrate --from <path> --to <path> [--backup] [--apply|--dry-run]
hmg store hygiene [--scope <t/w/r/b>] [--dry-run] [--force]      # 清理孤兒邊/索引
hmg store repair-edges [--backup] [--apply] [--dry-run]          # 修復損壞的邊
hmg verify                                                        # 圖與儲存完整性校驗
```

---

## 金鑰保險庫（secret vault）

憑證不進普通記憶，存保險庫：

```
hmg secret store <name> <value>     # 存入
hmg secret lookup <name>            # 查後設資料（不揭示明文）
hmg secret use <name>               # 服務端授權使用
hmg secret reveal <name>            # 必要時揭示明文
hmg secret rotate <name> <new>      # 輪換
hmg secret revoke <name>            # 吊銷
```

---

## 觀察層（可選）

Agent 整合中不啟用觀察層；以下面向 CLI / 自動化管道場景：

```
hmg obs capture <content> [--source <src>]   # 捕獲一條觀察
hmg obs review-queue                         # 看待晉升的觀察
hmg obs promote [--dry-run]                  # 晉升為長期記憶
hmg obs forget [<id>|--query <text>] [--confirm]   # 刪除觀察
hmg obs maintain                             # 執行保留策略清理
hmg observation config get|set <field> <value>     # 觀察配置
hmg observation scheduler status|run-once          # 合併排程器
```

---

## 其他

```
hmg tui [--theme <name>] [--language <lang>]   # 終端互動介面
hmg language show|list|set <lang>|reset        # CLI 語言
hmg completions <shell>                        # shell 補全指令碼
```

---

下一章：[MCP 參考](mcp-reference.md)
