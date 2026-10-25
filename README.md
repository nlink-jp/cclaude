# cclaude

`cclaude` (Containerized Claude Code) is a command-line tool that runs [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside an isolated container. Only the current project directory is mounted, so Claude Code cannot access anything outside the project. Claude Code state (`~/.claude`) is persisted on the host across sessions.

---

## Features

- **Security isolation**: Claude Code runs in a container and can only access the mounted project directory.
- **Memory persistence**: `~/.claude/` (project memory, settings, conversation history) is preserved across container restarts.
- **Subscription & API key support**: Works with both Claude subscription (OAuth) and API key authentication.
- **Pre-installed toolchains**: Go, Node.js, and Python (uv) are ready to use out of the box.
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

[toolchain]
# go_version = "1.27.3"   # leave commented out to follow the defaults
# node_version = "24"     # a Node.js major line (NodeSource)

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
| `CCC_GO_VERSION` | Go release for image build | `1.27.3` |
| `CCC_NODE_VERSION` | Node.js major line for image build | `24` |
| `CCC_DRY_RUN=1` | Print container command without executing | — |

### Toolchain versions

A version set in `config.toml` or the environment is used as written. A new cclaude release moves only the defaults.

Earlier versions of `make install` wrote `go_version = "1.23.4"` and `node_version = "20"` into `config.toml`. Both have reached end of life and get no more security fixes (Node.js 20 on 2026-04-30). If your `config.toml` still sets a version older than the default, `cclaude --build` and `cclaude --config` print a warning. Remove or comment out those lines, then rebuild:

```bash
cclaude --config   # check go_version and node_version under [toolchain]
cclaude --build
```

`go_version` takes an exact Go release, and `node_version` a major line from NodeSource. Use versions that are still supported ([Go release history](https://go.dev/doc/devel/release), [Node.js release schedule](https://github.com/nodejs/release#release-schedule)).

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

### Example: Adding Rust

```dockerfile
# Append to Dockerfile
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
```

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
test/               ← BATS test suite
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

`cclaude --build` builds with `--no-cache`, and the Dockerfile runs `apt-get upgrade`, so each rebuild takes Debian's security updates. The other tools are downloaded during the build. Several of them are **not** checked against a SHA256 published by their upstream authors:

| Tool | How it is fetched | What verifies it |
|------|-------------------|------------------|
| Debian packages | `debian:bookworm-slim` (by tag, not digest), then apt | apt signatures |
| Go | `go.dev/dl` tarball of `go_version` | nothing (no SHA256 check) |
| Node.js | NodeSource `setup_<line>.x` script piped to `bash`, then the newest `nodejs` of that line from NodeSource's apt repository | the script: nothing; its signing key: HTTPS only; the packages: apt signatures with that key |
| uv | `astral.sh/uv/install.sh` piped to `sh` (latest) | the script: nothing; the script checks the archive against SHA256 values written in it |
| Claude Code | `claude.ai/install.sh` piped to `bash` (latest) | the script: nothing; the script checks the binary against the SHA256 in the release manifest on the same server |
| GitHub CLI | release tarball of the version the GitHub API reports as latest | nothing |
| golangci-lint | `install.sh` from the repository's `HEAD` piped to `sh` (latest release) | the script: nothing; the script checks the archive against the release's checksums file |

So a rebuild can take whatever any of these upstreams serve at that moment. If that matters for your use, pin versions and add SHA256 checks in your copy of the Dockerfile (`~/.config/cclaude/Dockerfile`).

Not done yet: pinning the base image by digest and installing each tool at an exact version checked against its upstream SHA256 (a hash lock). That would change `go_version` and `node_version` into exact versions that come with their hashes, so it is left to a later release with its own design.

---

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
