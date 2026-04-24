#!/usr/bin/env bats

# Tests for worktree-merge-push.sh
# Mocks get-config-value.sh via WHOLEWORK_SCRIPT_DIR, and git via PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/worktree-merge-push.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    mkdir -p "$BATS_TEST_TMPDIR/test-repo"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    unset WHOLEWORK_PATCH_LOCK_TIMEOUT
    unset WHOLEWORK_PATCH_LOCK_LOG_INTERVAL

    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" 2>/dev/null || true
    rm -rf "$MOCK_DIR" 2>/dev/null || true
}

@test "lock dir is created during execution and released after with --from" {
    LOCK_CHECK_FILE="$BATS_TEST_TMPDIR/lock_check.txt"
    export LOCK_CHECK_FILE

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "push" ]]; then
    [ -d "${BATS_TEST_TMPDIR}/test-repo/.tmp/claude-auto-patch-lock" ] && echo "LOCK_EXISTS" > "\$LOCK_CHECK_FILE" || true
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]

    [ -f "$LOCK_CHECK_FILE" ]
    grep -q "LOCK_EXISTS" "$LOCK_CHECK_FILE"
    [ ! -d "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" ]
}

@test "stale PID is reclaimed and lock is acquired" {
    bash -c 'exit 0' &
    DEAD_PID=$!
    wait "$DEAD_PID" 2>/dev/null || true

    LOCK_DIR="$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"
    mkdir -p "$LOCK_DIR"
    echo "$DEAD_PID" > "$LOCK_DIR/pid"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stale lock detected"* ]]
    grep -q "push origin main" "$GIT_LOG"
}

@test "diagnostic log is output when waiting for a live lock holder" {
    LOCK_DIR="$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"
    mkdir -p "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    export WHOLEWORK_PATCH_LOCK_TIMEOUT=4
    export WHOLEWORK_PATCH_LOCK_LOG_INTERVAL=2

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 1 ]
    [[ "$output" == *"waiting for lock held by pid="* ]]
    [[ "$output" == *"Patch lock acquisition timeout"* ]]
}

@test "timeout is read from .wholework.yml via get-config-value.sh" {
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

    LOCK_DIR="$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"
    mkdir -p "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    unset WHOLEWORK_PATCH_LOCK_TIMEOUT
    export WHOLEWORK_PATCH_LOCK_LOG_INTERVAL=2

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Patch lock acquisition timeout (5s)"* ]]
}

@test "default timeout is 300 seconds" {
    grep -q -- ':-300}' "$SCRIPT"
}

@test "--from triggers git merge --ff-only" {
    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    grep -q "merge test-branch --ff-only" "$GIT_LOG"
    grep -q "push origin main" "$GIT_LOG"
}

@test "--from with FF failure triggers git pull --rebase and retry" {
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "merge" ]]; then
    COUNT_FILE="${BATS_TEST_TMPDIR}/merge_count"
    count=0
    [ -f "\$COUNT_FILE" ] && count=\$(cat "\$COUNT_FILE")
    count=\$((count + 1))
    echo "\$count" > "\$COUNT_FILE"
    [ "\$count" -eq 1 ] && exit 1
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FF merge failed"* ]]
    grep -q "pull --rebase origin main" "$GIT_LOG"
    grep -q "push origin main" "$GIT_LOG"
}

@test "--base targets non-main branch" {
    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch --base release/v1"
    [ "$status" -eq 0 ]
    grep -q "push origin release/v1" "$GIT_LOG"
}

@test "conflict markers cause abort with non-zero exit and no push" {
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "grep" ]]; then
    echo "conflict.txt"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Conflict markers remain"* ]]
    ! grep -q "push" "$GIT_LOG"
}
