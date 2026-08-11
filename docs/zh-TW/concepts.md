# 基礎概念

這一章解釋使用 HMG 需要知道的概念：記憶、原子（含作用域）、邊、召回、糾正與治理、交接與簡報。

## 記憶 {#memory}

HMG 的記憶**不是完整聊天記錄**，而是「以後會用到的資訊」：決策及理由、穩定偏好、專案約定、根因、驗證結論、已知風險、下一步待辦。

判斷原則只有一條：**這條資訊以後還會複用嗎？會影響未來決策嗎？** 會 → 值得記；只是當下產物（臨時輸出、日誌、一次性指令）→ 不該記。

詳細的適合 / 不適合對照表和寫法見 [最佳實踐](best-practices.md)。

## 原子

原子（atom）是 HMG 最小的記憶單位。每次 `memorize` 寫入的一條記憶就是一個 atom。

- 每個 atom 有**唯一 ID**：寫入時返回，後續糾正（`correct`）、治理（`govern`）、查歷史（`history`）都靠它精確定位
- 內容是一句**獨立自足的話**，例如一條決策、一個根因、一個驗證結論
- 後設資料自動附帶：建立時間、來源（`source`）、作用域（`scope`）

```bash
# 寫入後返回 atom id，記下來
hmg memorize "部署前必須先跑資料庫遷移，否則會因 schema 不一致啟動失敗" --source deploy-rule

# 用 atom id 查這條記憶的完整演變
hmg history <atom-id>
```

### 作用域 {#scope}

作用域（scope）標明一條記憶**屬於哪個上下文、在哪裡參與召回**，共四層：

```
tenant (你是誰)
  └─ workspace (哪個組織)
       └─ repository (哪個倉庫)
            └─ branch (哪個分支)
```

- **tenant**：本機使用者名稱，機器級身份，跨所有專案共享
- **workspace / repository**：通常對應 git remote 的 owner 和倉庫名
- **branch**：分支，用於隔離實驗結論和穩定決策

作用域決定召回行為。假設你在 `main` 上定了「快取用 SQLite」，在 `feature/redis-experiment` 上做實驗：

- 在 main 的會話裡召回，看到的是 SQLite 決策
- feature 分支的實驗結論不會汙染 main

#### scope 是怎麼確定的

**你不需要手動管理 scope。** HMG 從當前工作目錄實時推斷：tenant 取本機使用者名稱，workspace / repository / branch 取 git remote 和當前分支；沒有 git 時回退到目錄名。

- **Agent 整合**：scope 由會話所在目錄機械推斷並注入，agent 不傳、不會傳錯
- **CLI**：預設按當前目錄推斷，也可以用 `--scope tenant/workspace/repository/branch` 顯式指定

#### 臨時會話的共享 scope

不依附專案的會話（如 Codex 桌面端 Chats）統一共享固定 scope：

```
<本機使用者名稱> / personal / chats / main
```

不同臨時會話之間記憶互通；但臨時會話與專案會話互相隔離——臨時會話裡存的使用者偏好不會自動出現在專案會話裡，如需要，在專案會話中重新 memorize 一次。

## 邊

邊（edge）是 atom 之間的連線：糾正指向它糾正的舊記憶、交接關聯到本次任務的決策和風險、根因關聯到具體模組或檔案。

邊不需要你手動維護，它帶來的是一個直接效果：**召回時不只返回一句話，還會沿關係把相關上下文一起帶回來**——查一個 bug 能順帶帶回當時的決策、驗證和後續風險。

## 召回

召回（recall）就是用自然語言查詢過去的記憶。HMG 會從語義、關鍵詞、圖關係等多個角度同時檢索。

**query 寫法：用名詞短語、保留關鍵實體**（人名、專案名、技術名、檔名），去掉口語噪聲：

| ❌ 口語化 | ✅ 名詞短語 |
|---|---|
| 我們之前決定用什麼資料庫來著 | 資料庫選型決策 |
| 上次那個登入報錯怎麼處理的 | 登入 500 根因 |

一次召回通常夠用，不需要換著花樣反覆搜。

```bash
hmg recall "登入介面 500 的根因"

# 不確定怎麼問時，讓 HMG 推薦 query
hmg suggest-query "登入偶發 500"
```

Agent 整合中對應的 MCP 工具是 `memory_recall`，只傳 query 即可（scope 自動處理）。

## 糾正與治理 {#correct}

資訊會過期。舊資訊錯了、被替代了，**糾正它而不是追加一條新的**——追加會導致新舊並存，召回時返回過期資訊。

### correct：改內容

| 動作 | 含義 |
|------|------|
| `replace` | 用新內容替換舊記憶 |
| `confirm-actual` | 確認這條記憶是實際事實 |
| `confirm-necessary` | 確認這條記憶是必要約束 |
| `demote-possible` | 降級一條可能不再必要的記憶 |
| `negate`（MCP/SDK） | 否定並停用一條記憶 |

```bash
hmg correct <atom-id> --action replace \
  --reason "認證方案從 session cookie 改為 JWT" \
  --new-content "認證用 JWT，不用 session cookie，因為需要跨服務無狀態校驗"
```

兩點注意：

- `negate` 不可精確逆（沒有「取消否定」）；否定錯了用 `replace` 寫回正確內容
- `replace` 寫錯了就在那條 atom 上繼續 `replace`，保證任何時刻只有一條生效記憶

### govern：管生命週期

| 動作 | 含義 |
|------|------|
| `quarantine` | 隔離：召回不再出現，內容保留 |
| `seal` | 封存：僅審計可見 |
| `tombstone` | 墓碑化：邏輯刪除 |
| `derive-lesson` | 從內容提煉一條脫敏教訓，原文作廢 |

所有糾正和治理都保留審計歷史，`hmg history <atom-id>` 可查完整演變。敏感資訊誤寫的完整處理流程見 [刪除或隔離敏感資訊](daily-usage.md#sensitive-memory-governance)。

## 交接與簡報

**交接（handoff）** 是任務結束時寫給下一次會話的文件，包含五要素：做了什麼 / 為什麼 / 驗證 / 風險 / 下一步。下一次會話啟動時的簡報會優先召回它。

```bash
hmg handoff "修復登入 500: token 過期校驗改 UTC。驗證: 200 次併發無 500。風險: 舊客戶端快取 expiry。下一步: 查重新整理 token 流程。" --source bugfix-login-500
```

**簡報（agent-brief）** 是任務開始時的上下文摘要：上次交接、關鍵決策、已知問題、未完成事項。Agent 整合中它在會話啟動時自動注入；手動使用：

```bash
hmg agent-brief --query "修復登入介面偶發 500 錯誤"
```

## 觀察層（可選）

觀察（observation）是臨時記錄層：命令輸出、日誌、測試結果先進觀察層，篩選後再晉升（promote）為長期記憶，避免把所有輸出直接變成記憶造成噪聲。

> Agent 整合中**不啟用**觀察層——持久記憶只透過 agent 主動 memorize / handoff 寫入。觀察層面向 CLI 和自動化管道場景。

```bash
hmg obs review-queue        # 看待晉升的觀察
hmg obs promote             # 晉升為長期記憶
hmg obs forget --query "某條臨時記錄"
```

下一章：[日常使用指南](daily-usage.md)
