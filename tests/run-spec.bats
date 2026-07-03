#!/usr/bin/env bats

# Tests for run-spec.sh
# Mocks: claude, claude-watchdog.sh, phase-banner.sh, gh, emit-event.sh
#        (via MOCK_DIR + WHOLEWORK_SCRIPT_DIR)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-spec.sh"

setup() {
    # Isolate test from repo .wholework.yml
    echo "permission-mode: bypass" > "$BATS_TEST_TMPDIR/.wholework.yml"
    cd "$BATS_TEST_TMPDIR"
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude_calls.log"
    export CLAUDE_CALL_LOG

    # Mock get-config-value.sh: return "auto" for permission-mode (new default)
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "auto" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    # Mock claude: log flags, model, effort, ANTHROPIC_MODEL, CLAUDECODE, ARGUMENTS, GUARD
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "ARGS_COUNT=$#" >> "$CLAUDE_CALL_LOG"
for arg in "$@"; do
    case "$arg" in
        -p) echo "FLAG_P=1" >> "$CLAUDE_CALL_LOG" ;;
        --model) echo "FLAG_MODEL=1" >> "$CLAUDE_CALL_LOG" ;;
        --dangerously-skip-permissions) echo "FLAG_SKIP_PERMS=1" >> "$CLAUDE_CALL_LOG" ;;
        --permission-mode) echo "FLAG_PERM_MODE=1" >> "$CLAUDE_CALL_LOG" ;;
        --effort) echo "FLAG_EFFORT=1" >> "$CLAUDE_CALL_LOG" ;;
        --plugin-dir) echo "FLAG_PLUGIN_DIR=1" >> "$CLAUDE_CALL_LOG" ;;
    esac
done
echo "ANTHROPIC_MODEL=$ANTHROPIC_MODEL" >> "$CLAUDE_CALL_LOG"
echo "CLAUDECODE=${CLAUDECODE:-__UNSET__}" >> "$CLAUDE_CALL_LOG"
# Extract ARGUMENTS line and guard text from prompt (arg after -p)
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
# Extract model value (arg after --model)
FOUND_MODEL=0
for arg in "$@"; do
    if [[ $FOUND_MODEL -eq 1 ]]; then
        echo "MODEL_VALUE=$arg" >> "$CLAUDE_CALL_LOG"
        break
    fi
    [[ "$arg" == "--model" ]] && FOUND_MODEL=1
done
# Extract effort value (arg after --effort)
FOUND_EFFORT=0
for arg in "$@"; do
    if [[ $FOUND_EFFORT -eq 1 ]]; then
        echo "EFFORT_VALUE=$arg" >> "$CLAUDE_CALL_LOG"
        break
    fi
    [[ "$arg" == "--effort" ]] && FOUND_EFFORT=1
done
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    # Mock claude-watchdog.sh: pass through to the real claude mock in PATH
    cat > "$MOCK_DIR/claude-watchdog.sh" <<'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/claude-watchdog.sh"

    # Mock handle-permission-mode-failure.sh (always silent, exits 0)
    cat > "$MOCK_DIR/handle-permission-mode-failure.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/handle-permission-mode-failure.sh"

    # Mock phase-banner.sh (sourced by run-spec.sh)
    cat > "$MOCK_DIR/phase-banner.sh" <<'MOCK'
print_start_banner() { echo "Starting /$3 for issue #$2"; }
print_end_banner() { echo "Finished /$3 for issue #$2"; }
MOCK

    # Mock watchdog-defaults.sh (sourced by run-spec.sh via WHOLEWORK_SCRIPT_DIR)
    cat > "$MOCK_DIR/watchdog-defaults.sh" <<'MOCK'
WATCHDOG_TIMEOUT_DEFAULT=1800
load_watchdog_timeout() { WATCHDOG_TIMEOUT=1800; }
MOCK

    # Isolate from parent process env (e.g. running inside /code or /auto session)
    unset EMIT_PHASE_NAME EMIT_ISSUE_NUMBER AUTO_SESSION_ID

    # Mock emit-event.sh: no-op by default (tests that need capture override this)
    cat > "$MOCK_DIR/emit-event.sh" <<'MOCK'
emit_event() { return 0; }
_append_consumed_comments_section() { :; }
MOCK

    cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/check-verify-dirty.sh"

    # Real guard-prefix.sh and retry-on-kill.sh (sourced via WHOLEWORK_SCRIPT_DIR)
    cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/guard-prefix.sh" "$MOCK_DIR/guard-prefix.sh"
    cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/retry-on-kill.sh" "$MOCK_DIR/retry-on-kill.sh"

    # Mock reconcile-phase-state.sh: default returns empty (no false alarm)
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    # Mock gh for phase-banner title/url lookups
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

    # Create default SKILL.md with valid frontmatter at $BATS_TEST_TMPDIR/skills/spec/SKILL.md
    # run-spec.sh resolves: SKILL_FILE="${SCRIPT_DIR}/../skills/spec/SKILL.md"
    # With WHOLEWORK_SCRIPT_DIR=$MOCK_DIR, SCRIPT_DIR=$MOCK_DIR, so path is:
    # $MOCK_DIR/../skills/spec/SKILL.md = $BATS_TEST_TMPDIR/skills/spec/SKILL.md
    mkdir -p "$BATS_TEST_TMPDIR/skills/spec"
    cat > "$BATS_TEST_TMPDIR/skills/spec/SKILL.md" <<'SKILL'
---
type: skill
---
# Spec Skill Body
This is the skill body content used for testing.
SKILL
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: run-spec.sh <issue-number>"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Issue number must be numeric: abc"* ]]
}

@test "error: unknown option is rejected" {
    run bash "$SCRIPT" 123 --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid option: --unknown"* ]]
}

@test "success: default model is sonnet" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "MODEL_VALUE=sonnet" "$CLAUDE_CALL_LOG"
    grep -q "ANTHROPIC_MODEL=sonnet" "$CLAUDE_CALL_LOG"
    grep -q "FLAG_PLUGIN_DIR=1" "$CLAUDE_CALL_LOG"
}

@test "success: default effort is max" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "EFFORT_VALUE=max" "$CLAUDE_CALL_LOG"
}

@test "success: --permission-mode auto is passed by default" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "FLAG_PERM_MODE=1" "$CLAUDE_CALL_LOG"
    ! grep -q "FLAG_SKIP_PERMS=1" "$CLAUDE_CALL_LOG"
}

@test "success: --opus switches model to opus" {
    run bash "$SCRIPT" 123 --opus
    [ "$status" -eq 0 ]
    grep -q "MODEL_VALUE=opus" "$CLAUDE_CALL_LOG"
    grep -q "ANTHROPIC_MODEL=opus" "$CLAUDE_CALL_LOG"
}

@test "error: SKILL.md not found when file is absent" {
    rm -f "$BATS_TEST_TMPDIR/skills/spec/SKILL.md"
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"SKILL.md not found"* ]]
}

@test "error: frontmatter not found when SKILL.md has no --- delimiter" {
    cat > "$BATS_TEST_TMPDIR/skills/spec/SKILL.md" <<'SKILL'
# No frontmatter here
Just a body with no frontmatter delimiter.
SKILL
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"frontmatter not found"* ]]
}

@test "success: ARGUMENTS contains issue number with --non-interactive" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "PROMPT_CONTAINS_ARGUMENTS=ARGUMENTS: 123 --non-interactive" "$CLAUDE_CALL_LOG"
}

@test "success: CLAUDECODE env var is unset for claude subprocess" {
    export CLAUDECODE="parent-session-id"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "CLAUDECODE=__UNSET__" "$CLAUDE_CALL_LOG"
}

@test "success: --opus default effort is xhigh" {
    run bash "$SCRIPT" 123 --opus
    [ "$status" -eq 0 ]
    grep -q "EFFORT_VALUE=xhigh" "$CLAUDE_CALL_LOG"
}

@test "success: --opus --max explicit effort is max" {
    run bash "$SCRIPT" 123 --opus --max
    [ "$status" -eq 0 ]
    grep -q "EFFORT_VALUE=max" "$CLAUDE_CALL_LOG"
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

@test "permission-mode: bypass config uses --dangerously-skip-permissions" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "bypass" ;;
    *) echo "$DEFAULT" ;;
esac
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
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
echo '{"matches_expected":false,"phase":"spec"}'
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
echo '{"matches_expected":true,"phase":"spec"}'
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

@test "success: --fable switches model to claude-fable-5" {
    run bash "$SCRIPT" 123 --fable
    [ "$status" -eq 0 ]
    grep -q "MODEL_VALUE=claude-fable-5" "$CLAUDE_CALL_LOG"
    grep -q "ANTHROPIC_MODEL=claude-fable-5" "$CLAUDE_CALL_LOG"
}

@test "success: --fable default effort is high" {
    run bash "$SCRIPT" 123 --fable
    [ "$status" -eq 0 ]
    grep -q "EFFORT_VALUE=high" "$CLAUDE_CALL_LOG"
}

@test "success: --fable --max explicit effort is max" {
    run bash "$SCRIPT" 123 --fable --max
    [ "$status" -eq 0 ]
    grep -q "EFFORT_VALUE=max" "$CLAUDE_CALL_LOG"
}

@test "success: --fable outputs retention warning" {
    run bash "$SCRIPT" 123 --fable
    [ "$status" -eq 0 ]
    [[ "$output" == *"retention"* ]]
}

@test "success: --fable outputs credit warning" {
    run bash "$SCRIPT" 123 --fable
    [ "$status" -eq 0 ]
    [[ "$output" == *"credit"* ]]
}

@test "emit: phase_start emitted when EMIT_PHASE_NAME is not set" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
MOCK
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "phase_start" "$EMIT_LOG"
    grep -q "phase=spec" "$EMIT_LOG"
}

@test "emit: phase_start not emitted when EMIT_PHASE_NAME is pre-set (no double emit)" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
MOCK
    export EMIT_PHASE_NAME="spec"
    run bash "$SCRIPT" 123
    unset EMIT_PHASE_NAME
    [ "$status" -eq 0 ]
    ! grep -q "phase_start" "$EMIT_LOG"
    ! grep -q "phase_complete" "$EMIT_LOG"
}

@test "emit: phase_complete emitted on success" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
_append_consumed_comments_section() { :; }
MOCK
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "phase_complete" "$EMIT_LOG"
}

@test "fallback: no consumed comments section before and after claude → _append_consumed_comments_section called" {
    # Create spec file without ## Consumed Comments section (simulates fresh spec)
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    printf '%s\n' "# Issue #123: Test" > "$BATS_TEST_TMPDIR/docs/spec/issue-123-test.md"

    FALLBACK_LOG="$BATS_TEST_TMPDIR/fallback.log"
    export FALLBACK_LOG

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { return 0; }
_append_consumed_comments_section() { echo "CALLED \$*" >> "${FALLBACK_LOG}"; }
MOCK

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [ -f "$FALLBACK_LOG" ]
    grep -q "CALLED 123 spec" "$FALLBACK_LOG"
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

@test "retry-on-kill: retry-success - killed once then succeeds, wrapper exits 0" {
    COUNTER_FILE="$BATS_TEST_TMPDIR/call_counter"
    echo "0" > "$COUNTER_FILE"
    export COUNTER_FILE
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
N=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
N=$((N + 1))
echo "$N" > "$COUNTER_FILE"
if [[ $N -eq 1 ]]; then exit 143; fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [ "$(cat "$COUNTER_FILE")" -eq 2 ]
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
