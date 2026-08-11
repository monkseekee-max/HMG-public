# 日常利用ガイド

HMG はローカルの記憶システムです。AI Agent にセッションを越えた記憶を与えます——今回の会話で決めたことを、次の会話でも思い出せます。

このガイドでは 1 つの完全なプロジェクトシナリオで HMG のコア操作を一通り説明します。サンプルは TypeScript SDK で書いています。コマンドライン派には各操作に対応する `hmg` コマンドがあります（[CLI リファレンス](cli-reference.md)参照）。Agent を接続すると、これらの操作の多くは自動で行われます——あなたは考え方を追うだけで十分です。

---

## 「1 つ記憶する」から始める

新しいプロジェクトを始めるところです。チームはさっきミーティングで技術的な決定をしました。Agent にこれを記憶させ、次回繰り返さないようにしたい。

```typescript
const result = await client.memorize({
  content: "プロジェクトの主データベースは PostgreSQL 16 で、MongoDB は使わない",
});

console.log(result.atom_id);  // "01HKX2ABCDEF..."
console.log(result.effect);   // "applied"
```

これだけです。記憶が 1 件保存されました。HMG はこれを **atom**（アトム）と呼びます——記憶の最小単位です。

この記憶が「どれくらい確実か」「肯定か否定か」を HMG に伝える必要はありません——テキストから自分で推論します。あなたは自然言語を書くだけです。

### 重複して保存したら？

```typescript
await client.memorize({ content: "プロジェクトの主データベースは PostgreSQL 16 で、MongoDB は使わない" });
// → effect: "no_op"（重複排除にヒットし、2 件目は作られない）
```

HMG は自動的に重複排除します。同じ内容は 2 度保存されません。

---

## 記憶したものを、どう取り出す？

3 日後、新しいセッション。「データベースって何を使ってたっけ？」と Agent に聞きます。

Agent は内部で recall を呼びます：

```typescript
const result = await client.recall({
  query: "データベース選定",
});

// result.atoms:
// [
//   {
//     atom_id: "01HKX2ABCDEF...",
//     content: "プロジェクトの主データベースは PostgreSQL 16 で、MongoDB は使わない",
//     score: 0.92,
//     created_at: "2026-07-25T14:00:00Z",
//     source: "user"
//   }
// ]
```

query は**名詞句**が最も効果的です。「データベース選定」は「前に何のデータベースに決めたっけ」よりはるかに良い。

### スコープ：記憶はどこに属するか？

各記憶は自動的にスコープ（tenant / workspace / repository / branch）に紐付きます。通常は手動で渡す必要はありません——HMG がカレントディレクトリの git 情報から自動推論します。

`mem0ai/mem0` リポジトリの `main` ブランチで保存した記憶は、既定ではこのスコープでのみリコールされます。別のプロジェクトに切り替えると、無関係な記憶は見えません。

---

## 記憶が古くなったら？

2 ヶ月後、プロジェクトはデータベースのバージョンを上げました。古い記憶はまだ「PostgreSQL 16」と書いてありますが、すでに 17 にしています。

### 推奨：replace

```typescript
await client.correct({
  target_atom: "01HKX2ABCDEF...",
  action: "replace",
  reason: "PostgreSQL 17 にアップグレード済み",
  new_content: "プロジェクトの主データベースは PostgreSQL 17",
});
// → result.new_atom_id: "01NEW..."
```

1 ステップで完了。古い atom は保持され（Supersedes エッジで新 atom に関連付け）、検索時は新しいバージョンのみ返ります。

3 ヶ月後に `history("01NEW...")` を見ると：この記憶は「PostgreSQL 16」の記憶からアップグレードされたもので、理由は「PostgreSQL 17 にアップグレード済み」と分かります。監査チェーンは完全です。

### replace ではなく negate を使うのはどんなとき？

negate は「この件はもう成り立たず、代替もない」場面に適します。

たとえば半年後、MongoDB を使ったキャッシュ方案を完全にやめた場合：

```typescript
// 以前保存していた：「セッションキャッシュに MongoDB を使う」
// いまやこの方案は完全に廃止——「新版」はなく、ただ使わなくなった
await client.correct({
  target_atom: "01MONGO...",
  action: "negate",
  reason: "MongoDB キャッシュ方案は廃止、Redis に変更",
});
```

negate 後、この記憶は既定の検索から消えます。Agent は二度とこれを見ません。

注意：negate はテキストを「MongoDB を使わない」に書き換えるのではありません。「この記憶はもはや有効でない」とマークするだけで、原文は変わらず、リコールされなくなるだけです。

### どう使い分ける？

| 状況 | 使うもの | 例 |
|---|---|---|
| 同じ件に新しいバージョンができた | `replace` | 「PostgreSQL 16 を使う」→「PostgreSQL 17 を使う」 |
| 決定そのものが変わった（確認ではなく方針変更） | `replace` | 「K8s を検討」→「ECS でデプロイと決定」 |
| その件は廃止、代替なし | `negate` | 「キャッシュに MongoDB」→ 完全廃止 |
| 内容は変わらず「伝聞」から「確認済み」へ | `confirm_actual` | 「API ゲートウェイは Kong」（未確認だったが設定で確認できた） |
| 内容は変わらず「事実」から「ハード制約」へ | `confirm_necessary` | 「全 API に認証必須」（チーム慣例からセキュリティ要件へ昇格） |
| 内容は変わらず「決定済み」から「まだ評価中」へ | `demote` | 「K8s でデプロイ」（決まったと思っていたが、まだ未定だった） |

一言で：**内容が変わるなら replace、確信度だけ変わるなら confirm/demote、完全に廃止なら negate。**

`confirm_actual` は内容を変えない点に注意——確認するのは「content に書かれた事が事実である」ということです。決定そのものが変わった（「X を検討」→「Y を使う」）なら、それは内容の変更なので replace を使います。

### 確信度レベル（epistemic）

各記憶には確信度レベルがあり、confirm/demote が変えるのはまさにこれです：

```
possible  →  「真かもしれない」（伝聞、評価中、不確定）
actual    →  「真と確認済み」（検証済み、確認済み）
necessary →  「真でなければならない」（ハード制約、コンプライアンス要件、違反不可）
```

各アクションの方向：

```
possible ──confirm_actual──→ actual ──confirm_necessary──→ necessary
    ↑                          |                               |
    └──────────── demote ──────┘                               |
    ↑                                                          |
    └──────────────────── demote ──────────────────────────────┘
```

注意：

- `demote` は最低レベル（possible）まで一気に落ちます。1 段階ずつではありません。necessary を demote すると actual ではなく possible になります。
- `confirm_actual` は昇格のみ。すでに necessary の atom には使えません（エラーになります）。
- necessary を actual にしたい？一発ではできません。まず `demote`（possible へ）、次に `confirm_actual`（actual へ）。
- `confirm_actual` と `demote` は possible ↔ actual の間で可逆のペアです。ただし necessary が絡むと不可逆（demote は actual を飛ばして possible に落ちる）。

### correct は情報を失うか？

失いません。correct は内容を破棄しません。古い atom は削除されず、history でいつでも確認できます。

ただし negate と replace に「ワンクリック取り消し」はありません。操作を間違えたら、以下の方法で復旧します：

### 操作を間違えたときの復旧方法は？

「un-negate」も「undo replace」もありません。統一された復旧方法：**問題のある atom に対して replace を続ける**。

**negate の間違い**：「キャッシュに MongoDB」を廃止と思って negate した。1 週間後、まだ使っていると判明。

```typescript
await client.correct({
  target_atom: "01MONGO...",  // negate されたあの atom
  action: "replace",
  reason: "negate は誤り、MongoDB キャッシュはまだ使用中",
  new_content: "セッションキャッシュに MongoDB を使用、まだ使用中",
});
```

**replace の間違い**：昨日「PG 16 を使う」→「PG 17 を使う」と replace した。今日アップグレードが中止になり、やはり 16 と判明。

```typescript
await client.correct({
  target_atom: "01NEW...",  // 誤った「PG 17 を使う」の atom
  action: "replace",
  reason: "アップグレード中止、16 に戻す",
  new_content: "プロジェクトの主データベースは PostgreSQL 16",
});
```

なぜ新しく memorize しないのか？replace は古い atom と新しい atom の間に Supersedes エッジを作り、常に有効な記憶が 1 件だけであることを保証するからです。memorize だと、negate されたり置き換えられたりした古い atom がリコール結果に残り、新しい記憶と矛盾する可能性があります。

監査チェーンも完全です：各ステップに reason があり、history で完全な変遷を追跡できます。

---

## 消さなければならない記憶がある {#sensitive-memory-governance}

ある日、Agent が以前データベースのパスワードを記憶に保存してしまったと気づきました：

```typescript
// この記憶は存在してはならない
// atom_id: "01SECRET..."
// content: "DB パスワードは pg_admin_123、接続文字列は postgres://..."
```

### HMG は自動で秘匿化するのでは？

部分的には。接続文字列（`postgres://user:pass@host/db`）、`password=xxx` 形式、Bearer トークン、秘密鍵ブロック——これらは memorize 時に `[REDACTED:...]` に自動置換されます。

ただし「DB パスワードは pg_admin_123」のような自然言語の記述は防げません。したがって手動の govern が依然必要です。

---

ここで correct では足りなくなります——あなたは「認知を訂正」したいのではなく、「この記憶は消えなければならない」のです。

govern を使います：

### 最も安全な方法：教訓を抽出し、原文を封印

```typescript
await client.govern({
  target_atom: "01SECRET...",
  action: "derive_lesson",
  reason: "内容に平文のデータベースパスワードが含まれており、必ず消去する必要がある",
  lesson_content: "データベースのパスワードや接続文字列を記憶に保存せず、環境変数を使う",
});
// → result.lesson_atom_id: "01LESSON..."
```

何が起きたか：

```
元の atom (01SECRET): "DB パスワードは pg_admin_123..."
  → 封印された。内容は永久に復元不可。どのインターフェースからも原文は取得できない。

新しい atom (01LESSON): "データベースのパスワードや接続文字列を記憶に保存せず、環境変数を使う"
  → 通常どおりリコール可能。この教訓は残す価値がある。
```

いつ seal ではなく derive_lesson を使うか？**古い内容に「人に見せてはならない具体的な値」があるが、「こうしてはいけない」という経験自体は安全で再利用できる場合。** 残す価値のある教訓がなければ、seal か tombstone を直接使います。

両者の間には `derived_lesson_from` エッジがあります。後で教訓 atom の history を見ると、`related_lessons` フィールドが元の atom を指します（原文はすでに読めなくても）。逆に元の atom の history を見ると、そこから派生した教訓が分かります。

### その他のガバナンスアクション

| アクション | 効果 | 可逆？ |
|---|---|---|
| `quarantine` | 検索から隠す。内容は保持、人手の確認待ち | ✅ 復元可能 |
| `seal` | 永久に隠す。内容は復元不可 | ❌ |
| `tombstone` | 完全削除。ID とタイムスタンプのみ残る | ❌ |
| `derive_lesson` | 教訓を抽出 → 原文を封印 | ❌（原文は復元不可） |

### correct と govern の使い分けは？

一言で：**認知を変えるのは correct、存在を変えるのは govern。**

- 「この記憶は古くなった」→ correct（negate / replace）
- 「この記憶は存在すべきでない」→ govern（seal / tombstone / derive_lesson）
- 「この記憶は疑わしいので、確認するまで隠す」→ govern（quarantine）

---

## セッション終了時：次へ引き継ぐ

1 日の作業が終わりました。bug を 1 つ直し、いくつか決定し、まだ終わっていないこともあります。

handoff を呼び、コンテキストを次のセッションに引き継ぎます：

```typescript
await client.handoff({
  summary: "login.py の null ポインタを修正。根本原因は session 期限切れ時に get_session() が None を返すこと。line 38 に有効性チェックを追加、pytest はすべて通過。リスク：並行時に session 更新の競合の可能性。次：session モジュールに統合テストを追加。",
});
```

次にこのプロジェクトを開くと、新しいセッションの起動時にこの引き継ぎ要約が自動的に表示されます。「前回どこまでやったか」を再び説明する必要はありません。

### handoff と memorize の違い

| | memorize | handoff |
|---|---|---|
| 保存するもの | 単一の事実（「PostgreSQL 17 を使う」） | 完全なコンテキスト（何をしたか + なぜ + リスク + 次のステップ） |
| 1 セッションで何件 | 複数件（進めながら保存） | 通常 1 件（終了時のまとめ） |
| 次のセッションでの使われ方 | 検索にヒットしたとき返る | セッション起動時に優先表示 |

---

## ある記憶の完全な履歴を追いたい？

「この記憶は何回変わったか、誰が、なぜ変えたか」を知る必要があるときは history を使います：

```typescript
const result = await client.history({
  atom_id: "01LESSON...",
});

// result.current:
//   { content: "データベースのパスワードを記憶に保存しない...", exposure_state: "visible", ... }
//
// result.relations:
//   { related_lessons: ["01SECRET..."] }   ← どの元の atom から派生したか
//
// result.exposure_history:
//   []   ← この教訓 atom 自体はガバナンスされたことがない
```

元の atom（01SECRET）を調べると：

```typescript
const result = await client.history({
  atom_id: "01SECRET...",
});

// result.current:
//   { content: "[governed payload hidden: sealed]", exposure_state: "sealed", ... }
//
// result.relations:
//   { related_lessons: ["01LESSON..."] }   ← これから派生した教訓 atom
//
// result.exposure_history:
//   [{ from: "visible", to: "sealed", reason: "内容に平文の DB パスワードを含む", at: "2026-07-28T...", by: "agent" }]
```

`related_lessons` は双方向です：教訓 atom から調べればどの元の atom から来たかが分かり、元の atom から調べればどの教訓を派生したかが分かります。原文が封印されて読めなくても、関連関係は残ります。

history は監査ツールです。Agent の通常のワークフローでは呼ぶ必要はありません——あなた（人間）が「この記憶に何が起きたか」を追いたいときに使います。

---

## store に何があるか見る

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

## チートシート

| やりたいこと | 呼ぶもの | 必須 |
|---|---|---|
| 何かを記憶する | `memorize` | content |
| 過去の記憶を探す | `recall` | query |
| 記憶が古くなったとマーク | `correct` (negate) | target_atom, action, reason |
| 記憶の内容を更新 | `correct` (replace) | target_atom, action, reason, new_content |
| 記憶を消す | `govern` (seal/tombstone) | target_atom, action, reason |
| 教訓を抽出して原文を封印 | `govern` (derive_lesson) | target_atom, action, reason, lesson_content |
| 次のセッションへ引き継ぐ | `handoff` | summary |
| 記憶の履歴を追跡 | `history` | atom_id |
| store の概況 | `stats` | （なし） |
