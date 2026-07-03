# HMG 常见问题

## 一般问题

### HMG 是什么？

HMG（Holographic Memory Graph）是一个面向 AI Agent 的长期记忆内核。它让 Agent 能够在会话之间存储决策、追溯修正历史、治理敏感知识。

### HMG 和向量数据库有什么区别？

向量数据库只存储和检索嵌入向量。HMG 将记忆建模为**有类型图谱**，包含：
- 极性（肯定/否定/条件）
- 认知状态（可能/实际/必然）
- 治理暴露状态
- 修正谱系

这意味着 HMG 不仅仅是"搜索"，还能理解记忆之间的**关系**。

### HMG 是开源的吗？

**协议层是开源的**（Apache-2.0）：`hmg-protocol` crate 定义了记忆原子、修正、治理和范围的类型。任何兼容实现都可以使用。

**二进制文件**以免费 Community Edition 发布，遵循自定义许可（类似 Docker Desktop 模式）。

### 数据存在哪里？

数据完全在你的本地机器上。HMG 使用 嵌入式存储引擎。不需要外部数据库、不需要云服务。离线可用。

### 支持 Windows 吗？

目前支持 Linux (x86_64/ARM64) 和 macOS (Intel/Apple Silicon)。Windows 支持计划在后续版本中推出。

## Community Edition

### Community Edition 是免费的吗？

是的，完全免费。不需要 license key，不需要注册。100,000 记忆原子、5 Agent/实例、全部 48 个 MCP 工具。

### 100,000 原子够用吗？

对于个人使用足够了：
- 轻度使用（每天 50 条）：约 2.7 年
- 中度使用（每天 200 条）：约 8 个月
- 重度使用（每天 500 条）：约 3 个月

超过限制时，你可以升级到 Developer Edition（无限原子）。

### Community 缺少什么？

Community Edition 不包含：
- One-Shot Recall（一键完整上下文）
- 观察捕获与自动提升
- 向量语义搜索
- Consolidation 自动化
- 域包

这些功能需要 Developer ($12/月) 或 Enterprise 版本。

## 安装与使用

### 如何安装？

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```

安装脚本自动检测你的操作系统和 CPU 架构。

### 如何连接我的 Agent？

```bash
hmg init --agent codex    # Claude Code
hmg init --agent cursor   # Cursor
hmg init --agent pi       # Pi
```

或手动配置 MCP 服务器。

### 如何升级到 Developer？

```bash
hmg license apply <your-license-key>
```

同一个二进制文件，不需要重新安装。参见 [升级指南](upgrade.md)。

## 技术问题

### HMG 用什么语言写的？

Rust。全部。性能关键、内存安全、零 GC 暂停。

### MCP 是什么？

MCP (Model Context Protocol) 是一个开放标准，让 AI 工具能与外部系统交互。HMG 实现了完整的 MCP 服务端，提供 8 个标准工具。

### 记忆是如何检索的？

HMG 使用混合检索：
1. 关键词索引匹配
2. 图谱扩散投影
3. 确定性、认知状态、治理状态和时效性重排
4. 范围过滤

Community Edition 使用关键词索引。Developer/Enterprise 额外提供向量语义搜索。

### 修正会删除旧记忆吗？

不会。HMG 使用**只追加修正**。当你修正一个记忆时，原始记忆保留，修正历史永久记录。你可以随时追溯任何决策的完整变更链。
