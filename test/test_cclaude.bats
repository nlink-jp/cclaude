#!/usr/bin/env bats

load test_helper

# =========================================================================
# Version / Help
# =========================================================================

@test "--version prints version string" {
    run bash "$CCC_SRC" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^cclaude\ [0-9]+\.[0-9]+\.[0-9] ]]
}

@test "--help prints usage" {
    run bash "$CCC_SRC" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Containerized Claude Code" ]]
    [[ "$output" =~ "--build" ]]
    [[ "$output" =~ "--shell" ]]
}

@test "-h is alias for --help" {
    run bash "$CCC_SRC" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Containerized Claude Code" ]]
}

@test "unknown option fails" {
    run bash "$CCC_SRC" --nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]]
}

# =========================================================================
# Runtime detection
# =========================================================================

@test "CCC_RUNTIME overrides auto-detection" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "podman run" ]]
}

@test "CCC_RUNTIME=docker produces docker command" {
    run_ccc_dry_with_runtime docker
    [ "$status" -eq 0 ]
    [[ "$output" =~ "docker run" ]]
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
    [[ "$output" =~ "image         = my-image:v1" ]]

    teardown_config
}

@test "environment variable overrides config file" {
    setup_config '[container]
image = "from-config:v1"'

    CCC_IMAGE="from-env:v2" CCC_DRY_RUN=1 run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "image         = from-env:v2" ]]

    teardown_config
}

@test "missing config file uses defaults" {
    CCC_CONFIG_FILE="/nonexistent/config.toml" CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "image" ]] && [[ "$output" =~ "cclaude:latest" ]]
}

# =========================================================================
# Mount arguments (dry-run)
# =========================================================================

@test "project dir mounted at same absolute path" {
    local cwd
    cwd="$(pwd)"
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "-v ${cwd}:${cwd}" ]]
    [[ "$output" =~ "-w ${cwd}" ]]
}

@test "container claude home mounted to /root/.claude" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    # Container uses its own copy at ~/.config/cclaude/claude-home
    [[ "$output" =~ "cclaude/claude-home:/root/.claude" ]]
}

# =========================================================================
# API key handling
# =========================================================================

@test "ANTHROPIC_API_KEY is passed when set" {
    ANTHROPIC_API_KEY="sk-test-123" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ANTHROPIC_API_KEY=sk-test-123" ]]
}

@test "no API key in command when unset" {
    unset ANTHROPIC_API_KEY
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "ANTHROPIC_API_KEY" ]]
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
    [[ "$output" =~ "-v /tmp/test-ssh:/ssh-agent" ]]
    [[ "$output" =~ "SSH_AUTH_SOCK=/ssh-agent" ]]
}

@test "SSH_AUTH_SOCK not forwarded on macOS" {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        skip "Only applies on macOS"
    fi
    SSH_AUTH_SOCK="/tmp/test-ssh" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "ssh-agent" ]]
}

@test "SSH_AUTH_SOCK not forwarded when unset" {
    unset SSH_AUTH_SOCK
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "ssh-agent" ]]
}

# =========================================================================
# Git identity
# =========================================================================

@test "git identity passed as env vars" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "GIT_AUTHOR_NAME=" ]]
    [[ "$output" =~ "GIT_AUTHOR_EMAIL=" ]]
}

# =========================================================================
# Podman-specific flags
# =========================================================================

@test "podman gets label=disable security opt" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "label=disable" ]]
}

@test "docker does not get label=disable" {
    run_ccc_dry_with_runtime docker
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "label=disable" ]]
}

# =========================================================================
# Host network access
# =========================================================================

@test "podman adds host.containers.internal" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "host.containers.internal:host-gateway" ]]
}

@test "docker adds host.docker.internal" {
    run_ccc_dry_with_runtime docker
    [ "$status" -eq 0 ]
    [[ "$output" =~ "host.docker.internal:host-gateway" ]]
}

# =========================================================================
# Port forwarding (socat)
# =========================================================================

@test "forward_ports starts socat in container command" {
    CCC_FORWARD_PORTS="8080,11434" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "socat TCP-LISTEN:8080" ]]
    [[ "$output" =~ "socat TCP-LISTEN:11434" ]]
    [[ "$output" =~ "host.containers.internal:8080" ]]
    [[ "$output" =~ "host.containers.internal:11434" ]]
}

@test "no forward_ports runs claude directly" {
    unset CCC_FORWARD_PORTS
    CCC_CONFIG_FILE="/nonexistent" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "socat" ]]
    [[ "$output" =~ "claude"$ ]]
}

@test "publish_ports adds -p flags" {
    CCC_PUBLISH_PORTS="3000,5173" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "127.0.0.1:3000:3000" ]]
    [[ "$output" =~ "127.0.0.1:5173:5173" ]]
}

@test "extra_mounts adds volume flags" {
    CCC_EXTRA_MOUNTS="/tmp/shared,/tmp/other" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "-v /tmp/shared:/tmp/shared" ]]
    [[ "$output" =~ "-v /tmp/other:/tmp/other" ]]
}

@test "forward_ports uses host.docker.internal for docker" {
    CCC_FORWARD_PORTS="8080" run_ccc_dry_with_runtime docker
    [ "$status" -eq 0 ]
    [[ "$output" =~ "host.docker.internal:8080" ]]
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
    [[ "$output" =~ "run -d --rm" ]]
    [[ "$output" =~ "sshd -D" ]]
    [[ "$output" =~ "authorized_keys" ]]
}

@test "--ssh mode includes ssh -A command" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --ssh
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ssh -A -t" ]]
    [[ "$output" =~ "claude" ]]
}

# =========================================================================
# Shell mode
# =========================================================================

@test "--shell launches bash instead of claude" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --shell
    [ "$status" -eq 0 ]
    # Last word should be "bash", not "claude"
    [[ "$output" =~ " bash"$ ]]
    [[ ! "$output" =~ "claude "$ ]]
}

# =========================================================================
# Entrypoint / passthrough arguments
# =========================================================================

@test "default runs claude" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude"$ ]]
}

@test "arguments after -- are passed to claude" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" -- -p "hello"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude -p hello" ]]
}

@test "CCC_IMAGE overrides image name" {
    CCC_IMAGE="custom:v1" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "custom:v1 claude" ]]
}

# =========================================================================
# Toolchain versions
# =========================================================================

@test "default node_version is 24 and prints no warning" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "node_version  = 24" ]]
    [[ ! "$output" =~ "warning" ]]
}

@test "node_version older than the default warns" {
    setup_config '[toolchain]
node_version = "20"'

    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "node_version  = 20" ]]
    [[ "$output" =~ "warning: node_version = 20 is older than the default Node.js line (24)" ]]

    teardown_config
}

@test "CCC_NODE_VERSION older than the default warns" {
    CCC_NODE_VERSION=22 CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "warning: node_version = 22 is older" ]]
}

@test "node_version at or above the default does not warn" {
    CCC_NODE_VERSION=26 CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "node_version  = 26" ]]
    [[ ! "$output" =~ "warning" ]]
}

@test "non-numeric node_version does not warn or fail" {
    CCC_NODE_VERSION=lts CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "warning" ]]
}

@test "config.toml.example leaves toolchain versions to the defaults" {
    CCC_CONFIG_FILE="${BATS_TEST_DIRNAME}/../config.toml.example" CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "go_version    = 1.27.3" ]]
    [[ "$output" =~ "node_version  = 24" ]]
    [[ ! "$output" =~ "warning" ]]
}

@test "default go_version is 1.27.3" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "go_version    = 1.27.3" ]]
}

@test "go_version older than the default warns" {
    setup_config '[toolchain]
go_version = "1.23.4"
node_version = "20"'

    CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "warning: go_version = 1.23.4 is older than the default Go version (1.27.3)" ]]
    [[ "$output" =~ "warning: node_version = 20 is older than the default Node.js line (24)" ]]
    [[ "$output" =~ "Remove node_version from ${CCC_TEST_CONFIG}" ]]

    teardown_config
}

@test "warning from an environment variable says to unset it" {
    CCC_NODE_VERSION=20 CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Unset CCC_NODE_VERSION to follow the default" ]]
    [[ ! "$output" =~ "Remove node_version" ]]
}

@test "--build warns about an old toolchain and passes the versions as build args" {
    local stub="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$stub"
    printf '#!/bin/sh\nprintf "podman %%s\\n" "$*"\n' > "${stub}/podman"
    chmod +x "${stub}/podman"
    mkdir -p "${BATS_TEST_TMPDIR}/xdg/cclaude"
    touch "${BATS_TEST_TMPDIR}/xdg/cclaude/Dockerfile"
    setup_config '[toolchain]
node_version = "20"'

    XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/xdg" PATH="${stub}:${PATH}" CCC_RUNTIME=podman run bash "$CCC_SRC" --build
    [ "$status" -eq 0 ]
    [[ "$output" =~ "warning: node_version = 20 is older" ]]
    [[ "$output" =~ "--build-arg NODE_VERSION=20" ]]
    [[ "$output" =~ "--build-arg GO_VERSION=1.27.3" ]]

    teardown_config
}

@test "older patch of the default Go line warns" {
    CCC_GO_VERSION=1.27.0 CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "warning: go_version = 1.27.0 is older" ]]
}

@test "newer go_version does not warn (numeric, not lexical, compare)" {
    CCC_GO_VERSION=1.100.0 CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "warning" ]]
}

@test "go_version 1.28.0 does not warn" {
    CCC_GO_VERSION=1.28.0 CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "warning" ]]
}

@test "non-numeric go_version does not warn or fail" {
    CCC_GO_VERSION=1.28rc1 CCC_DRY_RUN=1 CCC_RUNTIME=podman run bash "$CCC_SRC" --config
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "warning" ]]
}

@test "Dockerfile ARG defaults match the script defaults" {
    local go node
    go="$(sed -n 's/^CCC_DEFAULT_GO_VERSION="\(.*\)"$/\1/p' "$CCC_SRC")"
    node="$(sed -n 's/^CCC_DEFAULT_NODE_VERSION="\(.*\)"$/\1/p' "$CCC_SRC")"
    grep -qx "ARG GO_VERSION=${go}" "${BATS_TEST_DIRNAME}/../Dockerfile"
    grep -qx "ARG NODE_VERSION=${node}" "${BATS_TEST_DIRNAME}/../Dockerfile"
}
