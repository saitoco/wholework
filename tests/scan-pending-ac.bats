#!/usr/bin/env bats

# Tests for scripts/scan-pending-ac.sh's Issue population fetch.
#
# Scope: this suite only verifies the `--state all` population fix (Issue
# #1242). Post-merge section scoping, --facts token filtering, gh-failure
# fail-open behavior, and --max-candidates truncation are already covered by
# tests/run-fact-matching.bats and are not duplicated here.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/scan-pending-ac.sh"

setup() {
    cd "$PROJECT_ROOT"

    export MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    printf '%s\n' "$@" >> "$MOCK_DIR/gh-list-args.txt"
    echo "[]"
    exit 0
fi
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "population: gh issue list is called with --state all, not --state closed (issue #1242)" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    args_joined="$(tr '\n' ' ' < "$MOCK_DIR/gh-list-args.txt")"
    [[ "$args_joined" == *"--state all"* ]]
    [[ "$args_joined" != *"--state closed"* ]]
}

@test "population: gh issue list is called with the phase/verify label and --json number,body" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    args_joined="$(tr '\n' ' ' < "$MOCK_DIR/gh-list-args.txt")"
    [[ "$args_joined" == *"--label phase/verify"* ]]
    [[ "$args_joined" == *"--json number,body"* ]]
}
