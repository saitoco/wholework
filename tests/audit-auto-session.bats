#!/usr/bin/env bats

# Tests for scripts/get-auto-session-report.sh
# Uses synthetic .jsonl fixtures and --no-github flag for hermetic execution.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-auto-session-report.sh"

setup() {
    export TMPDIR_OVERRIDE="$BATS_TEST_TMPDIR"
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    rm -f "$AUTO_EVENTS_LOG"
}

teardown() {
    rm -f "$AUTO_EVENTS_LOG"
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

    run bash "$SCRIPT" "abc-111" --metrics-only --no-github
    [ "$status" -eq 0 ]

    # Check Metrics section contains expected subsections
    echo "$output" | grep -q "^## Metrics"
    echo "$output" | grep -q "Issues processed"
    echo "$output" | grep -q "Sub-Issue Completion Timeline"
    echo "$output" | grep -q "Recovery Events"
    # Check route mix is computed (S=patch, M=pr)
    echo "$output" | grep -q "patch:.*pr:"
    # Narrative content lives in the rest of session.md, not in the Metrics section
    ! echo "$output" | grep -q "Narrative Section"
}

@test "success: parallel session isolation — only specified session events are aggregated" {
    # Two sessions in the same log; only abc-222 should appear in the Metrics section
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T09:00:00Z","issue":200,"event":"sub_start","session_id":"abc-111","size":"S"}
{"ts":"2026-06-14T09:01:00Z","issue":200,"event":"phase_complete","session_id":"abc-111","phase":"code-patch"}
{"ts":"2026-06-14T10:00:00Z","issue":300,"event":"sub_start","session_id":"abc-222","size":"M"}
{"ts":"2026-06-14T10:01:00Z","issue":300,"event":"phase_start","session_id":"abc-222","phase":"code-pr"}
{"ts":"2026-06-14T10:30:00Z","issue":300,"event":"phase_complete","session_id":"abc-222","phase":"code-pr"}
{"ts":"2026-06-14T10:30:01Z","issue":300,"event":"sub_complete","session_id":"abc-222","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "abc-222" --metrics-only --no-github
    [ "$status" -eq 0 ]

    # Issue 300 (abc-222) should appear, issue 200 (abc-111) should NOT
    echo "$output" | grep -q "300"
    # Issue 200 belongs to abc-111 and must not be counted
    ! echo "$output" | grep -q "Issues processed | 2"
    # Exactly 1 issue processed (from abc-222)
    echo "$output" | grep -q "Issues processed | 1"
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

    run bash "$SCRIPT" "abc-333" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Parent session manual interventions"
    echo "$output" | grep -q "verify FAIL.*reopen fix cycles"
    echo "$output" | grep -q "manual interventions | 1"
    echo "$output" | grep -q "reopen fix cycles | 1"
}

@test "success: empty session — no matching session_id produces graceful Metrics section" {
    # Log contains events for a different session only
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T08:00:00Z","issue":400,"event":"sub_start","session_id":"other-999","size":"XS"}
{"ts":"2026-06-14T08:05:00Z","issue":400,"event":"sub_complete","session_id":"other-999","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "nonexistent-000" --metrics-only --no-github
    [ "$status" -eq 0 ]

    # Metrics section should still be emitted with N/A or 0 values
    echo "$output" | grep -q "^## Metrics"
    echo "$output" | grep -q "Issues processed | 0"
    # Narrative content lives in the rest of session.md, not in the Metrics section
    ! echo "$output" | grep -q "Narrative Section"
}

@test "success: backfilled phase_complete shows annotation and Backfilled count in Summary" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"abc-backfill","size":"S"}
{"ts":"2026-06-14T10:00:01Z","issue":100,"event":"phase_start","session_id":"abc-backfill","phase":"code-patch"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"phase_complete","session_id":"abc-backfill","phase":"code-patch","backfilled":true}
FIXTURE_EOF
    run bash "$SCRIPT" "abc-backfill" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "backfilled"
    echo "$output" | grep -q "Backfilled phase_complete events"
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

    run bash "$SCRIPT" "abc-666" --metrics-only --no-github
    [ "$status" -eq 0 ]

    # Summary row must be present
    echo "$output" | grep -q "Phase silent windows"
    # Phase breakdown must show spec:1 (1 violation in spec phase)
    echo "$output" | grep -q "spec:1"
    # Per-issue Notes must include at-risk annotation
    echo "$output" | grep -q "within 600s of watchdog limit"
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
    run bash "$SCRIPT" "abc-vtype" --metrics-only --no-github
    [ "$status" -eq 0 ]

    echo "$output" | grep -q "Verify Phase Residuals"
    echo "$output" | grep -q "observation"
    echo "$output" | grep -q "opportunistic"
    echo "$output" | grep -q "#471"
    echo "$output" | grep -q "auto-run"
}
