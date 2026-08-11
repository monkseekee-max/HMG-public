# FAQ

### HMG 的数据存在哪里？

存在你本机的 **store 目录**，默认 `<用户数据目录>/hmg/stores/default`。在 macOS / Linux 上通常是 `~/.local/share/hmg/stores/default`。可用 `--store <path>` 指定，或用 `hmg doctor --verbose` 查看当前实际路径。数据默认保存在本机。

store 里包含：

- 长期记忆
- 索引
- observation
- 本地运行时相关状态

默认位置和目录结构详见 [配置](settings.md#store-directory)。

### 本地数据和隐私怎么理解？

HMG 的默认工作方式是本地优先：

- 记忆、索引、observation 都保存在本机 store
- 你可以自己决定 store 放在哪个目录
- 你可以直接备份、迁移、隔离或删除 store
- 多个 Agent 共享同一个 store 时，数据边界由 scope、治理状态和本地目录共同决定

要点只有两个：

1. 普通记忆不要写 secret、token、密码、客户敏感数据。
2. 需要持久保存凭证时，用 `hmg secret store`，不要把明文写进普通记忆。

### 需要登录吗？套餐怎么生效？

不需要强制登录，基础记忆功能无需登录即可使用。如需解锁开发者版能力与更高的记忆容量上限：

- 先在官网用户中心**升级套餐**，再在本地执行 `hmg login` 登录
- 登录需要联网：HMG 向远程服务验证账号，识别套餐后返回签名，本地校验签名成功即解锁
- 登录**不迁移、不修改**本地记忆数据：本地读写永远使用本机用户名作为 tenant，账号信息只在云同步时做身份对应
- 登出或换账号只清除 store 配置里的关联账号字段，本地记忆零影响

### HMG 和聊天历史有什么区别？

聊天历史是**对话的完整流水账**，按时间堆叠，越积越乱，难检索。HMG 记忆是**未来会用到的信息**——决策、根因、约束、偏好、验证结果，结构化、可检索、可纠正、带作用域。HMG 不是「记住你说过什么」，而是「记住以后有用的东西」。

### HMG 和向量数据库有什么区别？

向量数据库只做**语义相似度检索**。HMG 在此之上提供：

- **作用域**（tenant/workspace/repository/branch），上下文隔离
- **多路检索**（语义 + 关键词 + 图关系等）
- **纠正与治理**（信息会过期，可纠正、降级、隔离、墓碑化，保留审计）
- **结构化查询**（决策追溯、风险清单、影响面分析、知识图谱探索）

简单说：向量库是「存 + 搜」，HMG 是「会过期、会纠正、带上下文的记忆系统」。

### 我需要手动写记忆吗？

大多数情况不需要。接入 Agent 后，记忆写入完全自主：Agent 在做出决策、完成交换时调 `memorize` 增量存储，任务结束时调 `handoff` 写交接，并在信息过期时用 `correct` 纠正。手动写更适合项目约定、稳定偏好、长期约束这类你想主动沉淀的信息。

### Agent 调用 HMG 时需要传 scope 吗？

不需要，也不应该传。Agent 集成中 scope 由 hooks 从会话所在目录机械推断并注入（tenant / workspace / repository / branch 四层），Agent 传了错误值会被静默纠正。手动使用 CLI 时才可能用到 `--scope`。详见 [作用域](concepts.md#scope)。

### 为什么临时会话里存的记忆，项目会话里看不到？

这是作用域隔离的设计结果。不依附项目的临时会话（如 Codex 桌面端 Chats）统一共享 `personal/chats/main` 这个 scope，与项目 scope 互相隔离。临时会话里沉淀的用户偏好如果某个项目也需要，在项目会话中重新 memorize 一次即可。

### 记忆会不会越来越多、越来越乱？

HMG 设计了多重降噪：

- **写入源头控制**：Agent 集成中持久记忆只经 memorize / handoff 两个主动通道写入，不机械捕获对话原文和命令输出
- **纠正/降级/治理**：过期信息可纠正或降级，敏感信息可治理
- **精确去重**：相同内容不会存两遍
- **store hygiene**：`hmg store hygiene` 清理孤儿边/索引
- **作用域隔离**：不同项目/分支互不污染

配合 [最佳实践](best-practices.md) 的写法，记忆会保持精炼。

### HMG 适合哪些工作流？

适合任何希望让 Agent 持续记住上下文的工作流，典型包括：

- 单人项目的长期协作
- 多会话、多天任务的连续交接
- 多仓库、多分支的经验沉淀
- 同一台机器上多个 Agent 共享长期记忆

### 可以迁移到另一台电脑吗？

可以。两种方式：

```bash
# 1. 复制 store 目录到新机器
# 2. 官方迁移命令
hmg store migrate --from /old/store --to /new/store --backup --apply
```

最简单的备份方式也是直接复制整个 store 目录。

或先 `hmg export --format json` 导出，在新机器导入。详见 [如何备份或迁移本地数据](troubleshooting.md#backup-or-migrate-local-data)。

### 敏感信息应该怎么处理？

- **不要**把 API key、token、密码写进普通记忆。
- 必须存凭证时，用 **密钥保险库（secret vault）**：`hmg secret store <name> <value>`。
- 需要查看时按需揭示：`hmg secret reveal <name>`。
- 写入时 HMG 会自动脱敏结构化的敏感信息（连接串、`password=xxx`、Bearer token、私钥块）；自然语言描述的敏感内容不会自动检测。
- 如果误把敏感信息写进普通记忆，立即治理：`hmg govern <atom-id> --action tombstone --destroy-payload --reason "误写敏感信息"`。

相关治理方式详见 [删除或隔离敏感信息](daily-usage.md#sensitive-memory-governance)。

### 可以删除记忆吗？

可以，但 HMG 推荐**治理而非物理删除**，以保留审计痕迹：

```bash
# 墓碑化（逻辑删除，可选销毁 payload）
hmg govern <atom-id> --action tombstone --destroy-payload --reason "不再需要"

# 隔离（保留但召回不出现）
hmg govern <atom-id> --action quarantine --reason "暂时不用"

# 降级（可能不再需要）
hmg correct <atom-id> --action demote-possible --reason "已不适用"
```

观察层可用 `hmg obs forget` 删除。

### 已经积累的历史对话和记忆文件能导入 HMG 吗？

可以。对 Agent 说「导入记忆至 HMG」（`hmg-memory-import` skill），它会扫描历史对话与宿主原生记忆文件，提取有长期价值的条目，按项目 / 个人分类并确认后批量写入。详见 [导入已有记忆](integration.md#importing-existing-memories)。
