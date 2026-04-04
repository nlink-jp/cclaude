# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).


## [0.2.0] - 2026-04-04

### Added

- **`--ssh` mode**: Connect via sshd with SSH agent forwarding. Enables host SSH keys (including 1Password) inside the container on all platforms including macOS. Uses ephemeral key pairs — generated per session, destroyed on exit.
- **`forward_ports`**: Forward host localhost ports to container localhost via socat. Makes host services (e.g., local LLM APIs, Ollama) accessible as `localhost` inside the container.
- **`publish_ports`**: Publish container ports to the host via `-p` flags (e.g., dev servers).
- **Host network access**: Containers can reach host services via `host.containers.internal` (Podman) or `host.docker.internal` (Docker).
- **Configurable default mode**: Set `mode = "ssh"` in config.toml to always use SSH mode without `--ssh` flag.
- GitHub CLI (`gh`) pre-installed in container image.
- `socat` pre-installed for port forwarding.
- `openssh-server` pre-installed for `--ssh` mode.

### Changed

- **Container-specific Claude home**: Container uses its own copy at `~/.config/cclaude/claude-home/`, separate from host `~/.claude/`. Host settings are never modified. Sandbox is automatically disabled in the container copy.
- **`.claude.json` separation**: Session/auth state (`~/.claude.json`) is copied to `~/.config/cclaude/claude.json` on first run and managed independently.
- Image builds now use `--no-cache` to ensure Dockerfile changes are always applied.

### Fixed

- SSH agent forwarding on macOS: Unix domain sockets cannot pass through virtiofs. Solved via `--ssh` mode (sshd + `ssh -A` over TCP).
- OAuth port range (19400-19499) conflict with Podman Machine's gvproxy. Removed hardcoded port forwarding.
- Leftover containers from interrupted sessions are automatically cleaned up before starting.
- `INT`/`TERM` signals now trigger container cleanup.
- Bash 3.2 compatibility (removed nameref usage).

## [0.1.0] - 2026-04-04

### Added

- Initial release.
- `cclaude`: runs Claude Code inside an isolated container with the current project directory mounted.
- Auto-detects Podman or Docker (prefers Podman).
- Mounts project directory at the same absolute path for Claude Code memory compatibility.
- Persists `~/.claude/` (project memory, settings, history, OAuth tokens) across sessions.
- Supports both API key and subscription (OAuth) authentication.
- Pre-installed toolchains: Go, Node.js, Python (uv), golangci-lint.
- TOML configuration file (`~/.config/cclaude/config.toml`) with environment variable overrides.
- Subcommands: `--build`, `--shell`, `--config`, `--version`, `--help`.
- SSH agent forwarding when `SSH_AUTH_SOCK` is set.
- Git identity (name/email) passed to container for commits.
- `CCC_DRY_RUN=1` mode for testing and debugging.
- BATS test suite (24 tests) and shellcheck-clean.


[0.2.0]: https://github.com/nlink-jp/cclaude/releases/tag/v0.2.0
[0.1.0]: https://github.com/nlink-jp/cclaude/releases/tag/v0.1.0
