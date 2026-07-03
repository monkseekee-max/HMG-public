# HMG 快速開始

## 前提條件

- Linux (x86_64 或 ARM64) 或 macOS (Intel 或 Apple Silicon)
- 支援 MCP (Model Context Protocol) 的 AI Agent 或編碼工具

## 安裝

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```

### Windows (PowerShell)

```powershell
irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex
```

### WSL (Windows Subsystem for Linux)

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```


或者直接從 [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases) 下載：

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/
```

## 驗證

```bash
hmg --version
# hmg 1.7.1-community
```

## 啟動記憶服務

```bash
hmg daemon start
```

守護行程預設在 `~/.local/share/hmg/stores/default` 啟動本地 MCP 伺服器。
資料不會離開你的機器。

## 連接你的 Agent

### Cursor

```bash
hmg init --agent cursor
# 重新啟動 Cursor。HMG 工具會出現在 MCP 設定中。
```

### Claude Code (Codex)

```bash
hmg init --agent codex
```

### Pi

```bash
hmg init --agent pi
```

### 通用 MCP 用戶端

HMG 透過標準輸入輸出暴露標準 MCP 伺服器。設定你的用戶端：

```json
{
  "mcpServers": {
    "hmg": {
      "command": "hmg-server",
      "args": ["~/.local/share/hmg/stores/default"]
    }
  }
}
```

## 第一個記憶

使用任意 MCP 工具儲存和檢索記憶：

```json
// 儲存一個決策
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "決策：使用 PostgreSQL 儲存使用者資料。理由：ACID 合規和成熟的工具鏈。",
    "source": "architecture-review",
    "modality": "text"
  }
}

// 之後檢索
{
  "tool": "memory_recall",
  "arguments": {
    "query": "我們選了什麼資料庫？"
  }
}
```

## Community Edition 可用功能

| 功能 | 可用 |
|---|---|
| 記憶儲存 (memorize) | ✅ |
| 記憶檢索 (recall) | ✅ 基礎關鍵詞搜尋 |
| 修正生命週期 | ✅ 完整 |
| 治理生命週期 | ✅ 完整 |
| MCP 協議 | ✅ 完整 |
| HTTP API | ✅ 完整 |
| Agent 整合 | ✅ 所有適配器 |
| One-Shot Recall | ✅ Full (P1-P9) |
| 自動化整合 | ❌ Developer/Enterprise |
| 域包 (Domain Packs) | ❌ Developer/Enterprise |
| 語義（向量）搜尋 | ❌ Developer/Enterprise |

## 下一步

- [概念](concepts.md) — 理解記憶原子、修正、治理、範圍
- [架構](architecture.md) — HMG 的高層運作原理
- [API 參考](api-reference.md) — 所有 MCP 工具和 HTTP 端點
- [修正與治理](correction-governance.md)
- [常見問題](faq.md)
- [升級到 Developer](upgrade.md)
