---
sidebar_position: 2
---

# MCP リファレンス

HMG は MCP（Model Context Protocol）を通じて Agent に記憶ツールを公開します。ホスト内のツール名は `mcp__hmg__memory_memorize` の形式です（`mcp__<server>__<tool>`）。

## 概要

| ツール | 用途 | 必須フィールド |
|---|---|---|
| `memory_memorize` | 記憶を 1 件書き込む | `content` |
| `memory_recall` | 記憶を検索する | `query` |
| `memory_correct` | 記憶を 1 件訂正する | `target_atom`、`action`、`reason` |
| `memory_govern` | 記憶のライフサイクルを管理する | `target_atom`、`action`、`reason` |
| `memory_handoff` | セッション引き継ぎ要約 | `summary` |
| `memory_stats` | store の概況 | （なし） |

MCP ツールとして公開されない機能：`agent_brief`（SessionStart hook の内部実装）、`observation_*`（Agent 統合では起動しない）、`history` / `export`（SDK レイヤーのみ、[SDK リファレンス](sdk-reference.md)参照）。

## 共通規約

- **scope は agent が渡しません。** すべてのツールのスコープは PreToolUse hook がセッションのディレクトリから機械的に推論して注入します（または MCP server がプロセスの作業ディレクトリから推論）。agent が渡した scope は上書きされます。
- **確信度と極性は自動推論。** `epistemic`（事実/制約/推測）と `polarity`（肯定/否定/条件）は HMG が内容の表現から推論し、入力パラメータではありません。
- **書き込み時の自動秘匿化。** 構造化された機密情報（接続文字列、`password=xxx`、Bearer トークン、秘密鍵ブロック）は memorize 時に自動で秘匿化されます。自然言語で書かれた機密内容は自動検出されないので、書き込まないでください。
- **正確な重複排除。** 完全に同じ内容の書き込みは 2 件目の atom を作りません（`effect: "no_op"`）。

## ScopeInput（共通）

すべてのツールの任意 `scope` フィールドは同じ構造です（agent は渡しません）：

```json
{
  "tenant_id": "qiankun",
  "workspace": "HMG-AI",
  "repository": "HMG-DEV-brach",
  "branch": "main"
}
```

| フィールド | 説明 |
|---|---|
| `tenant_id` | テナント。OS のユーザー名で、HMG が store 設定から読み取り |
| `workspace` | ワークスペース。通常は git remote の owner |
| `repository` | リポジトリ名 |
| `branch` | ブランチ |

---

## memory_memorize

長期記憶を 1 件書き込みます。

**入力**

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `content` | string | はい | 記憶の内容。独立した一文 |
| `source` | string | いいえ | 出所の帰属：`user`（ユーザーの発言、より権威あり）/ `agent`（agent がまとめたもの）/ カスタム |
| `scope` | ScopeInput | いいえ | hook が自動注入。agent は渡さない |

**出力**

| フィールド | 説明 |
|---|---|
| `atom_id` | atom の ULID（重複排除ヒット時は既存 atom の ID） |
| `effect` | `applied`（新規作成）/ `no_op`（重複排除ヒット）/ `rejected`（准入で拒否） |
| `reason` | 重複排除または拒否の理由（`applied` 時は返らない） |
| `deduped_with` | 重複排除でヒットした既存 atom の ID（`no_op` のみ） |

**例**

```json
{
  "content": "このプロジェクトの主データベースは PostgreSQL 16 で MongoDB は使わない。トランザクションと複雑なクエリが必要なため",
  "source": "user"
}
```

**注意**

- 先に recall で重複チェックする必要はありません。HMG が内部で正確な重複排除を行います
- 現在のコンテキストにすでに意味の近い記憶が見えている場合は、新規追加ではなく `memory_correct`（`replace`）で更新してください
- 記憶はユーザーの現在の会話の言語で保存されます

---

## memory_recall

自然言語で記憶を検索します。

**入力**

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `query` | string | はい | 検索クエリ。名詞句が最も効果的 |
| `max_results` | number | いいえ | 最大返却件数。既定 10 |
| `include_negated` | boolean | いいえ | 否定済みの記憶を含むか。既定 false |
| `scope` | ScopeInput | いいえ | hook が自動注入。agent は渡さない |

**出力**

| フィールド | 説明 |
|---|---|
| `atoms` | 関連度の降順に並んだ結果リスト |
| `atoms[].atom_id` | atom の一意識別子。correct / govern で使用 |
| `atoms[].content` | 記憶の内容（隔離/封印済みはプレースホルダーを返す） |
| `atoms[].score` | 関連度スコア。0.0 ~ 1.0 |
| `atoms[].created_at` | 作成時刻（RFC 3339） |
| `atoms[].source` | 出所の帰属 |

**例**

```json
{ "query": "PostgreSQL コネクションプール設定" }
```

**注意**

- query は名詞句を使い、重要な固有名詞（人名、プロジェクト名、技術名、ファイル名）を残し、口語的な疑問文は避ける
- 通常 1 回のリコールで十分です。HMG は内部で意味、キーワード、グラフなど多角度から検索済みです

---

## memory_correct

記憶を 1 件訂正します。追記型の訂正：古い内容は監査チェーンに保持され、履歴は失われません。

**入力**

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `target_atom` | string | はい | 訂正する atom の ID（recall の結果から取得） |
| `action` | string | はい | 下記のアクション表を参照 |
| `reason` | string | はい | 訂正の理由。監査チェーンに書き込まれる |
| `new_content` | string | replace のとき必須 | 置換後の新しい内容 |
| `scope` | ScopeInput | いいえ | 既定で対象 atom から継承。渡さない |

**action の値**

| アクション | 意味 | 典型的な場面 |
|---|---|---|
| `negate` | 偽とマークして無効化 | 「この記憶はもう古い/間違っている」 |
| `confirm_actual` | 確認済みの事実に昇格 | 「前は不確定だったが、今は確認できた」 |
| `confirm_necessary` | ハード制約に昇格 | 「事実というだけでなく、必ず守るべき制約」 |
| `demote` | 可能性に格下げ | 「決まったと思っていたが、実は未定だった」 |
| `replace` | 新しい内容で置換（新 atom を作成し、旧 atom は変遷チェーンに保持） | 「内容を更新する必要がある」（必ず `new_content` を同時に渡す） |

**出力**

| フィールド | 説明 |
|---|---|
| `effect` | `applied` / `rejected` |
| `target_atom` | 訂正された元の atom の ID |
| `new_atom_id` | 新規 atom の ID（`replace` のみ） |
| `reason` | 拒否の理由（`rejected` のみ） |

**例**

```json
{
  "target_atom": "01J9ZK8V3QX7N2M4R6T8W0YB1C",
  "action": "replace",
  "reason": "v3 で PostgreSQL に移行済み、旧決定は古い",
  "new_content": "主データベースは PostgreSQL 16 で、旧 MongoDB 方案を置き換え"
}
```

**注意**

- `negate` は正確に元に戻せません（un-negate なし）。否定の間違いは `replace` で正しい内容を書き戻す
- `replace` を間違えたら、その atom に対してさらに `replace`——常に有効な記憶が 1 件だけであることを保証

---

## memory_govern

記憶のライフサイクルを管理します（隔離、封印、無効化、教訓の抽出）。

**入力**

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `target_atom` | string | はい | ガバナンスする atom の ID |
| `action` | string | はい | `quarantine` / `seal` / `tombstone` / `derive_lesson` |
| `reason` | string | はい | ガバナンスの理由。監査チェーンに書き込まれる |
| `lesson_content` | string | derive_lesson のとき必須 | 元の内容から抽出した秘匿化された教訓 |
| `scope` | ScopeInput | いいえ | 既定で対象 atom から継承。渡さない |

**action の値**

| アクション | 意味 |
|---|---|
| `quarantine` | 隔離：リコールに出なくなるが内容は保持、復元可能 |
| `seal` | 封印：監査のみ参照可能 |
| `tombstone` | 墓碑化：論理削除、既定で内容を破棄 |
| `derive_lesson` | 秘匿化された教訓を抽出（新 atom）、原文を封印 |

**出力**

| フィールド | 説明 |
|---|---|
| `effect` | `applied` / `rejected` |
| `target_atom` | ガバナンスされた元の atom の ID |
| `lesson_atom_id` | 教訓 atom の ID（`derive_lesson` のみ） |
| `reason` | 拒否の理由（`rejected` のみ） |

**例**

```json
{
  "target_atom": "01J9ZK8V3QX7N2M4R6T8W0YB1C",
  "action": "derive_lesson",
  "reason": "原文に漏洩した API キーを含む",
  "lesson_content": "API キーをコードや記憶にハードコードせず、環境変数を使う"
}
```

**注意**

- 機密情報の誤記：教訓として残す価値があれば `derive_lesson`、なければ `seal` か `tombstone`
- `tombstone` は既定で内容を破棄します。呼び出し側の追加指定は不要です

---

## memory_handoff

セッション引き継ぎ要約を書き込みます。handoff は特殊な記憶で、次のセッションの起動ブリーフが**優先的にリコール**します。

**入力**

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| `summary` | string | はい | 引き継ぎ要約。カバー推奨：何をしたか / なぜ / 検証 / リスク / 次のステップ（形式は自由） |
| `source` | string | いいえ | 出所の帰属 |
| `scope` | ScopeInput | いいえ | hook が自動注入。agent は渡さない |

**出力**

| フィールド | 説明 |
|---|---|
| `atom_id` | handoff atom の ULID |
| `effect` | `applied` / `rejected` |
| `reason` | 拒否の理由（`rejected` のみ） |

**例**

```json
{
  "summary": "login.py の null ポインタを修正。根本原因は session 期限切れ時に get_session() が None を返すことで、line 38 に有効性チェックを追加、pytest はすべて通過。リスク：並行時に session 更新の競合の可能性。次：session モジュールに統合テストを追加。",
  "source": "agent"
}
```

**注意**

- 呼び出しタイミング：タスク終了、マイルストーン完了、セッション終了間際
- memorize との分担：memorize は単一の増分知識を保存し、handoff は 1 回のタスク全体の引き継ぎを保存します

---

## memory_stats

store の概況を表示します。主に SessionStart hook が内部で使用（空の store → オンボーディングフローの判定）。Agent の通常のワークフローでは通常呼び出し不要です。

**入力**：なし。

**出力**

| フィールド | 説明 |
|---|---|
| `atoms` | 記憶 atom の総数 |
| `edges` | グラフエッジの総数 |
| `indexes` | 各インデックスのカバー数（semantic / keyword / temporal / categorical） |
| `snapshot_version` | 現在のスナップショットバージョン。書き込みごとに増加 |

---

前：[CLI リファレンス](cli-reference.md) · 次：[SDK リファレンス](sdk-reference.md)
