# トラブルシューティング

## インストール失敗 {#install-failure}
**症状**：`hmg --version` が無出力、またはコマンドが見つからない。

**対処**：
1. インストーラーが正常終了したか確認し、PATH に HMG のインストールディレクトリが含まれるかチェック。
2. 公式インストールコマンドを再実行。
3. バイナリを直接検証：
   ```bash
   /フルパス/hmg --version
   ```
4. ネットワーク/権限問題でダウンロード失敗の場合、プロキシとディスク権限を確認。

## Agent に HMG ツールが見えない {#agent-cant-see-hmg-tools}
**症状**：Agent のセッションに `memory_memorize` / `memory_recall` などの `memory_*` ツールがない。

**対処**：
1. MCP 設定が生成されたか確認：`hmg doctor --agent <id>`。
2. `hmg init --agent <id> --dry-run` を実行し、現バージョンがどのホストファイルを書くか確認。
3. 設定が `hmg-server <store-path>` を使っているか確認。
4. Agent を再起動（MCP 設定は通常再起動で有効化）。
5. ローカルランタイムを検証：`hmg doctor`、`hmg daemon status`。
6. Agent 自身の MCP / hooks ログに接続エラーがないか確認。

```bash
hmg doctor --agent codex
hmg init --agent codex --dry-run
hmg daemon status
```

## セッションに記憶コンテキストが注入されない

**症状**：新規セッション開始時に記憶ブリーフがない、または毎ターン先取り検索の結果がない。

**対処**：
1. hooks が登録され、3 イベント（`SessionStart` / `UserPromptSubmit` / `PreToolUse`）を含むか確認：
   ```bash
   cat ~/.codex/hooks.json        # Codex
   cat .cursor/hooks.json         # Cursor
   ```
2. アダプタースクリプトが存在し実行可能か確認：`ls -l ~/.codex/hooks/hmg-lifecycle.sh`。
3. dispatch の経路を手動検証（プロジェクトディレクトリ内で実行）：
   ```bash
   echo '{"hook_event_name":"SessionStart","cwd":"'"$PWD"'"}' | ~/.codex/hooks/hmg-lifecycle.sh
   ```
   正常なら記憶ブリーフのテキストが出力されます。無出力やエラーの場合は `hmg doctor` を確認。
4. hook の失敗は静かにスキップされます（Agent をブロックしない）。「エラーはないがブリーフもない」場合は上記の手順で能動的に排查してください。
5. 再接続：`hmg init --agent <id>` で hooks 設定を書き直します。

## HMG サービスが起動していない

**症状**：コマンドがデーモン不可用、モデル未準備と報告、または direct フォールバックが継続。

**対処**：
1. まず `hmg setup` を実行し、ローカルランタイムが準備済みか確認。
2. `hmg model status` で埋め込みモデルの状態を確認。
3. `hmg daemon status` でデーモンの状態を確認。
4. 起動失敗時はエラーメッセージを確認。store パスが違えば `--store` で指定。
5. 依然異常なら：`hmg daemon restart`、または一時的に `--direct` でデーモンを迂回して store を直接開く。
6. 自動起動が必要なら `hmg daemon install-service`。

```bash
hmg setup
hmg model status
hmg daemon status
```

## ログイン失敗 / プランが反映されない

**症状**：`hmg login` がエラー、または公式サイトでプランをアップグレードしたが機能がアンロックされない。

**対処**：
1. ログインにはネットワークが必要：HMG ユーザーセンターに到達できるか確認（プロキシも確認）。
2. 公式サイトでプランのアップグレードが完了していること、`hmg login` に使うアカウントがプランを購入したアカウントと一致することを確認。
3. 署名検証の失敗は 1 回再試行。それでも失敗する場合は `hmg doctor --verbose` の出力を添えてサポートに連絡。
4. ログインは開発者版の機能と容量上限にのみ影響します。基本的な記憶機能はログインなしで使えます。

## 欲しい情報がリコールできない {#recall-cannot-find}
**考えられる原因と対処**：

| 原因 | 対処 |
|------|------|
| query が広すぎる、または口語的 | 名詞句を使う。`ログイン 500 の根本原因` は「前はどう処理したっけ」より良い |
| そもそも記憶していない | まず `hmg memorize` で補う |
| スコープが違う | 現在のリポジトリ/ブランチが記憶時と不一致なら `--scope` を指定。一時セッションの記憶は `personal/chats/main` にあり、プロジェクトセッションからは見えない点に注意 |
| 記憶が格下げ/墓碑化されている | `hmg history <id>` で状態を確認 |
| ノイズの干渉 | `hmg noise-feedback` でノイズ句をフィードバック |
| 表記/用語の違い | 同義語を試すか、`hmg suggest-query` で HMG に提案させる |

## リコール結果が多すぎる・乱れている

**対処**：
1. query を絞る。
2. `--max-results <n>` で件数を制限。
3. `--profile compact` で出力を簡潔に。
4. 古い記憶を整理：`hmg store hygiene`、古い情報の訂正/格下げ。
5. ノイズのフィードバック：`hmg noise-feedback "<ノイズ句>"`。

## 記憶を間違えて書いた

**削除ではなく訂正**：

```bash
# 内容が間違い → 置換
hmg correct <atom-id> --action replace --reason "書き間違い" --new-content "正しい内容"

# もう不要 → 格下げ
hmg correct <atom-id> --action demote-possible --reason "もはや適用されない"
```

replace を間違えたら、その atom に対してさらに replace。訂正は履歴を保持し、`hmg history <atom-id>` で追跡できます。

## 機密情報を誤って書いた

**すぐにガバナンスし、削除だけで済ませない**（監査を保持）：

```bash
# 完全消去（墓碑化 + payload 破棄）
hmg govern <atom-id> --action tombstone --destroy-payload --reason "API キーを誤って書いた"

# 隔離のみ（内容は保持、リコールに出ない）
hmg govern <atom-id> --action quarantine --reason "機密情報を一時隔離"

# 秘匿化された教訓を抽出
hmg govern <atom-id> --action derive-lesson --lesson "認証情報は secret vault に保存すべき"
```

今後は `hmg secret store` で認証情報を保存してください。詳しくは [機密情報の削除または隔離](daily-usage.md#sensitive-memory-governance) を参照。

## 複数プロジェクトの記憶が混ざる

**原因**：デフォルト store を共用し、スコープで区別していない。

**対処**：
1. Agent 統合ではスコープがセッションディレクトリから自動推論されるため、通常は発生しません。プロジェクト外のディレクトリでセッションを起動した場合、記憶はそのディレクトリで推論されたスコープに入ります。
2. プロジェクト専用 store を使う：`hmg memorize "..." --store /proj/store`。
3. またはデフォルト store 内で明示的に `--scope repository`/`branch`。
4. プロジェクト横断の共通の好みだけ `--scope tenant` に置く。

スコープの仕組みは [スコープ](concepts.md#scope) を参照。

## store のロックやデーモンの異常

**症状**：書き込みがロックエラーになる、またはデーモンが無応答。

**対処**：
1. `hmg daemon status` で固まっていないか確認。
2. `hmg daemon restart` で再起動。
3. 複数プロセスが同じ store を奪い合っていないか確認（複数 Agent + 直接 CLI の同時書き込み）。デーモン経由に統一するのが推奨。
4. インデックス破損：`hmg store repair-edges --backup --apply`。
5. それでもダメなら：store をバックアップしてから `--direct` モードで操作し問題を切り分け。

## ローカルデータのバックアップまたは移行 {#backup-or-migrate-local-data}
```bash
# バックアップ：ディレクトリをコピー
cp -r "<storeディレクトリ>" ./hmg-backup-$(date +%F)

# またはエクスポート
hmg export --format json --output ./hmg-export.json

# 新しいマシン/パスへ移行
hmg store migrate --from /old/store --to /new/store --backup --apply
```

> デフォルトの store パスは [Store ディレクトリ](settings.md#store-directory) を参照。`hmg doctor --verbose` でも確認できます。

---

次：[FAQ](faq.md)
