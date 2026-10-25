# AGENTS.md — cclaude

## What it is

Bash CLI that runs Claude Code inside a Podman/Docker container with only the
current project directory mounted. `~/.claude` state is persisted on the host.
The image (Go, Node.js, Python/uv, Claude Code, gh, golangci-lint) is built on
the user's machine from the `Dockerfile` that `make install` copies to
`~/.config/cclaude/Dockerfile`.

## Build / test / run

```sh
make build        # src/cclaude.sh → dist/cclaude (version from git describe) + Dockerfile, examples
make test         # shellcheck + BATS (test/)
make install      # dist/cclaude → $(PREFIX)/bin; Dockerfile → ~/.config/cclaude/
make image-build  # podman/docker build of ./Dockerfile
dist/cclaude --build   # what users run: --no-cache build with GO_VERSION / NODE_VERSION build-args
```

No compile step; there are no platform binaries to attach to a release.

## Layout

```
src/cclaude.sh       the whole tool (not executable; make build stamps CCC_VERSION)
Dockerfile           image definition shipped to users
config.toml.example  copied to ~/.config/cclaude/config.toml only if absent
npmrc.example        npm hardening, mounted read-only
test/                BATS; tests drive the script with CCC_DRY_RUN=1 and --config
```

## Design invariants / gotchas

- **Defaults live in `CCC_DEFAULT_*` at the top of `src/cclaude.sh`, and the
  Dockerfile's `ARG` defaults must match them.** `--build` always passes
  `GO_VERSION` / `NODE_VERSION`, so the script wins over the Dockerfile.
- **A user's `config.toml` freezes toolchain versions.** `make install` never
  overwrites it, and installs before v0.5.0 wrote `go_version = "1.23.4"` and
  `node_version = "20"` into it. Changing a default does not reach those
  users; that is why `warn_old_toolchains` exists (numeric `version_lt`, so
  1.100 > 1.27). Keep `config.toml.example`'s toolchain lines commented out.
  A test pins the Dockerfile `ARG` defaults to the `CCC_DEFAULT_*` values.
  The warning only knows "older than the default", not "unsupported": an odd
  Node line (25) or a non-numeric value passes silently, and Node 22 warns
  while still supported. Keep the defaults on a supported line instead.
- **Pick toolchain defaults from the upstream schedule**, not memory:
  https://github.com/nodejs/release (schedule.json) and `go.dev/dl/?mode=json`.
  Node is installed as a NodeSource major line, so a rebuild takes the newest
  patch of that line.
- **Rebuilds must take updates:** `--build` uses `--no-cache` and the
  Dockerfile runs `apt-get upgrade`. Verify after a rebuild with
  `apt-get update && apt list --upgradable` in a throwaway container.
- **Unverified downloads are recorded, not fixed** (README "Security: what the
  image build downloads"): NodeSource / uv / claude.ai / golangci-lint install
  scripts are piped to a shell, gh and Go tarballs are not SHA256-checked, and
  the base image is pinned by tag. Moving to digest + hash-locked downloads
  changes the meaning of `go_version` / `node_version` (exact versions with
  hashes), so it needs its own design and release.
- Image build needs 8GB+ in the container VM (Claude Code native installer).
