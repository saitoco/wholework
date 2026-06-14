#!/usr/bin/env bats

# Tests for write_recovery_entry() in spawn-recovery-subagent.sh.
# Verifies that Tier 3 recovery events are recorded to orchestration-recoveries.md.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/spawn-recovery-subagent.sh"
REAL_SCRIPTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    export CLAUDE_BIN="$MOCK_DIR/claude-mock"

    LOG_FILE="$BATS_TEST_TMPDIR/wrapper.log"
    echo "phase failed: exit code 1" > "$LOG_FILE"
    export LOG_FILE

    RUNNER_LOG="$BATS_TEST_TMPDIR/runner.log"
    export RUNNER_LOG

    # Create docs/reports fixture (write_recovery_entry looks at dirname(SCRIPT_DIR)/docs/reports/...)
    mkdir -p "$BATS_TEST_TMPDIR/docs/reports"
    cat > "$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md" <<'FIXTURE'
---
type: report
---

# Orchestration Recovery Log

<!-- Log entries appear below, newest first. -->
FIXTURE

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

    cp "$REAL_SCRIPTS_DIR/validate-recovery-plan.sh" "$MOCK_DIR/validate-recovery-plan.sh"
    chmod +x "$MOCK_DIR/validate-recovery-plan.sh"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUNNER_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    # agents directory
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

make_claude_mock() {
    local plan_json="$1"
    printf '#!/bin/bash\necho '"'"'%s'"'"'\n' "$plan_json" > "$MOCK_DIR/claude-mock"
    chmod +x "$MOCK_DIR/claude-mock"
}

REPORT_FILE="$BATS_TEST_TMPDIR/docs/reports/orchestration-recoveries.md"

@test "auto-recovery: action=skip writes recovery-sub-agent entry to report" {
    make_claude_mock '{"action":"skip","rationale":"phase already completed","steps":[]}'
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    grep -q "recovery-sub-agent" "$REPORT_FILE"
    grep -q "action=skip" "$REPORT_FILE"
    grep -q "Source: recovery-sub-agent" "$REPORT_FILE"
}

@test "auto-recovery: action=retry writes recovery-sub-agent entry to report" {
    make_claude_mock '{"action":"retry","rationale":"transient failure","steps":[]}'
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    grep -q "recovery-sub-agent" "$REPORT_FILE"
    grep -q "action=retry" "$REPORT_FILE"
    grep -q "transient failure" "$REPORT_FILE"
}

@test "auto-recovery: action=recover writes recovery-sub-agent entry to report" {
    make_claude_mock '{"action":"recover","rationale":"manual step needed","steps":[{"op":"run_command","cmd":"echo fixed"}]}'
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    grep -q "recovery-sub-agent" "$REPORT_FILE"
    grep -q "action=recover" "$REPORT_FILE"
    grep -q "1 step(s)" "$REPORT_FILE"
}

@test "auto-recovery: action=abort does not write entry to report" {
    make_claude_mock '{"action":"abort","rationale":"cannot recover","steps":[]}'
    cd "$BATS_TEST_TMPDIR"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -ne 0 ]
    ! grep -q "recovery-sub-agent" "$REPORT_FILE"
}

@test "auto-recovery: missing report file skips write gracefully" {
    make_claude_mock '{"action":"skip","rationale":"already done","steps":[]}'
    cd "$BATS_TEST_TMPDIR"
    rm -f "$REPORT_FILE"

    run bash "$SCRIPT" code 42 --log "$LOG_FILE"
    [ "$status" -eq 0 ]
    [ ! -f "$REPORT_FILE" ]
}
