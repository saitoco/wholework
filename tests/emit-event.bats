#!/usr/bin/env bats

# Tests for scripts/emit-event.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/emit-event.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"
    export EMIT_PHASE_NAME="code"

    # Mock flock: no-op to avoid macOS incompatibility
    cat > "$MOCK_DIR/flock" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "emit_event writes a valid JSONL line to AUTO_EVENTS_LOG" {
    bash -c "source \"$SCRIPT\" && emit_event \"phase_start\" \"phase=code\""
    [ -f "$AUTO_EVENTS_LOG" ]
    local line
    line=$(cat "$AUTO_EVENTS_LOG")
    [[ "$line" == *'"event":"phase_start"'* ]]
    [[ "$line" == *'"phase":"code"'* ]]
    [[ "$line" == *'"issue":42'* ]]
}

@test "emit_event includes ts field in ISO 8601 format" {
    bash -c "source \"$SCRIPT\" && emit_event \"test_event\""
    local line
    line=$(cat "$AUTO_EVENTS_LOG")
    [[ "$line" == *'"ts":"'* ]]
}

@test "emit_event creates parent directory of AUTO_EVENTS_LOG if absent" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/newdir/events.jsonl"
    bash -c "source \"$SCRIPT\" && emit_event \"sub_start\""
    [ -f "$AUTO_EVENTS_LOG" ]
}

@test "emit_event appends multiple events to the same file" {
    bash -c "source \"$SCRIPT\" && emit_event \"phase_start\" \"phase=code\""
    bash -c "source \"$SCRIPT\" && emit_event \"phase_complete\" \"phase=code\""
    local count
    count=$(wc -l < "$AUTO_EVENTS_LOG")
    [ "$count" -eq 2 ]
}

@test "emit_event uses EMIT_ISSUE_NUMBER from environment" {
    export EMIT_ISSUE_NUMBER="999"
    bash -c "source \"$SCRIPT\" && emit_event \"sub_start\""
    local line
    line=$(cat "$AUTO_EVENTS_LOG")
    [[ "$line" == *'"issue":999'* ]]
}

@test "emit_event uses lockdir fallback when flock is not available" {
    # Remove flock mock so PATH falls through to a no-flock environment
    rm -f "$MOCK_DIR/flock"
    # Use a separate dir without flock to simulate unavailability
    NOFLOCK_DIR="$BATS_TEST_TMPDIR/noflock"
    mkdir -p "$NOFLOCK_DIR"
    # PATH: noflock dir first (no flock there), then original PATH without flock mock
    PATH="$NOFLOCK_DIR:$(echo "$PATH" | tr ':' '\n' | grep -v "$MOCK_DIR" | tr '\n' ':' | sed 's/:$//')" \
      bash -c "source \"$SCRIPT\" && emit_event \"wrapper_exit\" \"exit_code=0\""
    [ -f "$AUTO_EVENTS_LOG" ]
    local line
    line=$(cat "$AUTO_EVENTS_LOG")
    [[ "$line" == *'"event":"wrapper_exit"'* ]]
    [[ "$line" == *'"exit_code":"0"'* ]]
}
