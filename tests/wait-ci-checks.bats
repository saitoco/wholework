#!/usr/bin/env bats

# Tests for wait-ci-checks.sh
# Mocks external commands (gh, timeout) by placing them at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/wait-ci-checks.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    TIMEOUT_CALL_LOG="$BATS_TEST_TMPDIR/timeout_calls.log"
    export TIMEOUT_CALL_LOG

    # Default: timeout handles --kill-after=N prefix, passes through to gh
    cat > "$MOCK_DIR/timeout" <<'MOCK'
#!/bin/bash
if [[ "$1" == --kill-after* ]]; then shift; fi
shift  # Remove the timeout duration argument
echo "timeout called: $@" >> "$TIMEOUT_CALL_LOG"
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/timeout"

    # Default: gh pr checks returns SUCCESS JSON
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
    echo '[{"name":"Run bats tests","state":"SUCCESS"}]'
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    # sleep mock: no-op to keep tests fast
    cat > "$MOCK_DIR/sleep" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/sleep"

    # jq wrapper: delegate to real jq (needed for restricted-PATH tests)
    real_jq="$(type -P jq 2>/dev/null || echo "")"
    if [[ -n "$real_jq" ]]; then
        cat > "$MOCK_DIR/jq" <<MOCK
#!/bin/bash
exec "$real_jq" "\$@"
MOCK
        chmod +x "$MOCK_DIR/jq"
    fi

    # date wrapper: delegate to real date (needed for restricted-PATH tests)
    real_date="$(type -P date 2>/dev/null || echo "")"
    if [[ -n "$real_date" ]]; then
        cat > "$MOCK_DIR/date" <<MOCK
#!/bin/bash
exec "$real_date" "\$@"
MOCK
        chmod +x "$MOCK_DIR/date"
    fi
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no PR number argument" {
    run bash "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: wait-ci-checks.sh <pr-number>"* ]]
}

@test "success: outputs waiting and complete messages" {
    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [[ "$output" == *"Waiting for CI checks on PR #88"* ]]
    [[ "$output" == *"CI check wait complete for PR #88"* ]]
}

@test "success: passes PR number to timeout and gh pr checks" {
    run bash "$SCRIPT" 99
    [ "$status" -eq 0 ]
    grep -q "pr checks 99" "$TIMEOUT_CALL_LOG"
    grep -q "\-\-json" "$TIMEOUT_CALL_LOG"
}

@test "success: uses WHOLEWORK_CI_TIMEOUT_SEC when set" {
    export WHOLEWORK_CI_TIMEOUT_SEC=42
    run bash "$SCRIPT" 77
    [ "$status" -eq 0 ]
    [[ "$output" == *"timeout: 42s"* ]]
}

@test "success: defaults to 1200 when WHOLEWORK_CI_TIMEOUT_SEC is not set" {
    unset WHOLEWORK_CI_TIMEOUT_SEC
    run bash "$SCRIPT" 55
    [ "$status" -eq 0 ]
    [[ "$output" == *"timeout: 1200s"* ]]
}

@test "success: continues even when timeout exits non-zero (timeout occurred)" {
    # Per-poll timeout exits 124; outer TIMEOUT_SEC elapses and loop breaks
    cat > "$MOCK_DIR/timeout" <<'MOCK'
#!/bin/bash
exit 124
MOCK
    chmod +x "$MOCK_DIR/timeout"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
    echo '[{"name":"Run bats tests","state":"IN_PROGRESS"}]'
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    export WHOLEWORK_CI_TIMEOUT_SEC=2
    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI check wait complete for PR #88"* ]]
}

@test "success: continues even when gh pr checks fails" {
    # gh exits 1 but prints [] so _in_progress=0 and loop breaks immediately
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
    echo '[]'
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI check wait complete for PR #88"* ]]
}

@test "success: uses gtimeout when timeout is not available" {
    GTIMEOUT_CALL_LOG="$BATS_TEST_TMPDIR/gtimeout_calls.log"
    export GTIMEOUT_CALL_LOG

    rm -f "$MOCK_DIR/timeout"
    cat > "$MOCK_DIR/gtimeout" <<'MOCK'
#!/bin/bash
shift
echo "gtimeout called: $@" >> "$GTIMEOUT_CALL_LOG"
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/gtimeout"

    run env PATH="$MOCK_DIR" /bin/bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    grep -q "pr checks 88" "$GTIMEOUT_CALL_LOG"
    [[ "$output" == *"CI check wait complete for PR #88"* ]]
}

@test "success: runs gh directly when neither timeout nor gtimeout is available" {
    rm -f "$MOCK_DIR/timeout"

    run env PATH="$MOCK_DIR" /bin/bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI check wait complete for PR #88"* ]]
}

@test "ci_wait: event emitted to AUTO_EVENTS_LOG when AUTO_EVENTS_LOG is set" {
    EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    EMIT_DIR="$BATS_TEST_TMPDIR/emit-script-dir"
    mkdir -p "$EMIT_DIR"
    emit_event_src="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/emit-event.sh"
    cp "$emit_event_src" "$EMIT_DIR/emit-event.sh"

    run env AUTO_EVENTS_LOG="$EVENTS_LOG" \
      EMIT_ISSUE_NUMBER="88" \
      EMIT_PHASE_NAME="review" \
      WHOLEWORK_SCRIPT_DIR="$EMIT_DIR" \
      PATH="$MOCK_DIR:$PATH" \
      bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [ -f "$EVENTS_LOG" ]
    grep -q '"event":"ci_wait"' "$EVENTS_LOG"
    grep -q '"phase":"review"' "$EVENTS_LOG"
}

@test "ci_wait: event emitted with merge phase when EMIT_PHASE_NAME is merge" {
    EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events-merge.jsonl"
    EMIT_DIR="$BATS_TEST_TMPDIR/emit-script-dir-merge"
    mkdir -p "$EMIT_DIR"
    emit_event_src="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/emit-event.sh"
    cp "$emit_event_src" "$EMIT_DIR/emit-event.sh"

    run env AUTO_EVENTS_LOG="$EVENTS_LOG" \
      EMIT_ISSUE_NUMBER="101" \
      EMIT_PHASE_NAME="merge" \
      WHOLEWORK_SCRIPT_DIR="$EMIT_DIR" \
      PATH="$MOCK_DIR:$PATH" \
      bash "$SCRIPT" 101
    [ "$status" -eq 0 ]
    [ -f "$EVENTS_LOG" ]
    grep -q '"event":"ci_wait"' "$EVENTS_LOG"
    grep -q '"phase":"merge"' "$EVENTS_LOG"
}

@test "ci_wait: no event emitted when AUTO_EVENTS_LOG is not set" {
    EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"

    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [ ! -f "$EVENTS_LOG" ]
}

@test "success: does not pass --required flag to gh pr checks" {
    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "gh $@" >> "$GH_CALL_LOG"
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
    echo '[{"name":"Run bats tests","state":"SUCCESS"}]'
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    grep -q "pr checks 88" "$GH_CALL_LOG"
    ! grep -q "\-\-required" "$GH_CALL_LOG"
}

@test "ci_wait: event JSON is parseable when gh output has no pass/success matches (regression #678)" {
    EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events-nomatch.jsonl"
    EMIT_DIR="$BATS_TEST_TMPDIR/emit-nomatch"
    mkdir -p "$EMIT_DIR"
    emit_event_src="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/emit-event.sh"
    cp "$emit_event_src" "$EMIT_DIR/emit-event.sh"

    # gh outputs FAILURE JSON: _in_progress=0 so loop breaks; checks_passed=0
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "checks" ]]; then
    echo '[{"name":"c1","state":"FAILURE"}]'
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run env AUTO_EVENTS_LOG="$EVENTS_LOG" \
      EMIT_ISSUE_NUMBER="88" \
      EMIT_PHASE_NAME="review" \
      WHOLEWORK_SCRIPT_DIR="$EMIT_DIR" \
      PATH="$MOCK_DIR:$PATH" \
      bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [ -f "$EVENTS_LOG" ]
    # Verify the JSONL line is parseable (no literal newlines embedded in values)
    run jq . "$EVENTS_LOG"
    [ "$status" -eq 0 ]
    # checks_passed must be a clean integer string, not "0\n0"
    run jq -r '.checks_passed' "$EVENTS_LOG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
}
