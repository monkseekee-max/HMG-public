---
sidebar_position: 2
---

# クイックスタート

## HMG のインストール

HMG は単体のバイナリとして公式インストーラーで配布されます。インストーラーはプラットフォームを検出し、既定のディレクトリにインストールして PATH を設定します。

### macOS / Linux

```bash
curl -fsSL https://github.com/HMG-AI/HMG-public/releases/latest/download/install.sh | sh
```

### Windows

```powershell
irm https://github.com/HMG-AI/HMG-public/releases/latest/download/install.ps1 | iex
```

### インストールの確認

```bash
hmg version
# 出力例: hmg 1.7.8-developer
```

### アップグレード

```bash

# 最新版へアップグレード（インストール済みならこちら）
hmg update

# インストール元を指定する場合
hmg update --installer-url <公式インストーラーURL>
```

### アンインストール

インストールディレクトリを削除し、PATH から該当項目を削除してください。store のデータは自動的に削除されません（記憶は保持されます）。完全に消す場合は store ディレクトリを手動で削除してください。

> インストールに失敗する場合 → [インストール失敗](troubleshooting.md#install-failure)

## ログインとプラン（任意）

基本的な記憶機能はログインなしで使えます。開発者版の機能とより大きな記憶容量を利用するには：

1. HMG 公式サイトのユーザーセンターで**プランをアップグレード**
2. ローカルでログイン：

```bash
hmg login
```

ログインにはネットワークが必要です：HMG がリモートサービスでアカウントを検証し、プラン情報を識別して署名を受け取り、ローカルで署名検証が成功すると対応する機能がアンロックされます。

- ログインによる**データ移行は一切ありません**：ローカルの読み書きは常に OS のユーザー名をテナントとして使い、アカウント情報はクラウド同期時の身份対応にのみ使用されます
- ログアウトやアカウント変更はクラウド側の身份にのみ影響し、ローカルの記憶には影響しません

## ローカルで HMG を起動

初回インストール後、まずローカルランタイムを準備します。`setup` はデーモン、埋め込みモデル、ローカル実行に必要なコンポーネントを扱います。

### ランタイムの準備

```bash
# setup が何をするかプレビュー
hmg setup --dry-run

# 実際にローカルランタイムを準備
hmg setup
```

### 起動確認

```bash
hmg doctor
```

`doctor` はコア、store、統合、ランタイムの状態をチェックします。初回は一部の Agent が未接続と表示されることがありますが、正常です。

### Agent の接続

Codex、Cursor、Claude Code に日常の会話で記憶を自動管理させたい場合：

```bash
hmg init --agent codex --dry-run
```

その後、実際に使う Agent に対して `hmg init --agent <agent-id>` を実行します。詳細は [統合](integration.md) を参照。

---

## 記憶の書き込み・呼び出し・修正

HMG の記憶操作は 3 つのコアコマンドに集約されます：書き込み、呼び出し、修正。簡単な例で一通り試します。

### 1. 記憶を書き込む

```bash
hmg memorize "このプロジェクトのローカルキャッシュは SQLite を使い、Redis は導入しない。オフライン優先のため" --source quick-start
```

独立した一文で十分です：「決定：」のような接頭辞は不要で、HMG が確信度や極性などのメタデータを自動推論します。出力には atom id（記憶の一意識別子、例：`atom-xxxx`）が返ります。次のステップで使うので控えておいてください。

### 2. 記憶を呼び出す

```bash
hmg recall "ローカルキャッシュは何を使う？"
```

先ほど書き込んだ「SQLite キャッシュ」が結果に出れば、書き込みと呼び出しの経路は正常です。

### 3. 記憶を修正する

古い記憶が間違っている・更新が必要なときは、追加ではなく `correct` で修正します：

```bash
# 先ほど書き込んだ記憶の内容を新しい記述に置き換える
hmg correct atom-xxxx --action replace --reason "LevelDB に変更" --new-content "このプロジェクトのローカルキャッシュは LevelDB を使い、Redis は導入しない。オフライン優先のため"
```

再度 `hmg recall "ローカルキャッシュは何を使う？"` を実行すると、更新後の内容が返ります。

> Agent を接続すると、これら 3 ステップは Agent が適切なタイミングで自動実行します。手動操作は不要です。接続方法は [統合](integration.md) を参照。

---

次：[日常利用ガイド](daily-usage.md)
