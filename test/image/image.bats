#!/usr/bin/env bats
# image.bats — builds the Dockerfile with podman (or docker): each download
# stage with a wrong and with the pinned SHA256, then the whole image.
# Needs a container runtime and network, and downloads about 2 GB:
# run with `make test-image`, not `make test`. Build cache layers stay behind;
# `podman image prune` removes them.

WRONG_SHA256="0000000000000000000000000000000000000000000000000000000000000000"
TEST_TAG="localhost/cclaude-stage-test"

# tools — print TOOL:stage for every ARG <TOOL>_VERSION in the Dockerfile
# (GOLANGCI_LINT:golangci-lint), so a new download is tested without editing
# this file.
tools() {
    sed -n 's/^ARG \([A-Z_]*\)_VERSION=.*/\1/p' "$DOCKERFILE" \
        | while read -r t; do
            printf '%s:%s\n' "$t" "$(printf '%s' "$t" | tr 'A-Z_' 'a-z-')"
        done
}

setup_file() {
    RUNTIME="${CCC_TEST_RUNTIME:-$(command -v podman || command -v docker || true)}"
    [[ -n "$RUNTIME" ]] || { echo "no podman or docker in PATH" >&2; return 1; }
    export RUNTIME
    export DOCKERFILE="${BATS_TEST_DIRNAME}/../../Dockerfile"
    # The Dockerfile copies nothing from its context; build from an empty one.
    export CTX="${BATS_FILE_TMPDIR}/ctx"
    mkdir -p "$CTX"
}

teardown_file() {
    local ref
    for ref in $("$RUNTIME" images --format '{{.Repository}}:{{.Tag}}' | grep "^${TEST_TAG}:" || true); do
        "$RUNTIME" rmi "$ref" >/dev/null 2>&1 || true
    done
}

# wrong_hash_fails TOOL STAGE — build STAGE with both of TOOL's hashes replaced
# and expect sha256sum to stop the build.
wrong_hash_fails() {
    local tool="$1" stage="$2"
    run "$RUNTIME" build --target "$stage" \
        --build-arg "${tool}_SHA256_AMD64=${WRONG_SHA256}" \
        --build-arg "${tool}_SHA256_ARM64=${WRONG_SHA256}" \
        -f "$DOCKERFILE" "$CTX"
    # One expression: callers use `wrong_hash_fails … ||`, which turns off
    # errexit inside this function, so separate checks would not count.
    [ "$status" -ne 0 ] \
        && [[ "$output" == *": FAILED"* ]] \
        && [[ "$output" == *"computed checksum did NOT match"* ]]
}

@test "the Dockerfile has a stage for every pinned tool" {
    [ "$(tools | wc -l)" -ge 6 ]
    local pair
    for pair in $(tools); do
        grep -qx "FROM fetch AS ${pair#*:}" "$DOCKERFILE" || { echo "no stage: $pair"; return 1; }
    done
}

@test "a wrong SHA256 fails every download stage" {
    local pair
    for pair in $(tools); do
        wrong_hash_fails "${pair%%:*}" "${pair#*:}" || { echo "not refused: $pair"; echo "$output" | tail -20; return 1; }
    done
}

@test "every pinned SHA256 matches the upstream file on linux/amd64 and linux/arm64" {
    local platform pair stage
    for platform in linux/amd64 linux/arm64; do
        for pair in $(tools); do
            stage="${pair#*:}"
            # --no-cache: a cached layer would skip the download and the check.
            run "$RUNTIME" build --no-cache --platform "$platform" --target "$stage" \
                -t "${TEST_TAG}:${stage}-${platform#linux/}" \
                -f "$DOCKERFILE" "$CTX"
            if [ "$status" -ne 0 ] || [[ "$output" != *": OK"* ]]; then
                echo "$platform $stage failed:"
                echo "$output" | tail -20
                return 1
            fi
        done
    done
}

@test "the full image builds, every tool runs, and no Debian update is pending" {
    run "$RUNTIME" build --no-cache -t "${TEST_TAG}:image" -f "$DOCKERFILE" "$CTX"
    [ "$status" -eq 0 ] || { echo "$output" | tail -30; return 1; }
    run "$RUNTIME" run --rm "${TEST_TAG}:image" bash -lc \
        'go version && node --version && npm --version && uv --version && claude --version && gh --version && golangci-lint --version && apt-get update -qq && apt list --upgradable 2>/dev/null | tail -n +2'
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"(Claude Code)"* ]] || { echo "claude did not run: $output"; return 1; }
    # apt list prints nothing after its header when every package is current.
    [[ "$output" != *"[upgradable from"* ]] || { echo "updates pending: $output"; return 1; }
}
