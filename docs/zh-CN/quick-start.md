---
sidebar_position: 2
---

# 快速上手

## 安装 HMG

HMG 以独立二进制分发，通过官方安装器安装。安装器会自动检测平台、安装到默认目录并配置 PATH。

### macOS / Linux 安装

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```

### Windows 安装

```powershell
irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex
```

### 验证安装

```bash
hmg version
# 预期输出类似: hmg 1.7.8-developer
```

### 升级

```bash

# 升级到最新版（已安装后用此命令）
hmg update

# 如需指定安装源, 可指定 installer-url
hmg update --installer-url <官方安装包URL>
```

### 卸载

卸载请删除安装目录并清理 PATH 中的条目。store 数据不会自动删除（保留你的记忆），如需彻底清理，手动删除 store 目录。

> 安装失败？见 [安装失败](troubleshooting.md#install-failure)。

## 登录与套餐（可选）

HMG 的基础记忆能力无需登录即可使用。如需解锁开发者版功能与更高的记忆容量上限：

1. 在 HMG 官网用户中心**升级套餐**
2. 在本地执行登录：

```bash
hmg login
```

登录需要联网：HMG 向远程服务验证你的账号，识别套餐信息并返回签名，本地校验签名成功后解锁对应能力。

- 登录**不做任何数据迁移**：本地读写永远使用本机用户名作为租户标识（tenant），账号信息只用于云同步等场景的身份对应
- 登出或更换账号只影响云侧身份，本地记忆零影响

## 启动本地 HMG

首次安装后，先让 HMG 准备本地运行时。`setup` 会处理 daemon、嵌入模型和本地运行所需的基础组件。

### 准备运行时

```bash
# 预览 setup 会做什么
hmg setup --dry-run

# 实际准备本地运行时
hmg setup
```

### 确认启动成功

```bash
hmg doctor
```

`doctor` 会检查核心、store、集成和运行时状态。第一次通常会提示某些 Agent 尚未接入，属正常。

### 接入 Agent

如果你希望 Codex、Cursor、Claude Code 在日常对话里自动管理记忆，下一步执行：

```bash
hmg init --agent codex --dry-run
```

然后根据你实际使用的 Agent 执行 `hmg init --agent <agent-id>`。详细接入方式见 [集成](integration.md)。

---

## 写入、召回、修正记忆

HMG 的记忆操作就三条核心命令：写入、召回、修正。下面用最简单的例子走一遍。

### 1. 写入记忆

```bash
hmg memorize "本项目本地缓存用 SQLite，不引入 Redis，因为离线优先" --source quick-start
```

写成一句独立自足的话即可：不需要「决定：」之类的前缀，HMG 会自动推断它的确定性、极性等元数据。输出会返回 atom id（记忆的唯一标识），形如 `atom-xxxx`，记住它，下一步修正会用到。

### 2. 召回记忆

```bash
hmg recall "本地缓存用什么"
```

如果召回结果里出现刚才写入的「SQLite 缓存」，说明写入和召回链路已打通。

### 3. 修正记忆

当发现旧记忆有误或需要更新时，用 `correct` 纠正而非追加一条新的：

```bash
# 把刚才写入的记忆内容替换为新的描述
hmg correct atom-xxxx --action replace --reason "改用 LevelDB" --new-content "本项目本地缓存用 LevelDB，不引入 Redis，因为离线优先"
```

再次 `hmg recall "本地缓存用什么"` 会返回更新后的内容。

> Agent 接入后，这三步会由 Agent 在合适的时机自动完成，无需手动操作。接入方式见 [集成](integration.md)。

---

下一章：[日常使用指南](daily-usage.md)
