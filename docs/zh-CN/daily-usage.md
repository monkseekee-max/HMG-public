# 日常使用指南

HMG 是一个本地记忆系统。它让你的 AI agent 拥有跨会话的记忆——这次对话里决定的事，下次对话还能想起来。

这篇指南用一个完整的项目场景，带你走一遍 HMG 的核心操作。示例用 TypeScript SDK 书写；习惯命令行的话每个操作都有对应的 `hmg` 命令（见 [CLI 参考](cli-reference.md)），接入 Agent 后这些操作大多由 agent 自动完成，你只需要看思路。

---

## 从"记住一件事"开始

你正在做一个新项目。团队刚开完会，定了一个技术决策。你希望 agent 记住这件事，下次不用再说一遍。

```typescript
const result = await client.memorize({
  content: "项目用 PostgreSQL 16 做主数据库，不用 MongoDB",
});

console.log(result.atom_id);  // "01HKX2ABCDEF..."
console.log(result.effect);   // "applied"
```

就这样。一条记忆存进去了。HMG 把它叫做一个 **atom**——记忆的最小单元。

你不需要告诉 HMG 这条记忆"有多确定"、"是正面还是负面"——它自己会从文本里推断。你只管写自然语言。

### 如果重复存了呢？

```typescript
await client.memorize({ content: "项目用 PostgreSQL 16 做主数据库，不用 MongoDB" });
// → effect: "no_op"（去重命中，不会创建第二条）
```

HMG 会自动去重。同样的内容不会存两遍。

---

## 记住了，然后怎么找回来？

三天后，新会话。你问 agent："我们数据库用的什么来着？"

agent 内部会调用 recall：

```typescript
const result = await client.recall({
  query: "数据库选型",
});

// result.atoms:
// [
//   {
//     atom_id: "01HKX2ABCDEF...",
//     content: "项目用 PostgreSQL 16 做主数据库，不用 MongoDB",
//     score: 0.92,
//     created_at: "2026-07-25T14:00:00Z",
//     source: "user"
//   }
// ]
```

query 用**名词短语**效果最好。"数据库选型"比"我们之前决定用什么数据库来着"好得多。

### 作用域：记忆属于哪里？

每条记忆自动绑定到一个 scope（tenant / workspace / repository / branch）。你通常不需要手动传——HMG 从当前工作目录的 git 信息自动推断。

在 `mem0ai/mem0` 仓库的 `main` 分支下存的记忆，默认只在这个 scope 下被召回。切到另一个项目，不会看到无关的记忆。

---

## 记忆过时了怎么办？

两个月后，项目升级了数据库版本。之前那条记忆还写着"PostgreSQL 16"，但你们已经升到了 17。

### 推荐做法：replace

```typescript
await client.correct({
  target_atom: "01HKX2ABCDEF...",
  action: "replace",
  reason: "已升级到 PostgreSQL 17",
  new_content: "项目用 PostgreSQL 17 做主数据库",
});
// → result.new_atom_id: "01NEW..."
```

一步完成。旧 atom 保留（通过 Supersedes 边关联新 atom），搜索时只返回新版本。

三个月后你查 `history("01NEW...")`，能看到：这条记忆是从"PostgreSQL 16"那条升级来的，升级原因是"已升级到 PostgreSQL 17"。审计链完整。

### 什么时候不用 replace，只用 negate？

 negate 适合"这件事不再成立，且没有替代品"的场景。

比如半年后，你们彻底放弃了 MongoDB 相关的缓存方案：

```typescript
// 之前存过一条："用 MongoDB 做会话缓存"
// 现在这个方案整个废弃了，没有"新版本"，就是不用了
await client.correct({
  target_atom: "01MONGO...",
  action: "negate",
  reason: "MongoDB 缓存方案已废弃，改用 Redis",
});
```

negate 之后，这条记忆从默认搜索中消失。agent 不会再看到它。

注意：negate 不是把文本改成"不用 MongoDB"。它标记"这条记忆不再有效"，原文不变，只是不再被召回。

### 怎么判断用哪个？

| 情况 | 用什么 | 例子 |
|---|---|---|
| 同一件事有了新版本 | `replace` | "用 PostgreSQL 16" → "用 PostgreSQL 17" |
| 决定本身变了（不是确认，是改主意了） | `replace` | "考虑用 K8s" → "决定用 ECS 部署" |
| 这件事作废了，没有替代品 | `negate` | "用 MongoDB 做缓存" → 整个废弃 |
| 内容没变，从"听说"变成"确认属实" | `confirm_actual` | "API 网关用 Kong"（之前不确定，现在在配置里确认了） |
| 内容没变，从"事实"升级为"硬约束" | `confirm_necessary` | "所有 API 必须加认证"（从团队惯例升级为安全合规要求） |
| 内容没变，但从"已定"降为"还在评估" | `demote` | "用 K8s 部署"（之前以为定了，其实还没定） |

一句话：**内容要变就 replace，只是确定性变了就 confirm/demote，彻底作废就 negate。**

注意 `confirm_actual` 不改内容——它确认的是"content 里写的这件事是属实的"。如果决定本身变了（从"考虑 X"变成"用 Y"），那是内容变了，应该用 replace。

### 确定性等级（epistemic）

每条记忆有一个确定性等级，confirm/demote 改的就是它：

```
possible  →  "可能为真"（听说、在评估、不确定）
actual    →  "已确认为真"（验证过、确认了）
necessary →  "必须为真"（硬约束、合规要求、不可违反）
```

各动作的方向：

```
possible ──confirm_actual──→ actual ──confirm_necessary──→ necessary
    ↑                          |                               |
    └──────────── demote ──────┘                               |
    ↑                                                          |
    └──────────────────── demote ──────────────────────────────┘
```

注意事项：

- `demote` 是直接降到最低（possible），不是降一级。necessary 被 demote 后变成 possible，不是 actual。
- `confirm_actual` 只能升级，不能用在已经是 necessary 的 atom 上（会报错）。
- 想让 necessary 变成 actual？没有一步到位的方式。得先 `demote`（降到 possible），再 `confirm_actual`（升到 actual）。
- `confirm_actual` 和 `demote` 在 possible ↔ actual 之间是可逆的一对。但涉及 necessary 时不可逆（demote 会跳过 actual 直接到 possible）。

### correct 会丢失信息吗？

不会。correct 永远不销毁内容。旧 atom 不会被删除，你通过 history 随时能看到它。

但 negate 和 replace 没有"一键撤销"。操作错了，用下面的方式恢复：

### 操作错了怎么恢复？

没有 "un-negate" 也没有 "undo replace"。统一的恢复方式是：**在那条有问题的 atom 上继续 replace**。

**negate 错了**：你 negate 了"用 MongoDB 做缓存"，以为废弃了。一周后发现其实还在用。

```typescript
await client.correct({
  target_atom: "01MONGO...",  // 那条被 negate 的 atom
  action: "replace",
  reason: "negate 有误，MongoDB 缓存仍在使用",
  new_content: "用 MongoDB 做会话缓存，仍在使用",
});
```

**replace 错了**：昨天 replace 了"用 PG 16" → "用 PG 17"。今天发现升级取消了，还是 16。

```typescript
await client.correct({
  target_atom: "01NEW...",  // 那条错误的 "用 PG 17"
  action: "replace",
  reason: "升级取消，回退到 16",
  new_content: "项目用 PostgreSQL 16 做主数据库",
});
```

为什么不用 memorize 新的？因为 replace 会在旧 atom 和新 atom 之间建立 Supersedes 边，保证任何时刻只有一条 active 记忆。如果用 memorize，被 negate 或被取代的旧 atom 可能仍然残留在 recall 结果里，和新记忆产生矛盾。

审计链也完整：每一步都有 reason，history 可追溯完整演变过程。

---

## 有些记忆必须消失 {#sensitive-memory-governance}

某天你发现，之前 agent 不小心把数据库密码存进了记忆：

```typescript
// 这条记忆不该存在
// atom_id: "01SECRET..."
// content: "数据库密码是 pg_admin_123，连接串是 postgres://..."
```

### HMG 不是已经会自动脱敏吗？

部分会。连接串（`postgres://user:pass@host/db`）、`password=xxx` 格式、Bearer token、私钥块——这些在 memorize 时会被自动替换为 `[REDACTED:...]`。

但"数据库密码是 pg_admin_123"这种自然语言描述拦不住。所以仍然需要手动 govern。

---

这时候 correct 不够用了——你不是要"纠正认知"，你是要"这条记忆必须消失"。

用 govern：

### 最安全的方式：提取教训，封印原文

```typescript
await client.govern({
  target_atom: "01SECRET...",
  action: "derive_lesson",
  reason: "内容含明文数据库密码，必须清除",
  lesson_content: "不要在记忆中存储数据库密码和连接串，使用环境变量",
});
// → result.lesson_atom_id: "01LESSON..."
```

发生了什么：

```
原 atom (01SECRET): "数据库密码是 pg_admin_123..."
  → 被封印。内容永久不可恢复。任何接口都拿不回原文。

新 atom (01LESSON): "不要在记忆中存储数据库密码和连接串，使用环境变量"
  → 正常可召回。这个教训值得保留。
```

什么时候用 derive_lesson 而不是直接 seal？**旧内容里有"不能让人看到的具体值"，但"别这么干"这个经验本身是安全的、可复用的。** 如果里面没有任何值得保留的经验，直接用 seal 或 tombstone。

两者之间有一条 `derived_lesson_from` 边。如果你后来查看教训 atom 的 history，`related_lessons` 字段会指向原始 atom（虽然原文已不可读）。反过来查原始 atom 的 history，也能看到从它派生出的教训。

### 其他治理动作

| 动作 | 效果 | 可逆吗 |
|---|---|---|
| `quarantine` | 从搜索中隐藏，内容保留，等人工确认 | ✅ 可恢复 |
| `seal` | 永久隐藏，内容不可恢复 | ❌ |
| `tombstone` | 彻底删除，仅存 ID 和时间戳 | ❌ |
| `derive_lesson` | 提取教训 → 封印原文 | ❌（原文不可恢复） |

### correct 和 govern 怎么选？

一句话：**改认知用 correct，改存在用 govern。**

- "这条记忆过时了" → correct（negate / replace）
- "这条记忆不该存在" → govern（seal / tombstone / derive_lesson）
- "这条记忆可能有问题，先藏起来看看" → govern（quarantine）

---

## 会话结束时：交接给下一次

一天的工作结束了。你修了一个 bug，做了一些决策，还有一些事没做完。

调 handoff，把上下文交接给下一个会话：

```typescript
await client.handoff({
  summary: "修复了 login.py 的空指针问题。根因是 session 过期时 get_session() 返回 None，在 line 38 加了有效性检查，pytest 通过。风险：并发场景下 session 刷新可能有竞态。下一步：给 session 模块补集成测试。",
});
```

下次你打开这个项目，新会话启动时，agent 会自动看到这条交接摘要。不需要你再说一遍"上次做到哪了"。

### handoff 和 memorize 的区别

| | memorize | handoff |
|---|---|---|
| 存什么 | 单一事实（"用 PostgreSQL 17"） | 完整上下文（做了什么 + 为什么 + 风险 + 下一步） |
| 一次会话存几条 | 多条（边做边存） | 通常 1 条（结束时总结） |
| 下次会话怎么用 | 搜索命中时返回 | 会话启动时优先展示 |

---

## 想追溯一条记忆的完整历史？

当你需要知道"这条记忆被改过几次、谁改的、为什么改"，用 history：

```typescript
const result = await client.history({
  atom_id: "01LESSON...",
});

// result.current:
//   { content: "不要在记忆中存储数据库密码...", exposure_state: "visible", ... }
//
// result.relations:
//   { related_lessons: ["01SECRET..."] }   ← 它派生自哪个原始 atom
//
// result.exposure_history:
//   []   ← 这条教训 atom 本身没被治理过
```

如果查的是原始 atom（01SECRET）：

```typescript
const result = await client.history({
  atom_id: "01SECRET...",
});

// result.current:
//   { content: "[governed payload hidden: sealed]", exposure_state: "sealed", ... }
//
// result.relations:
//   { related_lessons: ["01LESSON..."] }   ← 从它派生出的教训 atom
//
// result.exposure_history:
//   [{ from: "visible", to: "sealed", reason: "内容含明文数据库密码", at: "2026-07-28T...", by: "agent" }]
```

`related_lessons` 是双向的：从教训 atom 查，能看到它来自哪个原始 atom；从原始 atom 查，能看到它派生出了哪个教训。即使原文已被封印不可读，关联关系仍然存在。

history 是审计工具。agent 正常工作流中不需要调它——当你（人类）想追溯"这条记忆经历了什么"时才用。

---

## 看看 store 里有什么

```typescript
const stats = await client.stats();

// {
//   atoms: 42,
//   edges: 306,
//   indexes: { semantic: 42, keyword: 42, temporal: 42, categorical: 42 },
//   snapshot_version: 64
// }
```

---

## 速查表

| 我想... | 调什么 | 必填 |
|---|---|---|
| 记住一件事 | `memorize` | content |
| 找回之前的记忆 | `recall` | query |
| 标记一条记忆过时了 | `correct` (negate) | target_atom, action, reason |
| 更新一条记忆的内容 | `correct` (replace) | target_atom, action, reason, new_content |
| 让一条记忆消失 | `govern` (seal/tombstone) | target_atom, action, reason |
| 提取教训后封印原文 | `govern` (derive_lesson) | target_atom, action, reason, lesson_content |
| 交接给下一个会话 | `handoff` | summary |
| 追溯一条记忆的历史 | `history` | atom_id |
| 看 store 概况 | `stats` | （无） |
