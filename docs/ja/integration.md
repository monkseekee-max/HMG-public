# 統合

HMG は MCP プロトコルとホストネイティブの hooks を通じて各種 Agent に統合されます。この章は 2026 年 8 月に確定した統合レイヤー設計に基づきます。

## 統合すると何が得られるか

統合後、Agent は日常の会話の中で正確な記憶管理を自動で行います。「これを覚えて」「先に履歴コンテキストを思い出して」と毎回指示する必要はありません。

具体的には：

- **セッション開始時**、Agent は自動的に記憶ブリーフ（前回の引き継ぎ、重要な決定、既知のリスク、次のステップ）を受け取ります。
- **毎ターン**、あなたのメッセージで関連記憶を先取り検索し、現在のコンテキストに補います。
- **スコープは自動分離**：プロジェクト / リポジトリ / ブランチはセッションのディレクトリから機械的に推論・注入され、Agent は渡さず、間違えることもありません。
- **書き込みは完全に自律**：Agent は決定ややり取りの発生時に `memorize` で増分保存し、タスク終了時に `handoff` で引き継ぎを書きます。
- 新しい情報が古い記憶と矛盾するとき、Agent は古い記憶を訂正（`correct`）し、古い結論を使い続けません。

これにより Agent は現在のセッションコンテキストだけに頼らず、継続的に蓄積し、必要に応じて呼び出せる長期記憶を持ちます。同じプロジェクトで長く使うほど、Agent はあなたのコードベース、規約、好みをより深く理解します。

## 仕組み

統合レイヤーは 3 つの部分から成ります：

1. **MCP サーバー**：Agent は MCP ツールで記憶を読み書きします（`memory_memorize` / `memory_recall` / `memory_correct` / `memory_govern` / `memory_handoff` / `memory_stats`）。
2. **ライフサイクル hooks（3 個）**：決まったタイミングでコンテキストを自動注入したり、パラメータを校正します。

   | Hook | タイミング | 役割 |
   |---|---|---|
   | `SessionStart` | セッション起動 / 復帰 / クリア / 圧縮後 | 記憶ブリーフ + ステータス行を出力 |
   | `UserPromptSubmit` | ユーザーメッセージごと | メッセージで関連記憶を先取り検索。必要に応じて保存を促す |
   | `PreToolUse` | Agent が HMG MCP ツールを呼ぶ前 | セッションディレクトリからスコープを推論し、ツール引数に注入 |

3. **記憶ポリシーファイル**（`hmg.md` / rules / CLAUDE.md への注入）：いつ自律検索するか、いつ保存するか、出所をどう判断するか、機密情報をどう扱うかを Agent に指導します。

設計上の 2 つの硬性ルール：

- **記憶の書き込みチャネルは 2 つだけ**：`memorize`（増分）と `handoff`（引き継ぎ）。機械的なフォールバックはありません——ルールスコアリングは「この会話に重要な決定が暗に含まれる」ことを判断できず、長期記憶は完全に Agent の自発性に依存します。
- **observation パイプラインは起動しない**：Agent 統合では元の会話やコマンド出力の機械的な捕捉を行わず、低品質な記憶の汚染を防ぎます。

## 共通の接続フロー

```bash
# 1. ローカルランタイムを準備
hmg setup

# 2. ある Agent にどのファイルが書き込まれるかプレビュー
hmg init --agent codex --dry-run

# 3. 実際に設定を書き込む
hmg init --agent codex

# 4. 接続状態を確認
hmg doctor --agent codex
```

`hmg init` が推奨エントリーポイントです。ホストごとに対応する MCP 設定、memory policy、lifecycle hooks を書き込みます。手動設定では `hmg-server` を直接使用します。

## Codex への接続

Codex の接続形態：

- `~/.codex/config.toml`：`hmg` MCP サーバーを登録
- `~/.codex/hooks.json`：3 個のライフサイクル hooks を登録
- `~/.codex/hooks/hmg-lifecycle.sh`：ホストイベントを `hmg hook dispatch` に渡す薄いアダプター（すべてのロジックは HMG バイナリ内部）
- `~/.codex/hmg.md`：自律記憶ポリシーを注入

### 設定のプレビュー

```bash
hmg init --agent codex --dry-run
```

### 設定の適用

```bash
hmg init --global --agent codex

# または現在のプロジェクトコンテキストに紐付く設定のみ更新
hmg init --agent codex
```

### MCP 設定例

`hmg init` が自動で書き込みます。形態は次のとおり：

```toml
[mcp_servers.hmg]
type = "stdio"
command = "/Users/<user>/.local/bin/hmg-server"
args = ["/Users/<user>/.local/share/hmg/stores/default"]
startup_timeout_sec = 30

[mcp_servers.hmg.env]
HMG_PROVIDER_BACKEND = "local"
HMG_USE_LOCAL_DAEMON = "1"
```

> `mcp_servers.hmg` に固定の `cwd` を設定しないでください：MCP サーバーの子プロセスはセッションの作業ディレクトリを継承する必要があり、HMG はそれに依存してスコープを推論します。

### hooks の挙動

- **SessionStart**：HMG が記憶ブリーフ（直近の引き継ぎ、重要な決定）+ ステータス行（`HMG Active | scope=... | atoms=N`）を組み立て、コンテキストとしてセッションに注入します。
- **UserPromptSubmit**：現在のユーザーメッセージを query として先取りリコールを実行。ヒットすれば Agent はそのまま使い、未命中時はポリシーに従って自律的に追加検索できます。
- **PreToolUse**：Agent が `mcp__hmg__*` ツールを呼ぶ前に、セッションディレクトリからスコープを推論して引数に注入します。Agent が誤ったスコープを渡した場合は静かに訂正されます。

### 検証

```bash
hmg doctor --agent codex
hmg doctor --agent codex --live-tool-smoke
```

接続に成功すると、Codex に `memory_memorize`、`memory_recall`、`memory_correct`、`memory_govern`、`memory_handoff`、`memory_stats` などの HMG ツールが表示されます。

## Cursor への接続

Cursor の接続ファイルは通常プロジェクトディレクトリにあります：

- `.cursor/mcp.json`
- `.cursor/rules/hmg-memory.mdc`
- `.cursor/hooks.json`
- `.cursor/hooks/hmg-lifecycle.sh`

### プレビューと適用

```bash
hmg init --agent cursor --dry-run
hmg init --agent cursor
```

### MCP 設定例

```json
{
  "mcpServers": {
    "hmg": {
      "command": "/Users/<user>/.local/bin/hmg-server",
      "args": ["/Users/<user>/.local/share/hmg/stores/default"],
      "env": {
        "HMG_DATA_DIR": "/Users/<user>/.local/share/hmg/stores/default",
        "HMG_PROVIDER_BACKEND": "local",
        "HMG_USE_LOCAL_DAEMON": "1"
      }
    }
  }
}
```

Cursor の hook イベント名は Codex と異なります（方言の違い）。アダプターレイヤーが自動で対応付けます：

| Codex イベント | Cursor イベント |
|---|---|
| `SessionStart` | `sessionStart` |
| `UserPromptSubmit` | `beforeSubmitPrompt` |
| `PreToolUse` | `preToolUse` |

`.cursor/rules/hmg-memory.mdc` が記憶利用ルールを注入します。役割は Codex の `hmg.md` と同じです。

### 検証

```bash
hmg doctor --agent cursor
```

詳しくは [Agent に HMG ツールが見えない](troubleshooting.md#agent-cant-see-hmg-tools) を参照。

## Claude Code への接続

Claude Code の接続ファイルは通常次を含みます：

- プロジェクト直下の `.mcp.json`
- プロジェクト直下の `CLAUDE.md`
- `~/.claude/settings.json`
- `~/.claude/hooks/hmg-lifecycle.sh`

### 設定

```bash
hmg init --agent claude --dry-run
hmg init --agent claude
```

### MCP 設定例

```json
{
  "mcpServers": {
    "hmg": {
      "command": "/Users/<user>/.local/bin/hmg-server",
      "args": ["/Users/<user>/.local/share/hmg/stores/default"],
      "env": {
        "HMG_DATA_DIR": "/Users/<user>/.local/share/hmg/stores/default",
        "HMG_PROVIDER_BACKEND": "local",
        "HMG_USE_LOCAL_DAEMON": "1"
      }
    }
  }
}
```

Claude Code の hook イベント名は Codex と完全に同じ（`SessionStart` / `UserPromptSubmit` / `PreToolUse`）で、`~/.claude/settings.json` の hooks セクションに設定されます。挙動も Codex と同じ：起動時ブリーフ、毎ターンの先取り検索、スコープの機械的注入。

### 検証

```bash
hmg doctor --agent claude
```

## 一時セッションの記憶の帰属

Codex デスクトップの左下 Chats から開く一時セッションは、どのプロジェクトにも紐付きません。こうしたセッションは固定のスコープを共有します：

```
<os-username> / personal / chats / main
```

- 異なる一時セッション間で記憶は共通です（セッションディレクトリの違いで分離されない）
- 一時セッションとプロジェクトセッションは相互に分離：一時セッションで保存したユーザーの好みはプロジェクトセッションに自動では現れません。必要な場合はプロジェクトセッションで再度 memorize してください

## 既存記憶のインポート {#importing-existing-memories}

HMG を使う前にすでに会話履歴やホストネイティブの記憶ファイル（Codex memories、CLAUDE.md、Cursor rules など）がたまっている場合は、`hmg-memory-import` skill で一括インポートできます：

Agent に「**記憶を HMG にインポートして**」と話しかけると：

1. 会話履歴とネイティブ記憶ファイルをスキャンし、長期的な価値のある項目を抽出
2. 帰属で分類：プロジェクト関連 → 現在のプロジェクトスコープ、プロジェクト横断のユーザーの好み → `personal/chats/main`
3. 確認用の一覧を表示し、確認後に 1 件ずつ書き込み、結果を報告

この skill は `~/.codex/skills/hmg-memory-import/`（Claude Code では `~/.claude/skills/`）に置かれ、HMG に同梱されます。

## その他の MCP クライアント

HMG が対応する Agent は上記 3 つだけではありません。現在の対応一覧の確認：

```bash
hmg integrations list
hmg integrations detect
hmg integrations explain codex cursor claude
```

### 汎用 MCP 接続方法

MCP 互換のクライアントなら手動で接続できますが、`hmg init` による自動生成が依然おすすめです。

1. クライアントの MCP 設定にサーバーを追加：
   ```json
   {
     "mcpServers": {
       "hmg": {
         "command": "/Users/<user>/.local/bin/hmg-server",
         "args": ["/Users/<user>/.local/share/hmg/stores/default"]
       }
     }
   }
   ```
2. store やデーモン形態を指定する場合は、環境変数に `HMG_DATA_DIR`、`HMG_USE_LOCAL_DAEMON=1` を追加。
3. クライアントに `memory_memorize`、`memory_recall`、`memory_correct`、`memory_handoff` などのツールが並ぶことを確認。

hooks のないホストでも使えます：MCP の読み書きは完全に利用可能で、スコープは HMG が MCP サーバープロセスの作業ディレクトリから推論します——ただし 2 つの自動注入ポイント（セッション起動時のブリーフと毎ターンの先取り検索）はありません。

### 外部イベントブリッジ

MCP を直接接続しにくいホストは、lifecycle bridge 経由でも接続できます：

```bash
hmg agent-event --explain --payload '{"event":"pre_edit_recall","files":["src/lib.rs"]}'
```

---

次：[トラブルシューティング](troubleshooting.md)
