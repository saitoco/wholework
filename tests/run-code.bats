#!/usr/bin/env bats

# Tests for run-code.sh
# Mocks: claude, claude-watchdog.sh, phase-banner.sh, gh, git (via MOCK_DIR + WHOLEWORK_SCRIPT_DIR)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-code.sh"

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

    # Mock get-config-value.sh: return "bypass" by default (preserve existing test behavior)
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

    # Mock claude: log flags, model, ANTHROPIC_MODEL, CLAUDECODE, ARGUMENTS, GUARD
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "ARGS_COUNT=$#" >> "$CLAUDE_CALL_LOG"
for arg in "$@"; do
    case "$arg" in
        -p) echo "FLAG_P=1" >> "$CLAUDE_CALL_LOG" ;;
        --model) echo "FLAG_MODEL=1" >> "$CLAUDE_CALL_LOG" ;;
        --dangerously-skip-permissions) echo "FLAG_SKIP_PERMS=1" >> "$CLAUDE_CALL_LOG" ;;
        --permission-mode) echo "FLAG_PERM_MODE=1" >> "$CLAUDE_CALL_LOG" ;;
    esac
done
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
echo "CLAUDECODE=${CLAUDECODE:-__UNSET__}" >> "$CLAUDE_CALL_LOG"
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
print_start_banner() { echo "Starting /$3 for issue #$2"; }
print_end_banner() { echo "Finished /$3 for issue #$2"; }
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
_append_consumed_comments_section() { :; }
MOCK

    # Real guard-prefix.sh (sourced via WHOLEWORK_SCRIPT_DIR)
    cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/guard-prefix.sh" "$MOCK_DIR/guard-prefix.sh"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test issue title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/issues/123"
  fi
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    # Mock reconcile-phase-state.sh: default returns empty (no false alarm)
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    # Create SKILL.md fixture
    # SCRIPT_DIR=$MOCK_DIR so SKILL_FILE=$MOCK_DIR/../skills/code/SKILL.md
    mkdir -p "$BATS_TEST_TMPDIR/skills/code"
    cat > "$BATS_TEST_TMPDIR/skills/code/SKILL.md" <<'SKILL'
---
type: skill
---
# Code Skill Body
This is the skill body content used for testing.
SKILL
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: run-code.sh <issue-number>"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Issue number must be numeric: abc"* ]]
}

@test "success: valid issue number calls claude with --non-interactive" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_MODEL=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"

    grep -q "ARGUMENTS: 123 --non-interactive" "$CLAUDE_CALL_LOG"

    grep -q "ANTHROPIC_MODEL=sonnet" "$CLAUDE_CALL_LOG"
}

@test "success: --patch option calls claude with --patch --non-interactive" {
    run bash "$SCRIPT" 123 --patch
    [ "$status" -eq 0 ]

    grep -q "ARGUMENTS: 123 --patch --non-interactive" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_MODEL=1" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"
}

@test "success: --patch option shows patch route in output" {
    run bash "$SCRIPT" 456 --patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Route: patch (main direct commit)"* ]]
}

@test "error: invalid option is rejected" {
    run bash "$SCRIPT" 123 --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid option: --unknown"* ]]
}

@test "success: --pr option calls claude with --pr --non-interactive" {
    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]

    grep -q "ARGUMENTS: 123 --pr --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "error: --full option is not supported by run-code.sh" {
    run bash "$SCRIPT" 123 --full
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid option: --full"* ]]
}

@test "success: output shows start and finish messages" {
    run bash "$SCRIPT" 456
    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting /code for issue #456"* ]]
    [[ "$output" == *"Finished /code for issue #456"* ]]
    [[ "$output" == *"Model: sonnet"* ]]
    [[ "$output" == *"Permissions: skip (autonomous mode)"* ]]
}

@test "success: CLAUDECODE env var is not inherited by claude subprocess" {
    export CLAUDECODE="parent-session-id"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    grep -q "CLAUDECODE=__UNSET__" "$CLAUDE_CALL_LOG"
}

@test "success: --base option passes base branch in ARGUMENTS" {
    run bash "$SCRIPT" 123 --base release/v2.0
    [ "$status" -eq 0 ]

    grep -q "ARGUMENTS: 123 --base release/v2.0 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: --patch and --base together pass both flags" {
    run bash "$SCRIPT" 123 --patch --base release/v2.0
    [ "$status" -eq 0 ]

    grep -q "ARGUMENTS: 123 --patch --base release/v2.0 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: --base option shows base branch in output" {
    run bash "$SCRIPT" 456 --base release/v2.0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Base branch: release/v2.0"* ]]
}

@test "error: --base without branch name is rejected" {
    run bash "$SCRIPT" 123 --base
    [ "$status" -eq 1 ]
    [[ "$output" == *"--base requires a branch name"* ]]
}

@test "cleanup: stale branch detected and cleaned up before execution" {
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$1" == "branch" && "$2" == "--list" ]]; then
    echo "  worktree-code+issue-123"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"stale branch"* ]]
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
    [[ "$output" == *"Starting /code for issue #789"* ]]
    [[ "$output" == *"Finished /code for issue #789"* ]]
    [[ "$output" == *"Exit code: 42"* ]]
}

@test "idempotency guard: --pr with no existing PR calls claude normally" {
    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
    grep -q "ARGUMENTS: 123 --pr --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "idempotency guard: --pr with existing PR skips claude and exits 0" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test issue title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/issues/123"
  fi
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  echo '[{"headRefName":"worktree-code+issue-123","number":456}]'
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "view" ]]; then
  echo "https://github.com/test/repo/pull/456"
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    [[ "$output" == *"Existing PR #456 detected for issue #123, skipping /code"* ]]
    [ ! -f "$CLAUDE_CALL_LOG" ]
}

@test "idempotency guard: --patch with existing PR calls claude normally" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test issue title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/issues/123"
  fi
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  echo '[{"headRefName":"worktree-code+issue-123","number":456}]'
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123 --patch
    [ "$status" -eq 0 ]
    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
}

@test "idempotency guard: no route flag with existing PR calls claude normally" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
  if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
    echo "test issue title"
  elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
    echo "https://github.com/test/repo/issues/123"
  fi
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  echo '[{"headRefName":"worktree-code+issue-123","number":456}]'
  exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "FLAG_P=1" "$CLAUDE_CALL_LOG"
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

@test "permission-mode: bypass in .wholework.yml uses --dangerously-skip-permissions" {
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
echo '{"matches_expected":false,"phase":"code-pr"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"Warning:"*"silent no-op"* ]]
}

@test "reconcile: exit 0 + matches_expected:true results in exit 0" {
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":true,"phase":"code-pr"}'
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

@test "emit: phase_start emitted when EMIT_PHASE_NAME is not set" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
MOCK
    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    grep -q "phase_start" "$EMIT_LOG"
    grep -q "phase=code-pr" "$EMIT_LOG"
}

@test "emit: phase_start not emitted when EMIT_PHASE_NAME is pre-set (no double emit)" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
MOCK
    export EMIT_PHASE_NAME="code-pr"
    run bash "$SCRIPT" 123 --pr
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
_append_consumed_comments_section() { :; }
MOCK
    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    grep -q "phase_complete" "$EMIT_LOG"
}

@test "side-effect: _emit_comments_consumed called before claude invocation" {
    CALL_ORDER_LOG="$BATS_TEST_TMPDIR/call-order.log"
    export CALL_ORDER_LOG

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { :; }
_emit_comments_consumed() { echo "comments_consumed_called" >> "${CALL_ORDER_LOG}"; }
MOCK

    cat > "$MOCK_DIR/claude" <<MOCK
#!/bin/bash
echo "claude_called" >> "${CALL_ORDER_LOG}"
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    grep -q "comments_consumed_called" "$CALL_ORDER_LOG"
    local cc_line claude_line
    cc_line=$(grep -n "comments_consumed_called" "$CALL_ORDER_LOG" | head -1 | cut -d: -f1)
    claude_line=$(grep -n "claude_called" "$CALL_ORDER_LOG" | head -1 | cut -d: -f1)
    [ "${cc_line:-0}" -lt "${claude_line:-999}" ]
}

@test "side-effect: append-loop-state-heartbeat.sh called on code phase success" {
    HEARTBEAT_LOG="$BATS_TEST_TMPDIR/heartbeat.log"
    export HEARTBEAT_LOG

    cat > "$MOCK_DIR/append-loop-state-heartbeat.sh" <<MOCK
#!/bin/bash
echo "heartbeat_called \$@" >> "${HEARTBEAT_LOG}"
exit 0
MOCK
    chmod +x "$MOCK_DIR/append-loop-state-heartbeat.sh"

    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    grep -q "heartbeat_called" "$HEARTBEAT_LOG"
    grep -q -- "--from spec" "$HEARTBEAT_LOG"
    grep -q -- "--to code" "$HEARTBEAT_LOG"
}

@test "fallback: no consumed comments section before and after claude → _append_consumed_comments_section called" {
    # Create spec file without ## Consumed Comments section (simulates fresh spec)
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    printf '%s\n' "# Issue #123: Test" > "$BATS_TEST_TMPDIR/docs/spec/issue-123-test.md"

    FALLBACK_LOG="$BATS_TEST_TMPDIR/fallback.log"
    export FALLBACK_LOG

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { return 0; }
_emit_comments_consumed() { :; }
_append_consumed_comments_section() { echo "CALLED \$*" >> "${FALLBACK_LOG}"; }
MOCK

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [ -f "$FALLBACK_LOG" ]
    grep -q "CALLED 123 code" "$FALLBACK_LOG"
}

@test "no fallback: consumed comments section added by claude (count increases) → _append_consumed_comments_section not called" {
    # Create spec file without ## Consumed Comments section
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    printf '%s\n' "# Issue #123: Test" > "$BATS_TEST_TMPDIR/docs/spec/issue-123-test.md"

    FALLBACK_LOG="$BATS_TEST_TMPDIR/fallback.log"
    SPEC_FILE_IN_MOCK="$BATS_TEST_TMPDIR/docs/spec/issue-123-test.md"
    export FALLBACK_LOG SPEC_FILE_IN_MOCK

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { return 0; }
_emit_comments_consumed() { :; }
_append_consumed_comments_section() { echo "CALLED \$*" >> "${FALLBACK_LOG}"; }
MOCK

    # Claude mock writes ## Consumed Comments to the spec file (simulates LLM writing it)
    cat > "$MOCK_DIR/claude" <<MOCK
#!/bin/bash
printf '\n%s\n' "## Consumed Comments" >> "${SPEC_FILE_IN_MOCK}"
printf '%s\n' "No new comments since last phase." >> "${SPEC_FILE_IN_MOCK}"
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [ ! -f "$FALLBACK_LOG" ]
}
