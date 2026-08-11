---
sidebar_position: 1
---

# CLI リファレンス

HMG のすべての機能は `hmg` コマンドラインから利用できます。本ページは公開コマンドをカテゴリ別に記載します。セッション内で Agent が使うツールとの対応は [MCP リファレンス](mcp-reference.md) を参照。

## グローバルオプション

多くのコマンドが対応：

| オプション | 説明 |
|---|---|
| `--store <path>` | store ディレクトリを指定（既定 `~/.local/share/hmg/stores/default`） |
| `--scope <tenant/workspace/repository/branch>` | スコープを明示指定。未指定時はカレントディレクトリから推論 |
| `--format text\|json\|yaml` | 出力形式 |
| `--direct` | デーモンを迂回し、プロセス内で store を直接開く |
| `--dry-run` | 変更をプレビューし、実際には実行しない |

`hmg help <command>` で個別コマンドの例、`hmg help commands` で完全なコマンド一覧を確認できます。

## コマンド一覧

| カテゴリ | コマンド |
|---|---|
| 記憶の読み書き | `memorize`、`recall`、`correct`、`govern`、`history`、`stats`、`export` |
| タスクコンテキスト | `agent-brief`、`handoff` |
| クエリ | `query`、`suggest-query`、`query-templates`、`explain-query`、`schema`、`recall-view`、`noise-feedback`、`panorama`、`impact` |
| インストールと接続 | `setup`、`init`、`doctor`、`login`、`account status`、`onboard`、`integrations`、`update`、`uninstall` |
| ランタイム | `daemon`、`model`、`hook`、`agent-event`、`agent-timeline` |
| store メンテナンス | `store migrate`、`store hygiene`、`store repair-edges`、`verify` |
| secret vault | `secret store / lookup / use / reveal / rotate / revoke` |
| 観察レイヤー | `obs capture / promote / forget / maintain / review-queue`、`observation config / scheduler` |
| その他 | `tui`、`version`、`language`、`completions` |

---

## 記憶の読み書き

### hmg memorize

長期記憶を 1 件書き込みます。

```
hmg memorize <content> [--source <src>] [--scope <t/w/r/b>] [--file <path>] [--dry-run]
```

| パラメータ | 説明 |
|---|---|
| `--source` | 出所の帰属（`user`、`cli`、カスタムラベルなど） |
| `--file` | ファイルから内容を読み取る（内容に引用符/複数行がある場合） |

```bash
hmg memorize "このプロジェクトの主データベースは PostgreSQL 16 で、MongoDB は使わない" --source cli
```

> 同じ内容は重複して書き込まれません（既存の atom が返る）。スコープ未指定時はカレントディレクトリから推論します。

### hmg recall

自然言語で記憶をリコールします。

```
hmg recall <query> [--max-results <n>] [--profile compact|summary|full|debug]
                   [--scope <t/w/r/b>] [--include-negated] [--precision]
```

```bash
hmg recall "データベース選定の決定"
hmg recall "ログイン 500 の根本原因" --profile full
```

| パラメータ | 説明 |
|---|---|
| `--profile` | 出力の詳細度：`compact`（既定）/ `summary` / `full`（エッジつき）/ `debug`（検索診断つき） |
| `--include-negated` | 否定済みの記憶を含む（「以前正しいと思っていた情報」の確認用） |
| `--precision` | より厳格なリコールゲーティング |

### hmg correct

記憶を 1 件訂正します。

```
hmg correct <atom_id> --action <action> --reason <text> [--new-content <text>]
```

`--action` の値：`replace` / `confirm-actual` / `confirm-necessary` / `demote-possible`。

```bash
hmg correct 01J9ZK8... --action replace \
  --reason "v3 で PostgreSQL に移行済み" \
  --new-content "主データベースは PostgreSQL 16 で、旧 MongoDB 方案を置き換え"
```

> 記憶の否定は `govern quarantine`（CLI レイヤー）を使用。MCP/SDK レイヤーは `negate` に対応。`negate` は正確に元に戻せず、復旧は `replace` を使います。

### hmg govern

記憶のライフサイクルをガバナンスします。

```
hmg govern <atom_id> --action <action> --reason <text> [--lesson <text>] [--destroy-payload]
```

`--action` の値：`quarantine` / `seal` / `tombstone` / `derive-lesson`。

```bash
# 機密情報の誤記：完全消去
hmg govern 01J9ZK8... --action tombstone --destroy-payload --reason "API キーを誤って書いた"

# 秘匿化された教訓を抽出し、原文を無効化
hmg govern 01J9ZK8... --action derive-lesson --reason "原文に認証情報を含む" \
  --lesson "認証情報は secret vault に保存し、通常の記憶に入れない"
```

### hmg history / stats / export

```
hmg history <atom_id>          # ある記憶の完全な訂正/ガバナンスの変遷
hmg stats                      # atom / edge / インデックス / スナップショットバージョンの統計
hmg export [--format json|csv] [--output <path>]   # すべての atom と edge をエクスポート
```

---

## タスクコンテキスト

### hmg agent-brief

タスク開始時のコンテキスト要約（前回の引き継ぎ、重要な決定、既知の問題、未完了事項）。

```
hmg agent-brief [<query>] [--profile compact|summary|full|debug] [--scope <t/w/r/b>]
```

```bash
hmg agent-brief --query "ログイン API のたまに出る 500 を修正する"
```

> Agent 統合ではブリーフは SessionStart hook が自動注入するため、手動呼び出しは不要です。

### hmg handoff

タスク終了時に引き継ぎ要約を書き込みます（次のセッションの起動ブリーフが優先的にリコール）。

```
hmg handoff <summary> [--source <src>] [--scope <t/w/r/b>]
```

```bash
hmg handoff "ログイン 500 を修正：token の期限検証を UTC に変更。検証：200 並列で 500 なし。リスク：旧クライアントが expiry をキャッシュ。次：refresh token のフローを確認。"
```

> 5 要素をカバー推奨：何をしたか / なぜ / 検証 / リスク / 次のステップ。

---

## クエリ

| コマンド | 用途 |
|---|---|
| `hmg query <intent-task> <query-text>` | 構造化クエリテンプレートを実行（決定の追跡など） |
| `hmg query --sql <sql>` | 読み取り専用 MemoryQL クエリ（上級） |
| `hmg query-templates` | 利用可能なクエリテンプレートを一覧 |
| `hmg suggest-query <text>` | HMG に聞き方を提案させる |
| `hmg explain-query` | クエリプランを説明 |
| `hmg schema` | MemoryQL の論理スキーマを表示 |
| `hmg recall-view <query> --view <id>` | 名前つきビューでリコール（normal / governance / audit） |
| `hmg noise-feedback <content>` | ノイズ句をフィードバックし、検索時に降権 |
| `hmg panorama <query>` | より広いグラフコンテキストを探索 |
| `hmg impact <query>` | ある変更の影響面を評価 |

```bash
hmg query-templates                 # まずテンプレートを確認
hmg query <intent-task> "キャッシュ選定の決定"
hmg noise-feedback "npm install 成功"
```

---

## インストールと接続

### hmg setup / init / doctor

```
hmg setup [--dry-run] [--no-daemon] [--no-model] [--no-agent-adapters]
hmg init [--global] [--agent <id>] [--all-agents] [--dry-run]
hmg doctor [--agent <id>] [--all-agents] [--fix] [--live-tool-smoke] [--verbose]
```

| コマンド | 役割 |
|---|---|
| `setup` | ローカルランタイムを準備（デーモン、埋め込みモデル） |
| `init` | Agent 接続設定を書き込み（MCP、hooks、記憶ポリシーファイル）。`--dry-run` でプレビュー |
| `doctor` | ヘルスチェック：コア / store / 統合 / ランタイム。`--fix` で修復可能な項目を自動修復 |

```bash
hmg setup
hmg init --agent codex --dry-run
hmg init --agent codex
hmg doctor --agent codex
```

### hmg login / account status

```
hmg login
hmg account status
```

基本的な記憶機能はログインなしで使えます。公式サイトのユーザーセンターでプランをアップグレードした後、`hmg login` を実行してアカウントをオンライン検証し、対応する機能と容量をアンロックします。ログインはローカルデータを移行せず、tenant は常に OS のユーザー名です。

### hmg onboard

既存の agent 記憶をインポートし、実際のリコールで検証します。

```
hmg onboard [--import <file>] [--memory-path <path>] [--all] [--dry-run] [--non-interactive]
```

> Agent に「記憶を HMG にインポートして」と話しかける（`hmg-memory-import` skill）のは対話型のインポートで、`hmg onboard` は CLI による直接インポートです。

### その他

```
hmg update [--installer-url <url>]    # アップグレード
hmg uninstall [--purge-data]          # アンインストール（既定で store データは保持）
hmg integrations list|detect|explain|remove   # Agent 統合の管理
hmg version                           # バージョンと edition
```

---

## ランタイム

```
hmg daemon start|status|stop|restart [--store <path>]
hmg daemon install-service            # ユーザーサービスとしてインストール（自動起動）
hmg model status                      # 埋め込みモデルの状態
```

hooks とイベントブリッジ：

```
hmg hook dispatch --host <id> --event <name> [--payload <json>]   # ホスト hook の統一入口
hmg hook status [--host <id>] [--session-id <id>]                 # セッションとレシートの診断（本文なし）
hmg agent-event --payload <json> [--explain] [--dry-run]          # 外部 agent ライフサイクルイベントのブリッジ
hmg agent-timeline --event-id <id>                                # 永続化された agent タイムラインの照会
```

> `hmg hook dispatch` はホストの hook スクリプトから呼ばれます（[統合](integration.md)参照）。通常は手動実行不要で、hook 経路の排查時に手動で検証できます。

---

## store メンテナンス

```
hmg store migrate --from <path> --to <path> [--backup] [--apply|--dry-run]
hmg store hygiene [--scope <t/w/r/b>] [--dry-run] [--force]      # 孤立エッジ/インデックスを掃除
hmg store repair-edges [--backup] [--apply] [--dry-run]          # 破損エッジを修復
hmg verify                                                        # グラフとストレージの整合性検証
```

---

## secret vault

認証情報は通常の記憶に入れません。vault へ：

```
hmg secret store <name> <value>     # 保存
hmg secret lookup <name>            # メタデータを確認（平文は出さない）
hmg secret use <name>               # サーバー側の認可された使用
hmg secret reveal <name>            # 必要時に平文を表示
hmg secret rotate <name> <new>      # ローテーション
hmg secret revoke <name>            # 失効
```

---

## 観察レイヤー（任意）

Agent 統合では起動しません。CLI / 自動化パイプライン向け：

```
hmg obs capture <content> [--source <src>]   # 観察を 1 件捕捉
hmg obs review-queue                         # 昇格待ちの観察を見る
hmg obs promote [--dry-run]                  # 長期記憶に昇格
hmg obs forget [<id>|--query <text>] [--confirm]   # 観察を削除
hmg obs maintain                             # 保持ポリシーのクリーンアップを実行
hmg observation config get|set <field> <value>     # 観察の設定
hmg observation scheduler status|run-once          # マージスケジューラー
```

---

## その他

```
hmg tui [--theme <name>] [--language <lang>]   # ターミナル UI
hmg language show|list|set <lang>|reset        # CLI の言語
hmg completions <shell>                        # shell 補完スクリプト
```

---

次：[MCP リファレンス](mcp-reference.md)
