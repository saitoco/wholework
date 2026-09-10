#!/usr/bin/env bats

# Tests for scripts/emit-skill-event.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/emit-skill-event.sh"

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
    [ "$status" -eq 0 ] || false
    [ "$output" = "sid-abc" ] || false
}

@test "--persist-session with empty sid deletes the pointer file" {
    mkdir -p "$WORKDIR/.tmp"
    echo "stale-session" > "$WORKDIR/.tmp/auto-session-issue-1075"
    run bash -c "cd \"$WORKDIR\" && bash \"$SCRIPT\" --persist-session '' 1075 && { test -f .tmp/auto-session-issue-1075 && echo EXISTS || echo GONE; }"
    [ "$status" -eq 0 ] || false
    [ "$output" = "GONE" ] || false
}

@test "standard mode is a no-op when AUTO_EVENTS_LOG is unset" {
    run bash -c "cd \"$WORKDIR\" && unset AUTO_EVENTS_LOG AUTO_SESSION_ID && bash \"$SCRIPT\" 42 phase_start phase=verify"
    [ "$status" -eq 0 ] || false
    [ ! -f "$WORKDIR/.tmp/auto-events.jsonl" ] || false
}

@test "standard mode emits when AUTO_EVENTS_LOG is set" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && bash \"$SCRIPT\" 42 phase_start phase=verify"
    [ "$status" -eq 0 ] || false
    run jq -r '.event' "$WORKDIR/events.jsonl"
    [ "$status" -eq 0 ] || false
    [ "$output" = "phase_start" ] || false
    run jq -r '.phase' "$WORKDIR/events.jsonl"
    [ "$output" = "verify" ] || false
    run jq -r '.issue' "$WORKDIR/events.jsonl"
    [ "$output" = "42" ] || false
}

@test "--require-session-id is a no-op when AUTO_SESSION_ID is unset" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && unset AUTO_SESSION_ID && bash \"$SCRIPT\" 42 verify_reopen_cycle --require-session-id iteration=1 reopen_reason=pre_merge_ac_fail"
    [ "$status" -eq 0 ] || false
    [ ! -f "$WORKDIR/events.jsonl" ] || false
}

@test "--require-session-id emits when both AUTO_EVENTS_LOG and AUTO_SESSION_ID are set" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" AUTO_SESSION_ID=sid-1 && bash \"$SCRIPT\" 42 verify_reopen_cycle --require-session-id iteration=1 reopen_reason=pre_merge_ac_fail"
    [ "$status" -eq 0 ] || false
    run jq -r '.event' "$WORKDIR/events.jsonl"
    [ "$output" = "verify_reopen_cycle" ] || false
    run jq -r '.iteration' "$WORKDIR/events.jsonl"
    [ "$output" = "1" ] || false
    run jq -r '.reopen_reason' "$WORKDIR/events.jsonl"
    [ "$output" = "pre_merge_ac_fail" ] || false
}

@test "--unconditional emits even when AUTO_EVENTS_LOG is unset (defaults to .tmp/auto-events.jsonl)" {
    run bash -c "cd \"$WORKDIR\" && unset AUTO_EVENTS_LOG AUTO_SESSION_ID && bash \"$SCRIPT\" 42 recoveries_threshold_fire --unconditional symptom=foo count=3 issue_number=999"
    [ "$status" -eq 0 ] || false
    [ -f "$WORKDIR/.tmp/auto-events.jsonl" ] || false
    run jq -r '.event' "$WORKDIR/.tmp/auto-events.jsonl"
    [ "$output" = "recoveries_threshold_fire" ] || false
    run jq -r '.symptom' "$WORKDIR/.tmp/auto-events.jsonl"
    [ "$output" = "foo" ] || false
}

@test "key=value arguments are reflected in the emitted JSON (verify_executability shape)" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && bash \"$SCRIPT\" 42 verify_executability ac_index=3 executable=true reason="
    [ "$status" -eq 0 ] || false
    run jq -r '.ac_index' "$WORKDIR/events.jsonl"
    [ "$output" = "3" ] || false
    run jq -r '.executable' "$WORKDIR/events.jsonl"
    [ "$output" = "true" ] || false
    run jq -r '.reason' "$WORKDIR/events.jsonl"
    [ "$output" = "" ] || false
}

@test "usage error exits 1 when the event name is missing" {
    run bash -c "cd \"$WORKDIR\" && bash \"$SCRIPT\" 42"
    [ "$status" -eq 1 ] || false
}

@test "usage error exits 1 when the issue number is missing" {
    run bash -c "cd \"$WORKDIR\" && bash \"$SCRIPT\""
    [ "$status" -eq 1 ] || false
}

@test "usage error exits 1 when --persist-session is missing the issue argument" {
    run bash -c "cd \"$WORKDIR\" && bash \"$SCRIPT\" --persist-session sid-abc"
    [ "$status" -eq 1 ] || false
}

@test "--emit-issue overrides the emitted issue field while positional issue still resolves the session pointer" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && bash \"$SCRIPT\" 42 opportunistic_verify_result --emit-issue 99 skill=/spec result=PASS"
    [ "$status" -eq 0 ] || false
    run jq -r '.issue' "$WORKDIR/events.jsonl"
    [ "$output" = "99" ] || false
    run jq -r '.skill' "$WORKDIR/events.jsonl"
    [ "$output" = "/spec" ] || false
}

@test "--emit-issue with a non-numeric value warns and falls back to issue=0" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && bash \"$SCRIPT\" 42 opportunistic_verify_result --emit-issue notanumber skill=/spec 2>&1 1>/dev/null"
    [ "$status" -eq 0 ] || false
    [[ "$output" == *"Warning:"*"--emit-issue"* ]] || false
    run jq -r '.issue' "$WORKDIR/events.jsonl"
    [ "$output" = "0" ] || false
}

@test "non-numeric positional issue falls back to issue=0 and still emits valid JSON" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && bash \"$SCRIPT\" batch-abc retro_proposal_classified tier=1"
    [ "$status" -eq 0 ] || false
    run jq -r '.issue' "$WORKDIR/events.jsonl"
    [ "$output" = "0" ] || false
    run jq -r '.event' "$WORKDIR/events.jsonl"
    [ "$output" = "retro_proposal_classified" ] || false
}

@test "--session-id sets session_id in the emitted JSON without a pointer file" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && bash \"$SCRIPT\" batch-xyz retro_proposal_classified --session-id sid-literal tier=1"
    [ "$status" -eq 0 ] || false
    run jq -r '.session_id' "$WORKDIR/events.jsonl"
    [ "$output" = "sid-literal" ] || false
}

@test "flag order is unordered: --emit-issue and --require-session-id together" {
    run bash -c "cd \"$WORKDIR\" && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" AUTO_SESSION_ID=sid-1 && bash \"$SCRIPT\" 42 opportunistic_verify_result --emit-issue 7 --require-session-id skill=/code"
    [ "$status" -eq 0 ] || false
    run jq -r '.issue' "$WORKDIR/events.jsonl"
    [ "$output" = "7" ] || false
    run bash -c "cd \"$WORKDIR\" && rm -f events.jsonl && export AUTO_EVENTS_LOG=\"\$PWD/events.jsonl\" && unset AUTO_SESSION_ID && bash \"$SCRIPT\" 42 opportunistic_verify_result --require-session-id --emit-issue 7 skill=/code"
    [ "$status" -eq 0 ] || false
    [ ! -f "$WORKDIR/events.jsonl" ] || false
}

@test "missing sibling emit-event.sh exits 1 with an error on stderr" {
    EMPTY_DIR="$BATS_TEST_TMPDIR/empty-script-dir"
    mkdir -p "$EMPTY_DIR"
    run bash -c "cd \"$WORKDIR\" && export WHOLEWORK_SCRIPT_DIR=\"$EMPTY_DIR\" && bash \"$SCRIPT\" 42 phase_start phase=verify"
    [ "$status" -eq 1 ] || false
    [[ "$output" == *"Error:"*"emit-event.sh not found"* ]] || false
}
