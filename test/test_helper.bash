# test_helper.bash — shared helpers for cclaude BATS tests

# Path to the cclaude source script
CCC_SRC="${BATS_TEST_DIRNAME}/../src/cclaude.sh"

# Isolate tests from user's config file
export CCC_CONFIG_FILE="/dev/null"

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
    CCC_TEST_CONFIG="$(mktemp "${BATS_TMPDIR}/ccc-config-XXXXXX.toml")"
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
