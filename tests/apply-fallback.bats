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
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
    echo "worktree-code+issue-42"
    exit 0
fi
if [[ "\$1" == "commit" && "\$*" == *"--amend"* ]]; then
    echo "\$@" >> "$GIT_AMEND_LOG"
    exit 0
fi
if [[ "\$1" == "push" && "\$*" == *"--force-with-lease"* ]]; then
    echo "\$@" >> "$GIT_PUSH_LOG"
    exit 0
fi
if [[ "\$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    # Default mock: reconcile-phase-state.sh reports completion succeeded.
    # Individual tests override this to simulate matches_expected:false.
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":true}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"
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
    [ "$status" -eq 2 ]
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
    [ "$status" -eq 2 ]
    [[ "$output" == *"refuses to amend on protected branch"* ]]
}

@test "apply-fallback: no arguments exits non-zero" {
    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
}

@test "code-patch-silent-no-op pattern triggers run-code.sh retry" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "Warning: claude exited 0 but code-patch phase did not complete (silent no-op)." > "$LOG_FILE"

    RUN_CODE_LOG="$BATS_TEST_TMPDIR/run-code.log"
    cat > "$MOCK_DIR/run-code.sh" <<MOCK
#!/bin/bash
echo "\$@" >> "$RUN_CODE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    run bash "$SCRIPT" code-patch 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]

    grep -q "42" "$RUN_CODE_LOG"
    grep -q -- "--patch" "$RUN_CODE_LOG"
}

@test "code-patch-silent-no-op pattern does not fire for non-code-patch phase" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "Warning: claude exited 0 but code-patch phase did not complete (silent no-op)." > "$LOG_FILE"

    run bash "$SCRIPT" verify 42 --log "$LOG_FILE"
    [ "$status" -eq 1 ]
}

@test "apply-fallback: dco-signoff-missing-autofix: stdout contains Orchestration Anomalies metadata" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "ERROR: missing sign-off" > "$LOG_FILE"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Orchestration Anomalies"* ]]
    [[ "$output" == *"dco-signoff-missing-autofix"* ]]
    [[ "$output" == *"result=recovered"* ]]
}

@test "code-patch-silent-no-op: retry itself returns silent no-op → not reported as recovered, escalates to Tier 3" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "Warning: claude exited 0 but code-patch phase did not complete (silent no-op)." > "$LOG_FILE"

    RUN_CODE_LOG="$BATS_TEST_TMPDIR/run-code.log"
    cat > "$MOCK_DIR/run-code.sh" <<MOCK
#!/bin/bash
echo "\$@" >> "$RUN_CODE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    # Override the default mock: retry completed (exit 0) but produced no commit,
    # so the post-retry completion check still reports matches_expected:false.
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    run bash "$SCRIPT" code-patch 42 --log "$LOG_FILE"
    [ "$status" -eq 2 ]
    [[ "$output" != *"result=recovered"* ]]

    # The retry was still attempted before the completion check failed
    grep -q "42" "$RUN_CODE_LOG"
    grep -q -- "--patch" "$RUN_CODE_LOG"
}

@test "apply-fallback: code-patch-silent-no-op: stdout contains Orchestration Anomalies metadata" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "Warning: claude exited 0 but code-patch phase did not complete (silent no-op)." > "$LOG_FILE"

    RUN_CODE_LOG="$BATS_TEST_TMPDIR/run-code.log"
    cat > "$MOCK_DIR/run-code.sh" <<MOCK
#!/bin/bash
echo "\$@" >> "$RUN_CODE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    run bash "$SCRIPT" code-patch 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Orchestration Anomalies"* ]]
    [[ "$output" == *"code-patch-silent-no-op"* ]]
}

@test "json-mode-silent-hang pattern triggers run-code.sh --pr retry for code-pr phase" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "still waiting (json mode)" > "$LOG_FILE"

    RUN_CODE_LOG="$BATS_TEST_TMPDIR/run-code.log"
    cat > "$MOCK_DIR/run-code.sh" <<MOCK
#!/bin/bash
echo "\$@" >> "$RUN_CODE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    run bash "$SCRIPT" code-pr 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]

    grep -q "42" "$RUN_CODE_LOG"
    grep -q -- "--pr" "$RUN_CODE_LOG"
}

@test "json-mode-silent-hang pattern does not fire for non-code-pr phase" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "still waiting (json mode)" > "$LOG_FILE"

    run bash "$SCRIPT" verify 42 --log "$LOG_FILE"
    [ "$status" -eq 1 ]
}

@test "apply-fallback: json-mode-silent-hang: stdout contains Orchestration Anomalies metadata" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "still waiting (json mode)" > "$LOG_FILE"

    RUN_CODE_LOG="$BATS_TEST_TMPDIR/run-code.log"
    cat > "$MOCK_DIR/run-code.sh" <<MOCK
#!/bin/bash
echo "\$@" >> "$RUN_CODE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    run bash "$SCRIPT" code-pr 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Orchestration Anomalies"* ]]
    [[ "$output" == *"json-mode-silent-hang"* ]]
    [[ "$output" == *"result=recovered"* ]]
}

@test "apply-fallback: dco-signoff handler: git commit --amend fails: exits 2, not reported as recovered" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "ERROR: missing sign-off" > "$LOG_FILE"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$1" == "rev-parse" && "$2" == "--abbrev-ref" ]]; then
    echo "worktree-code+issue-42"
    exit 0
fi
if [[ "$1" == "commit" && "$*" == *"--amend"* ]]; then
    echo "commit failed" >&2
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 2 ]
    [[ "$output" != *"result=recovered"* ]]
}

@test "apply-fallback: json-mode-silent-hang handler: run-code.sh fails: exits 2, not reported as recovered" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "still waiting (json mode)" > "$LOG_FILE"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    run bash "$SCRIPT" code-pr 42 --log "$LOG_FILE"
    [ "$status" -eq 2 ]
    [[ "$output" != *"result=recovered"* ]]
}

@test "write_recovery_entry: prepends entry after marker with --record-issue Issue number, not phase-local issue arg" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "ERROR: missing sign-off" > "$LOG_FILE"

    mkdir -p "$BATS_TEST_TMPDIR/docs/reports"
    cat > "$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md" <<'REPORT_EOF'
# Orchestration Recoveries

<!-- Log entries appear below, newest first. -->

## 2026-01-01 00:00 UTC: pre-existing-entry

### Context
- Issue #1, phase: code
REPORT_EOF

    # The positional <issue> arg (99) simulates a PR number in review/merge phases;
    # --record-issue carries the real Issue number that should be written to the report.
    run bash "$SCRIPT" code 99 --log "$LOG_FILE" --record-issue 555
    [ "$status" -eq 0 ]

    report_content="$(cat "$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md")"
    [[ "$report_content" == *"code-tier2-recovery"* ]]
    [[ "$report_content" == *"- Issue #555, phase: code"* ]]
    [[ "$report_content" != *"- Issue #99, phase: code"* ]]
    [[ "$report_content" == *"- Source: fallback-catalog"* ]]
    [[ "$report_content" == *"- N/A (resolved by known catalog)"* ]]

    # New entry must be prepended (appear before the pre-existing entry)
    new_entry_pos=$(grep -n "code-tier2-recovery" "$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md" | head -1 | cut -d: -f1)
    old_entry_pos=$(grep -n "pre-existing-entry" "$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md" | head -1 | cut -d: -f1)
    [ "$new_entry_pos" -lt "$old_entry_pos" ]
}

@test "write_recovery_entry: gracefully skips when orchestration-recoveries.md does not exist" {
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    echo "ERROR: missing sign-off" > "$LOG_FILE"

    # No docs/reports/orchestration-recoveries.md created in $BATS_TEST_TMPDIR
    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"result=recovered"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md" ]
}
