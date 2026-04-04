# cclaude

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) を隔離されたコンテナ内で実行するコマンドラインツール。
カレントディレクトリだけがマウントされるため、Claude Code はプロジェクト外にアクセスできません。
Claude Code の状態（`~/.claude`）はホスト上に永続化されます。

## 機能

- **セキュリティ隔離**: Claude Code はコンテナ内で実行され、マウントされたプロジェクトディレクトリのみアクセス可能
- **メモリ永続化**: `~/.claude/`（プロジェクトメモリ、設定、会話履歴）はコンテナ再起動後も保持される
- **サブスクリプション & API キー対応**: Claude サブスクリプション（OAuth）と API キー認証の両方に対応
- **プリインストール済みツールチェーン**: Go、Node.js、Python（uv）がすぐに使える
- **サンドボックスの問題を回避**: コンテナレベルの隔離により、サンドボックスモードとビルドツールの非互換性を解消
- **自動検出**: Podman または Docker を自動検出（Podman 優先）
- **カスタマイズ可能**: TOML 設定ファイル + 環境変数オーバーライド。Dockerfile を拡張してツールチェーンを追加可能

## インストール

### 前提条件

- [Podman](https://podman.io/) または [Docker](https://www.docker.com/)
- Bash 3.2+
- コンテナ VM メモリ 8GB 以上（イメージビルド時）。Podman Machine: `podman machine set --memory 8192`

### ソースからインストール

```bash
git clone https://github.com/nlink-jp/cclaude.git
cd cclaude
make install        # /usr/local/bin/cclaude にインストール
cclaude --build     # コンテナイメージをビルド
```

`/usr/local/bin` に書き込み権限がない場合は、別のディレクトリを指定できます:

```bash
make install PREFIX=$HOME/.local    # ~/.local/bin/cclaude にインストール
```

`make install` で配置されるファイル:
- `cclaude` スクリプト → `$(PREFIX)/bin/cclaude`（デフォルト: `/usr/local/bin/cclaude`）
- `Dockerfile` → `~/.config/cclaude/Dockerfile`
- `config.toml` → `~/.config/cclaude/config.toml`（既存の場合はスキップ）

## クイックスタート

```bash
# コンテナイメージをビルド（初回のみ）
cclaude --build

# 任意のプロジェクトディレクトリで Claude Code を起動
cd ~/my-project
cclaude
```

## 使い方

```
cclaude [options] [-- claude-args...]
```

| オプション | 説明 |
|-----------|------|
| `cclaude` | カレントディレクトリで Claude Code を起動 |
| `cclaude --build` | コンテナイメージをビルド/リビルド |
| `cclaude --shell` | コンテナ内の bash シェルを開く（デバッグ用） |
| `cclaude --config` | 解決済みの設定を表示 |
| `cclaude --version` | バージョンを表示 |
| `cclaude --help` | ヘルプを表示 |
| `cclaude -- <args>` | `claude` に引数を直接渡す |

### 例

```bash
# 対話セッション
cclaude

# claude に引数を渡す
cclaude -- -p "go test ./... を実行して"

# デバッグ: コンテナのシェルに入る
cclaude --shell

# 解決済み設定を確認
cclaude --config
```

## 認証

### API キー

`ANTHROPIC_API_KEY` 環境変数を設定:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
cclaude
```

### サブスクリプション（OAuth）

API キーなしで `cclaude` を実行します。Claude Code がターミナルに OAuth ログイン URL を表示するので、
ホストのブラウザでその URL を開いて認証します。ログイン状態は `~/.claude/` に永続化されます。

## 設定

設定ファイル: `${XDG_CONFIG_HOME:-~/.config}/cclaude/config.toml`

環境変数は設定ファイルの値を上書きします。

```toml
[container]
runtime = "auto"       # "podman", "docker", "auto"（podman 優先）
image = "cclaude:latest"

[network]
# forward_ports = [8080, 11434]    # ホスト→コンテナ (socat)
# publish_ports = [3000, 5173]     # コンテナ→ホスト (-p)

[toolchain]
go_version = "1.23.4"
node_version = "20"

[paths]
claude_home = "~/.claude"
```

### 環境変数

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `ANTHROPIC_API_KEY` | Claude API キー（サブスクリプション利用時は不要） | — |
| `CCC_RUNTIME` | コンテナランタイム | `auto` |
| `CCC_IMAGE` | コンテナイメージ名 | `cclaude:latest` |
| `CCC_FORWARD_PORTS` | ホスト→コンテナ転送ポート（例: `8080,11434`） | — |
| `CCC_PUBLISH_PORTS` | コンテナ→ホスト公開ポート（例: `3000,5173`） | — |
| `CCC_CLAUDE_HOME` | Claude ホームディレクトリ | `~/.claude` |
| `CCC_GO_VERSION` | イメージビルド時の Go バージョン | `1.23.4` |
| `CCC_NODE_VERSION` | イメージビルド時の Node.js バージョン | `20` |
| `CCC_DRY_RUN=1` | コンテナコマンドを実行せず表示のみ | — |

## 仕組み

### パスマッピング

プロジェクトディレクトリはコンテナ内で**ホストと同じ絶対パス**にマウントされます:

```
ホスト:    /Users/user/my-project
コンテナ:  /Users/user/my-project  （同一パス）
```

Claude Code はプロジェクトメモリを絶対パスベースで保存します（例: `~/.claude/projects/-Users-user-my-project/`）。
同じパスを使用することで、ホストとコンテナ間でプロジェクトメモリの完全な互換性が維持されます。

### コンテナ専用の Claude ホーム

コンテナはホストとは独立した Claude Code 状態のコピーを使用します:

```
ホスト:    ~/.claude/                          （ホスト設定 — 変更されない）
コンテナ:  ~/.config/cclaude/claude-home/      （コンテナ専用コピー）
```

初回起動時に `cclaude` はホストの `~/.claude/` を `~/.config/cclaude/claude-home/` にコピーします。
以降はコンテナ用コピーが独立して使用されます。この設計により:

- **ホスト設定は変更されない** — ホスト側のサンドボックス、パーミッション、プラグイン設定はそのまま維持されます。
- **コンテナは独自の設定を持つ** — サンドボックスは自動的に無効化され（コンテナ自体が隔離を提供）、パーミッションも独立して変更可能です。
- **コンテナ再起動後も状態が保持される** — プロジェクトメモリ、会話履歴、OAuth トークン、プラグインはコンテナ用コピーに保持されます。

ホスト設定と再同期する場合（ホスト側でパーミッションを変更した後など）は、コンテナ用コピーを削除すると次回起動時に再作成されます:

```bash
rm -rf ~/.config/cclaude/claude-home
cclaude    # ホストの ~/.claude/ から再コピー
```

### ホストネットワークアクセス

#### ポートフォワーディング（推奨）

`forward_ports` を設定すると、ホストのサービスにコンテナ内から `localhost` としてアクセスできます。`socat` による透過的なポート転送を使用するため、コンテナ内の Claude Code やツールはコンテナで動作していることを意識する必要がありません。

```toml
[network]
forward_ports = [8080, 11434]   # 例: ローカル LLM API, Ollama
```

環境変数でも指定可能:

```bash
CCC_FORWARD_PORTS="8080,11434" cclaude
```

この設定により、コンテナ内の `http://localhost:8080` がホストの `localhost:8080` に到達します。

#### ポートパブリッシング（コンテナ→ホスト��

コンテナ内で動作するサービス（例: Claude Code が起動した開発サーバー）をホストからアクセス可能にするには:

```toml
[network]
publish_ports = [3000, 5173]
```

環境変数: `CCC_PUBLISH_PORTS="3000,5173" cclaude`

ホストの `127.0.0.1:3000` が��ンテナのポート 3000 に転送されます。

#### ホスト名による直接アクセス

ポートフォワーディングなしでも、ランタイム固有のホスト名でアクセス可能です:

| ランタイム | ホスト名 |
|-----------|----------|
| Podman | `host.containers.internal` |
| Docker | `host.docker.internal` |

### SSH エージェント転送

`--ssh` モードを使うと、ホストの SSH エージェント（1Password 含む）をコンテナに転送できます。コンテナ内で sshd を起動し `ssh -A` で接続することで、全プラットフォームで動作します:

```bash
cclaude --ssh
```

コンテナ内で `git clone`、`git push` などの SSH 操作がホストの SSH 鍵を使って行えます。鍵をコンテナにコピーする必要はありません。

**仕組み**: コンテナ内で sshd を起動し、ホストの SSH 公開鍵を認証用に注入、`ssh -A` でエージェント転送付きで接続します。終了時にコンテナは自動的に停止・削除されます。

**要件**: `~/.ssh/` に SSH 公開鍵（ed25519、RSA、または ECDSA）が必要です。

**デフォルトモード（`--ssh` なし）**: Linux では `SSH_AUTH_SOCK` がコンテナに直接マウントされます（高速、sshd 不要）。macOS ではデフォルトモードで SSH エージェントは利用できません（VM の制約）。代わりに `--ssh` を使用してください。

## イメージのカスタマイズ

デフォルトイメージには Go、Node.js、Python（uv）が含まれています。ツールチェーンを追加するには:

1. `~/.config/cclaude/Dockerfile` を編集
2. パッケージを追加（例: Rust、Java、Ruby）
3. リビルド: `cclaude --build`

### 例: Rust を追加

```dockerfile
# Dockerfile に追記
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
```

### 例: Java（Eclipse Temurin）を追加

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        temurin-21-jdk \
    && rm -rf /var/lib/apt/lists/*
```

## 開発

### 前提ツール

- [ShellCheck](https://www.shellcheck.net/) — bash スクリプトの静的解析
- [bats-core](https://github.com/bats-core/bats-core) — テストフレームワーク

```bash
# macOS
brew install shellcheck bats-core

# Debian/Ubuntu
apt install shellcheck bats
```

### Make ターゲット

```bash
make build        # スクリプト + アセットを dist/ にコピー
make install      # /usr/local/bin にインストール
make image-build  # コンテナイメージをビルド
make test         # shellcheck + BATS テスト
make lint         # shellcheck のみ
make clean        # dist/ を削除
```

## プラットフォームに関する注意事項

### macOS（Docker Desktop / Podman Machine）

Linux VM を経由するボリュームマウントは、ネイティブ Linux より I/O が遅くなる場合があります。
Docker Desktop および Podman Machine on macOS の既知の制限です。
大規模プロジェクトではネイティブ Linux の使用を検討してください。

### Docker: ファイル所有権

Docker（Podman でない場合）では、コンテナ内で作成されたファイルがホスト上で root 所有になる場合があります。
Podman のルートレスモードはコンテナの root をホストユーザーにマッピングするため、この問題を回避できます。
問題が生じた場合は、終了後に所有権を修正できます:

```bash
sudo chown -R "$(id -u):$(id -g)" .
```

### SELinux（Podman）

Podman 使用時は `--security-opt label=disable` が自動的に適用され、
SELinux 環境でのバインドマウントが正しく動作します。

### セキュリティ: `--ssh` モード

`--ssh` モードでは、コンテナ内で sshd が動作し、**ランダムな高ポート**（49152–65535）で `127.0.0.1` のみにバインドされます。アクセスはセッションごとに生成・破棄されるエフェメラル ed25519 鍵ペアで保護されます。パスワード認証は無効です。

注意: 同一ホスト上の他のユーザーはエフェメラル秘密鍵を持たないため接続できませんが、ポート自体は `127.0.0.1` から到達可能です。共有ホスト環境で懸念がある場合は、追加のネットワーク隔離を検討してください。

## ライセンス

このプロジェクトは [MIT License](https://opensource.org/licenses/MIT) の下で公開されています。
