#!/usr/bin/env bats

# Tests for scripts/detect-external-kill.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/detect-external-kill.sh"

setup() {
    LOG_FILE="$BATS_TEST_TMPDIR/wrapper.log"
    EVENTS_FILE="$BATS_TEST_TMPDIR/auto-events.jsonl"
    : > "$LOG_FILE"
    : > "$EVENTS_FILE"
}

@test "error: missing required arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "error: unknown argument" {
    run bash "$SCRIPT" --bogus foo
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown argument"* ]]
}

@test "error: log file not found" {
    run bash "$SCRIPT" --log "/nonexistent/path.log" --events "$EVENTS_FILE" --exit-code 137 --issue 1014 --phase code-pr
    [ "$status" -eq 2 ]
    [[ "$output" == *"log file not found"* ]]
}

@test "exit code 137 matches unconditionally" {
    echo "some log content, no Exit code trailer" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --events "$EVENTS_FILE" --exit-code 137 --issue 1014 --phase code-pr
    [ "$status" -eq 0 ]
    [ "$output" = "external-kill" ]
}

@test "exit code 143 with both markers missing matches" {
    echo "watchdog: still waiting (json mode), silent for 480s" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --events "$EVENTS_FILE" --exit-code 143 --issue 1014 --phase code-pr
    [ "$status" -eq 0 ]
    [ "$output" = "external-kill" ]
}

@test "unknown exit code with both markers missing matches" {
    echo "watchdog: still waiting (json mode), silent for 900s" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --events "$EVENTS_FILE" --exit-code unknown --issue 1014 --phase code-pr
    [ "$status" -eq 0 ]
    [ "$output" = "external-kill" ]
}

@test "exit code 143 with Exit code trailer present does not match" {
    echo "Exit code: 143" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --events "$EVENTS_FILE" --exit-code 143 --issue 1014 --phase code-pr
    [ "$status" -eq 1 ]
    [ "$output" = "no-match" ]
}

@test "unknown exit code with matching wrapper_exit event does not match" {
    echo "watchdog: still waiting (json mode)" > "$LOG_FILE"
    echo '{"ts":"2026-07-15T00:00:00Z","issue":1014,"event":"wrapper_exit","session_id":"abc","phase":"code-pr","exit_code":"143"}' > "$EVENTS_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --events "$EVENTS_FILE" --exit-code unknown --issue 1014 --phase code-pr
    [ "$status" -eq 1 ]
    [ "$output" = "no-match" ]
}

@test "unknown exit code with wrapper_exit event for a different phase still matches" {
    echo "watchdog: still waiting (json mode)" > "$LOG_FILE"
    echo '{"ts":"2026-07-15T00:00:00Z","issue":1014,"event":"wrapper_exit","session_id":"abc","phase":"review","exit_code":"143"}' > "$EVENTS_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --events "$EVENTS_FILE" --exit-code unknown --issue 1014 --phase code-pr
    [ "$status" -eq 0 ]
    [ "$output" = "external-kill" ]
}

@test "unknown exit code with wrapper_exit event for a different issue still matches" {
    echo "watchdog: still waiting (json mode)" > "$LOG_FILE"
    echo '{"ts":"2026-07-15T00:00:00Z","issue":1006,"event":"wrapper_exit","session_id":"abc","phase":"code-pr","exit_code":"143"}' > "$EVENTS_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --events "$EVENTS_FILE" --exit-code unknown --issue 1014 --phase code-pr
    [ "$status" -eq 0 ]
    [ "$output" = "external-kill" ]
}

@test "missing events file falls back to external-kill when log trailer absent" {
    echo "watchdog: still waiting (json mode)" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --events "$BATS_TEST_TMPDIR/nonexistent-events.jsonl" --exit-code 143 --issue 1014 --phase code-pr
    [ "$status" -eq 0 ]
    [ "$output" = "external-kill" ]
}

@test "other exit codes do not match" {
    echo "some other failure" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --events "$EVENTS_FILE" --exit-code 1 --issue 1014 --phase code-pr
    [ "$status" -eq 1 ]
    [ "$output" = "no-match" ]
}
