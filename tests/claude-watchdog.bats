#!/usr/bin/env bats

# Tests for scripts/claude-watchdog.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/claude-watchdog.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: claude-watchdog.sh"* ]]
}

@test "normal exit 0: output and exit code pass through" {
    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
echo "hello from command"
exit 0
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello from command"* ]]
}

@test "normal exit non-zero: exit code passes through without retry" {
    COUNTER_FILE="$BATS_TEST_TMPDIR/invocation_count"
    echo "0" > "$COUNTER_FILE"

    cat > "$MOCK_DIR/cmd.sh" <<MOCK
#!/bin/bash
count=\$(cat "$COUNTER_FILE")
echo \$((count + 1)) > "$COUNTER_FILE"
echo "error output"
exit 42
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -eq 42 ]
    [[ "$output" == *"error output"* ]]

    # Verify command was invoked exactly once (no retry on normal non-zero exit)
    [ "$(cat "$COUNTER_FILE")" -eq 1 ]
}

@test "watchdog timeout: command with no output is killed after WATCHDOG_TIMEOUT" {
    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
sleep 60
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env WATCHDOG_TIMEOUT=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    # Should be non-zero (killed by watchdog)
    [ "$status" -ne 0 ]
    [[ "$output" == *"watchdog: no output for 2s, killing process"* ]]
}


@test "WATCHDOG_TIMEOUT env var: custom value takes effect" {
    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
sleep 60
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    # With WATCHDOG_TIMEOUT=2, the watchdog should fire quickly
    start_time=$(date +%s)
    run env WATCHDOG_TIMEOUT=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    end_time=$(date +%s)
    elapsed=$((end_time - start_time))

    # Should complete well under 30 seconds (default 2700s would take much longer)
    [ "$elapsed" -lt 30 ]
    [ "$status" -ne 0 ]
}

@test "heartbeat: diagnostic message emitted during silence" {
    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
sleep 60
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env WATCHDOG_TIMEOUT=3 WATCHDOG_HEARTBEAT_INTERVAL=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"watchdog: still waiting"* ]]
}

@test "OUTPUT_FORMAT_JSON=1: process that exits normally completes without false kill" {
    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
sleep 1
echo '{"result":"done"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env OUTPUT_FORMAT_JSON=1 WATCHDOG_TIMEOUT=10 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -eq 0 ]
}

@test "OUTPUT_FORMAT_JSON=1: process that hangs past WATCHDOG_TIMEOUT is killed" {
    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
sleep 60
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env OUTPUT_FORMAT_JSON=1 WATCHDOG_TIMEOUT=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"killing process"* ]]
}

@test "watchdog_kill: event emitted to AUTO_EVENTS_LOG on kill" {
    EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    emit_event_sh="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/emit-event.sh"

    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
sleep 60
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env AUTO_EVENTS_LOG="$EVENTS_LOG" \
      EMIT_ISSUE_NUMBER="42" \
      EMIT_PHASE_NAME="code" \
      WATCHDOG_TIMEOUT=2 \
      bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -ne 0 ]
    [ -f "$EVENTS_LOG" ]
    grep -q '"event":"watchdog_kill"' "$EVENTS_LOG"
}

@test "max_silent_window: event emitted to AUTO_EVENTS_LOG after process completes" {
    EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"

    cat > "$MOCK_DIR/cmd.sh" <<'MOCK'
#!/bin/bash
echo "hello"
exit 0
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env AUTO_EVENTS_LOG="$EVENTS_LOG" \
      EMIT_ISSUE_NUMBER="42" \
      EMIT_PHASE_NAME="code" \
      WATCHDOG_TIMEOUT=10 \
      bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -eq 0 ]
    [ -f "$EVENTS_LOG" ]
    grep -q '"event":"max_silent_window"' "$EVENTS_LOG"
}

@test "no retry: watchdog kills and does not retry" {
    COUNTER_FILE="$BATS_TEST_TMPDIR/invocation_count"
    echo "0" > "$COUNTER_FILE"

    cat > "$MOCK_DIR/cmd.sh" <<MOCK
#!/bin/bash
count=\$(cat "$COUNTER_FILE")
count=\$((count + 1))
echo \$count > "$COUNTER_FILE"
# Hang to trigger watchdog kill
sleep 60
MOCK
    chmod +x "$MOCK_DIR/cmd.sh"

    run env WATCHDOG_TIMEOUT=2 bash "$SCRIPT" bash "$MOCK_DIR/cmd.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"retrying disabled"* ]]

    # Verify command was invoked exactly once (no retry)
    [ "$(cat "$COUNTER_FILE")" -eq 1 ]
}
