# cclaude

`cclaude` (Containerized Claude Code) is a command-line tool that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside an isolated container. Only the current project directory is mounted, so Claude Code cannot access anything outside the project. Claude Code state (`~/.claude`) is persisted on the host across sessions.

---

## Features

- **Security isolation**: Claude Code runs in a container and can only access the mounted project directory.
- **Memory persistence**: `~/.claude/` (project memory, settings, conversation history) is preserved across container restarts.
- **Subscription & API key support**: Works with both Claude subscription (OAuth) and API key authentication.
- **Pre-installed toolchains**: Go, Node.js, and Python (uv) are ready to use out of the box, each pinned to an exact version and checked against its upstream SHA256.
- **No sandbox issues**: Container-level isolation eliminates sandbox mode incompatibilities with build tools.
- **Auto-detection**: Automatically detects Podman or Docker; prefers Podman.
- **Customizable**: TOML config file with environment variable overrides. Extend the Dockerfile for additional toolchains.

---

## Installation

### Prerequisites

- [Podman](https://podman.io/) or [Docker](https://www.docker.com/)
- Bash 3.2+
- Container VM with 8GB+ memory (for image build). For Podman Machine: `podman machine set --memory 8192`

### Install from source

```bash
git clone https://github.com/nlink-jp/cclaude.git
cd cclaude
make install        # installs to /usr/local/bin/cclaude
cclaude --build     # builds the container image
```

To install to a different directory (e.g., if `/usr/local/bin` is not writable):

```bash
make install PREFIX=$HOME/.local    # installs to ~/.local/bin/cclaude
```

The `make install` command places:
- `cclaude` script → `$(PREFIX)/bin/cclaude` (default: `/usr/local/bin/cclaude`)
- `Dockerfile` → `~/.config/cclaude/Dockerfile`
- `config.toml` → `~/.config/cclaude/config.toml` (if not already present)

---

## Quick Start

```bash
# Build the container image (first time only)
cclaude --build

# Run Claude Code in any project directory
cd ~/my-project
cclaude
```

> **Important**: Always run `cclaude` from the **project root directory** (where `.git/`, `go.mod`, `package.json`, etc. live). If you run it from a parent directory containing multiple projects, Claude Code may not correctly identify the project scope and could clone repositories instead of editing local files.

---

## Usage

```
cclaude [options] [-- claude-args...]
```

| Option | Description |
|--------|-------------|
| `cclaude` | Launch Claude Code for the current directory |
| `cclaude --build` | Build or rebuild the container image |
| `cclaude --shell` | Open a bash shell inside the container (debug) |
| `cclaude --config` | Show resolved configuration |
| `cclaude --version` | Print version |
| `cclaude --help` | Show help |
| `cclaude -- <args>` | Pass arguments directly to `claude` |

### Examples

```bash
# Interactive session
cclaude

# Pass arguments to claude
cclaude -- -p "run go test ./..."

# Debug: drop into container shell
cclaude --shell

# Check resolved configuration
cclaude --config
```

---

## Authentication

### API Key

Set the `ANTHROPIC_API_KEY` environment variable:

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
cclaude
```

### Subscription (OAuth)

Run `cclaude` without an API key. Claude Code will display an OAuth login URL in the terminal. Open the URL in your host browser to authenticate. The login state is persisted in `~/.claude/` across sessions.

---

## Configuration

Configuration file: `${XDG_CONFIG_HOME:-~/.config}/cclaude/config.toml`

Environment variables override config file values.

```toml
[container]
runtime = "auto"       # "podman", "docker", or "auto" (prefers podman)
image = "cclaude:latest"
# extra_mounts = ["/path/to/shared-lib"]   # additional directories to mount

[network]
# forward_ports = [8080, 11434]    # host → container (socat)
# publish_ports = [3000, 5173]     # container → host (-p)

[paths]
claude_home = "~/.claude"
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Claude API key (optional if using subscription) | — |
| `CCC_RUNTIME` | Container runtime | `auto` |
| `CCC_IMAGE` | Container image name | `cclaude:latest` |
| `CCC_EXTRA_MOUNTS` | Additional directories to mount (comma-separated) | — |
| `CCC_FORWARD_PORTS` | Ports forwarded host → container (e.g., `8080,11434`) | — |
| `CCC_PUBLISH_PORTS` | Ports published container → host (e.g., `3000,5173`) | — |
| `CCC_CLAUDE_HOME` | Claude home directory | `~/.claude` |
| `CCC_DRY_RUN=1` | Print container command without executing | — |

### Toolchain versions

The Dockerfile pins every tool to an exact version, together with the SHA256 its upstream author publishes for amd64 and arm64 (see [Security: what the image build downloads](#security-what-the-image-build-downloads)). A new cclaude release moves them. `cclaude --config` lists the versions your Dockerfile pins.

Since v0.6.0, `go_version` and `node_version` under `[toolchain]`, and `CCC_GO_VERSION` / `CCC_NODE_VERSION`, are no longer read: a version cannot be changed without its hashes. If one is still set, `cclaude --build` and `cclaude --config` print a warning and the build uses the pinned versions. Earlier versions of `make install` wrote `go_version = "1.23.4"` and `node_version = "20"` into `config.toml`. Remove those lines, then rebuild:

```bash
cclaude --config   # warns about each setting that is ignored
cclaude --build
```

To build with another version, edit its `ARG` lines in `~/.config/cclaude/Dockerfile`: the version and both hashes, copied from the checksum file named in the comment above them. `make install` replaces that file with the release's Dockerfile.

---

## How It Works

### Path Mapping

The project directory is mounted at the **same absolute path** inside the container:

```
Host:      /home/user/my-project
Container: /home/user/my-project  (identical)
```

Claude Code stores project memory keyed by absolute path (e.g., `~/.claude/projects/-home-user-my-project/`). By using the same path, project memory is fully compatible between host and container sessions.

### Container-Specific Claude Home

The container uses its own copy of the Claude Code state, separate from the host:

```
Host:      ~/.claude/                          (host settings — untouched)
Container: ~/.config/cclaude/claude-home/      (container-specific copy)
```

On first run, `cclaude` copies the host's `~/.claude/` to `~/.config/cclaude/claude-home/`. After that, the container copy is used independently. This design ensures:

- **Host settings are never modified** — sandbox, permissions, and plugin configuration on the host remain unchanged.
- **Container has its own settings** — sandbox is automatically disabled (the container itself provides isolation), and you can customize permissions independently.
- **State persists across container restarts** — project memory, conversation history, OAuth tokens, and plugins are retained in the container copy.

To re-sync with host settings (e.g., after changing host permissions), delete the container copy and it will be recreated on next run:

```bash
rm -rf ~/.config/cclaude/claude-home
cclaude    # re-copies from host ~/.claude/
```

### Host Network Access

#### Port Forwarding (recommended)

Configure `forward_ports` to make host services accessible as `localhost` inside the container. This uses `socat` to transparently forward ports, so Claude Code and tools inside the container do not need to know they are running in a container.

```toml
[network]
forward_ports = [8080, 11434]   # e.g., local LLM API, Ollama
```

Or via environment variable:

```bash
CCC_FORWARD_PORTS="8080,11434" cclaude
```

With this configuration, `http://localhost:8080` inside the container reaches the host's `localhost:8080`.

#### Port Publishing (container → host)

To make services running inside the container accessible from the host (e.g., a dev server started by Claude Code):

```toml
[network]
publish_ports = [3000, 5173]
```

Or: `CCC_PUBLISH_PORTS="3000,5173" cclaude`

This publishes `127.0.0.1:3000` on the host, forwarding to the container's port 3000.

> **Important**: Dev servers inside the container must bind to `0.0.0.0`, not `127.0.0.1`. Many tools (Vite, Next.js, etc.) default to localhost only, which is unreachable from outside the container. Use `--host 0.0.0.0` or equivalent option when starting the server. If Claude Code starts a dev server, instruct it to bind to `0.0.0.0` (e.g., via project CLAUDE.md).

#### Direct hostname access

Without port forwarding, host services are also available via runtime-specific hostnames:

| Runtime | Hostname |
|---------|----------|
| Podman | `host.containers.internal` |
| Docker | `host.docker.internal` |

### SSH Agent Forwarding

Use `--ssh` mode to forward your host SSH agent (including 1Password) into the container. This works on all platforms by running sshd inside the container and connecting via `ssh -A`:

```bash
cclaude --ssh
```

This enables `git clone`, `git push`, and other SSH operations inside the container using your host's SSH keys — without copying keys into the container.

**How it works**: The container starts sshd, your host's SSH public key is injected for authentication, and `cclaude` connects via `ssh -A` which forwards the agent. On exit, the container is automatically stopped and removed.

**Requirements**: An SSH public key in `~/.ssh/` (ed25519, RSA, or ECDSA).

**Default mode (without `--ssh`)**: On Linux, `SSH_AUTH_SOCK` is mounted directly into the container (faster, no sshd needed). On macOS, SSH agent is not available in default mode due to VM limitations — use `--ssh` instead.

---

## Customizing the Image

The default image includes Go, Node.js, and Python (uv). To add more toolchains:

1. Edit `~/.config/cclaude/Dockerfile`
2. Add your packages (e.g., Rust, Java, Ruby)
3. Rebuild: `cclaude --build`

Anything you add is downloaded on every rebuild. Fetch it the way the Dockerfile fetches its own tools, so a rebuild cannot take a file nobody checked: an exact version, and the SHA256 its author publishes, checked with `sha256sum -c` before the file is used. Piping an install script into a shell (`curl … | sh`) skips that check.

`cclaude --build` builds from an empty, temporary directory, not from `~/.config/cclaude/`, so `claude-home/` and `claude.json` there are never sent to the builder. `COPY` and `ADD` of local files therefore do not work; download what you need instead, as above.

### Example: Adding Rust

```dockerfile
# Append to Dockerfile. rustup-init at an exact version; each hash is the
# rustup-init.sha256 published next to it under static.rust-lang.org/rustup/archive/
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

`--default-toolchain` pins the Rust release too; without it, every rebuild installs whatever `stable` is that day. rustup checks the toolchain's files against the SHA256 in that release's channel manifest, which it downloads from `static.rust-lang.org` during the build.

### Example: Adding Java (Eclipse Temurin)

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        temurin-21-jdk \
    && rm -rf /var/lib/apt/lists/*
```

---

## Development

### Project layout

```
src/cclaude.sh      ← source (not executable)
dist/cclaude        ← build output (make build)
Dockerfile          ← container image definition
config.toml.example ← default config template
npmrc.example       ← npm security hardening template
test/               ← BATS test suite (make test)
test/image/         ← image tests: builds the Dockerfile (make test-image)
```

### Prerequisites

- [ShellCheck](https://www.shellcheck.net/) — static analysis for the bash script
- [bats-core](https://github.com/bats-core/bats-core) — test framework

```bash
# macOS
brew install shellcheck bats-core

# Debian/Ubuntu
apt install shellcheck bats
```

### Make targets

```bash
make build        # build src/cclaude.sh → dist/cclaude (with version injection)
make install      # install to /usr/local/bin
make image-build  # build container image
make test         # shellcheck + BATS tests
make test-image   # build the Dockerfile: a wrong SHA256 must fail each download,
                  # each pinned SHA256 must match on amd64 and arm64, and the full
                  # image must build and run every tool (podman/docker, network,
                  # about 2 GB of downloads)
make lint         # shellcheck only
make clean        # remove dist/
```

---

## Platform Notes

### macOS (Docker Desktop / Podman Machine)

Volume mounts through a Linux VM may have slower I/O than native Linux. This is a known limitation of Docker Desktop and Podman Machine on macOS. For large projects, consider using native Linux.

### Docker: File Ownership

When using Docker (not Podman), files created inside the container may be owned by root on the host. Podman's rootless mode maps container root to your host user, avoiding this issue. If this is a problem, you can fix ownership after exiting:

```bash
sudo chown -R "$(id -u):$(id -g)" .
```

### SELinux (Podman)

When using Podman, `--security-opt label=disable` is automatically applied to allow bind-mounted volumes to work under SELinux.

### Security: `--ssh` mode

In `--ssh` mode, sshd runs inside the container and listens on a **random high port** (49152–65535) bound to `127.0.0.1` only. Access is protected by an ephemeral ed25519 key pair that is generated per session and destroyed on exit. No password authentication is allowed.

Note: other users on the same host cannot connect because they do not possess the ephemeral private key, but the port is technically reachable from `127.0.0.1`. If this is a concern in shared-host environments, consider additional network isolation.

### Security: what the image build downloads

Every download is pinned, and each file is checked against a SHA256 its upstream author publishes before it is unpacked:

| What | Pinned to | Checked against |
|------|-----------|-----------------|
| Base image | the multi-arch index digest of `debian:bookworm-slim` (amd64 and arm64) | the digest |
| Debian packages | the Debian release in that base; `apt-get upgrade` takes its updates | apt signatures |
| Go | an exact release from `go.dev/dl` | SHA256 from `go.dev/dl/?mode=json` |
| Node.js | an exact release, the official build from `nodejs.org/dist` | `SHASUMS256.txt` of that release |
| uv | an exact GitHub release | `sha256.sum` of that release |
| Claude Code | an exact release of the native binary from `downloads.claude.ai` | the checksum in that release's `manifest.json` |
| GitHub CLI | an exact GitHub release | `gh_<version>_checksums.txt` of that release |
| golangci-lint | an exact GitHub release | `golangci-lint-<version>-checksums.txt` of that release |

The hashes for amd64 and arm64 are written in the Dockerfile, and `sha256sum -c` fails the build on a mismatch. `make test-image` builds each download with a wrong hash and expects the build to fail, checks every pinned hash against the real file on both architectures, and builds the whole image.

So `cclaude --build` (`--no-cache`) reproduces the release and takes only Debian's updates on its own, whose signatures apt verifies. A new base image or a new version of a tool arrives with a new cclaude release. That includes security fixes: a fix in Node.js or Go reaches the image when a release moves its pin, not when you rebuild.

Not covered:
- The hashes were copied from the checksum files on the same servers as the files. The GPG signature over Node.js's `SHASUMS256.txt` and the signature of Claude Code's manifest are not checked.
- Packages that the tools fetch while you work (npm, Go modules, uv) are outside the image build. For npm, see `npmrc.example`.
- Each `--no-cache` rebuild leaves the previous image untagged. Remove those with `podman image prune` (or `docker image prune`).

---

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
