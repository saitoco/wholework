#!/usr/bin/env bats

# Tests for scripts/get-auto-session-report.sh
# Uses synthetic .jsonl fixtures and --no-github flag for hermetic execution.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-auto-session-report.sh"

setup() {
    export TMPDIR_OVERRIDE="$BATS_TEST_TMPDIR"
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export OUTPUT_PATH="$BATS_TEST_TMPDIR/report.md"
    rm -f "$AUTO_EVENTS_LOG" "$OUTPUT_PATH"
}

teardown() {
    rm -f "$AUTO_EVENTS_LOG" "$OUTPUT_PATH"
}

@test "success: single session generates per-issue durations and summary" {
    # Write synthetic events for session abc-111
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"abc-111","size":"S"}
{"ts":"2026-06-14T10:00:01Z","issue":100,"event":"phase_start","session_id":"abc-111","phase":"code-patch"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"phase_complete","session_id":"abc-111","phase":"code-patch"}
{"ts":"2026-06-14T10:05:01Z","issue":100,"event":"sub_complete","session_id":"abc-111","exit_code":"0"}
{"ts":"2026-06-14T10:06:00Z","issue":101,"event":"sub_start","session_id":"abc-111","size":"M"}
{"ts":"2026-06-14T10:06:01Z","issue":101,"event":"phase_start","session_id":"abc-111","phase":"code-pr"}
{"ts":"2026-06-14T10:20:00Z","issue":101,"event":"phase_complete","session_id":"abc-111","phase":"code-pr"}
{"ts":"2026-06-14T10:20:01Z","issue":101,"event":"sub_complete","session_id":"abc-111","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "abc-111" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [[ "$output" == *"Report written to"* ]]
    [ -f "$OUTPUT_PATH" ]

    # Check report contains expected sections
    grep -q "Session Report.*abc-111" "$OUTPUT_PATH"
    grep -q "Issues processed" "$OUTPUT_PATH"
    grep -q "Per-Issue Durations" "$OUTPUT_PATH"
    grep -q "Recovery Events" "$OUTPUT_PATH"
    grep -q "Narrative Section" "$OUTPUT_PATH"
    # Check route mix is computed (S=patch, M=pr)
    grep -q "patch:.*pr:" "$OUTPUT_PATH"
}

@test "success: parallel session isolation — only specified session events are aggregated" {
    # Two sessions in the same log; only abc-222 should appear in the report
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T09:00:00Z","issue":200,"event":"sub_start","session_id":"abc-111","size":"S"}
{"ts":"2026-06-14T09:01:00Z","issue":200,"event":"phase_complete","session_id":"abc-111","phase":"code-patch"}
{"ts":"2026-06-14T10:00:00Z","issue":300,"event":"sub_start","session_id":"abc-222","size":"M"}
{"ts":"2026-06-14T10:01:00Z","issue":300,"event":"phase_start","session_id":"abc-222","phase":"code-pr"}
{"ts":"2026-06-14T10:30:00Z","issue":300,"event":"phase_complete","session_id":"abc-222","phase":"code-pr"}
{"ts":"2026-06-14T10:30:01Z","issue":300,"event":"sub_complete","session_id":"abc-222","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "abc-222" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]

    # Issue 300 (abc-222) should appear, issue 200 (abc-111) should NOT
    grep -q "300" "$OUTPUT_PATH"
    # Issue 200 belongs to abc-111 and must not be counted
    ! grep -q "Issues processed | 2" "$OUTPUT_PATH"
    # Exactly 1 issue processed (from abc-222)
    grep -q "Issues processed | 1" "$OUTPUT_PATH"
}

@test "success: empty session — no matching session_id produces graceful report" {
    # Log contains events for a different session only
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T08:00:00Z","issue":400,"event":"sub_start","session_id":"other-999","size":"XS"}
{"ts":"2026-06-14T08:05:00Z","issue":400,"event":"sub_complete","session_id":"other-999","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "nonexistent-000" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]

    # Report should still be generated with N/A or 0 values
    grep -q "Session Report.*nonexistent-000" "$OUTPUT_PATH"
    grep -q "Issues processed | 0" "$OUTPUT_PATH"
    # Narrative section skeleton should still be present
    grep -q "Narrative Section" "$OUTPUT_PATH"
}
