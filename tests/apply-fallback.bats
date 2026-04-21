#!/usr/bin/env bats

# Tests for apply-fallback.sh
# Mocks git via PATH and uses WHOLEWORK_SCRIPT_DIR for sibling isolation.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/apply-fallback.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    export GIT_AMEND_LOG="$BATS_TEST_TMPDIR/git-amend.log"
    export GIT_PUSH_LOG="$BATS_TEST_TMPDIR/git-push.log"

    # Mock git: capture amend and push invocations
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$1" == "rev-parse" && "$2" == "--abbrev-ref" ]]; then
    echo "worktree-code+issue-42"
    exit 0
fi
if [[ "$1" == "commit" && "$*" == *"--amend"* ]]; then
    echo "$@" >> "$GIT_AMEND_LOG"
    exit 0
fi
if [[ "$1" == "push" && "$*" == *"--force-with-lease"* ]]; then
    echo "$@" >> "$GIT_PUSH_LOG"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "apply-fallback: missing --log argument exits non-zero" {
    run bash "$SCRIPT" code 42
    [ "$status" -ne 0 ]
    [[ "$output" == *"--log"* ]]
}

@test "apply-fallback: --log with nonexistent file exits non-zero" {
    run bash "$SCRIPT" code 42 --log /nonexistent/file.log
    [ "$status" -ne 0 ]
    [[ "$output" == *"log file not found"* ]]
}

@test "apply-fallback: unknown symptom returns 1 (escalate to tier3)" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "Some unrecognized error message" > "$LOG_FILE"
    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 1 ]
}

@test "apply-fallback: dco-signoff-missing-autofix pattern detected: amend and force-with-lease invoked" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "ERROR: missing sign-off" > "$LOG_FILE"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]

    # Verify git commit --amend -s --no-edit was called
    grep -q -- "--amend" "$GIT_AMEND_LOG"
    grep -q -- "-s" "$GIT_AMEND_LOG"
    grep -q -- "--no-edit" "$GIT_AMEND_LOG"

    # Verify git push --force-with-lease was called
    grep -q -- "--force-with-lease" "$GIT_PUSH_LOG"
}

@test "apply-fallback: dco-signoff handler refuses to operate on main branch" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "ERROR: missing sign-off" > "$LOG_FILE"

    # Override git mock to return main as current branch
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$1" == "rev-parse" && "$2" == "--abbrev-ref" ]]; then
    echo "main"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refuses to amend on protected branch"* ]]
}

@test "apply-fallback: dco-signoff handler refuses to operate on master branch" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "ERROR: missing sign-off" > "$LOG_FILE"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$1" == "rev-parse" && "$2" == "--abbrev-ref" ]]; then
    echo "master"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refuses to amend on protected branch"* ]]
}

@test "apply-fallback: no arguments exits non-zero" {
    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
}
