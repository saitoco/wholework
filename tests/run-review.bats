#!/usr/bin/env bats

# Tests for run-review.sh
# Mocks: claude, claude-watchdog.sh, phase-banner.sh, gh, wait-ci-checks.sh,
#        gh-extract-issue-from-pr.sh, reconcile-phase-state.sh (via MOCK_DIR + WHOLEWORK_SCRIPT_DIR)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-review.sh"

setup() {
    # Isolate test from repo .wholework.yml
    echo "permission-mode: bypass" > "$BATS_TEST_TMPDIR/.wholework.yml"
    cd "$BATS_TEST_TMPDIR"
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    # Record file for verifying claude calls
    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude_calls.log"
    export CLAUDE_CALL_LOG

    # Mock get-config-value.sh: return "bypass" by default
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "bypass" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    # Mock claude: log flags, ANTHROPIC_MODEL, CLAUDECODE, ARGUMENTS, GUARD
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
echo "CLAUDECODE=${CLAUDECODE:-__UNSET__}" >> "$CLAUDE_CALL_LOG"
for arg in "$@"; do
    case "$arg" in
        -p) echo "FLAG_P=1" >> "$CLAUDE_CALL_LOG" ;;
        --model) echo "FLAG_MODEL=1" >> "$CLAUDE_CALL_LOG" ;;
        --dangerously-skip-permissions) echo "FLAG_SKIP_PERMS=1" >> "$CLAUDE_CALL_LOG" ;;
        --permission-mode) echo "FLAG_PERM_MODE=1" >> "$CLAUDE_CALL_LOG" ;;
        --plugin-dir) echo "FLAG_PLUGIN_DIR=1" >> "$CLAUDE_CALL_LOG" ;;
    esac
done
FOUND_P=0
for arg in "$@"; do
    if [[ $FOUND_P -eq 1 ]]; then
        echo "PROMPT_CONTAINS_ARGUMENTS=$(echo "$arg" | grep -o 'ARGUMENTS:.*' | head -1)" >> "$CLAUDE_CALL_LOG"
        if echo "$arg" | grep -q 'IMPORTANT - HEADLESS SKILL EXECUTION'; then
            echo "PROMPT_HAS_GUARD=1" >> "$CLAUDE_CALL_LOG"
        fi
        break
    fi
    [[ "$arg" == "-p" ]] && FOUND_P=1
done
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    cat > "$MOCK_DIR/claude-watchdog.sh" <<'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/claude-watchdog.sh"

    cat > "$MOCK_DIR/handle-permission-mode-failure.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/handle-permission-mode-failure.sh"

    cat > "$MOCK_DIR/phase-banner.sh" <<'MOCK'
print_start_banner() { echo "Starting /$3 for PR #$2"; }
print_end_banner() { echo "Finished /$3 for PR #$2"; }
MOCK

    cat > "$MOCK_DIR/watchdog-defaults.sh" <<'MOCK'
WATCHDOG_TIMEOUT_DEFAULT=1800
load_watchdog_timeout() { WATCHDOG_TIMEOUT=1800; }
MOCK

    # Isolate from parent process env (e.g. running inside /code or /auto session)
    unset EMIT_PHASE_NAME EMIT_ISSUE_NUMBER AUTO_SESSION_ID

    cat > "$MOCK_DIR/emit-event.sh" <<'MOCK'
emit_event() { return 0; }
_emit_comments_consumed() { :; }
MOCK

    cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/check-verify-dirty.sh"

    # Real guard-prefix.sh (sourced via WHOLEWORK_SCRIPT_DIR)
    cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/guard-prefix.sh" "$MOCK_DIR/guard-prefix.sh"

    # Mock wait-ci-checks.sh: emit expected output lines
    cat > "$MOCK_DIR/wait-ci-checks.sh" <<'MOCK'
#!/bin/bash
echo "Waiting for CI checks on PR #$1"
echo "CI check wait complete for PR #$1"
exit 0
MOCK
    chmod +x "$MOCK_DIR/wait-ci-checks.sh"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test PR title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/pull/88"
  fi
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    # Mock gh-extract-issue-from-pr.sh: default returns issue_number 99
    cat > "$MOCK_DIR/gh-extract-issue-from-pr.sh" <<'MOCK'
#!/bin/bash
echo '{"issue_number": 99}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh-extract-issue-from-pr.sh"

    # Mock reconcile-phase-state.sh: default returns empty (no false alarm)
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    # Mock post-fallback-review-summary.sh: default exit 1 (no recovery)
    cat > "$MOCK_DIR/post-fallback-review-summary.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/post-fallback-review-summary.sh"

    # Create SKILL.md fixture
    mkdir -p "$BATS_TEST_TMPDIR/skills/review"
    cat > "$BATS_TEST_TMPDIR/skills/review/SKILL.md" <<'SKILL'
---
type: skill
---
# Review Skill Body
This is the skill body content used for testing.
SKILL
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: run-review.sh <pr-number>"* ]]
}

@test "error: non-numeric PR number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: PR number must be numeric: abc"* ]]
}

@test "success: valid PR number calls claude with correct arguments" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_MODEL=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_PLUGIN_DIR=1" "$CLAUDE_CALL_LOG"

    grep -q "ANTHROPIC_MODEL=sonnet" "$CLAUDE_CALL_LOG"
}

@test "success: ARGUMENTS contains --non-interactive flag" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: output shows start and finish messages" {
    run bash "$SCRIPT" 456
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting /review for PR #456"* ]]
    [[ "$output" == *"Finished /review for PR #456"* ]]
    [[ "$output" == *"Model: sonnet"* ]]
    [[ "$output" == *"Permissions: skip (autonomous mode)"* ]]
}

@test "success: CLAUDECODE env var is not inherited by claude subprocess" {
    export CLAUDECODE="parent-session-id"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    grep -q "CLAUDECODE=__UNSET__" "$CLAUDE_CALL_LOG"
}

@test "success: --review-only flag is passed through to ARGUMENTS with --non-interactive" {
    run bash "$SCRIPT" 123 --review-only
    [ "$status" -eq 0 ]

    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --review-only --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: --light flag is passed through to ARGUMENTS with --non-interactive" {
    run bash "$SCRIPT" 123 --light
    [ "$status" -eq 0 ]

    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --light --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: --full flag is passed through to ARGUMENTS with --non-interactive" {
    run bash "$SCRIPT" 123 --full
    [ "$status" -eq 0 ]

    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --full --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: no extra flags includes only --non-interactive in ARGUMENTS" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: wait-ci-checks.sh is called before claude" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"Waiting for CI checks on PR #123"* ]]
    [[ "$output" == *"CI check wait complete for PR #123"* ]]
}

@test "error: claude command fails with non-zero exit code" {
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "$@" >> "$CLAUDE_CALL_LOG"
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
exit 42
MOCK
    chmod +x "$MOCK_DIR/claude"

    run bash "$SCRIPT" 789
    [ "$status" -eq 42 ]
    [[ "$output" == *"Starting /review for PR #789"* ]]
    [[ "$output" == *"Finished /review for PR #789"* ]]
    [[ "$output" == *"Exit code: 42"* ]]
}

@test "permission-mode: auto config passes --permission-mode auto" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "auto" ;;
    *) echo "$DEFAULT" ;;
esac
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        --dangerously-skip-permissions) echo "FLAG_SKIP_PERMS=1" >> "$CLAUDE_CALL_LOG" ;;
        --permission-mode) echo "FLAG_PERM_MODE=1" >> "$CLAUDE_CALL_LOG" ;;
        --plugin-dir) echo "FLAG_PLUGIN_DIR=1" >> "$CLAUDE_CALL_LOG" ;;
    esac
done
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "FLAG_PERM_MODE=1" "$CLAUDE_CALL_LOG"
    ! grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"
}

@test "permission-mode: bypass uses --dangerously-skip-permissions" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"
}

@test "guard: prompt contains HEADLESS SKILL EXECUTION guard text" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "PROMPT_HAS_GUARD=1" "$CLAUDE_CALL_LOG"
}

@test "reconcile: exit 0 + matches_expected:false results in exit 1" {
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false,"phase":"review"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"Warning:"*"silent no-op"* ]]
}

@test "reconcile: fallback post succeeds and recheck confirms matches_expected:true results in exit 0" {
    RECONCILE_CALL_COUNT_FILE="$BATS_TEST_TMPDIR/reconcile_call_count"
    echo 0 > "$RECONCILE_CALL_COUNT_FILE"
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<MOCK
#!/bin/bash
COUNT=\$(cat "$RECONCILE_CALL_COUNT_FILE")
COUNT=\$((COUNT + 1))
echo "\$COUNT" > "$RECONCILE_CALL_COUNT_FILE"
if [[ "\$COUNT" -eq 1 ]]; then
    echo '{"matches_expected":false,"phase":"review"}'
else
    echo '{"matches_expected":true,"phase":"review"}'
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/post-fallback-review-summary.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/post-fallback-review-summary.sh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"fallback Response Summary posted"* ]]
}

@test "reconcile: fallback post itself fails keeps exit 1" {
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false,"phase":"review"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/post-fallback-review-summary.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/post-fallback-review-summary.sh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"Warning:"*"silent no-op"* ]]
}

@test "reconcile: exit 0 + matches_expected:true results in exit 0" {
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":true,"phase":"review"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
}

@test "reconcile: exit 0 + empty reconcile output results in exit 0 (no false alarm)" {
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" != *"Warning:"* ]]
}

@test "reconcile: issue extraction failure skips reconcile and exits 0" {
    cat > "$MOCK_DIR/gh-extract-issue-from-pr.sh" <<'MOCK'
#!/bin/bash
echo ""
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh-extract-issue-from-pr.sh"
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false,"phase":"review"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipping reconcile"* ]]
}

@test "emit: phase_start emitted when EMIT_PHASE_NAME is not set" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
MOCK
    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    grep -q "phase_start" "$EMIT_LOG"
    grep -q "phase=review" "$EMIT_LOG"
}

@test "emit: EMIT_ISSUE_NUMBER uses resolved issue number, not PR number" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$1 issue=\$EMIT_ISSUE_NUMBER" >> "${EMIT_LOG}"; }
MOCK
    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    grep -q "issue=99" "$EMIT_LOG"
    ! grep -q "issue=88" "$EMIT_LOG"
}

@test "emit: EMIT_ISSUE_NUMBER falls back to PR number when issue resolution fails" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/gh-extract-issue-from-pr.sh" <<'MOCK'
#!/bin/bash
echo ""
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh-extract-issue-from-pr.sh"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$1 issue=\$EMIT_ISSUE_NUMBER" >> "${EMIT_LOG}"; }
MOCK
    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    grep -q "issue=88" "$EMIT_LOG"
}

@test "emit: phase_start not emitted when EMIT_PHASE_NAME is pre-set (no double emit)" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
MOCK
    export EMIT_PHASE_NAME="review"
    run bash "$SCRIPT" 88
    unset EMIT_PHASE_NAME
    [ "$status" -eq 0 ]
    ! grep -q "phase_start" "$EMIT_LOG"
    ! grep -q "phase_complete" "$EMIT_LOG"
}

@test "emit: phase_complete emitted on success" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
_emit_comments_consumed() { :; }
MOCK
    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    grep -q "phase_complete" "$EMIT_LOG"
}


@test "session-isolation: exit 1 causes abort with error" {
    cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/check-verify-dirty.sh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"parent main has uncommitted changes"* ]]
}

@test "session-isolation: exit 2 shows warning and continues" {
    cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
#!/bin/bash
exit 2
MOCK
    chmod +x "$MOCK_DIR/check-verify-dirty.sh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"other-session dirty files"* ]]
}

@test "worktree-recovery: SCRIPT_DIR pointing at a removed worktree falls back to main repo and completes trailing steps" {
    MAIN_REPO="$BATS_TEST_TMPDIR/main_repo"
    mkdir -p "$MAIN_REPO"
    (
        cd "$MAIN_REPO"
        git init -q
        git config user.email "test@example.com"
        git config user.name "Test"
        mkdir -p scripts skills/review
        cp "$MOCK_DIR"/*.sh scripts/
        chmod +x scripts/*.sh
        cp "$BATS_TEST_TMPDIR/skills/review/SKILL.md" skills/review/SKILL.md
        git add -A
        git commit -q -m init
    )

    WORKTREE_DIR="$BATS_TEST_TMPDIR/linked_wt"
    git -C "$MAIN_REPO" worktree add -q -b wt-issue-887-test "$WORKTREE_DIR"
    # Simulate the linked worktree already having been removed (e.g. by /review's
    # own worktree-lifecycle Exit) by the time run-review.sh captures SCRIPT_DIR
    # from a stale WHOLEWORK_SCRIPT_DIR reference.
    git -C "$MAIN_REPO" worktree remove --force "$WORKTREE_DIR"

    export WHOLEWORK_SCRIPT_DIR="$WORKTREE_DIR/scripts"
    cd "$MAIN_REPO"

    run bash "$SCRIPT" 555
    [ "$status" -eq 0 ]
    [[ "$output" == *"Exit code: 0"* ]]
    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"

    cd "$BATS_TEST_TMPDIR"
}
