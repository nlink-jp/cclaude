#!/usr/bin/env bats

load test_helper

# =========================================================================
# Version / Help
# =========================================================================

@test "--version prints version string" {
    run bash "$CCC_SRC" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^cclaude\ v[0-9]+\.[0-9]+\.[0-9] ]] || { echo "not a version: $output"; return 1; }
}

@test "--version, --help and --config print a stamped version with one v" {
    # Stamp the way make build does: git describe gives "v0.6.0".
    local stamped="${BATS_TEST_TMPDIR}/cclaude"
    sed 's/^CCC_VERSION=".*"/CCC_VERSION="v9.8.7"/' "$CCC_SRC" > "$stamped"
    use_repo_dockerfile

    local args
    for args in --version --help --config; do
        CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$stamped" "$args"
        [ "$status" -eq 0 ]
        [[ "$output" =~ "v9.8.7" ]] || { echo "no version: $args"; return 1; }
        [[ ! "$output" =~ "vv" ]] || { echo "vv in: $args"; return 1; }
    done
}

@test "--help prints usage" {
    run bash "$CCC_SRC" --help
    [ "$status" -eq 0 ]
    output_has "Containerized Claude Code"
    output_has "--build"
    output_has "--shell"
}

@test "-h is alias for --help" {
    run bash "$CCC_SRC" -h
    [ "$status" -eq 0 ]
    output_has "Containerized Claude Code"
}

@test "unknown option fails" {
    run bash "$CCC_SRC" --nonexistent
    [ "$status" -eq 1 ]
    output_has "Unknown option"
}

# =========================================================================
# Runtime detection
# =========================================================================

@test "CCC_RUNTIME overrides auto-detection" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "podman run"
}

@test "CCC_RUNTIME=docker produces docker command" {
    run_ccc_dry_with_runtime docker
    [ "$status" -eq 0 ]
    output_has "docker run"
}

# =========================================================================
# Config file parsing
# =========================================================================

@test "config_get reads value from config file" {
    setup_config '[container]
runtime = "docker"
image = "my-image:v1"'

    CCC_DRY_RUN=1 run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    output_has "image              = my-image:v1"

    teardown_config
}

@test "environment variable overrides config file" {
    setup_config '[container]
image = "from-config:v1"'

    CCC_IMAGE="from-env:v2" CCC_DRY_RUN=1 run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    output_has "image              = from-env:v2"

    teardown_config
}

@test "missing config file uses defaults" {
    CCC_CONFIG_FILE="/nonexistent/config.toml" CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    output_has "image"
    output_has "cclaude:latest"
}

# =========================================================================
# Mount arguments (dry-run)
# =========================================================================

@test "project dir mounted at same absolute path" {
    local cwd
    cwd="$(pwd)"
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "-v ${cwd}:${cwd}"
    output_has "-w ${cwd}"
}

@test "container claude home mounted to /root/.claude" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    # Container uses its own copy at ~/.config/cclaude/claude-home
    output_has "cclaude/claude-home:/root/.claude"
}

# =========================================================================
# API key handling
# =========================================================================

@test "ANTHROPIC_API_KEY is passed when set" {
    ANTHROPIC_API_KEY="sk-test-123" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "ANTHROPIC_API_KEY=sk-test-123"
}

@test "no API key in command when unset" {
    unset ANTHROPIC_API_KEY
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_lacks "ANTHROPIC_API_KEY"
}

# =========================================================================
# SSH agent forwarding
# =========================================================================

@test "SSH_AUTH_SOCK forwarded when set on Linux" {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        skip "SSH agent forwarding is disabled on macOS"
    fi
    SSH_AUTH_SOCK="/tmp/test-ssh" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "-v /tmp/test-ssh:/ssh-agent"
    output_has "SSH_AUTH_SOCK=/ssh-agent"
}

@test "SSH_AUTH_SOCK not forwarded on macOS" {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        skip "Only applies on macOS"
    fi
    SSH_AUTH_SOCK="/tmp/test-ssh" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_lacks "ssh-agent"
}

@test "SSH_AUTH_SOCK not forwarded when unset" {
    unset SSH_AUTH_SOCK
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_lacks "ssh-agent"
}

# =========================================================================
# Git identity
# =========================================================================

@test "git identity passed as env vars" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "GIT_AUTHOR_NAME="
    output_has "GIT_AUTHOR_EMAIL="
}

# =========================================================================
# Podman-specific flags
# =========================================================================

@test "podman gets label=disable security opt" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "label=disable"
}

@test "docker does not get label=disable" {
    run_ccc_dry_with_runtime docker
    [ "$status" -eq 0 ]
    output_lacks "label=disable"
}

# =========================================================================
# Host network access
# =========================================================================

@test "podman adds host.containers.internal" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "host.containers.internal:host-gateway"
}

@test "docker adds host.docker.internal" {
    run_ccc_dry_with_runtime docker
    [ "$status" -eq 0 ]
    output_has "host.docker.internal:host-gateway"
}

# =========================================================================
# Port forwarding (socat)
# =========================================================================

@test "forward_ports starts socat in container command" {
    CCC_FORWARD_PORTS="8080,11434" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "socat TCP-LISTEN:8080"
    output_has "socat TCP-LISTEN:11434"
    output_has "host.containers.internal:8080"
    output_has "host.containers.internal:11434"
}

@test "no forward_ports runs claude directly" {
    unset CCC_FORWARD_PORTS
    CCC_CONFIG_FILE="/nonexistent" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_lacks "socat"
    [[ "$output" =~ "claude"$ ]] || { echo "does not end in claude: $output"; return 1; }
}

@test "publish_ports adds -p flags" {
    CCC_PUBLISH_PORTS="3000,5173" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "127.0.0.1:3000:3000"
    output_has "127.0.0.1:5173:5173"
}

@test "extra_mounts adds volume flags" {
    CCC_EXTRA_MOUNTS="/tmp/shared,/tmp/other" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "-v /tmp/shared:/tmp/shared"
    output_has "-v /tmp/other:/tmp/other"
}

@test "forward_ports uses host.docker.internal for docker" {
    CCC_FORWARD_PORTS="8080" run_ccc_dry_with_runtime docker
    [ "$status" -eq 0 ]
    output_has "host.docker.internal:8080"
}

# =========================================================================
# Shell mode
# =========================================================================

# =========================================================================
# SSH mode (dry-run)
# =========================================================================

@test "--ssh mode starts detached container with sshd" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --ssh
    [ "$status" -eq 0 ]
    output_has "run -d --rm"
    output_has "sshd -D"
    output_has "authorized_keys"
}

@test "--ssh mode includes ssh -A command" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --ssh
    [ "$status" -eq 0 ]
    output_has "ssh -A -t"
    output_has "claude"
}

# =========================================================================
# Shell mode
# =========================================================================

@test "--shell launches bash instead of claude" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --shell
    [ "$status" -eq 0 ]
    # Last word should be "bash", not "claude"
    [[ "$output" =~ " bash"$ ]] || { echo "does not end in bash: $output"; return 1; }
    [[ ! "$output" =~ "claude "$ ]] || { echo "ends in claude: $output"; return 1; }
}

# =========================================================================
# Entrypoint / passthrough arguments
# =========================================================================

@test "default runs claude" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude"$ ]] || { echo "does not end in claude: $output"; return 1; }
}

@test "arguments after -- are passed to claude" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" -- -p "hello"
    [ "$status" -eq 0 ]
    output_has "claude -p hello"
}

@test "CCC_IMAGE overrides image name" {
    CCC_IMAGE="custom:v1" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    output_has "custom:v1 claude"
}

# =========================================================================
# Toolchain versions (pinned in the Dockerfile; config keys retired)
# =========================================================================

# Point the config dir at a copy of the repository's Dockerfile, so tests never
# read the one installed in the user's ~/.config/cclaude.
use_repo_dockerfile() {
    mkdir -p "${BATS_TEST_TMPDIR}/xdg/cclaude"
    cp "${BATS_TEST_DIRNAME}/../Dockerfile" "${BATS_TEST_TMPDIR}/xdg/cclaude/Dockerfile"
    export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/xdg"
}

@test "--config lists the versions pinned in the Dockerfile and warns about nothing" {
    use_repo_dockerfile
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    output_has "(pinned in ${XDG_CONFIG_HOME}/cclaude/Dockerfile)"
    output_has "go            = 1.27.3"
    output_has "node          = 24.22.1"
    output_has "claude        = 2.1.310"
    output_has "golangci_lint = 2.15.0"
    output_lacks "warning"
}

@test "--config without a Dockerfile still succeeds" {
    mkdir -p "${BATS_TEST_TMPDIR}/empty"
    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/empty" CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    output_has "(pinned in (not found))"
}

@test "go_version and node_version left in config.toml are ignored with a warning" {
    use_repo_dockerfile
    setup_config '[toolchain]
go_version = "1.23.4"
node_version = "20"'

    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    output_has "warning: go_version in ${CCC_TEST_CONFIG} is ignored: toolchain versions are pinned in the Dockerfile. Remove the line."
    output_has "warning: node_version in ${CCC_TEST_CONFIG} is ignored"
    output_has "go            = 1.27.3"
    output_has "node          = 24.22.1"

    teardown_config
}

@test "CCC_GO_VERSION and CCC_NODE_VERSION are ignored with a warning to unset them" {
    use_repo_dockerfile
    CCC_GO_VERSION=1.28.0 CCC_NODE_VERSION=22 CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    output_has "warning: CCC_GO_VERSION is ignored: toolchain versions are pinned in the Dockerfile. Unset CCC_GO_VERSION."
    output_has "warning: CCC_NODE_VERSION is ignored"
    output_lacks "Remove the line"
    output_has "node          = 24.22.1"
}

@test "commented-out toolchain keys do not warn" {
    use_repo_dockerfile
    setup_config '[toolchain]
# go_version = "1.27.3"
# node_version = "24"'

    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    output_lacks "warning"

    teardown_config
}

@test "config.toml.example sets no retired toolchain key" {
    use_repo_dockerfile
    CCC_CONFIG_FILE="${BATS_TEST_DIRNAME}/../config.toml.example" CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    output_lacks "warning"
}

@test "--build warns about a retired key and passes no version build args" {
    local stub="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$stub"
    printf '#!/bin/sh\nprintf "podman %%s\\n" "$*"\n' > "${stub}/podman"
    chmod +x "${stub}/podman"
    use_repo_dockerfile
    setup_config '[toolchain]
node_version = "20"'

    PATH="${stub}:${PATH}" CCC_RUNTIME=podman run bash "$CCC_SRC" --build
    [ "$status" -eq 0 ]
    output_has "warning: node_version in ${CCC_TEST_CONFIG} is ignored"
    output_has "podman build --no-cache -t cclaude:latest"
    output_lacks "--build-arg"

    teardown_config
}

# Stub runtime for --build: records the build context (last argument) and
# what it holds, then exits with $STUB_EXIT.
stub_build_runtime() {
    local stub="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$stub"
    cat > "${stub}/podman" <<'STUB'
#!/bin/sh
for a; do ctx="$a"; done
printf 'context=%s\n' "$ctx" > "$STUB_LOG"
ls -A "$ctx" >> "$STUB_LOG"
printf 'podman %s\n' "$*"
exit "${STUB_EXIT:-0}"
STUB
    chmod +x "${stub}/podman"
    export STUB_LOG="${BATS_TEST_TMPDIR}/stub.log"
    export PATH="${stub}:${PATH}"
}

# The context the stub saw. macOS mktemp ignores TMPDIR, so the test checks
# this exact path rather than a directory it chose.
stub_context() {
    sed -n 's/^context=//p' "$STUB_LOG"
}

@test "--build sends an empty context, not the config dir, and removes it" {
    stub_build_runtime
    use_repo_dockerfile
    local config_dir="${XDG_CONFIG_HOME}/cclaude"
    echo '{"oauth":"secret"}' > "${config_dir}/claude.json"
    mkdir -p "${config_dir}/claude-home"

    CCC_RUNTIME=podman run bash "$CCC_SRC" --build
    [ "$status" -eq 0 ]
    [[ "$output" =~ "-f ${config_dir}/Dockerfile" ]] || { echo "no -f: $output"; return 1; }
    local ctx
    ctx="$(stub_context)"
    [ -n "$ctx" ]
    [ "$ctx" != "$config_dir" ]
    # Only the context= line: the stub's ls -A of the context printed nothing.
    [ "$(wc -l < "$STUB_LOG")" -eq 1 ]
    [ ! -e "$ctx" ]
}

@test "--build removes the empty context when the build fails" {
    stub_build_runtime
    use_repo_dockerfile

    STUB_EXIT=3 CCC_RUNTIME=podman run bash "$CCC_SRC" --build
    [ "$status" -eq 3 ]
    [[ ! "$output" =~ "built successfully" ]] || { echo "reported success"; return 1; }
    local ctx
    ctx="$(stub_context)"
    [ -n "$ctx" ]
    [ ! -e "$ctx" ]
}

# =========================================================================
# Dockerfile: every download pinned and hash-checked
# =========================================================================

DOCKERFILE="${BATS_TEST_DIRNAME}/../Dockerfile"
TOOLS="GO NODE UV CLAUDE GH GOLANGCI_LINT"

@test "Dockerfile pins the base image by its digest and builds every stage from it" {
    grep -Eqx 'ARG BASE_IMAGE=debian:bookworm-slim@sha256:[0-9a-f]{64}' "$DOCKERFILE"
    # Every FROM is the pinned base or an earlier stage.
    run grep -E '^FROM ' "$DOCKERFILE"
    local line
    for line in "${lines[@]}"; do
        [[ "$line" =~ ^FROM\ (\$\{BASE_IMAGE\}|fetch)(\ AS\ [a-z-]+)?$ ]] || {
            echo "unpinned: $line"
            return 1
        }
    done
}

@test "Dockerfile pins each tool to an exact version and an amd64 and arm64 SHA256" {
    local t
    for t in $TOOLS; do
        grep -Eqx "ARG ${t}_VERSION=[0-9]+(\.[0-9]+)+" "$DOCKERFILE" || { echo "no version: $t"; return 1; }
        grep -Eqx "ARG ${t}_SHA256_AMD64=[0-9a-f]{64}" "$DOCKERFILE" || { echo "no amd64 hash: $t"; return 1; }
        grep -Eqx "ARG ${t}_SHA256_ARM64=[0-9a-f]{64}" "$DOCKERFILE" || { echo "no arm64 hash: $t"; return 1; }
    done
    # No other ARG *_VERSION, so a new download cannot skip the list above.
    [ "$(grep -Ec '^ARG [A-Z_]+_VERSION=' "$DOCKERFILE")" -eq 6 ]
}

@test "Dockerfile checks every download against its SHA256 and runs no fetched script" {
    # One curl per tool, each writing a file that sha256sum -c checks next.
    [ "$(grep -c 'curl -' "$DOCKERFILE")" -eq 6 ]
    [ "$(grep -c 'curl -fsSLo ' "$DOCKERFILE")" -eq 6 ]
    [ "$(grep -c 'sha256sum -c -' "$DOCKERFILE")" -eq 6 ]
    run grep -A1 'curl -fsSLo ' "$DOCKERFILE"
    local i
    for (( i = 0; i < ${#lines[@]}; i++ )); do
        if [[ "${lines[i]}" == *"curl -fsSLo "* ]]; then
            # Exactly `… | sha256sum -c - \`: a trailing `|| true` would forgive it.
            [[ "${lines[i+1]}" =~ \|\ sha256sum\ -c\ -\ \\$ ]] || { echo "unchecked: ${lines[i]}"; return 1; }
        fi
    done
    # Nothing piped into a shell, nothing that floats. (`! grep` would not
    # fail the test: bash ignores errexit for a negated command.)
    run grep -Eq '\|[[:space:]]*(ba|z|da)?sh([[:space:]]|$)' "$DOCKERFILE"
    [ "$status" -eq 1 ]
    run grep -Eiq '/latest|/HEAD/|releases/latest|setup_[0-9]+\.x' "$DOCKERFILE"
    [ "$status" -eq 1 ]
}

@test "Dockerfile upgrades Debian packages in the final image so a rebuild takes their updates" {
    # From the last FROM on: the image itself, not a download stage.
    awk '/^FROM /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$DOCKERFILE" \
        | grep -q 'apt-get update && apt-get upgrade -y'
}
