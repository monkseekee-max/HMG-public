# HMG クイックスタート

## 前提条件

- Linux (x86_64 または ARM64) または macOS (Intel または Apple Silicon)
- MCP (Model Context Protocol) をサポートする AI エージェントまたはコーディングツール

## インストール

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```

### Windows (PowerShell)

```powershell
irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex
```

### WSL (Windows Subsystem for Linux)

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```


または [GitHub Releases](https://github.com/HMG-AI/HMG-public/releases) から直接ダウンロード：

```bash
# Linux x86_64
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-x86_64-unknown-linux-gnu.tar.gz | tar -xzf - -C ~/.local/bin/

# macOS Apple Silicon
curl -L https://github.com/HMG-AI/HMG-public/releases/latest/download/hmg-1.7.1-aarch64-apple-darwin.tar.gz | tar -xzf - -C ~/.local/bin/
```

## 確認

```bash
hmg --version
# hmg 1.7.1-community
```

## メモリサービスの起動

```bash
hmg daemon start
```

デーモンはデフォルトで `~/.local/share/hmg/stores/default` にローカル MCP サーバーを起動します。
データがマシン外に送信されることはありません。

## エージェントの接続

### Cursor

```bash
hmg init --agent cursor
# Cursor を再起動。HMG ツールが MCP 設定に表示されます。
```

### Claude Code (Codex)

```bash
hmg init --agent codex
```

### Pi

```bash
hmg init --agent pi
```

### 汎用 MCP クライアント

HMG は標準入出力で標準 MCP サーバーを公開します。クライアントの設定：

```json
{
  "mcpServers": {
    "hmg": {
      "command": "hmg-server",
      "args": ["~/.local/share/hmg/stores/default"]
    }
  }
}
```

## 最初のメモリ

MCP ツールを使用してメモリを保存・取得：

```json
// 意思決定を保存
{
  "tool": "memory_memorize",
  "arguments": {
    "content": "決定：ユーザーデータに PostgreSQL を使用。理由：ACID 準拠と成熟したツール。",
    "source": "architecture-review",
    "modality": "text"
  }
}

// 後で検索
{
  "tool": "memory_recall",
  "arguments": {
    "query": "どのデータベースを選択しましたか？"
  }
}
```

## Community Edition の利用可能機能

| 機能 | 利用可能 |
|---|---|
| メモリ保存 (memorize) | ✅ |
| メモリ取得 (recall) | ✅ One-Shot Recall (P1-P9) |
| 修正ライフサイクル | ✅ 完全 |
| ガバナンスライフサイクル | ✅ 完全 |
| MCP プロトコル | ✅ 完全 |
| HTTP API | ✅ 完全 |
| エージェント統合 | ✅ 全アダプタ |
| One-Shot Recall | ✅ Full (P1-P9) |
| 自動統合 | ❌ Developer/Enterprise |
| ドメインパック | ❌ Developer/Enterprise |
| セマンティック（ベクトル）検索 | ❌ Developer/Enterprise |

## 次のステップ

- [コンセプト](concepts.md) — メモリアトム、修正、ガバナンス、スコープ
- [アーキテクチャ](architecture.md) — HMG の仕組み
- [API リファレンス](api-reference.md) — 全 MCP ツールと HTTP エンドポイント
- [修正とガバナンス](correction-governance.md)
- [FAQ](faq.md)
- [Developer へのアップグレード](upgrade.md)
