#!/usr/bin/env bats

# Tests for filter-session-verified-issues.sh
# Covers: (a) exclusion of Issues with a phase=verify phase_start/phase_complete
# event recorded for the current session, (b) negative case — Issues without
# such an event are not excluded, (c) fail-open passthrough when the session
# id or the events log cannot be resolved.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/filter-session-verified-issues.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export AUTO_SESSION_ID="session-A"
}

@test "excludes issues with a phase=verify event recorded for the session" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"issue":984,"event":"phase_start","session_id":"session-A","phase":"verify"}
{"issue":984,"event":"phase_complete","session_id":"session-A","phase":"verify"}
{"issue":995,"event":"phase_start","session_id":"session-A","phase":"verify"}
FIXTURE_EOF

    run bash -c "printf '984\n995\n' | \"$SCRIPT\""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "negative case: issues without a session verify event are not excluded" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"issue":984,"event":"phase_start","session_id":"session-A","phase":"verify"}
{"issue":1009,"event":"phase_start","session_id":"other-session","phase":"verify"}
{"issue":1035,"event":"phase_start","session_id":"session-A","phase":"code-pr"}
FIXTURE_EOF

    run bash -c "printf '984\n1009\n1035\n1037\n' | \"$SCRIPT\""
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -qx "984"
    echo "$output" | grep -qx "1009"
    echo "$output" | grep -qx "1035"
    echo "$output" | grep -qx "1037"
}

@test "fail-open: candidates pass through unchanged when session id cannot be resolved" {
    unset AUTO_SESSION_ID
    run bash -c "printf '984\n995\n' | \"$SCRIPT\""
    [ "$status" -eq 0 ]
    echo "$output" | grep -qx "984"
    echo "$output" | grep -qx "995"
}

@test "fail-open: candidates pass through unchanged when events log does not exist" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/does-not-exist.jsonl"
    run bash -c "printf '984\n995\n' | \"$SCRIPT\""
    [ "$status" -eq 0 ]
    echo "$output" | grep -qx "984"
    echo "$output" | grep -qx "995"
}
