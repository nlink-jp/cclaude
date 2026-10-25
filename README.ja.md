# cclaude

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) を隔離されたコンテナ内で実行するコマンドラインツール。
カレントディレクトリだけがマウントされるため、Claude Code はプロジェクト外にアクセスできません。
Claude Code の状態（`~/.claude`）はホスト上に永続化されます。

## 機能

- **セキュリティ隔離**: Claude Code はコンテナ内で実行され、マウントされたプロジェクトディレクトリのみアクセス可能
- **メモリ永続化**: `~/.claude/`（プロジェクトメモリ、設定、会話履歴）はコンテナ再起動後も保持される
- **サブスクリプション & API キー対応**: Claude サブスクリプション（OAuth）と API キー認証の両方に対応
- **プリインストール済みツールチェーン**: Go、Node.js、Python（uv）がすぐに使える。どれも正確なバージョンに固定し、上流の SHA256 と照合して入れる
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

> **重要**: `cclaude` は必ず**プロジェクトルートディレクトリ**（`.git/`、`go.mod`、`package.json` 等がある場所）で実行してください。複数プロジェクトを含む親ディレクトリで実行すると、Claude Code がプロジェクトスコープを正しく認識できず、ローカルファイルの編集ではなくリポジトリのクローンを行う場合があります。

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
# extra_mounts = ["/path/to/shared-lib"]   # 追加マウントディレクトリ

[network]
# forward_ports = [8080, 11434]    # ホスト→コンテナ (socat)
# publish_ports = [3000, 5173]     # コンテナ→ホスト (-p)

[paths]
claude_home = "~/.claude"
```

### 環境変数

| 変数 | 説明 | デフォルト |
|------|------|-----------|
| `ANTHROPIC_API_KEY` | Claude API キー（サブスクリプション利用時は不要） | — |
| `CCC_RUNTIME` | コンテナランタイム | `auto` |
| `CCC_IMAGE` | コンテナイメージ名 | `cclaude:latest` |
| `CCC_EXTRA_MOUNTS` | 追加マウントディレクトリ（カンマ区切り） | — |
| `CCC_FORWARD_PORTS` | ホスト→コンテナ転送ポート（例: `8080,11434`） | — |
| `CCC_PUBLISH_PORTS` | コンテナ→ホスト公開ポート（例: `3000,5173`） | — |
| `CCC_CLAUDE_HOME` | Claude ホームディレクトリ | `~/.claude` |
| `CCC_DRY_RUN=1` | コンテナコマンドを実行せず表示のみ | — |

### ツールチェーンのバージョン

Dockerfile は各ツールを正確なバージョンに固定し、上流の作者が amd64 と arm64 について公開している SHA256 を併記しています（[セキュリティ: イメージビルドがダウンロードするもの](#セキュリティ-イメージビルドがダウンロードするもの)）。これを動かすのは cclaude の新しいリリースです。`cclaude --config` は、手元の Dockerfile が固定しているバージョンを表示します。

v0.6.0 から、`[toolchain]` の `go_version` と `node_version`、および `CCC_GO_VERSION` / `CCC_NODE_VERSION` は読まれません。ハッシュを伴わずにバージョンだけを変えることはできないためです。設定が残っていると `cclaude --build` と `cclaude --config` が警告を出し、ビルドは固定されたバージョンで行われます。以前の `make install` は `config.toml` に `go_version = "1.23.4"` と `node_version = "20"` を書き込んでいました。それらの行を削除してから、リビルドしてください:

```bash
cclaude --config   # 無視される設定ごとに警告が出る
cclaude --build
```

別のバージョンでビルドするには、`~/.config/cclaude/Dockerfile` のそのツールの `ARG` 行を書き換えます。バージョンと 2 つのハッシュを、行の上のコメントにあるチェックサムファイルから写してください。`make install` はこのファイルをリリースの Dockerfile で置き換えます。

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

#### ポートパブリッシング（コンテナ→ホスト）

コンテナ内で動作するサービス（例: Claude Code が起動した開発サーバー）をホストからアクセス可能にするには:

```toml
[network]
publish_ports = [3000, 5173]
```

環境変数: `CCC_PUBLISH_PORTS="3000,5173" cclaude`

ホストの `127.0.0.1:3000` がコンテナのポート 3000 に転送されます。

> **重要**: コンテナ内の開発サーバーは `127.0.0.1` ではなく `0.0.0.0` にバインドする必要があります。多くのツール（Vite、Next.js 等）はデフォルトで localhost のみにバインドするため、コンテナ外からアクセスできません。サーバー起動時に `--host 0.0.0.0` 等のオプションを使用してください。Claude Code が開発サーバーを起動する場合は、プロジェクトの CLAUDE.md で `0.0.0.0` にバインドするよう指示してください。

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

追加したものはリビルドのたびにダウンロードされます。Dockerfile が自身のツールを入れるのと同じやり方で取得してください。そうすれば、誰も確かめていないファイルをリビルドが取り込むことはありません: 正確なバージョンを指定し、作者が公開している SHA256 を、使う前に `sha256sum -c` で照合します。インストールスクリプトをシェルにパイプする（`curl … | sh`）と、この照合が抜けます。

`cclaude --build` は `~/.config/cclaude/` ではなく、空の一時ディレクトリをビルドコンテキストにします。そのため、そこにある `claude-home/` と `claude.json` がビルダーに送られることはありません。その代わり、ローカルファイルの `COPY` や `ADD` は使えません。必要なものは上のようにダウンロードしてください。

### 例: Rust を追加

```dockerfile
# Dockerfile に追記。rustup-init を正確なバージョンで入れる。各ハッシュは
# static.rust-lang.org/rustup/archive/ で隣に公開されている rustup-init.sha256
ARG RUSTUP_VERSION=1.29.2
ARG RUSTUP_SHA256_AMD64=5be191e8c70a5007074254cb74d78dbfdd25cd5a61c27de7b8e5410122ec24f4
ARG RUSTUP_SHA256_ARM64=a9c168dbea81a84671c6b7a5c1795cb0eb699020110d107ddfca427bd797e697
RUN case "$(dpkg --print-architecture)" in \
         amd64) sha="$RUSTUP_SHA256_AMD64"; triple=x86_64-unknown-linux-gnu ;; \
         arm64) sha="$RUSTUP_SHA256_ARM64"; triple=aarch64-unknown-linux-gnu ;; \
         *) echo "unsupported architecture" >&2; exit 1 ;; \
       esac \
    && curl -fsSLo /tmp/rustup-init "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/${triple}/rustup-init" \
    && echo "${sha}  /tmp/rustup-init" | sha256sum -c - \
    && chmod +x /tmp/rustup-init && /tmp/rustup-init -y --no-modify-path --default-toolchain 1.99.1 \
    && rm /tmp/rustup-init
ENV PATH="/root/.cargo/bin:${PATH}"
```

`--default-toolchain` で Rust のリリースも固定します。指定しないと、リビルドのたびにその日の `stable` が入ります。rustup はツールチェーンのファイルを、そのリリースのチャンネルマニフェストにある SHA256 と照合します。マニフェストはビルド中に `static.rust-lang.org` から取得されます。

### 例: Java（Eclipse Temurin）を追加

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        temurin-21-jdk \
    && rm -rf /var/lib/apt/lists/*
```

## 開発

### プロジェクト構成

```
src/cclaude.sh      ← ソースコード（実行権限なし）
dist/cclaude        ← ビルド成果物（make build で生成）
Dockerfile          ← コンテナイメージ定義
config.toml.example ← デフォルト設定テンプレート
npmrc.example       ← npm セキュリティ強化テンプレート
test/               ← BATS テストスイート（make test）
test/image/         ← イメージのテスト: Dockerfile をビルドする（make test-image）
```

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
make build        # src/cclaude.sh → dist/cclaude（バージョン注入付き）
make install      # /usr/local/bin にインストール
make image-build  # コンテナイメージをビルド
make test         # shellcheck + BATS テスト
make test-image   # Dockerfile をビルド: 誤った SHA256 なら各ダウンロードが失敗すること、
                  # 固定した SHA256 が amd64 と arm64 で一致すること、イメージ全体が
                  # ビルドでき各ツールが動くことを確かめる（podman/docker とネット
                  # ワークが必要、約 2 GB をダウンロード）
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

### セキュリティ: イメージビルドがダウンロードするもの

ダウンロードするものはすべて固定され、各ファイルは展開する前に、上流の作者が公開している SHA256 と照合されます:

| 対象 | 固定先 | 照合するもの |
|------|--------|--------------|
| ベースイメージ | `debian:bookworm-slim` の multi-arch インデックスのダイジェスト（amd64 と arm64） | ダイジェスト |
| Debian パッケージ | そのベースの Debian リリース。`apt-get upgrade` がその更新を取り込む | apt の署名 |
| Go | `go.dev/dl` の正確なリリース | `go.dev/dl/?mode=json` の SHA256 |
| Node.js | `nodejs.org/dist` の公式ビルドの正確なリリース | そのリリースの `SHASUMS256.txt` |
| uv | GitHub の正確なリリース | そのリリースの `sha256.sum` |
| Claude Code | `downloads.claude.ai` のネイティブバイナリの正確なリリース | そのリリースの `manifest.json` にある checksum |
| GitHub CLI | GitHub の正確なリリース | そのリリースの `gh_<version>_checksums.txt` |
| golangci-lint | GitHub の正確なリリース | そのリリースの `golangci-lint-<version>-checksums.txt` |

amd64 と arm64 のハッシュは Dockerfile に書かれており、一致しなければ `sha256sum -c` がビルドを失敗させます。`make test-image` は、各ダウンロードを誤ったハッシュでビルドして失敗することを確かめ、固定したハッシュすべてを両アーキテクチャの実ファイルと照合し、イメージ全体をビルドします。

つまり `cclaude --build`（`--no-cache`）はリリースを再現し、自動的に取り込むのは apt が署名を検証する Debian の更新だけです。新しいベースイメージや新しいバージョンのツールは、cclaude の新しいリリースで届きます。セキュリティ修正も同じで、Node.js や Go の修正がイメージに入るのは、リビルドしたときではなく、リリースが固定先を動かしたときです。

対象外のもの:
- ハッシュは、ファイルと同じサーバにあるチェックサムファイルから写したものです。Node.js の `SHASUMS256.txt` の GPG 署名と、Claude Code のマニフェストの署名は検証していません。
- 作業中にツールが取得するパッケージ（npm、Go モジュール、uv）はイメージビルドの外です。npm については `npmrc.example` を参照してください。
- `--no-cache` のリビルドのたびに、前のイメージがタグなしで残ります。`podman image prune`（または `docker image prune`）で削除してください。

## ライセンス

このプロジェクトは [MIT License](https://opensource.org/licenses/MIT) の下で公開されています。
