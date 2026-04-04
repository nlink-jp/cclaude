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
- Bash 4+

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

[network]
# forward_ports = [8080, 11434]    # host → container (socat)
# publish_ports = [3000, 5173]     # container → host (-p)

[toolchain]
go_version = "1.23.4"
node_version = "20"

[paths]
claude_home = "~/.claude"
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ANTHROPIC_API_KEY` | Claude API key (optional if using subscription) | — |
| `CCC_RUNTIME` | Container runtime | `auto` |
| `CCC_IMAGE` | Container image name | `cclaude:latest` |
| `CCC_FORWARD_PORTS` | Ports forwarded host → container (e.g., `8080,11434`) | — |
| `CCC_PUBLISH_PORTS` | Ports published container → host (e.g., `3000,5173`) | — |
| `CCC_CLAUDE_HOME` | Claude home directory | `~/.claude` |
| `CCC_GO_VERSION` | Go version for image build | `1.23.4` |
| `CCC_NODE_VERSION` | Node.js version for image build | `20` |
| `CCC_DRY_RUN=1` | Print container command without executing | — |

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
make build        # copy script + assets to dist/
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

When using Docker (not Podman), files created inside the container may be owned by root on the host. Podman's rootless mode maps container root to your host user, avoiding this issue.

### SELinux (Podman)

When using Podman, `--security-opt label=disable` is automatically applied to allow bind-mounted volumes to work under SELinux.

---

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT).
