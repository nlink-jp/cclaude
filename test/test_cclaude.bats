#!/usr/bin/env bats

load test_helper

# =========================================================================
# Version / Help
# =========================================================================

@test "--version prints version string" {
    run "$CCC_BIN" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^cclaude\ [0-9]+\.[0-9]+\.[0-9] ]]
}

@test "--help prints usage" {
    run "$CCC_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Containerized Claude Code" ]]
    [[ "$output" =~ "--build" ]]
    [[ "$output" =~ "--shell" ]]
}

@test "-h is alias for --help" {
    run "$CCC_BIN" -h
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Containerized Claude Code" ]]
}

@test "unknown option fails" {
    run "$CCC_BIN" --nonexistent
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

    CCC_DRY_RUN=1 run "$CCC_BIN" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "image         = my-image:v1" ]]

    teardown_config
}

@test "environment variable overrides config file" {
    setup_config '[container]
image = "from-config:v1"'

    CCC_IMAGE="from-env:v2" CCC_DRY_RUN=1 run "$CCC_BIN" --config
    [ "$status" -eq 0 ]
    [[ "$output" =~ "image         = from-env:v2" ]]

    teardown_config
}

@test "missing config file uses defaults" {
    CCC_CONFIG_FILE="/nonexistent/config.toml" CCC_DRY_RUN=1 CCC_RUNTIME=podman run "$CCC_BIN" --config
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

@test "forward_ports uses host.docker.internal for docker" {
    CCC_FORWARD_PORTS="8080" run_ccc_dry_with_runtime docker
    [ "$status" -eq 0 ]
    [[ "$output" =~ "host.docker.internal:8080" ]]
}

# =========================================================================
# OAuth port forwarding
# =========================================================================

@test "OAuth port range is forwarded" {
    run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "127.0.0.1:19400-19499:19400-19499" ]]
}

# =========================================================================
# Shell mode
# =========================================================================

@test "--shell launches bash instead of claude" {
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run "$CCC_BIN" --shell
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
    CCC_DRY_RUN=1 CCC_RUNTIME=podman run "$CCC_BIN" -- -p "hello"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "claude -p hello" ]]
}

@test "CCC_IMAGE overrides image name" {
    CCC_IMAGE="custom:v1" run_ccc_dry_with_runtime podman
    [ "$status" -eq 0 ]
    [[ "$output" =~ "custom:v1 claude" ]]
}
