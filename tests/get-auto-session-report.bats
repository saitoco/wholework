#!/usr/bin/env bats

# Direct unit tests for scripts/get-auto-session-report.sh
# Covers: session_id filter, --since list mode, empty jsonl, --metrics-only stdout output.
# All tests use --no-github for hermetic execution.
# Exception: the "live phase/verify label lookup" test below mocks `gh` via PATH
# (see tests/get-issue-type.bats for the same convention) instead of using --no-github,
# since it exercises the live label lookup path directly (#900).

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-auto-session-report.sh"

setup() {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
}

@test "session_id filter: only specified session events appear in Metrics section" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-A","size":"S"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"phase_start","session_id":"session-A","phase":"code-patch"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"phase_complete","session_id":"session-A","phase":"code-patch"}
{"ts":"2026-06-14T10:05:01Z","issue":100,"event":"sub_complete","session_id":"session-A","exit_code":"0"}
{"ts":"2026-06-14T11:00:00Z","issue":200,"event":"sub_start","session_id":"session-B","size":"M"}
{"ts":"2026-06-14T11:01:00Z","issue":200,"event":"sub_complete","session_id":"session-B","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-A" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "^## Metrics"
    echo "$output" | grep -q "Issues processed | 1"
    echo "$output" | grep -q "#100"
    ! echo "$output" | grep -q "| #200 |"
    # Required subsections
    echo "$output" | grep -q "### Summary"
    echo "$output" | grep -q "### Phase Activity Summary"
    echo "$output" | grep -q "### Sub-Issue Completion Timeline"
    echo "$output" | grep -q "### Token Usage Aggregate"
    echo "$output" | grep -q "### Verify Phase Residuals"
    echo "$output" | grep -q "### Recovery Events"
}

@test "Issues processed: batch Issue and observation dispatch Issue are both counted" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-mix","size":"S"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"phase_start","session_id":"session-mix","phase":"code-patch"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"phase_complete","session_id":"session-mix","phase":"code-patch"}
{"ts":"2026-06-14T10:05:01Z","issue":100,"event":"sub_complete","session_id":"session-mix","exit_code":"0"}
{"ts":"2026-06-14T11:00:00Z","issue":200,"event":"phase_start","session_id":"session-mix","phase":"verify"}
{"ts":"2026-06-14T11:02:00Z","issue":200,"event":"phase_complete","session_id":"session-mix","phase":"verify"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-mix" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Issues processed | 2"
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

    run bash "$SCRIPT" "arbitrary-session-id" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "^## Metrics"
    echo "$output" | grep -q "Issues processed | 0"
}

@test "Tier 2 candidate surfacing: approaching threshold appears in Improvement Candidates" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-t2","size":"S"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"phase_start","session_id":"session-t2","phase":"code-patch"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"recovery","session_id":"session-t2","phase":"code-patch","tier":"2","result":"recovered"}
{"ts":"2026-06-14T10:06:00Z","issue":100,"event":"phase_complete","session_id":"session-t2","phase":"code-patch"}
{"ts":"2026-06-14T10:07:00Z","issue":100,"event":"sub_complete","session_id":"session-t2","exit_code":"0"}
{"ts":"2026-06-14T10:10:00Z","issue":101,"event":"sub_start","session_id":"session-t2","size":"S"}
{"ts":"2026-06-14T10:11:00Z","issue":101,"event":"phase_start","session_id":"session-t2","phase":"code-patch"}
{"ts":"2026-06-14T10:15:00Z","issue":101,"event":"recovery","session_id":"session-t2","phase":"code-patch","tier":"2","result":"recovered"}
{"ts":"2026-06-14T10:16:00Z","issue":101,"event":"phase_complete","session_id":"session-t2","phase":"code-patch"}
{"ts":"2026-06-14T10:17:00Z","issue":101,"event":"sub_complete","session_id":"session-t2","exit_code":"0"}
FIXTURE_EOF

    # WHOLEWORK_CONFIG_PATH=/dev/null forces default threshold=3 -> RECOVERIES_APPROACH=2
    # 2 Tier 2 events in phase=code-patch -> count=2 >= approach=2 -> should appear as "approaching threshold"
    export WHOLEWORK_CONFIG_PATH=/dev/null
    run bash "$SCRIPT" "session-t2" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Tier 2 recovery"
    echo "$output" | grep -q "approaching threshold"
}

@test "Tier 2 candidate surfacing: threshold reached when count equals threshold" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-t3","size":"S"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"phase_start","session_id":"session-t3","phase":"code-patch"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"recovery","session_id":"session-t3","phase":"code-patch","tier":"2","result":"recovered"}
{"ts":"2026-06-14T10:06:00Z","issue":100,"event":"phase_complete","session_id":"session-t3","phase":"code-patch"}
{"ts":"2026-06-14T10:07:00Z","issue":100,"event":"sub_complete","session_id":"session-t3","exit_code":"0"}
{"ts":"2026-06-14T10:10:00Z","issue":101,"event":"sub_start","session_id":"session-t3","size":"S"}
{"ts":"2026-06-14T10:11:00Z","issue":101,"event":"phase_start","session_id":"session-t3","phase":"code-patch"}
{"ts":"2026-06-14T10:15:00Z","issue":101,"event":"recovery","session_id":"session-t3","phase":"code-patch","tier":"2","result":"recovered"}
{"ts":"2026-06-14T10:16:00Z","issue":101,"event":"phase_complete","session_id":"session-t3","phase":"code-patch"}
{"ts":"2026-06-14T10:17:00Z","issue":101,"event":"sub_complete","session_id":"session-t3","exit_code":"0"}
{"ts":"2026-06-14T10:20:00Z","issue":102,"event":"sub_start","session_id":"session-t3","size":"S"}
{"ts":"2026-06-14T10:21:00Z","issue":102,"event":"phase_start","session_id":"session-t3","phase":"code-patch"}
{"ts":"2026-06-14T10:25:00Z","issue":102,"event":"recovery","session_id":"session-t3","phase":"code-patch","tier":"2","result":"recovered"}
{"ts":"2026-06-14T10:26:00Z","issue":102,"event":"phase_complete","session_id":"session-t3","phase":"code-patch"}
{"ts":"2026-06-14T10:27:00Z","issue":102,"event":"sub_complete","session_id":"session-t3","exit_code":"0"}
FIXTURE_EOF

    # WHOLEWORK_CONFIG_PATH=/dev/null forces default threshold=3 -> RECOVERIES_APPROACH=2
    # 3 Tier 2 events in phase=code-patch -> count=3 >= threshold=3 -> should appear as "threshold reached"
    export WHOLEWORK_CONFIG_PATH=/dev/null
    run bash "$SCRIPT" "session-t3" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Tier 2 recovery"
    echo "$output" | grep -q "threshold reached"
}

@test "concurrent_commit_detected: commit without #N hint does not abort report" {
    # Regression test for #848 reopen: concurrent_commit_detected with a commit message
    # that contains no "#NNN" reference (e.g. "chore: loop-state heartbeat auto-commit")
    # used to abort the script via `set -e` + pipefail because the grep no-match exited 1.
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-grepfix","size":"S"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"concurrent_commit_detected","session_id":"session-grepfix","phase":"code","commit_sha":"deadbeefdeadbeefdeadbeefdeadbeefdeadbeef","author":"Toshihiro Saito"}
{"ts":"2026-06-14T10:02:00Z","issue":100,"event":"sub_complete","session_id":"session-grepfix","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-grepfix" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Concurrent Commits\|concurrent_commit_detected\|Concurrent commits" || true
    # The line for the commit without a #NNN hint should be present (without an issue hint).
    echo "$output" | grep -q "deadbeef"
}

@test "Verify Phase Residuals: issue carrying live phase/verify label is detected" {
    # #900: detection is based solely on the current phase/verify label (live lookup),
    # not on phase_start/phase_complete(phase=="verify") events (which /verify never emits).
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":300,"event":"sub_start","session_id":"session-residual","size":"M"}
FIXTURE_EOF

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" ]]; then
    if [[ "$*" == *"body,title"* ]]; then
        echo '{"body":"","title":"#300"}'
    else
        echo "phase/verify"
    fi
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "[]"
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" "session-residual" --metrics-only
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "### Verify Phase Residuals"
    echo "$output" | grep -q "#300"
    # Scope the "(none)" degrade check to the Verify Phase Residuals section only —
    # other sections (e.g. Retro Proposal Tier Breakdown) legitimately show "(none)"
    # in this fixture, which has no retro_proposal_classified events.
    residuals_section="$(echo "$output" | sed -n '/### Verify Phase Residuals/,/### Concurrent Sessions Detected/p')"
    ! echo "$residuals_section" | grep -qE "^\(none\)$"
}

@test "Verify Phase Residuals: --no-github shows explicit non-detection note" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":300,"event":"sub_start","session_id":"session-nogh","size":"M"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-nogh" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "### Verify Phase Residuals"
    echo "$output" | grep -q -- "--no-github mode: cannot detect phase/verify residuals"
}

@test "Retro Proposal Tier Breakdown: mixed tier 1/2/3 events surface counts and hit rate" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-tiers","size":"S"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"retro_proposal_classified","session_id":"session-tiers","tier":"1","title":"proposal A","reason":"multi-file ripple","action":"issue_created"}
{"ts":"2026-06-14T10:02:00Z","issue":100,"event":"retro_proposal_classified","session_id":"session-tiers","tier":"2","title":"proposal B","reason":"single lesson","action":"memory_proposal"}
{"ts":"2026-06-14T10:03:00Z","issue":100,"event":"retro_proposal_classified","session_id":"session-tiers","tier":"2","title":"proposal C","reason":"single lesson","action":"memory_proposal"}
{"ts":"2026-06-14T10:04:00Z","issue":100,"event":"retro_proposal_classified","session_id":"session-tiers","tier":"3","title":"proposal D","reason":"one-time memo","action":"spec_only"}
{"ts":"2026-06-14T10:05:00Z","issue":100,"event":"sub_complete","session_id":"session-tiers","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-tiers" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "### Retro Proposal Tier Breakdown"
    echo "$output" | grep -q "Retro proposal tiers (1/2/3) | 1 / 2 / 1"
    echo "$output" | grep -q "Filter hit rate: 75% (2+1/4)"
}

@test "Retro Proposal Tier Breakdown: no events degrades to 0/0/0 and (none)" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-notiers","size":"S"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"sub_complete","session_id":"session-notiers","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-notiers" --metrics-only --no-github
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Retro proposal tiers (1/2/3) | 0 / 0 / 0"
    echo "$output" | grep -q "### Retro Proposal Tier Breakdown"
    # Scope the "(none)" degrade check to the Retro Proposal Tier Breakdown section only —
    # an unscoped check would silently pass if a different section's degrade string were
    # ever normalized to a bare "(none)" while this section actually broke.
    breakdown_section="$(echo "$output" | sed -n '/### Retro Proposal Tier Breakdown/,$p')"
    echo "$breakdown_section" | grep -qE "^\(none\)$"
}

@test "Recovery Metrics: fired-based count includes failed results, success rate breakdown shown per tier" {
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-14T10:00:00Z","issue":100,"event":"sub_start","session_id":"session-recovery-mix","size":"M"}
{"ts":"2026-06-14T10:01:00Z","issue":100,"event":"recovery","session_id":"session-recovery-mix","phase":"code-pr","tier":"2","result":"recovered"}
{"ts":"2026-06-14T10:02:00Z","issue":101,"event":"recovery","session_id":"session-recovery-mix","phase":"code-pr","tier":"2","result":"failed"}
{"ts":"2026-06-14T10:03:00Z","issue":101,"event":"recovery","session_id":"session-recovery-mix","phase":"review","tier":"3","result":"recovered"}
{"ts":"2026-06-14T10:04:00Z","issue":102,"event":"recovery","session_id":"session-recovery-mix","phase":"merge","tier":"3","result":"failed","action":"abort"}
{"ts":"2026-06-14T10:05:00Z","issue":102,"event":"recovery","session_id":"session-recovery-mix","phase":"code-pr","tier":"3","result":"failed","action":"abort"}
{"ts":"2026-06-14T10:06:00Z","issue":100,"event":"sub_complete","session_id":"session-recovery-mix","exit_code":"0"}
FIXTURE_EOF

    run bash "$SCRIPT" "session-recovery-mix" --metrics-only --no-github
    [ "$status" -eq 0 ]
    # Fired-based count: 2 tier-2 events + 3 tier-3 events, regardless of result
    echo "$output" | grep -q "Tier 1/2/3 recoveries | 0 / 2 / 3"
    echo "$output" | grep -q "Recovery success rate (tier) | T1: 0 recovered / 0 failed, T2: 1 recovered / 1 failed, T3: 1 recovered / 2 failed"
}
