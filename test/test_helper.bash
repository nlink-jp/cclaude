# test_helper.bash — shared helpers for cclaude BATS tests

# Path to the cclaude source script
CCC_SRC="${BATS_TEST_DIRNAME}/../src/cclaude.sh"

# Isolate tests from user's config file
export CCC_CONFIG_FILE="/dev/null"

# bats runs under macOS's /bin/bash 3.2, where a false [[ ]] that is not the
# last command of a test does not fail it.  These return 1 instead, which a
# plain call does fail the test with.  The text is matched literally.
output_has() {
    [[ "$output" =~ "$1" ]] && return
    printf 'output lacks: %s\n--- output:\n%s\n' "$1" "$output"
    return 1
}

output_lacks() {
    [[ ! "$output" =~ "$1" ]] && return
    printf 'output has: %s\n--- output:\n%s\n' "$1" "$output"
    return 1
}

# Run cclaude in dry-run mode with controlled environment
run_ccc_dry() {
    CCC_DRY_RUN=1 run bash "$CCC_SRC" "$@"
}

# Run cclaude in dry-run mode with specific runtime
run_ccc_dry_with_runtime() {
    local runtime="$1"
    shift
    CCC_DRY_RUN=1 CCC_RUNTIME="$runtime" run bash "$CCC_SRC" "$@"
}

# Create a temporary config file and set CCC_CONFIG_FILE
setup_config() {
    local content="$1"
    # Per-test directory, removed by bats.  Not mktemp: macOS mktemp fills in
    # only trailing X's, so "XXXXXX.toml" was one literal name for every test.
    CCC_TEST_CONFIG="${BATS_TEST_TMPDIR}/config.toml"
    printf '%s\n' "$content" > "$CCC_TEST_CONFIG"
    export CCC_CONFIG_FILE="$CCC_TEST_CONFIG"
}

# Clean up temporary config
teardown_config() {
    if [[ -n "${CCC_TEST_CONFIG:-}" && -f "$CCC_TEST_CONFIG" ]]; then
        rm -f "$CCC_TEST_CONFIG"
    fi
    unset CCC_CONFIG_FILE CCC_TEST_CONFIG
}
