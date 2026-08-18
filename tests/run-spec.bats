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
        if echo "$arg" | grep -q 'no re-invocation guarantee'; then
            echo "PROMPT_HAS_BG_GUARD=1" >> "$CLAUDE_CALL_LOG"
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

    # Mock git: default handles `rev-parse --show-toplevel` (used for REPO_ROOT), else no-op success.
    # Needed so auto-retry-on-fail's `git ls-files` preflight check does not fall through to the
    # real system git (which would fail with "not a git repository" inside $BATS_TEST_TMPDIR).
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ "\$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

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

@test "guard: prompt contains background-wait no re-invocation guarantee text" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "PROMPT_HAS_BG_GUARD=1" "$CLAUDE_CALL_LOG"
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
    if grep -q "phase_start" "$EMIT_LOG"; then false; fi
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

@test "emit: wrapper_exit emitted with phase=spec and exit_code=0" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
_append_consumed_comments_section() { :; }
MOCK
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "wrapper_exit phase=spec exit_code=0" "$EMIT_LOG"
}

@test "emit: wrapper_exit not emitted when EMIT_PHASE_NAME is pre-set (no double emit)" {
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
MOCK
    export EMIT_PHASE_NAME="spec"
    run bash "$SCRIPT" 123
    unset EMIT_PHASE_NAME
    [ "$status" -eq 0 ]
    if grep -q "wrapper_exit" "$EMIT_LOG"; then false; fi
    ! grep -q "token_usage" "$EMIT_LOG"
}

@test "emit: token_usage emitted with phase=spec and model= when TOKEN_USAGE_FILE is produced" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    EMIT_LOG="$BATS_TEST_TMPDIR/emit.log"
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() { echo "\$@" >> "${EMIT_LOG}"; }
_append_consumed_comments_section() { :; }
MOCK

    # Real CLI output shape: top-level "model" is always null; the actual
    # model ID lives under modelUsage.<id>.*
    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
cat <<'JSON'
{"result":"done","model":null,"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20},"modelUsage":{"claude-sonnet-5":{"inputTokens":100,"outputTokens":50}}}
JSON
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "token_usage phase=spec model=claude-sonnet-5 input_tokens=100 output_tokens=50 cache_read_tokens=20" "$EMIT_LOG"
    [ ! -f ".tmp/token-usage-123.json" ]
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

@test "phase-guard: phase/code label blocks spec execution" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "phase/code"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"classify=phase-guard-blocked"* ]]
    [[ "$output" == *"issue #123 already has label 'phase/code'"* ]]
    [ ! -f "$CLAUDE_CALL_LOG" ]
}

@test "phase-guard: phase/merge label blocks spec execution" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "phase/merge"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"classify=phase-guard-blocked"* ]]
    [[ "$output" == *"issue #123 already has label 'phase/merge'"* ]]
    [ ! -f "$CLAUDE_CALL_LOG" ]
}

@test "phase-guard: phase/ready label does not block spec execution" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "phase/ready"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" != *"classify=phase-guard-blocked"* ]]
}

@test "auto-retry: silent no-op + AUTO_RETRY_ENABLED=true fires retry (SPEC_RETRY_COUNT increments)" {
    # When reconcile returns matches_expected:false and auto-retry is configured,
    # run-spec.sh re-invokes itself via exec. To avoid an infinite loop in the test,
    # the second invocation uses a reconcile mock that returns matches_expected:true.
    RETRY_COUNTER_FILE="$BATS_TEST_TMPDIR/retry_count.txt"
    echo "0" > "$RETRY_COUNTER_FILE"
    export RETRY_COUNTER_FILE

    cat > "$BATS_TEST_TMPDIR/.wholework.yml" <<'EOF'
permission-mode: bypass
auto-retry-on-fail:
  enabled: true
  max_iterations: 3
EOF

    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "bypass" ;;
    autonomy) echo "L3" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<MOCK
#!/bin/bash
N=\$(cat "${RETRY_COUNTER_FILE}" 2>/dev/null || echo 0)
N=\$((N + 1))
echo "\$N" > "${RETRY_COUNTER_FILE}"
if [[ "\$N" -eq 1 ]]; then
  echo '{"matches_expected":false,"phase":"spec"}'
else
  echo '{"matches_expected":true,"phase":"spec"}'
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"auto-retry: spec phase silent no-op"* ]]
    [ "$(cat "$RETRY_COUNTER_FILE")" -ge 2 ]
}

@test "auto-retry: silent no-op + AUTO_RETRY_ENABLED=false does not retry, exits 1" {
    # Counts claude invocations directly (rather than relying on exit status/log text
    # alone) so this test cannot pass vacuously against pre-#1369 run-spec.sh, which
    # also exits 1 on a silent no-op but for an unrelated reason (no retry branch existed
    # at all yet) -- the counter proves specifically that AUTO_RETRY_ENABLED=false
    # suppressed a second invocation, not just that the exit code happened to match.
    CLAUDE_INVOKE_COUNTER_FILE="$BATS_TEST_TMPDIR/claude_invoke_count.txt"
    echo "0" > "$CLAUDE_INVOKE_COUNTER_FILE"
    export CLAUDE_INVOKE_COUNTER_FILE

    cat > "$BATS_TEST_TMPDIR/.wholework.yml" <<'EOF'
permission-mode: bypass
auto-retry-on-fail:
  enabled: false
EOF

    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "bypass" ;;
    autonomy) echo "L3" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    cat > "$MOCK_DIR/claude" <<MOCK
#!/bin/bash
N=\$(cat "$CLAUDE_INVOKE_COUNTER_FILE" 2>/dev/null || echo 0)
N=\$((N + 1))
echo "\$N" > "$CLAUDE_INVOKE_COUNTER_FILE"
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false,"phase":"spec"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" != *"auto-retry: spec phase silent no-op"* ]]
    [ "$(cat "$CLAUDE_INVOKE_COUNTER_FILE")" -eq 1 ]
}

@test "auto-retry: SPEC_RETRY_COUNT at max does not retry and exits 1 with advisory" {
    cat > "$BATS_TEST_TMPDIR/.wholework.yml" <<'EOF'
permission-mode: bypass
auto-retry-on-fail:
  enabled: true
  max_iterations: 3
EOF

    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "bypass" ;;
    autonomy) echo "L3" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false,"phase":"spec"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    SPEC_RETRY_COUNT=3 run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" != *"auto-retry: spec phase silent no-op, retry"* ]]
    [[ "$output" == *"max iterations reached"* ]]
}

@test "auto-retry: preflight stashes parent-main stray untracked file before retry re-invocation" {
    # Simulates Issue #886 (code phase) applied to the spec phase: claude's first
    # invocation leaves a stray untracked file (silent no-op side effect) that would
    # otherwise block check-verify-dirty.sh on the retry re-invocation. The preflight
    # block must stash it via `git stash push` so the retry can proceed.
    STRAY_FILE="$BATS_TEST_TMPDIR/stray-output.md"
    GIT_CALL_LOG="$BATS_TEST_TMPDIR/git_calls.log"
    : > "$GIT_CALL_LOG"
    export GIT_CALL_LOG

    RETRY_COUNTER_FILE="$BATS_TEST_TMPDIR/retry_count.txt"
    echo "0" > "$RETRY_COUNTER_FILE"
    export RETRY_COUNTER_FILE

    CLAUDE_INVOKE_COUNTER_FILE="$BATS_TEST_TMPDIR/claude_invoke_count.txt"
    echo "0" > "$CLAUDE_INVOKE_COUNTER_FILE"
    export CLAUDE_INVOKE_COUNTER_FILE

    cat > "$BATS_TEST_TMPDIR/.wholework.yml" <<'EOF'
permission-mode: bypass
auto-retry-on-fail:
  enabled: true
  max_iterations: 3
EOF

    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "bypass" ;;
    autonomy) echo "L3" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    # claude: only the first invocation leaves a stray untracked file behind
    # (simulating a silent no-op side effect).
    cat > "$MOCK_DIR/claude" <<MOCK
#!/bin/bash
N=\$(cat "$CLAUDE_INVOKE_COUNTER_FILE" 2>/dev/null || echo 0)
N=\$((N + 1))
echo "\$N" > "$CLAUDE_INVOKE_COUNTER_FILE"
if [[ "\$N" -eq 1 ]]; then
  touch "$STRAY_FILE"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    # check-verify-dirty.sh: exit 1 while the stray file exists, exit 0 once
    # it has been stashed away.
    cat > "$MOCK_DIR/check-verify-dirty.sh" <<MOCK
#!/bin/bash
if [[ -f "$STRAY_FILE" ]]; then
  exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/check-verify-dirty.sh"

    # git: report the stray file for `ls-files --others --exclude-standard`,
    # and remove it (simulating a real stash) on `stash push`, logging both calls.
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$*" >> "$GIT_CALL_LOG"
if [[ "\$1" == "ls-files" ]]; then
  if [[ -f "$STRAY_FILE" ]]; then
    echo "stray-output.md"
  fi
  exit 0
fi
if [[ "\$1" == "stash" && "\$2" == "push" ]]; then
  rm -f "$STRAY_FILE"
  exit 0
fi
if [[ "\$*" == *"rev-parse --show-toplevel"* ]]; then
  echo "$BATS_TEST_TMPDIR"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<MOCK
#!/bin/bash
N=\$(cat "${RETRY_COUNTER_FILE}" 2>/dev/null || echo 0)
N=\$((N + 1))
echo "\$N" > "${RETRY_COUNTER_FILE}"
if [[ "\$N" -eq 1 ]]; then
  echo '{"matches_expected":false,"phase":"spec"}'
else
  echo '{"matches_expected":true,"phase":"spec"}'
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" == *"auto-retry preflight: stashing parent-main untracked files: stray-output.md"* ]]
    grep -q "stash push" "$GIT_CALL_LOG"
    [ ! -f "$STRAY_FILE" ]
}

@test "auto-retry: spec_retry_fire records recovery entry before exec re-invocation (Issue #1369)" {
    # Simulates Issue #1369: when auto-retry-on-fail fires, run-spec.sh must record a
    # spec-retry-fire entry to orchestration-recoveries.md and commit/push it BEFORE the
    # `exec` self-restart -- exec replaces the process, so the retried invocation has no
    # memory of the failure that triggered it. Verifies (a) the entry is appended to the
    # mocked orchestration-recoveries.md, and (b) git add/commit/push are logged before the
    # second `claude` invocation (i.e. before the exec re-invocation runs).
    RECOVERIES_FILE="$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md"
    mkdir -p "$(dirname "$RECOVERIES_FILE")"
    cat > "$RECOVERIES_FILE" <<'EOF'
---
type: report
description: Cross-Issue orchestration recovery log. Append-only. Newest entries first.
---

# Orchestration Recovery Log

<!-- Log entries appear below, newest first. -->
EOF
    export RECOVERIES_FILE

    RETRY_COUNTER_FILE="$BATS_TEST_TMPDIR/retry_count.txt"
    echo "0" > "$RETRY_COUNTER_FILE"
    export RETRY_COUNTER_FILE

    COMBINED_LOG="$BATS_TEST_TMPDIR/combined_calls.log"
    : > "$COMBINED_LOG"
    export COMBINED_LOG

    cat > "$BATS_TEST_TMPDIR/.wholework.yml" <<'EOF'
permission-mode: bypass
auto-retry-on-fail:
  enabled: true
  max_iterations: 3
EOF

    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "bypass" ;;
    autonomy) echo "L3" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    cat > "$MOCK_DIR/claude" <<MOCK
#!/bin/bash
echo "CLAUDE_INVOKE" >> "$COMBINED_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<MOCK
#!/bin/bash
N=\$(cat "${RETRY_COUNTER_FILE}" 2>/dev/null || echo 0)
N=\$((N + 1))
echo "\$N" > "${RETRY_COUNTER_FILE}"
if [[ "\$N" -eq 1 ]]; then
  echo '{"matches_expected":false,"phase":"spec"}'
else
  echo '{"matches_expected":true,"phase":"spec"}'
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ "\$*" == *"rev-parse --show-toplevel"* ]]; then
  echo "$BATS_TEST_TMPDIR"
  exit 0
fi
ARGS=("\$@")
if [[ "\${ARGS[0]}" == "-C" ]]; then
  ARGS=("\${ARGS[@]:2}")
fi
case "\${ARGS[0]}" in
  diff)
    echo "GIT diff" >> "$COMBINED_LOG"
    exit 1
    ;;
  add)
    echo "GIT add \${ARGS[*]}" >> "$COMBINED_LOG"
    exit 0
    ;;
  commit)
    echo "GIT commit" >> "$COMBINED_LOG"
    exit 0
    ;;
  push)
    echo "GIT push" >> "$COMBINED_LOG"
    exit 0
    ;;
  ls-files)
    exit 0
    ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]

    # (a) spec-retry-fire entry appended with expected fields
    grep -q ": spec-retry-fire$" "$RECOVERIES_FILE"
    grep -q "Issue #123, phase: spec" "$RECOVERIES_FILE"
    grep -q "modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire" "$RECOVERIES_FILE"

    # (b) git add/commit/push happened before the second claude invocation (exec re-invocation)
    SECOND_CLAUDE_LINE=$(grep -n "CLAUDE_INVOKE" "$COMBINED_LOG" | sed -n '2p' | cut -d: -f1)
    COMMIT_LINE=$(grep -n "GIT commit" "$COMBINED_LOG" | head -1 | cut -d: -f1)
    PUSH_LINE=$(grep -n "GIT push" "$COMBINED_LOG" | head -1 | cut -d: -f1)
    [ -n "$SECOND_CLAUDE_LINE" ]
    [ -n "$COMMIT_LINE" ]
    [ -n "$PUSH_LINE" ]
    [ "$COMMIT_LINE" -lt "$SECOND_CLAUDE_LINE" ]
    [ "$PUSH_LINE" -lt "$SECOND_CLAUDE_LINE" ]
}

@test "AUTO_SESSION_ID does not fall back to .tmp/auto-session-current when PGID file absent (Issue #1317, no misattribution)" {
    # Issue #1317: run-spec.sh's inline AUTO_SESSION_ID resolve no longer falls back to
    # .tmp/auto-session-current — that file is written only by /auto Step 1, so a wrapper
    # invoked outside /auto (e.g. a manual `/spec` run while another /auto session is
    # active) has no claim to it. Reproduces the same shell snippet as scripts/run-spec.sh
    # with the PGID file absent and .tmp/auto-session-current holding a DIFFERENT
    # (concurrent) session's ID, and asserts AUTO_SESSION_ID resolves to empty (fail-closed)
    # rather than adopting it.
    mkdir -p .tmp
    echo "concurrent-session-sid-12345-1782604910" > .tmp/auto-session-current
    # Intentionally do NOT create .tmp/auto-session-${PGID}

    unset AUTO_SESSION_ID
    PGID=$(ps -o pgid= -p $$ | tr -d ' ')
    AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"

    [ -z "$AUTO_SESSION_ID" ]
}
