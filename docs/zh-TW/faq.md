# FAQ

### HMG 的資料存在哪裡？

存在你本機的 **store 目錄**，預設 `<使用者資料目錄>/hmg/stores/default`。在 macOS / Linux 上通常是 `~/.local/share/hmg/stores/default`。可用 `--store <path>` 指定，或用 `hmg doctor --verbose` 檢視當前實際路徑。資料預設儲存在本機。

store 裡包含：

- 長期記憶
- 索引
- observation
- 本地執行時相關狀態

預設位置和目錄結構詳見 [配置](settings.md#store-directory)。

### 本地資料和隱私怎麼理解？

HMG 的預設工作方式是本地優先：

- 記憶、索引、observation 都儲存在本機 store
- 你可以自己決定 store 放在哪個目錄
- 你可以直接備份、遷移、隔離或刪除 store
- 多個 Agent 共享同一個 store 時，資料邊界由 scope、治理狀態和本地目錄共同決定

要點只有兩個：

1. 普通記憶不要寫 secret、token、密碼、客戶敏感資料。
2. 需要持久儲存憑證時，用 `hmg secret store`，不要把明文寫進普通記憶。

### 需要登入嗎？套餐怎麼生效？

不需要強制登入，基礎記憶功能無需登入即可使用。如需解鎖開發者版能力與更高的記憶容量上限：

- 先在官網使用者中心**升級套餐**，再在本地執行 `hmg login` 登入
- 登入需要聯網：HMG 向遠端服務驗證賬號，識別套餐後返回簽名，本地校驗簽名成功即解鎖
- 登入**不遷移、不修改**本地記憶資料：本地讀寫永遠使用本機使用者名稱作為 tenant，賬號資訊只在雲同步時做身份對應
- 登出或換賬號只清除 store 配置裡的關聯賬號欄位，本地記憶零影響

### HMG 和聊天曆史有什麼區別？

聊天曆史是**對話的完整流水賬**，按時間堆疊，越積越亂，難檢索。HMG 記憶是**未來會用到的資訊**——決策、根因、約束、偏好、驗證結果，結構化、可檢索、可糾正、帶作用域。HMG 不是「記住你說過什麼」，而是「記住以後有用的東西」。

### HMG 和向量資料庫有什麼區別？

向量資料庫只做**語義相似度檢索**。HMG 在此之上提供：

- **作用域**（tenant/workspace/repository/branch），上下文隔離
- **多路檢索**（語義 + 關鍵詞 + 圖關係等）
- **糾正與治理**（資訊會過期，可糾正、降級、隔離、墓碑化，保留審計）
- **結構化查詢**（決策追溯、風險清單、影響面分析、知識圖譜探索）

簡單說：向量庫是「存 + 搜」，HMG 是「會過期、會糾正、帶上下文的記憶系統」。

### 我需要手動寫記憶嗎？

大多數情況不需要。接入 Agent 後，記憶寫入完全自主：Agent 在做出決策、完成交換時調 `memorize` 增量儲存，任務結束時調 `handoff` 寫交接，並在資訊過期時用 `correct` 糾正。手動寫更適合專案約定、穩定偏好、長期約束這類你想主動沉澱的資訊。

### Agent 呼叫 HMG 時需要傳 scope 嗎？

不需要，也不應該傳。Agent 整合中 scope 由 hooks 從會話所在目錄機械推斷並注入（tenant / workspace / repository / branch 四層），Agent 傳了錯誤值會被靜默糾正。手動使用 CLI 時才可能用到 `--scope`。詳見 [作用域](concepts.md#scope)。

### 為什麼臨時會話裡存的記憶，專案會話裡看不到？

這是作用域隔離的設計結果。不依附專案的臨時會話（如 Codex 桌面端 Chats）統一共享 `personal/chats/main` 這個 scope，與專案 scope 互相隔離。臨時會話裡沉澱的使用者偏好如果某個專案也需要，在專案會話中重新 memorize 一次即可。

### 記憶會不會越來越多、越來越亂？

HMG 設計了多重降噪：

- **寫入源頭控制**：Agent 整合中持久記憶只經 memorize / handoff 兩個主動通道寫入，不機械捕獲對話原文和命令輸出
- **糾正/降級/治理**：過期資訊可糾正或降級，敏感資訊可治理
- **精確去重**：相同內容不會存兩遍
- **store hygiene**：`hmg store hygiene` 清理孤兒邊/索引
- **作用域隔離**：不同專案/分支互不汙染

配合 [最佳實踐](best-practices.md) 的寫法，記憶會保持精煉。

### HMG 適合哪些工作流？

適合任何希望讓 Agent 持續記住上下文的工作流，典型包括：

- 單人專案的長期協作
- 多會話、多天任務的連續交接
- 多倉庫、多分支的經驗沉澱
- 同一臺機器上多個 Agent 共享長期記憶

### 可以遷移到另一臺電腦嗎？

可以。兩種方式：

```bash
# 1. 複製 store 目錄到新機器
# 2. 官方遷移命令
hmg store migrate --from /old/store --to /new/store --backup --apply
```

最簡單的備份方式也是直接複製整個 store 目錄。

或先 `hmg export --format json` 匯出，在新機器匯入。詳見 [如何備份或遷移本地資料](troubleshooting.md#backup-or-migrate-local-data)。

### 敏感資訊應該怎麼處理？

- **不要**把 API key、token、密碼寫進普通記憶。
- 必須存憑證時，用 **金鑰保險庫（secret vault）**：`hmg secret store <name> <value>`。
- 需要檢視時按需揭示：`hmg secret reveal <name>`。
- 寫入時 HMG 會自動脫敏結構化的敏感資訊（連線串、`password=xxx`、Bearer token、私鑰塊）；自然語言描述的敏感內容不會自動檢測。
- 如果誤把敏感資訊寫進普通記憶，立即治理：`hmg govern <atom-id> --action tombstone --destroy-payload --reason "誤寫敏感資訊"`。

相關治理方式詳見 [刪除或隔離敏感資訊](daily-usage.md#sensitive-memory-governance)。

### 可以刪除記憶嗎？

可以，但 HMG 推薦**治理而非物理刪除**，以保留審計痕跡：

```bash
# 墓碑化（邏輯刪除，可選銷燬 payload）
hmg govern <atom-id> --action tombstone --destroy-payload --reason "不再需要"

# 隔離（保留但召回不出現）
hmg govern <atom-id> --action quarantine --reason "暫時不用"

# 降級（可能不再需要）
hmg correct <atom-id> --action demote-possible --reason "已不適用"
```

觀察層可用 `hmg obs forget` 刪除。

### 已經積累的歷史對話和記憶檔案能匯入 HMG 嗎？

可以。對 Agent 說「匯入記憶至 HMG」（`hmg-memory-import` skill），它會掃描歷史對話與宿主原生記憶檔案，提取有長期價值的條目，按專案 / 個人分類並確認後批次寫入。詳見 [匯入已有記憶](integration.md#importing-existing-memories)。
