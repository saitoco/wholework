#!/usr/bin/env bats

# Tests for run-auto-sub.sh
# Mocks sibling scripts via WHOLEWORK_SCRIPT_DIR, and gh/git via PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-auto-sub.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    # Call logs for sibling script invocations
    export RUN_SPEC_LOG="$BATS_TEST_TMPDIR/run-spec.log"
    export RUN_CODE_LOG="$BATS_TEST_TMPDIR/run-code.log"
    export RUN_REVIEW_LOG="$BATS_TEST_TMPDIR/run-review.log"
    export RUN_MERGE_LOG="$BATS_TEST_TMPDIR/run-merge.log"
    export RUN_VERIFY_LOG="$BATS_TEST_TMPDIR/run-verify.log"

    # Mock phase-banner.sh (sourced by run-auto-sub.sh)
    cat > "$MOCK_DIR/phase-banner.sh" <<'MOCK'
print_start_banner() { echo "Starting /$3 for issue #$2"; }
print_end_banner() { echo "Finished /$3 for issue #$2"; }
MOCK

    # Mock get-issue-size.sh: default Size M
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "M"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Mock sibling run-*.sh scripts: log args and exit 0
    cat > "$MOCK_DIR/run-spec.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_SPEC_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-spec.sh"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_CODE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/run-review.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_REVIEW_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-review.sh"

    cat > "$MOCK_DIR/run-merge.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_MERGE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-merge.sh"

    cat > "$MOCK_DIR/run-verify.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_VERIFY_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-verify.sh"

    # Mock get-config-value.sh: returns empty string for any key (default behavior)
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    # Mock git: rev-parse --show-toplevel returns per-test directory (for PATCH_LOCK_DIR computation)
    # run-auto-sub.sh calls: git -C "${SCRIPT_DIR}/.." rev-parse --show-toplevel
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ "\$1" == "-C" && "\$3" == "rev-parse" && "\$4" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "pull" ]]; then
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    # Mock gh: default phase/ready label present, pr list returns PR 99
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json labels"* ]]; then
    echo "phase/ready"
    echo "triaged"
    exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
    if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
        echo "test issue title"
    elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
        echo "https://github.com/test/repo/issues/99"
    fi
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "99"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
    # Clean up any leftover patch lock (now contains pid file, so use rm -rf)
    rm -rf "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" 2>/dev/null || true
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: run-auto-sub.sh <sub-issue-number>"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Issue number must be numeric: abc"* ]]
}

@test "error: --base without branch argument" {
    run bash "$SCRIPT" 99 --base
    [ "$status" -eq 1 ]
    [[ "$output" == *"--base requires a branch name"* ]]
}

@test "error: unknown option is rejected" {
    run bash "$SCRIPT" 99 --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid option: --unknown"* ]]
}

@test "Size XS: run-code.sh --patch is called, run-review.sh and run-merge.sh are not called" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --patch" "$RUN_CODE_LOG"
    [ ! -f "$RUN_REVIEW_LOG" ]
    [ ! -f "$RUN_MERGE_LOG" ]
}

@test "Size S: run-code.sh --patch is called, run-review.sh and run-merge.sh are not called" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "S"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --patch" "$RUN_CODE_LOG"
    [ ! -f "$RUN_REVIEW_LOG" ]
    [ ! -f "$RUN_MERGE_LOG" ]
}

@test "Size M: run-code.sh --pr, run-review.sh --light, run-merge.sh, run-verify.sh are called" {
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --pr" "$RUN_CODE_LOG"
    grep -q -- "--light" "$RUN_REVIEW_LOG"
    [ -f "$RUN_MERGE_LOG" ]
    [ -f "$RUN_VERIFY_LOG" ]
}

@test "Size L: run-code.sh --pr, run-review.sh --full, run-merge.sh, run-verify.sh are called" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "L"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --pr" "$RUN_CODE_LOG"
    grep -q -- "--full" "$RUN_REVIEW_LOG"
    [ -f "$RUN_MERGE_LOG" ]
    [ -f "$RUN_VERIFY_LOG" ]
}

@test "Size XL: exits with error about sub-issue splitting" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XL"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 1 ]
    [[ "$output" == *"Further sub-issue splitting is required"* ]]
}

@test "phase/ready present: run-spec.sh is not called" {
    # Default gh mock has phase/ready
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ ! -f "$RUN_SPEC_LOG" ]
}

@test "phase/ready absent: run-spec.sh is called" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json labels"* ]]; then
    echo "triaged"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "99"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ -f "$RUN_SPEC_LOG" ]
}

@test "--base flag propagates to run-code.sh and run-verify.sh for Size M" {
    run bash "$SCRIPT" 42 --base release/v1
    [ "$status" -eq 0 ]
    grep -q -- "--base release/v1" "$RUN_CODE_LOG"
    grep -q -- "--base release/v1" "$RUN_VERIFY_LOG"
}

@test "PATCH_LOCK: lock dir is created during code execution and released after for Size XS" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    LOCK_CHECK_FILE="$BATS_TEST_TMPDIR/lock_existed.txt"
    export LOCK_CHECK_FILE

    # Override run-code.sh to verify lock dir exists during execution
    cat > "$MOCK_DIR/run-code.sh" <<MOCK
#!/bin/bash
echo "\$@" >> "\$RUN_CODE_LOG"
[ -d "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" ] && echo "LOCK_EXISTS" > "\$LOCK_CHECK_FILE" || true
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]

    # Lock existed during code phase
    [ -f "$LOCK_CHECK_FILE" ]
    grep -q "LOCK_EXISTS" "$LOCK_CHECK_FILE"

    # Lock released after script completes
    [ ! -d "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" ]
}

@test "PATCH_LOCK: stale PID is reclaimed and lock is acquired" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Start a subshell and wait for it to die, giving us a definitely-dead PID
    bash -c 'exit 0' &
    DEAD_PID=$!
    wait "$DEAD_PID" 2>/dev/null || true

    # Pre-create lock dir with the dead PID
    LOCK_DIR="$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"
    mkdir -p "$LOCK_DIR"
    echo "$DEAD_PID" > "$LOCK_DIR/pid"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stale lock detected"* ]]
    grep -q "42 --patch" "$RUN_CODE_LOG"
}

@test "PATCH_LOCK: diagnostic log is output when waiting for a live lock holder" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Pre-create lock dir with current (live) process PID
    LOCK_DIR="$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"
    mkdir -p "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    # Short timeout and log interval so the test finishes quickly
    export WHOLEWORK_PATCH_LOCK_TIMEOUT=4
    export WHOLEWORK_PATCH_LOCK_LOG_INTERVAL=2

    run bash "$SCRIPT" 42
    [ "$status" -eq 1 ]
    [[ "$output" == *"waiting for lock held by pid="* ]]
    [[ "$output" == *"sub-issue=#"* ]]
    [[ "$output" == *"Patch lock acquisition timeout"* ]]
}

@test "PATCH_LOCK: timeout is read from .wholework.yml via get-config-value.sh" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Override get-config-value.sh to return 5 seconds for patch-lock-timeout
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "patch-lock-timeout" ]]; then
    echo "5"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    # Pre-create lock dir with current (live) process PID to force waiting
    LOCK_DIR="$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"
    mkdir -p "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    # No WHOLEWORK_PATCH_LOCK_TIMEOUT override — must use yml value of 5
    unset WHOLEWORK_PATCH_LOCK_TIMEOUT
    export WHOLEWORK_PATCH_LOCK_LOG_INTERVAL=2

    run bash "$SCRIPT" 42
    [ "$status" -eq 1 ]
    [[ "$output" == *"Patch lock acquisition timeout (5s)"* ]]
}
