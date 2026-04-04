# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).


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


[0.1.0]: https://github.com/nlink-jp/cclaude/releases/tag/v0.1.0
