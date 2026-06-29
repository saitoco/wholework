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
    # Check route mix is computed (S=patch, M=pr)
    grep -q "patch:.*pr:" "$OUTPUT_PATH"
    # Narrative content lives in session.md, not data-layer.md
    ! grep -q "Narrative Section" "$OUTPUT_PATH"
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

@test "success: manual_intervention and verify_reopen_cycle events appear in Summary table" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"abc-333","size":"M"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"phase_start","session_id":"abc-333","phase":"code-pr"}
{"ts":"2026-06-14T10:20:00Z","issue":100,"event":"phase_complete","session_id":"abc-333","phase":"code-pr"}
{"ts":"2026-06-14T10:21:00Z","issue":100,"event":"manual_intervention","session_id":"abc-333","recovery_target":"code-pr","wrapper_exit_code":"1","intervention_type":"tier3_abort_manual_fix"}
{"ts":"2026-06-14T10:30:00Z","issue":100,"event":"verify_reopen_cycle","session_id":"abc-333","iteration":"1","reopen_reason":"pre_merge_ac_fail"}
{"ts":"2026-06-14T10:35:00Z","issue":100,"event":"sub_complete","session_id":"abc-333","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "abc-333" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]
    grep -q "Parent session manual interventions" "$OUTPUT_PATH"
    grep -q "verify FAIL.*reopen fix cycles" "$OUTPUT_PATH"
    grep -q "manual interventions | 1" "$OUTPUT_PATH"
    grep -q "reopen fix cycles | 1" "$OUTPUT_PATH"
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
    # Narrative content lives in session.md, not data-layer.md
    ! grep -q "Narrative Section" "$OUTPUT_PATH"
}

@test "success: backfilled phase_complete shows annotation and Backfilled count in Summary" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"abc-backfill","size":"S"}
{"ts":"2026-06-14T10:00:01Z","issue":100,"event":"phase_start","session_id":"abc-backfill","phase":"code-patch"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"phase_complete","session_id":"abc-backfill","phase":"code-patch","backfilled":true}
FIXTURE_EOF
    run bash "$SCRIPT" "abc-backfill" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    grep -q "backfilled" "$OUTPUT_PATH"
    grep -q "Backfilled phase_complete events" "$OUTPUT_PATH"
}

@test "success: phase silent window threshold violation appears in Summary and Notes" {
    # spec phase: WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800, SILENT_MARGIN=600, threshold=1200
    # max_sec=1500 > 1200 => violation
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-15T10:00:00Z","issue":500,"event":"sub_start","session_id":"abc-666","size":"M"}
{"ts":"2026-06-15T10:00:01Z","issue":500,"event":"phase_start","session_id":"abc-666","phase":"spec"}
{"ts":"2026-06-15T10:25:00Z","issue":500,"event":"max_silent_window","session_id":"abc-666","phase":"spec","max_sec":1500}
{"ts":"2026-06-15T10:25:01Z","issue":500,"event":"phase_complete","session_id":"abc-666","phase":"spec"}
{"ts":"2026-06-15T10:25:02Z","issue":500,"event":"sub_complete","session_id":"abc-666","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "abc-666" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]

    # Summary row must be present
    grep -q "Phase silent windows" "$OUTPUT_PATH"
    # Phase breakdown must show spec:1 (1 violation in spec phase)
    grep -q "spec:1" "$OUTPUT_PATH"
    # Per-issue Notes must include at-risk annotation
    grep -q "within 600s of watchdog limit" "$OUTPUT_PATH"
}

@test "success: verify-type breakdown appears in Verify Phase Residuals section" {
    # Issue 471: has verify phase_start but no phase_complete (residual)
    # Issue 645: same
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-15T10:00:00Z","issue":471,"event":"sub_start","session_id":"abc-vtype","size":"M"}
{"ts":"2026-06-15T10:01:00Z","issue":471,"event":"phase_start","session_id":"abc-vtype","phase":"verify"}
{"ts":"2026-06-15T10:02:00Z","issue":645,"event":"sub_start","session_id":"abc-vtype","size":"M"}
{"ts":"2026-06-15T10:03:00Z","issue":645,"event":"phase_start","session_id":"abc-vtype","phase":"verify"}
FIXTURE_EOF

    # Create issue body fixtures with verify-type markers in Post-merge section
    mkdir -p "$BATS_TEST_TMPDIR/issue-bodies"
    cat > "$BATS_TEST_TMPDIR/issue-bodies/471.md" << 'BODY_EOF'
## Acceptance Criteria

### Post-merge

- [ ] Confirm next /auto run aggregates correctly <!-- verify-type: observation event=auto-run -->
BODY_EOF

    cat > "$BATS_TEST_TMPDIR/issue-bodies/645.md" << 'BODY_EOF'
## Acceptance Criteria

### Post-merge

- [ ] Check opportunistic trigger fires <!-- verify-type: opportunistic -->
- [ ] Manual review of output format <!-- verify-type: manual -->
BODY_EOF

    export WHOLEWORK_ISSUE_BODY_DIR="$BATS_TEST_TMPDIR/issue-bodies"
    run bash "$SCRIPT" "abc-vtype" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]

    grep -q "Verify Phase Residuals" "$OUTPUT_PATH"
    grep -q "observation" "$OUTPUT_PATH"
    grep -q "opportunistic" "$OUTPUT_PATH"
    grep -q "#471" "$OUTPUT_PATH"
    grep -q "auto-run" "$OUTPUT_PATH"
}

@test "success: --day generates _period report" {
    # Write synthetic events covering 2026-06-14 with two sessions
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"day-aaa","size":"S"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"sub_complete","session_id":"day-aaa","exit_code":"0"}
{"ts":"2026-06-14T11:00:00Z","issue":200,"event":"sub_start","session_id":"day-bbb","size":"M"}
{"ts":"2026-06-14T11:30:00Z","issue":200,"event":"sub_complete","session_id":"day-bbb","exit_code":"0"}
{"ts":"2026-06-15T08:00:00Z","issue":300,"event":"sub_start","session_id":"other-ccc","size":"S"}
FIXTURE_EOF

    PERIOD_OUTPUT="$BATS_TEST_TMPDIR/_period/2026-06-14.md"
    mkdir -p "$BATS_TEST_TMPDIR/_period"

    run bash "$SCRIPT" --day 2026-06-14 --output "$PERIOD_OUTPUT" --no-github
    [ "$status" -eq 0 ]
    [[ "$output" == *"Period report written to"* ]]
    [ -f "$PERIOD_OUTPUT" ]

    # Period report structure
    grep -q "Period Report.*2026-06-14" "$PERIOD_OUTPUT"
    grep -q "Sessions covered" "$PERIOD_OUTPUT"
    grep -q "Cross-session patterns" "$PERIOD_OUTPUT"
    grep -q "Improvement candidates" "$PERIOD_OUTPUT"
    grep -q "Trend" "$PERIOD_OUTPUT"

    # Sessions from 2026-06-14 should appear; 2026-06-15 event should NOT
    grep -q "day-aaa" "$PERIOD_OUTPUT"
    grep -q "day-bbb" "$PERIOD_OUTPUT"
    ! grep -q "other-ccc" "$PERIOD_OUTPUT"

    # _period path marker in output
    [[ "$output" == *"_period"* ]]
}

@test "success: --since-days generates _period since report" {
    # Write synthetic events for today and 3 days ago (relative dates replaced with fixed dates)
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":500,"event":"sub_start","session_id":"recent-aaa","size":"M"}
{"ts":"2026-06-14T10:30:00Z","issue":500,"event":"sub_complete","session_id":"recent-aaa","exit_code":"0"}
{"ts":"2026-06-14T11:00:00Z","issue":501,"event":"sub_start","session_id":"recent-bbb","size":"S"}
{"ts":"2026-06-14T11:10:00Z","issue":501,"event":"sub_complete","session_id":"recent-bbb","exit_code":"0"}
FIXTURE_EOF

    PERIOD_DIR="$BATS_TEST_TMPDIR/_period"
    mkdir -p "$PERIOD_DIR"

    run bash "$SCRIPT" --since-days 7 --output "${PERIOD_DIR}/since-test-7d.md" --no-github
    [ "$status" -eq 0 ]
    [[ "$output" == *"Period report written to"* ]]
    [ -f "${PERIOD_DIR}/since-test-7d.md" ]

    # Period report structure
    grep -q "Period Report" "${PERIOD_DIR}/since-test-7d.md"
    grep -q "Sessions covered" "${PERIOD_DIR}/since-test-7d.md"
    grep -q "Trend" "${PERIOD_DIR}/since-test-7d.md"
    [[ "$output" == *"_period"* ]]
}
