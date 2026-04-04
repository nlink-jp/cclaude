# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).


## [0.3.1] - 2026-04-04

### Changed

- Use native installer (`claude.ai/install.sh`) instead of deprecated npm for Claude Code installation.
- Document 8GB+ container VM memory requirement for image builds.

### Fixed

- `cclaude --ssh -- --resume` no longer passes `--` to claude (was causing args to be treated as prompts).
- `CCC_CONFIG_FILE` environment variable override now works (was being unconditionally reassigned).
- Tests isolated from user config to prevent false failures.

## [0.3.0] - 2026-04-04

### Added

- **Custom `.npmrc` for supply chain hardening**: Default `.npmrc` with `engine-strict`, `ignore-scripts`, `audit` baked into the image. Override by placing `~/.config/cclaude/npmrc`. Mounted read-only.
- Improved port conflict error message with guidance to check `publish_ports` and restart Podman Machine.

### Fixed

- **Cleanup on Ctrl+D exit**: `ssh` returns non-zero when Claude Code exits via Ctrl+D, which caused `set -e` to skip cleanup. Fixed with `|| true`.
- **Trap variable scoping**: Cleanup trap handler now uses global variables (`_CCC_CLEANUP_*`) instead of `local` variables, which were invisible to the trap when fired at script exit.
- **Orphan container cleanup**: Reverted to PID-based container names (`cclaude-ssh-$$`) for safe concurrent use. Orphan detection checks if the parent PID is still alive before stopping.
- **Dockerfile age check timezone**: Use `.Created.Unix` (epoch) from image inspect instead of parsing timestamp strings, fixing false warnings on non-UTC systems.

## [0.2.1] - 2026-04-04

### Fixed

- Randomize SSH port (49152–65535) instead of fixed 2222 to avoid conflicts and improve security.
- Warn when Dockerfile is newer than the built image, prompting `cclaude --build`.
- Copy `~/.claude.json` (session/auth state) into container Claude home to prevent fresh setup on every launch.
- Clean up leftover containers from interrupted sessions before starting.
- Remove hardcoded OAuth port range (19400–19499) that conflicted with Podman Machine's gvproxy.
- Use `--no-cache` for `cclaude --build` to ensure Dockerfile changes are always applied.
- Fix Bash version requirement in README: 4+ → 3.2+ (matches actual compatibility).
- Add security notes for `--ssh` mode and Docker file ownership workaround to README.

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


[0.3.1]: https://github.com/nlink-jp/cclaude/releases/tag/v0.3.1
[0.3.0]: https://github.com/nlink-jp/cclaude/releases/tag/v0.3.0
[0.2.1]: https://github.com/nlink-jp/cclaude/releases/tag/v0.2.1
[0.2.0]: https://github.com/nlink-jp/cclaude/releases/tag/v0.2.0
[0.1.0]: https://github.com/nlink-jp/cclaude/releases/tag/v0.1.0
