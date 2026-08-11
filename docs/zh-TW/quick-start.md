---
sidebar_position: 2
---

# 快速上手

## 安裝 HMG

HMG 以獨立二進位制分發，透過官方安裝器安裝。安裝器會自動檢測平臺、安裝到預設目錄並配置 PATH。

### macOS / Linux 安裝

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```

### Windows 安裝

```powershell
irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex
```

### 驗證安裝

```bash
hmg version
# 預期輸出類似: hmg 1.7.8-developer
```

### 升級

```bash

# 升級到最新版（已安裝後用此命令）
hmg update

# 如需指定安裝源, 可指定 installer-url
hmg update --installer-url <官方安裝包URL>
```

### 解除安裝

解除安裝請刪除安裝目錄並清理 PATH 中的條目。store 資料不會自動刪除（保留你的記憶），如需徹底清理，手動刪除 store 目錄。

> 安裝失敗？見 [安裝失敗](troubleshooting.md#install-failure)。

## 登入與套餐（可選）

HMG 的基礎記憶能力無需登入即可使用。如需解鎖開發者版功能與更高的記憶容量上限：

1. 在 HMG 官網使用者中心**升級套餐**
2. 在本地執行登入：

```bash
hmg login
```

登入需要聯網：HMG 向遠端服務驗證你的賬號，識別套餐資訊並返回簽名，本地校驗簽名成功後解鎖對應能力。

- 登入**不做任何資料遷移**：本地讀寫永遠使用本機使用者名稱作為租戶標識（tenant），賬號資訊只用於雲同步等場景的身份對應
- 登出或更換賬號隻影響雲側身份，本地記憶零影響

## 啟動本地 HMG

首次安裝後，先讓 HMG 準備本地執行時。`setup` 會處理 daemon、嵌入模型和本地執行所需的基礎元件。

### 準備執行時

```bash
# 預覽 setup 會做什麼
hmg setup --dry-run

# 實際準備本地執行時
hmg setup
```

### 確認啟動成功

```bash
hmg doctor
```

`doctor` 會檢查核心、store、整合和執行時狀態。第一次通常會提示某些 Agent 尚未接入，屬正常。

### 接入 Agent

如果你希望 Codex、Cursor、Claude Code 在日常對話裡自動管理記憶，下一步執行：

```bash
hmg init --agent codex --dry-run
```

然後根據你實際使用的 Agent 執行 `hmg init --agent <agent-id>`。詳細接入方式見 [整合](integration.md)。

---

## 寫入、召回、修正記憶

HMG 的記憶操作就三條核心命令：寫入、召回、修正。下面用最簡單的例子走一遍。

### 1. 寫入記憶

```bash
hmg memorize "本專案本地快取用 SQLite，不引入 Redis，因為離線優先" --source quick-start
```

寫成一句獨立自足的話即可：不需要「決定：」之類的字首，HMG 會自動推斷它的確定性、極性等後設資料。輸出會返回 atom id（記憶的唯一標識），形如 `atom-xxxx`，記住它，下一步修正會用到。

### 2. 召回記憶

```bash
hmg recall "本地快取用什麼"
```

如果召回結果裡出現剛才寫入的「SQLite 快取」，說明寫入和召回鏈路已打通。

### 3. 修正記憶

當發現舊記憶有誤或需要更新時，用 `correct` 糾正而非追加一條新的：

```bash
# 把剛才寫入的記憶內容替換為新的描述
hmg correct atom-xxxx --action replace --reason "改用 LevelDB" --new-content "本專案本地快取用 LevelDB，不引入 Redis，因為離線優先"
```

再次 `hmg recall "本地快取用什麼"` 會返回更新後的內容。

> Agent 接入後，這三步會由 Agent 在合適的時機自動完成，無需手動操作。接入方式見 [整合](integration.md)。

---

下一章：[日常使用指南](daily-usage.md)
