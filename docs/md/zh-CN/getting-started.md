# HMG 快速开始

## 前提条件

- Linux (x86_64 或 ARM64) 或 macOS (Intel 或 Apple Silicon)
- 支持 MCP (Model Context Protocol) 的 AI Agent 或编码工具

## 安装

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


或者直接从 [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases) 下载：

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/
```

## 验证

```bash
hmg --version
# hmg 1.7.1-community
```

## 启动记忆服务

```bash
hmg daemon start
```

守护进程默认在 `~/.local/share/hmg/stores/default` 启动本地 MCP 服务器。
数据不会离开你的机器。

## 连接你的 Agent

### Cursor

```bash
hmg init --agent cursor
# 重启 Cursor。HMG 工具出现在 MCP 设置中。
```

### Claude Code (Codex)

```bash
hmg init --agent codex
```

### Pi

```bash
hmg init --agent pi
```

### 通用 MCP 客户端

HMG 通过标准输入输出暴露标准 MCP 服务器。配置你的客户端运行：

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

## 第一个记忆

使用任意 MCP 工具存储和检索记忆：

```json
// 存储一个决策
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "决策：使用 PostgreSQL 存储用户数据。理由：ACID 合规和成熟的工具链。",
    "source": "architecture-review",
    "modality": "text"
  }
}

// 之后检索
{
  "tool": "memory_recall",
  "arguments": {
    "query": "我们选了什么数据库？"
  }
}
```

## Community Edition 可用功能

| 功能 | 可用 |
|---|---|
| 记忆存储 (memorize) | ✅ |
| 记忆检索 (recall) | ✅ 基础关键词搜索 |
| 修正生命周期 | ✅ 完整 |
| 治理生命周期 | ✅ 完整 |
| MCP 协议 | ✅ 完整 |
| HTTP API | ✅ 完整 |
| Agent 集成 | ✅ 所有适配器 |
| One-Shot Recall | ✅ Full (P1-P9) |
| 自动化整合 | ❌ Developer/Enterprise |
| 域包 (Domain Packs) | ❌ Developer/Enterprise |
| 语义（向量）搜索 | ❌ Developer/Enterprise |

## 下一步

- [概念](concepts.md) — 理解记忆原子、修正、治理、范围
- [架构](architecture.md) — HMG 的高层工作原理
- [API 参考](api-reference.md) — 所有 MCP 工具和 HTTP 端点
- [修正与治理](correction-governance.md)
- [常见问题](faq.md)
- [升级到 Developer](upgrade.md)
