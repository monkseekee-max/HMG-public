# 設定

## 設定ファイルの説明

HMG が関わる設定は大きく 3 種類：Agent 統合ファイル、store データディレクトリ、ランタイム環境変数。ここではユーザーが実際に触れるものだけを挙げます。

| ファイル | 役割 | 生成元 |
|------|------|--------|
| `~/.codex/config.toml` / `.cursor/mcp.json` / `.mcp.json` | ホストに HMG MCP サーバーの起動方法を伝える | `hmg init --agent <id>` |
| `~/.codex/hooks.json` / `.cursor/hooks.json` / `~/.claude/settings.json` | ホストのライフサイクル hooks（SessionStart / UserPromptSubmit / PreToolUse の 3 個） | `hmg init --agent <id>` |
| `AGENTS.md` / `CLAUDE.md` / `.cursor/rules/hmg-memory.mdc` | Agent の memory policy と利用規約 | `hmg init --agent <id>` |
| store ディレクトリ | データ本体（記憶/インデックス/観察） | 自動作成 |

### store path

- デフォルト store：`<ユーザーデータディレクトリ>/hmg/stores/default`
  - macOS/Linux：`~/.local/share/hmg/stores/default`
  - Windows：通常 `%LOCALAPPDATA%\hmg\stores\default`
- `--store <path>` で任意の store を指定。
- 多くのコマンドが `--store` に対応。例：`hmg memorize "..." --store /my/store`。

### 身份とログイン（store.toml）

store ディレクトリ配下の `store.toml` にマシンの身份を記録します：

```toml
# ~/.local/share/hmg/stores/default/store.toml

[identity]
local_tenant = "qiankun"              # OS のユーザー名。hmg init 時に書き込まれ、以後不変
linked_account = "userB"              # hmg login ログイン後に書き込まれ、ログアウト時に消去
linked_at = "2026-07-28T10:00:00Z"    # ログイン時刻
```

- **local_tenant**：すべての記憶の tenant（スコープの第 1 層）はこれで、`hmg init` 時に OS のユーザー名を書き込み、以後変わりません。
- **linked_account**：公式サイトでプランをアップグレード後に `hmg login` を実行して書き込まれる HMG ユーザーセンターのアカウント。ログインによる**データ移行は一切なし**——ローカルの読み書きは常に `local_tenant` を使い、アカウントのマッピングはクラウド同期時のみ使用。
- ログアウト / アカウント変更：`linked_account` を消去するだけで、ローカルの記憶には影響なし。

### 環境変数

[よく使う環境変数](#common-env-vars) を参照。

## Store ディレクトリの説明 {#store-directory}
store は HMG データのルートディレクトリです。

### 既定の場所

上記参照。`hmg doctor --verbose` が実際に使う data directory を表示するので、まずその出力を基準にしてください。

### プロジェクト store の選び方

- **デフォルト store + スコープ**：repository/branch でプロジェクトを区別（Agent 統合の既定——スコープはセッションディレクトリから自動推論）。複数ディレクトリを管理したくない場合に適する。
- **プロジェクト独立 store**：`--store /path/to/proj`。物理的に隔離し、汚染を防ぐ。複数プロジェクトに推奨。

### バックアップと移行

```bash
# 方法 1: store ディレクトリを直接コピー
cp -r /old/store /backup/store

# 方法 2: 公式移行（バックアップつき）
hmg store migrate --from /old/store --to /new/store --backup --apply

# まず dry-run でプレビュー
hmg store migrate --from /old/store --to /new/store --dry-run
```

### メンテナンスコマンド

```bash
# 孤立エッジ/インデックスを掃除
hmg store hygiene --dry-run
hmg store hygiene

# 破損したエッジを修復
hmg store repair-edges --dry-run
hmg store repair-edges --backup --apply
```

## よく使う環境変数 {#common-env-vars}
ローカルでよく使うものだけを挙げます。

| 変数 | 役割 |
|------|------|
| `HMG_STORE` | デフォルト store パス |
| `HMG_DATA_DIR` | 現在のホストが使うデータディレクトリ |
| `HMG_PROVIDER_BACKEND` | 現在の provider backend。一般的には `local` |
| `HMG_USE_LOCAL_DAEMON` | ローカルデーモンを優先するか |
| `HMG_CONSOLIDATION_SCHEDULER` | 観察マージスケジューラー（`embedded` など、observation シーンのみ） |
| `HMG_CAPTURE_MODE` | 観察捕捉モード（`raw-with-retention` など） |
| `HMG_PROMOTION_MODE` | 観察昇格モード（`execute` など） |
| `HMG_AUTOMATION_TIER` | 自動化レベル（`remember-first-govern-later` など） |
| `HMG_AGENT_ID` | 現在のホスト識別子。`codex` / `cursor` / `claude` など |
| `HMG_HTTP_ADDR` | HTTP fallback を有効にしたときのローカルアドレス |

### observation の設定確認とスケジューリング

> observation パイプラインは Agent 統合では起動しません（長期記憶は agent が自発的に呼ぶ memorize/handoff で書き込み）。以下のコマンドは手動 / 自動化パイプライン向けです。

```bash
hmg observation config get
hmg observation config set capture_mode raw-with-retention
hmg observation scheduler status
hmg observation scheduler run-once
```
