#!/usr/bin/env bats

# Tests for scripts/emit-verify-event.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/emit-verify-event.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Mock flock: no-op to avoid macOS incompatibility
    cat > "$MOCK_DIR/flock" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"

    WORKDIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORKDIR"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "--persist-session writes the issue-scoped pointer file" {
    run bash -c "cd \"$WORKDIR\" && bash \"$SCRIPT\" --persist-session sid-abc 1075 && cat .tmp/auto-session-issue-1075"
    [ "$status" -eq 0 ]
    [[ "$output" == "sid-abc" ]]
}

@test "--persist-session with empty sid deletes the pointer file" {
    mkdir -p "$WORKDIR/.tmp"
    echo "stale-session" > "$WORKDIR/.tmp/auto-session-issue-1075"
    run bash -c "cd \"$WORKDIR\" && bash \"$SCRIPT\" --persist-session '' 1075 && { test -f .tmp/auto-session-issue-1075 && echo EXISTS || echo GONE; }"
    [ "$status" -eq 0 ]
    [[ "$output" == "GONE" ]]
}

@test "standard mode is a no-op when AUTO_EVENTS_LOG is unset" {
    run bash -c "cd \"$WORKDIR\" && unset AUTO_EVENTS_LOG AUTO_SESSION_ID && bash \"$SCRIPT\" 42 phase_start phase=verify"
    [ "$status" -eq 0 ]
    [ ! -f "$WORKDIR/.tmp/auto-events.jsonl" ]
}

@test "standard mode emits when AUTO_EVENTS_LOG is set" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && bash \"$SCRIPT\" 42 phase_start phase=verify"
    [ "$status" -eq 0 ]
    run jq -r '.event' "$WORKDIR/events.jsonl"
    [ "$status" -eq 0 ]
    [[ "$output" == "phase_start" ]]
    run jq -r '.phase' "$WORKDIR/events.jsonl"
    [[ "$output" == "verify" ]]
    run jq -r '.issue' "$WORKDIR/events.jsonl"
    [[ "$output" == "42" ]]
}

@test "--require-session-id is a no-op when AUTO_SESSION_ID is unset" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && unset AUTO_SESSION_ID && bash \"$SCRIPT\" 42 verify_reopen_cycle --require-session-id iteration=1 reopen_reason=pre_merge_ac_fail"
    [ "$status" -eq 0 ]
    [ ! -f "$WORKDIR/events.jsonl" ]
}

@test "--require-session-id emits when both AUTO_EVENTS_LOG and AUTO_SESSION_ID are set" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" AUTO_SESSION_ID=sid-1 && bash \"$SCRIPT\" 42 verify_reopen_cycle --require-session-id iteration=1 reopen_reason=pre_merge_ac_fail"
    [ "$status" -eq 0 ]
    run jq -r '.event' "$WORKDIR/events.jsonl"
    [[ "$output" == "verify_reopen_cycle" ]]
    run jq -r '.iteration' "$WORKDIR/events.jsonl"
    [[ "$output" == "1" ]]
    run jq -r '.reopen_reason' "$WORKDIR/events.jsonl"
    [[ "$output" == "pre_merge_ac_fail" ]]
}

@test "--unconditional emits even when AUTO_EVENTS_LOG is unset (defaults to .tmp/auto-events.jsonl)" {
    run bash -c "cd \"$WORKDIR\" && unset AUTO_EVENTS_LOG AUTO_SESSION_ID && bash \"$SCRIPT\" 42 recoveries_threshold_fire --unconditional symptom=foo count=3 issue_number=999"
    [ "$status" -eq 0 ]
    [ -f "$WORKDIR/.tmp/auto-events.jsonl" ]
    run jq -r '.event' "$WORKDIR/.tmp/auto-events.jsonl"
    [[ "$output" == "recoveries_threshold_fire" ]]
    run jq -r '.symptom' "$WORKDIR/.tmp/auto-events.jsonl"
    [[ "$output" == "foo" ]]
}

@test "key=value arguments are reflected in the emitted JSON (verify_executability shape)" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && bash \"$SCRIPT\" 42 verify_executability ac_index=3 executable=true reason="
    [ "$status" -eq 0 ]
    run jq -r '.ac_index' "$WORKDIR/events.jsonl"
    [[ "$output" == "3" ]]
    run jq -r '.executable' "$WORKDIR/events.jsonl"
    [[ "$output" == "true" ]]
    run jq -r '.reason' "$WORKDIR/events.jsonl"
    [[ "$output" == "" ]]
}

@test "usage error exits 1 when the event name is missing" {
    run bash -c "cd \"$WORKDIR\" && bash \"$SCRIPT\" 42"
    [ "$status" -eq 1 ]
}

@test "usage error exits 1 when the issue number is missing" {
    run bash -c "cd \"$WORKDIR\" && bash \"$SCRIPT\""
    [ "$status" -eq 1 ]
}

@test "usage error exits 1 when --persist-session is missing the issue argument" {
    run bash -c "cd \"$WORKDIR\" && bash \"$SCRIPT\" --persist-session sid-abc"
    [ "$status" -eq 1 ]
}
