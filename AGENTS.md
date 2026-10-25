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
make test-image   # podman: wrong SHA256 fails each download stage; every pinned
                  # SHA256 matches on amd64 + arm64; full image builds and runs
                  # each tool with nothing upgradable (network, ~2 GB) — release step
make image-build  # podman/docker build of ./Dockerfile
dist/cclaude --build   # what users run: --no-cache build, no build args
```

No compile step; there are no platform binaries to attach to a release.

## Layout

```
src/cclaude.sh       the whole tool (not executable; make build stamps CCC_VERSION)
Dockerfile           image definition shipped to users
config.toml.example  copied to ~/.config/cclaude/config.toml only if absent
npmrc.example        npm hardening, mounted read-only
test/                BATS; tests drive the script with CCC_DRY_RUN=1 and --config,
                     and read the Dockerfile for its pins
test/image/          BATS run by make test-image (builds stages with podman/docker)
```

## Design invariants / gotchas

- **Every download is pinned and hash-checked (v0.6.0).** The base is
  `ARG BASE_IMAGE=debian:bookworm-slim@sha256:<index digest>`; each tool has a
  stage `FROM fetch AS <tool>` with `ARG <TOOL>_VERSION`, `<TOOL>_SHA256_AMD64`,
  `<TOOL>_SHA256_ARM64`, one `curl -fsSLo` and `sha256sum -c` on the next line.
  `test_cclaude.bats` enforces that shape (exactly 6 tools, every FROM is the
  base or `fetch`, nothing piped into a shell, no latest/HEAD). Adding a tool
  means updating the counts there; `test/image/image.bats` derives its tool
  list from the `ARG *_VERSION` lines (stage = lowercased name, `_` → `-`).
  A bats `! cmd` never fails a test (errexit ignores negation) — use
  `run cmd; [ "$status" -eq 1 ]`; likewise a function called as `f || …`
  runs without errexit, so make its last expression carry every check.
  bats runs under macOS's /bin/bash 3.2, where a `[[ … ]]` that is not the
  last command of a test never fails it: use `[ … ]` or `[[ … ]] || return 1`.
  macOS `mktemp -d` ignores `TMPDIR`, so a test cannot choose where it lands.
- **The Dockerfile is the only place versions live.** `go_version` /
  `node_version` and `CCC_GO_VERSION` / `CCC_NODE_VERSION` are retired: read
  only to warn that they are ignored (installs before v0.5.0 wrote
  `go_version = "1.23.4"` / `node_version = "20"` into users' config.toml,
  which `make install` never overwrites). `--build` passes no build args.
  `--config` prints the `ARG *_VERSION` lines of the Dockerfile it would use.
- **Moving a pin** (a release step, never a rebuild):
  - Pick versions from upstream, not memory: Go `go.dev/dl/?mode=json` (also
    gives the SHA256), Node a supported line from
    https://github.com/nodejs/release then `nodejs.org/dist/v<ver>/SHASUMS256.txt`,
    uv `sha256.sum`, gh `gh_<ver>_checksums.txt`, golangci-lint
    `golangci-lint-<ver>-checksums.txt` (its binary must be built with a Go at
    least as new as GO_VERSION: `golangci-lint --version` prints it), Claude
    Code `downloads.claude.ai/claude-code-releases/<ver>/manifest.json`
    (`platforms."linux-x64"/"linux-arm64".checksum`).
  - Base digest: the `Docker-Content-Digest` of
    `registry-1.docker.io/v2/library/debian/manifests/bookworm-slim` requested
    with the OCI index Accept header; confirm the index lists linux/amd64 and
    linux/arm64.
  - Then `make test-image`: re-downloads with `--no-cache` and checks every
    hash on both arches, and builds the full image with `--no-cache`.
- **`--build` sends an empty context.** `build_image` passes `-f <Dockerfile>`
  and a `mktemp -d` directory as the context, removed by an EXIT trap on
  failure (safe only because `build_image` runs before `--ssh` sets its own
  EXIT trap). The Dockerfile's directory is `~/.config/cclaude/`, which holds
  `claude-home/` and `claude.json`; never use it as the context, so the
  Dockerfile must never `COPY`/`ADD` from its context.
- **Rebuilds take only Debian's updates:** `--build` uses `--no-cache` and the
  final stage runs `apt-get upgrade`. Verify after a rebuild with
  `apt-get update && apt list --upgradable` in a throwaway container. A fix in
  Node/Go/etc. needs a release that moves the pin.
- **Not verified beyond the published SHA256:** Node's `SHASUMS256.txt.asc`
  and Claude Code's `manifest.json.sig` signatures are not checked.
- Claude Code is laid out like the native installer
  (`~/.local/bin/claude` → `~/.local/share/claude/versions/<ver>`) by the
  `claude` stage itself; `claude install` is not run, so nothing beyond the
  checked binary is fetched.
- README asks for 8GB+ in the container VM. That was set for the Claude Code
  native installer, which the build no longer runs (v0.6.0 built on a
  7.45 GiB podman machine); not re-measured, so the README keeps 8GB.
