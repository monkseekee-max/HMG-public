# 日常使用指南

HMG 是一個本地記憶系統。它讓你的 AI agent 擁有跨會話的記憶——這次對話裡決定的事，下次對話還能想起來。

這篇指南用一個完整的專案場景，帶你走一遍 HMG 的核心操作。示例用 TypeScript SDK 書寫；習慣命令列的話每個操作都有對應的 `hmg` 命令（見 [CLI 參考](cli-reference.md)），接入 Agent 後這些操作大多由 agent 自動完成，你只需要看思路。

---

## 從"記住一件事"開始

你正在做一個新專案。團隊剛開完會，定了一個技術決策。你希望 agent 記住這件事，下次不用再說一遍。

```typescript
const result = await client.memorize({
  content: "專案用 PostgreSQL 16 做主資料庫，不用 MongoDB",
});

console.log(result.atom_id);  // "01HKX2ABCDEF..."
console.log(result.effect);   // "applied"
```

就這樣。一條記憶存進去了。HMG 把它叫做一個 **atom**——記憶的最小單元。

你不需要告訴 HMG 這條記憶"有多確定"、"是正面還是負面"——它自己會從文字里推斷。你只管寫自然語言。

### 如果重複存了呢？

```typescript
await client.memorize({ content: "專案用 PostgreSQL 16 做主資料庫，不用 MongoDB" });
// → effect: "no_op"（去重命中，不會建立第二條）
```

HMG 會自動去重。同樣的內容不會存兩遍。

---

## 記住了，然後怎麼找回來？

三天後，新會話。你問 agent："我們資料庫用的什麼來著？"

agent 內部會呼叫 recall：

```typescript
const result = await client.recall({
  query: "資料庫選型",
});

// result.atoms:
// [
//   {
//     atom_id: "01HKX2ABCDEF...",
//     content: "專案用 PostgreSQL 16 做主資料庫，不用 MongoDB",
//     score: 0.92,
//     created_at: "2026-07-25T14:00:00Z",
//     source: "user"
//   }
// ]
```

query 用**名詞短語**效果最好。"資料庫選型"比"我們之前決定用什麼資料庫來著"好得多。

### 作用域：記憶屬於哪裡？

每條記憶自動繫結到一個 scope（tenant / workspace / repository / branch）。你通常不需要手動傳——HMG 從當前工作目錄的 git 資訊自動推斷。

在 `mem0ai/mem0` 倉庫的 `main` 分支下存的記憶，預設只在這個 scope 下被召回。切到另一個專案，不會看到無關的記憶。

---

## 記憶過時了怎麼辦？

兩個月後，專案升級了資料庫版本。之前那條記憶還寫著"PostgreSQL 16"，但你們已經升到了 17。

### 推薦做法：replace

```typescript
await client.correct({
  target_atom: "01HKX2ABCDEF...",
  action: "replace",
  reason: "已升級到 PostgreSQL 17",
  new_content: "專案用 PostgreSQL 17 做主資料庫",
});
// → result.new_atom_id: "01NEW..."
```

一步完成。舊 atom 保留（透過 Supersedes 邊關聯新 atom），搜尋時只返回新版本。

三個月後你查 `history("01NEW...")`，能看到：這條記憶是從"PostgreSQL 16"那條升級來的，升級原因是"已升級到 PostgreSQL 17"。審計鏈完整。

### 什麼時候不用 replace，只用 negate？

 negate 適合"這件事不再成立，且沒有替代品"的場景。

比如半年後，你們徹底放棄了 MongoDB 相關的快取方案：

```typescript
// 之前存過一條："用 MongoDB 做會話快取"
// 現在這個方案整個廢棄了，沒有"新版本"，就是不用了
await client.correct({
  target_atom: "01MONGO...",
  action: "negate",
  reason: "MongoDB 快取方案已廢棄，改用 Redis",
});
```

negate 之後，這條記憶從預設搜尋中消失。agent 不會再看到它。

注意：negate 不是把文字改成"不用 MongoDB"。它標記"這條記憶不再有效"，原文不變，只是不再被召回。

### 怎麼判斷用哪個？

| 情況 | 用什麼 | 例子 |
|---|---|---|
| 同一件事有了新版本 | `replace` | "用 PostgreSQL 16" → "用 PostgreSQL 17" |
| 決定本身變了（不是確認，是改主意了） | `replace` | "考慮用 K8s" → "決定用 ECS 部署" |
| 這件事作廢了，沒有替代品 | `negate` | "用 MongoDB 做快取" → 整個廢棄 |
| 內容沒變，從"聽說"變成"確認屬實" | `confirm_actual` | "API 閘道器用 Kong"（之前不確定，現在在配置裡確認了） |
| 內容沒變，從"事實"升級為"硬約束" | `confirm_necessary` | "所有 API 必須加認證"（從團隊慣例升級為安全合規要求） |
| 內容沒變，但從"已定"降為"還在評估" | `demote` | "用 K8s 部署"（之前以為定了，其實還沒定） |

一句話：**內容要變就 replace，只是確定性變了就 confirm/demote，徹底作廢就 negate。**

注意 `confirm_actual` 不改內容——它確認的是"content 裡寫的這件事是屬實的"。如果決定本身變了（從"考慮 X"變成"用 Y"），那是內容變了，應該用 replace。

### 確定性等級（epistemic）

每條記憶有一個確定性等級，confirm/demote 改的就是它：

```
possible  →  "可能為真"（聽說、在評估、不確定）
actual    →  "已確認為真"（驗證過、確認了）
necessary →  "必須為真"（硬約束、合規要求、不可違反）
```

各動作的方向：

```
possible ──confirm_actual──→ actual ──confirm_necessary──→ necessary
    ↑                          |                               |
    └──────────── demote ──────┘                               |
    ↑                                                          |
    └──────────────────── demote ──────────────────────────────┘
```

注意事項：

- `demote` 是直接降到最低（possible），不是降一級。necessary 被 demote 後變成 possible，不是 actual。
- `confirm_actual` 只能升級，不能用在已經是 necessary 的 atom 上（會報錯）。
- 想讓 necessary 變成 actual？沒有一步到位的方式。得先 `demote`（降到 possible），再 `confirm_actual`（升到 actual）。
- `confirm_actual` 和 `demote` 在 possible ↔ actual 之間是可逆的一對。但涉及 necessary 時不可逆（demote 會跳過 actual 直接到 possible）。

### correct 會丟失資訊嗎？

不會。correct 永遠不銷燬內容。舊 atom 不會被刪除，你透過 history 隨時能看到它。

但 negate 和 replace 沒有"一鍵撤銷"。操作錯了，用下面的方式恢復：

### 操作錯了怎麼恢復？

沒有 "un-negate" 也沒有 "undo replace"。統一的恢復方式是：**在那條有問題的 atom 上繼續 replace**。

**negate 錯了**：你 negate 了"用 MongoDB 做快取"，以為廢棄了。一週後發現其實還在用。

```typescript
await client.correct({
  target_atom: "01MONGO...",  // 那條被 negate 的 atom
  action: "replace",
  reason: "negate 有誤，MongoDB 快取仍在使用",
  new_content: "用 MongoDB 做會話快取，仍在使用",
});
```

**replace 錯了**：昨天 replace 了"用 PG 16" → "用 PG 17"。今天發現升級取消了，還是 16。

```typescript
await client.correct({
  target_atom: "01NEW...",  // 那條錯誤的 "用 PG 17"
  action: "replace",
  reason: "升級取消，回退到 16",
  new_content: "專案用 PostgreSQL 16 做主資料庫",
});
```

為什麼不用 memorize 新的？因為 replace 會在舊 atom 和新 atom 之間建立 Supersedes 邊，保證任何時刻只有一條 active 記憶。如果用 memorize，被 negate 或被取代的舊 atom 可能仍然殘留在 recall 結果裡，和新記憶產生矛盾。

審計鏈也完整：每一步都有 reason，history 可追溯完整演變過程。

---

## 有些記憶必須消失 {#sensitive-memory-governance}

某天你發現，之前 agent 不小心把資料庫密碼存進了記憶：

```typescript
// 這條記憶不該存在
// atom_id: "01SECRET..."
// content: "資料庫密碼是 pg_admin_123，連線串是 postgres://..."
```

### HMG 不是已經會自動脫敏嗎？

部分會。連線串（`postgres://user:pass@host/db`）、`password=xxx` 格式、Bearer token、私鑰塊——這些在 memorize 時會被自動替換為 `[REDACTED:...]`。

但"資料庫密碼是 pg_admin_123"這種自然語言描述攔不住。所以仍然需要手動 govern。

---

這時候 correct 不夠用了——你不是要"糾正認知"，你是要"這條記憶必須消失"。

用 govern：

### 最安全的方式：提取教訓，封印原文

```typescript
await client.govern({
  target_atom: "01SECRET...",
  action: "derive_lesson",
  reason: "內容含明文資料庫密碼，必須清除",
  lesson_content: "不要在記憶中儲存資料庫密碼和連線串，使用環境變數",
});
// → result.lesson_atom_id: "01LESSON..."
```

發生了什麼：

```
原 atom (01SECRET): "資料庫密碼是 pg_admin_123..."
  → 被封印。內容永久不可恢復。任何介面都拿不回原文。

新 atom (01LESSON): "不要在記憶中儲存資料庫密碼和連線串，使用環境變數"
  → 正常可召回。這個教訓值得保留。
```

什麼時候用 derive_lesson 而不是直接 seal？**舊內容裡有"不能讓人看到的具體值"，但"別這麼幹"這個經驗本身是安全的、可複用的。** 如果裡面沒有任何值得保留的經驗，直接用 seal 或 tombstone。

兩者之間有一條 `derived_lesson_from` 邊。如果你後來檢視教訓 atom 的 history，`related_lessons` 欄位會指向原始 atom（雖然原文已不可讀）。反過來查原始 atom 的 history，也能看到從它派生出的教訓。

### 其他治理動作

| 動作 | 效果 | 可逆嗎 |
|---|---|---|
| `quarantine` | 從搜尋中隱藏，內容保留，等人工確認 | ✅ 可恢復 |
| `seal` | 永久隱藏，內容不可恢復 | ❌ |
| `tombstone` | 徹底刪除，僅存 ID 和時間戳 | ❌ |
| `derive_lesson` | 提取教訓 → 封印原文 | ❌（原文不可恢復） |

### correct 和 govern 怎麼選？

一句話：**改認知用 correct，改存在用 govern。**

- "這條記憶過時了" → correct（negate / replace）
- "這條記憶不該存在" → govern（seal / tombstone / derive_lesson）
- "這條記憶可能有問題，先藏起來看看" → govern（quarantine）

---

## 會話結束時：交接給下一次

一天的工作結束了。你修了一個 bug，做了一些決策，還有一些事沒做完。

調 handoff，把上下文交接給下一個會話：

```typescript
await client.handoff({
  summary: "修復了 login.py 的空指標問題。根因是 session 過期時 get_session() 返回 None，在 line 38 加了有效性檢查，pytest 透過。風險：併發場景下 session 重新整理可能有競態。下一步：給 session 模組補整合測試。",
});
```

下次你開啟這個專案，新會話啟動時，agent 會自動看到這條交接摘要。不需要你再說一遍"上次做到哪了"。

### handoff 和 memorize 的區別

| | memorize | handoff |
|---|---|---|
| 存什麼 | 單一事實（"用 PostgreSQL 17"） | 完整上下文（做了什麼 + 為什麼 + 風險 + 下一步） |
| 一次會話存幾條 | 多條（邊做邊存） | 通常 1 條（結束時總結） |
| 下次會話怎麼用 | 搜尋命中時返回 | 會話啟動時優先展示 |

---

## 想追溯一條記憶的完整歷史？

當你需要知道"這條記憶被改過幾次、誰改的、為什麼改"，用 history：

```typescript
const result = await client.history({
  atom_id: "01LESSON...",
});

// result.current:
//   { content: "不要在記憶中儲存資料庫密碼...", exposure_state: "visible", ... }
//
// result.relations:
//   { related_lessons: ["01SECRET..."] }   ← 它派生自哪個原始 atom
//
// result.exposure_history:
//   []   ← 這條教訓 atom 本身沒被治理過
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
//   { related_lessons: ["01LESSON..."] }   ← 從它派生出的教訓 atom
//
// result.exposure_history:
//   [{ from: "visible", to: "sealed", reason: "內容含明文資料庫密碼", at: "2026-07-28T...", by: "agent" }]
```

`related_lessons` 是雙向的：從教訓 atom 查，能看到它來自哪個原始 atom；從原始 atom 查，能看到它派生出了哪個教訓。即使原文已被封印不可讀，關聯關係仍然存在。

history 是審計工具。agent 正常工作流中不需要調它——當你（人類）想追溯"這條記憶經歷了什麼"時才用。

---

## 看看 store 裡有什麼

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

| 我想... | 調什麼 | 必填 |
|---|---|---|
| 記住一件事 | `memorize` | content |
| 找回之前的記憶 | `recall` | query |
| 標記一條記憶過時了 | `correct` (negate) | target_atom, action, reason |
| 更新一條記憶的內容 | `correct` (replace) | target_atom, action, reason, new_content |
| 讓一條記憶消失 | `govern` (seal/tombstone) | target_atom, action, reason |
| 提取教訓後封印原文 | `govern` (derive_lesson) | target_atom, action, reason, lesson_content |
| 交接給下一個會話 | `handoff` | summary |
| 追溯一條記憶的歷史 | `history` | atom_id |
| 看 store 概況 | `stats` | （無） |
