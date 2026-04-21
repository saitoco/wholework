#!/usr/bin/env bats

# Tests for spawn-recovery-subagent.sh
# Uses CLAUDE_BIN mock to avoid real claude -p invocations.
# Integration tests (real claude -p) are tagged with @test "... # integration" and excluded from CI.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/spawn-recovery-subagent.sh"
REAL_SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    export CLAUDE_BIN="$MOCK_DIR/claude-mock"

    LOG_FILE="$BATS_TEST_TMPDIR/wrapper.log"
    echo "some failure output" > "$LOG_FILE"
    export LOG_FILE

    RUNNER_LOG="$BATS_TEST_TMPDIR/runner.log"
    export RUNNER_LOG

    # Mock sibling scripts
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo "bypass"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    cat > "$MOCK_DIR/watchdog-defaults.sh" <<'MOCK'
WATCHDOG_TIMEOUT_DEFAULT=1800
load_watchdog_timeout() { WATCHDOG_TIMEOUT=1800; }
MOCK

    cat > "$MOCK_DIR/claude-watchdog.sh" <<'MOCK'
#!/bin/bash
# claude-watchdog.sh: pass through to the actual command
shift 0
"$@"
MOCK
    chmod +x "$MOCK_DIR/claude-watchdog.sh"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    # Use real validate-recovery-plan.sh
    cp "$REAL_SCRIPTS_DIR/validate-recovery-plan.sh" "$MOCK_DIR/validate-recovery-plan.sh"
    chmod +x "$MOCK_DIR/validate-recovery-plan.sh"

    # Mock run-code.sh for retry action
    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUNNER_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    # agents directory (needed for agent body loading)
    AGENT_DIR="$MOCK_DIR/../agents"
    mkdir -p "$AGENT_DIR"
    cat > "$AGENT_DIR/orchestration-recovery.md" <<'AGENTEOF'
---
name: orchestration-recovery
description: Test agent
---

You are a recovery agent. Return a minimal JSON plan.
AGENTEOF
}

teardown() {
    rm -rf "$MOCK_DIR"
    rm -rf "$BATS_TEST_TMPDIR/.tmp" 2>/dev/null || true
}

# Helper: create a mock claude binary that returns a given JSON plan
make_claude_mock() {
    local plan_json="$1"
    cat > "$MOCK_DIR/claude-mock" <<MOCK
#!/bin/bash
echo '$plan_json'
MOCK
    # Use printf to avoid issues with single quotes in JSON
    printf '#!/bin/bash\necho '"'"'%s'"'"'\n' "$plan_json" > "$MOCK_DIR/claude-mock"
    chmod +x "$MOCK_DIR/claude-mock"
}

@test "spawn-recovery: missing --log argument exits non-zero" {
    run bash "$SCRIPT" code 42
    [ "$status" -ne 0 ]
    [[ "$output" == *"--log"* ]]
}

@test "spawn-recovery: CLAUDE_BIN mock returns valid retry plan: runner_script re-invoked" {
    make_claude_mock '{"action":"retry","rationale":"transient failure","steps":[]}'
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"action=retry"* ]]
    [ -f "$RUNNER_LOG" ]
    grep -q "42" "$RUNNER_LOG"
}

@test "spawn-recovery: CLAUDE_BIN mock returns action=skip: exits 0 without runner invocation" {
    make_claude_mock '{"action":"skip","rationale":"phase already completed","steps":[]}'
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"action=skip"* ]]
    [ ! -f "$RUNNER_LOG" ]
}

@test "spawn-recovery: CLAUDE_BIN mock returns plan with forbidden op force_push: validation aborts" {
    make_claude_mock '{"action":"recover","rationale":"fix","steps":[{"op":"force_push","cmd":"git push -f"}]}'
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"safety validation"* ]]
}

@test "spawn-recovery: CLAUDE_BIN mock returns plan with 6 steps: step limit aborts" {
    make_claude_mock '{"action":"recover","rationale":"fix","steps":[{"op":"run_command","cmd":"echo 1"},{"op":"run_command","cmd":"echo 2"},{"op":"run_command","cmd":"echo 3"},{"op":"run_command","cmd":"echo 4"},{"op":"run_command","cmd":"echo 5"},{"op":"run_command","cmd":"echo 6"}]}'
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"safety validation"* ]]
}

@test "spawn-recovery: CLAUDE_BIN mock returns action=abort: exits non-zero" {
    make_claude_mock '{"action":"abort","rationale":"cannot recover","steps":[]}'
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"action=abort"* ]]
}

@test "spawn-recovery: slot cap reached (existing slot dir) causes immediate abort" {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p ".tmp"
    mkdir ".tmp/recovery-subagent-slot-1"
    # Use current shell PID: this process is running, so the lock is not stale
    echo "$$" > ".tmp/recovery-subagent-slot-1/pid"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"slot(s) occupied"* ]]
}

@test "spawn-recovery: stale slot lock (dead pid) is reclaimed and script proceeds" {
    make_claude_mock '{"action":"skip","rationale":"already done","steps":[]}'
    cd "$BATS_TEST_TMPDIR"
    mkdir -p ".tmp"
    mkdir ".tmp/recovery-subagent-slot-1"
    # Use a PID that is guaranteed to not be running (extremely high number)
    echo "999999999" > ".tmp/recovery-subagent-slot-1/pid"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"action=skip"* ]]
}

@test "spawn-recovery: CLAUDE_BIN mock returns prose + JSON + prose: JSON extracted correctly" {
    cat > "$MOCK_DIR/claude-mock" <<'MOCK'
#!/bin/bash
printf 'Let me analyze this issue.\n\n{"action":"skip","rationale":"already resolved","steps":[]}\n\nHope that helps!'
MOCK
    chmod +x "$MOCK_DIR/claude-mock"
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"action=skip"* ]]
}

# Integration test: tagged with 'integration', excluded from CI runs
# @test "spawn-recovery integration: real claude -p returns valid JSON" {
#     # tags: integration
#     # This test is excluded from CI and must be run manually:
#     # bats --filter-tags integration tests/spawn-recovery-subagent.bats
#     unset CLAUDE_BIN
#     cd "$BATS_TEST_TMPDIR"
#     run bash "$SCRIPT" code 42 --log "$LOG_FILE"
#     [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
# }
