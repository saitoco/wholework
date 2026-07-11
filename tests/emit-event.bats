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

@test "emit_event sanitizes newline in value to produce parseable JSON (regression #678)" {
    export TEST_VAL=$'0\n0'
    bash -c "source \"$SCRIPT\" && emit_event \"ci_wait\" \"checks_failed=\${TEST_VAL}\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    run jq -r '.checks_failed' "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == "00" ]]
}

@test "emit_event sanitizes tab in value" {
    export TEST_VAL=$'value\ttab'
    bash -c "source \"$SCRIPT\" && emit_event \"test_event\" \"key=\${TEST_VAL}\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    run jq -r '.key' "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == "value tab" ]]
}

@test "emit_event sanitizes backslash in value" {
    export TEST_VAL='value\backslash'
    bash -c "source \"$SCRIPT\" && emit_event \"test_event\" \"key=\${TEST_VAL}\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    run jq -r '.key' "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == 'value\backslash' ]]
}

@test "emit_event sanitizes double-quote in value" {
    export TEST_VAL='value"quote'
    bash -c "source \"$SCRIPT\" && emit_event \"test_event\" \"key=\${TEST_VAL}\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    run jq -r '.key' "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == 'value"quote' ]]
}

@test "emit_event sanitizes combined control characters in value (regression #678)" {
    export TEST_VAL=$'line1\nline2\ttab\\end"quote'
    bash -c "source \"$SCRIPT\" && emit_event \"test_event\" \"key=\${TEST_VAL}\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
}

@test "emit_event writes phase=verify phase_start with correct JSON shape" {
    bash -c "source \"$SCRIPT\" && emit_event \"phase_start\" \"phase=verify\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    local line
    line=$(cat "$AUTO_EVENTS_LOG")
    [[ "$line" == *'"event":"phase_start"'* ]]
    [[ "$line" == *'"phase":"verify"'* ]]
    [[ "$line" == *'"issue":42'* ]]
}

@test "emit_event writes phase=verify phase_complete with correct JSON shape" {
    bash -c "source \"$SCRIPT\" && emit_event \"phase_complete\" \"phase=verify\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    local line
    line=$(cat "$AUTO_EVENTS_LOG")
    [[ "$line" == *'"event":"phase_complete"'* ]]
    [[ "$line" == *'"phase":"verify"'* ]]
    [[ "$line" == *'"issue":42'* ]]
}

@test "emit_event writes verify_user_confirm with ac_index and response fields" {
    bash -c "source \"$SCRIPT\" && emit_event \"verify_user_confirm\" \"ac_index=2\" \"response=Claude Execute\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    run jq -r '.ac_index' "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == "2" ]]
    run jq -r '.response' "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == "Claude Execute" ]]
}

@test "emit_event sourced under zsh parses without error (regression #891)" {
    command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
    run zsh -c "source \"$SCRIPT\" && emit_event \"zsh_compat\" \"phase=code\""
    [ "$status" -eq 0 ]
    [ -f "$AUTO_EVENTS_LOG" ]
    local line
    line=$(cat "$AUTO_EVENTS_LOG")
    [[ "$line" == *'"event":"zsh_compat"'* ]]
    [[ "$line" == *'"phase":"code"'* ]]
}

@test "emit_event includes pr field when EMIT_PR_NUMBER is set (Issue #987)" {
    export EMIT_PR_NUMBER="1001"
    bash -c "source \"$SCRIPT\" && emit_event \"phase_start\" \"phase=review\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    run jq -r '.pr' "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == "1001" ]]
    run jq -r '.issue' "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == "42" ]]
}

@test "emit_event omits pr field when EMIT_PR_NUMBER is unset (Issue #987)" {
    unset EMIT_PR_NUMBER
    bash -c "source \"$SCRIPT\" && emit_event \"phase_start\" \"phase=code-pr\""
    run jq . "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    run jq -r 'has("pr")' "$AUTO_EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" == "false" ]]
}

@test "restore_auto_session_pointer restores AUTO_SESSION_ID/AUTO_EVENTS_LOG from auto-session-current (Issue #902)" {
    mkdir -p "$BATS_TEST_TMPDIR/work1/.tmp"
    echo "test-session-123" > "$BATS_TEST_TMPDIR/work1/.tmp/auto-session-current"
    run bash -c "cd \"$BATS_TEST_TMPDIR/work1\" && unset AUTO_EVENTS_LOG AUTO_SESSION_ID && source \"$SCRIPT\" && restore_auto_session_pointer && echo \"SID=[\$AUTO_SESSION_ID] LOG=[\$AUTO_EVENTS_LOG]\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"SID=[test-session-123]"* ]]
    [[ "$output" == *"LOG=[.tmp/auto-events.jsonl]"* ]]
}

@test "restore_auto_session_pointer no-ops when no pointer file exists (Issue #902)" {
    mkdir -p "$BATS_TEST_TMPDIR/work2/.tmp"
    run bash -c "cd \"$BATS_TEST_TMPDIR/work2\" && unset AUTO_EVENTS_LOG AUTO_SESSION_ID && source \"$SCRIPT\" && restore_auto_session_pointer && echo \"LOG=[\$AUTO_EVENTS_LOG]\""
    [ "$status" -eq 0 ]
    [[ "$output" == "LOG=[]" ]]
}

@test "restore_auto_session_pointer does not overwrite an already-set AUTO_EVENTS_LOG (Issue #902)" {
    mkdir -p "$BATS_TEST_TMPDIR/work3/.tmp"
    echo "other-session" > "$BATS_TEST_TMPDIR/work3/.tmp/auto-session-current"
    run bash -c "cd \"$BATS_TEST_TMPDIR/work3\" && unset AUTO_SESSION_ID && export AUTO_EVENTS_LOG=/preset/path.jsonl && source \"$SCRIPT\" && restore_auto_session_pointer && echo \"LOG=[\$AUTO_EVENTS_LOG] SID=[\$AUTO_SESSION_ID]\""
    [ "$status" -eq 0 ]
    [[ "$output" == "LOG=[/preset/path.jsonl] SID=[]" ]]
}
