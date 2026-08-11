# 基础概念

这一章解释使用 HMG 需要知道的概念：记忆、原子（含作用域）、边、召回、纠正与治理、交接与简报。

## 记忆 {#memory}

HMG 的记忆**不是完整聊天记录**，而是「以后会用到的信息」：决策及理由、稳定偏好、项目约定、根因、验证结论、已知风险、下一步待办。

判断原则只有一条：**这条信息以后还会复用吗？会影响未来决策吗？** 会 → 值得记；只是当下产物（临时输出、日志、一次性指令）→ 不该记。

详细的适合 / 不适合对照表和写法见 [最佳实践](best-practices.md)。

## 原子

原子（atom）是 HMG 最小的记忆单位。每次 `memorize` 写入的一条记忆就是一个 atom。

- 每个 atom 有**唯一 ID**：写入时返回，后续纠正（`correct`）、治理（`govern`）、查历史（`history`）都靠它精确定位
- 内容是一句**独立自足的话**，例如一条决策、一个根因、一个验证结论
- 元数据自动附带：创建时间、来源（`source`）、作用域（`scope`）

```bash
# 写入后返回 atom id，记下来
hmg memorize "部署前必须先跑数据库迁移，否则会因 schema 不一致启动失败" --source deploy-rule

# 用 atom id 查这条记忆的完整演变
hmg history <atom-id>
```

### 作用域 {#scope}

作用域（scope）标明一条记忆**属于哪个上下文、在哪里参与召回**，共四层：

```
tenant (你是谁)
  └─ workspace (哪个组织)
       └─ repository (哪个仓库)
            └─ branch (哪个分支)
```

- **tenant**：本机用户名，机器级身份，跨所有项目共享
- **workspace / repository**：通常对应 git remote 的 owner 和仓库名
- **branch**：分支，用于隔离实验结论和稳定决策

作用域决定召回行为。假设你在 `main` 上定了「缓存用 SQLite」，在 `feature/redis-experiment` 上做实验：

- 在 main 的会话里召回，看到的是 SQLite 决策
- feature 分支的实验结论不会污染 main

#### scope 是怎么确定的

**你不需要手动管理 scope。** HMG 从当前工作目录实时推断：tenant 取本机用户名，workspace / repository / branch 取 git remote 和当前分支；没有 git 时回退到目录名。

- **Agent 集成**：scope 由会话所在目录机械推断并注入，agent 不传、不会传错
- **CLI**：默认按当前目录推断，也可以用 `--scope tenant/workspace/repository/branch` 显式指定

#### 临时会话的共享 scope

不依附项目的会话（如 Codex 桌面端 Chats）统一共享固定 scope：

```
<本机用户名> / personal / chats / main
```

不同临时会话之间记忆互通；但临时会话与项目会话互相隔离——临时会话里存的用户偏好不会自动出现在项目会话里，如需要，在项目会话中重新 memorize 一次。

## 边

边（edge）是 atom 之间的连接：纠正指向它纠正的旧记忆、交接关联到本次任务的决策和风险、根因关联到具体模块或文件。

边不需要你手动维护，它带来的是一个直接效果：**召回时不只返回一句话，还会沿关系把相关上下文一起带回来**——查一个 bug 能顺带带回当时的决策、验证和后续风险。

## 召回

召回（recall）就是用自然语言查找过去的记忆。HMG 会从语义、关键词、图关系等多个角度同时检索。

**query 写法：用名词短语、保留关键实体**（人名、项目名、技术名、文件名），去掉口语噪声：

| ❌ 口语化 | ✅ 名词短语 |
|---|---|
| 我们之前决定用什么数据库来着 | 数据库选型决策 |
| 上次那个登录报错怎么处理的 | 登录 500 根因 |

一次召回通常够用，不需要换着花样反复搜。

```bash
hmg recall "登录接口 500 的根因"

# 不确定怎么问时，让 HMG 推荐 query
hmg suggest-query "登录偶发 500"
```

Agent 集成中对应的 MCP 工具是 `memory_recall`，只传 query 即可（scope 自动处理）。

## 纠正与治理 {#correct}

信息会过期。旧信息错了、被替代了，**纠正它而不是追加一条新的**——追加会导致新旧并存，召回时返回过期信息。

### correct：改内容

| 动作 | 含义 |
|------|------|
| `replace` | 用新内容替换旧记忆 |
| `confirm-actual` | 确认这条记忆是实际事实 |
| `confirm-necessary` | 确认这条记忆是必要约束 |
| `demote-possible` | 降级一条可能不再必要的记忆 |
| `negate`（MCP/SDK） | 否定并停用一条记忆 |

```bash
hmg correct <atom-id> --action replace \
  --reason "认证方案从 session cookie 改为 JWT" \
  --new-content "认证用 JWT，不用 session cookie，因为需要跨服务无状态校验"
```

两点注意：

- `negate` 不可精确逆（没有「取消否定」）；否定错了用 `replace` 写回正确内容
- `replace` 写错了就在那条 atom 上继续 `replace`，保证任何时刻只有一条生效记忆

### govern：管生命周期

| 动作 | 含义 |
|------|------|
| `quarantine` | 隔离：召回不再出现，内容保留 |
| `seal` | 封存：仅审计可见 |
| `tombstone` | 墓碑化：逻辑删除 |
| `derive-lesson` | 从内容提炼一条脱敏教训，原文作废 |

所有纠正和治理都保留审计历史，`hmg history <atom-id>` 可查完整演变。敏感信息误写的完整处理流程见 [删除或隔离敏感信息](daily-usage.md#sensitive-memory-governance)。

## 交接与简报

**交接（handoff）** 是任务结束时写给下一次会话的文档，包含五要素：做了什么 / 为什么 / 验证 / 风险 / 下一步。下一次会话启动时的简报会优先召回它。

```bash
hmg handoff "修复登录 500: token 过期校验改 UTC。验证: 200 次并发无 500。风险: 旧客户端缓存 expiry。下一步: 查刷新 token 流程。" --source bugfix-login-500
```

**简报（agent-brief）** 是任务开始时的上下文摘要：上次交接、关键决策、已知问题、未完成事项。Agent 集成中它在会话启动时自动注入；手动使用：

```bash
hmg agent-brief --query "修复登录接口偶发 500 错误"
```

## 观察层（可选）

观察（observation）是临时记录层：命令输出、日志、测试结果先进观察层，筛选后再晋升（promote）为长期记忆，避免把所有输出直接变成记忆造成噪声。

> Agent 集成中**不启用**观察层——持久记忆只通过 agent 主动 memorize / handoff 写入。观察层面向 CLI 和自动化管道场景。

```bash
hmg obs review-queue        # 看待晋升的观察
hmg obs promote             # 晋升为长期记忆
hmg obs forget --query "某条临时记录"
```

下一章：[日常使用指南](daily-usage.md)
