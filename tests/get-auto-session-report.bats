#!/usr/bin/env bats

# Direct unit tests for scripts/get-auto-session-report.sh
# Covers: session_id filter, --since list mode, empty jsonl, --narrative-draft insertion.
# All tests use --no-github for hermetic execution.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-auto-session-report.sh"

setup() {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export OUTPUT_PATH="$BATS_TEST_TMPDIR/report.md"
}

@test "session_id filter: only specified session events appear in report" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-A","size":"S"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"phase_start","session_id":"session-A","phase":"code-patch"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"phase_complete","session_id":"session-A","phase":"code-patch"}
{"ts":"2026-06-14T10:05:01Z","issue":100,"event":"sub_complete","session_id":"session-A","exit_code":"0"}
{"ts":"2026-06-14T11:00:00Z","issue":200,"event":"sub_start","session_id":"session-B","size":"M"}
{"ts":"2026-06-14T11:01:00Z","issue":200,"event":"sub_complete","session_id":"session-B","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-A" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]
    grep -q "Issues processed | 1" "$OUTPUT_PATH"
    grep -q "#100" "$OUTPUT_PATH"
    ! grep -q "| #200 |" "$OUTPUT_PATH"
}

@test "--since list mode: lists distinct session_ids from event log" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-X","size":"S"}
{"ts":"2026-06-14T11:00:00Z","issue":200,"event":"sub_start","session_id":"session-Y","size":"M"}
FIXTURE_EOF

    run bash "$SCRIPT" --since 2020-01-01
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "session-X"
    echo "$output" | grep -q "session-Y"
}

@test "empty jsonl: graceful degrade when log file is empty" {
    touch "$AUTO_EVENTS_LOG"

    run bash "$SCRIPT" "arbitrary-session-id" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]
    grep -q "Issues processed | 0" "$OUTPUT_PATH"
}

@test "--narrative-draft: draft content inserted into report" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-draft","size":"S"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"sub_complete","session_id":"session-draft","exit_code":"0"}
FIXTURE_EOF

    DRAFT_PATH="$BATS_TEST_TMPDIR/narrative-draft.md"
    cat > "$DRAFT_PATH" << 'DRAFT_EOF'
### What worked
Parallel execution completed without conflict.
DRAFT_EOF

    run bash "$SCRIPT" "session-draft" --output "$OUTPUT_PATH" --no-github --narrative-draft "$DRAFT_PATH"
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]
    grep -q "Parallel execution completed without conflict" "$OUTPUT_PATH"
}
