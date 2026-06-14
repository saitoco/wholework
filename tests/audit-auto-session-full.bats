#!/usr/bin/env bats

# Tests for --narrative-draft flag in scripts/get-auto-session-report.sh
# Verifies draft insertion, LLM draft marker attachment, and classification marker pass-through.
# Uses synthetic fixtures and --no-github for hermetic execution.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-auto-session-report.sh"

setup() {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export OUTPUT_PATH="$BATS_TEST_TMPDIR/report.md"
    rm -f "$AUTO_EVENTS_LOG" "$OUTPUT_PATH"

    # Synthetic events fixture
    cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
{"ts":"2026-06-15T10:00:00Z","issue":999,"event":"sub_start","session_id":"abc-999","size":"M"}
{"ts":"2026-06-15T10:01:00Z","issue":999,"event":"phase_start","session_id":"abc-999","phase":"code-pr"}
{"ts":"2026-06-15T10:30:00Z","issue":999,"event":"phase_complete","session_id":"abc-999","phase":"code-pr"}
{"ts":"2026-06-15T10:30:01Z","issue":999,"event":"sub_complete","session_id":"abc-999","exit_code":"0"}
FIXTURE_EOF
}

teardown() {
    rm -f "$AUTO_EVENTS_LOG" "$OUTPUT_PATH" "$BATS_TEST_TMPDIR/draft-fixture.md"
}

@test "full mode: --narrative-draft inserts draft content into report" {
    # Generate base report first
    run bash "$SCRIPT" "abc-999" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]

    # Create a narrative draft fixture with content for each section
    cat > "$BATS_TEST_TMPDIR/draft-fixture.md" << 'DRAFT_EOF'
### What worked
1. Phase completion was clean with no recovery events.

### Limits and gaps
1. All issues terminated at phase/verify without automated follow-up.

### Improvement candidates surfaced
1. Batch verify orchestration — Issue 起票候補: Add verify step after each run-auto-sub.sh.

### Conclusion
The session processed 1 issue cleanly. The primary gap is the universal phase/verify terminal state.
DRAFT_EOF

    # Apply draft to report
    run bash "$SCRIPT" "abc-999" --narrative-draft "$BATS_TEST_TMPDIR/draft-fixture.md" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]

    # Draft content should appear in the report
    grep -q "Phase completion was clean" "$OUTPUT_PATH"
    grep -q "All issues terminated at phase/verify" "$OUTPUT_PATH"
    grep -q "Batch verify orchestration" "$OUTPUT_PATH"
    grep -q "primary gap is the universal phase/verify terminal state" "$OUTPUT_PATH"
}

@test "full mode: [LLM draft marker is attached to narrative sections" {
    # Generate report first, then apply narrative draft
    run bash "$SCRIPT" "abc-999" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]

    cat > "$BATS_TEST_TMPDIR/draft-fixture.md" << 'DRAFT_EOF'
### What worked
1. The watchdog held throughout the session.

### Limits and gaps
1. Verify phase was not automated in batch mode.

### Improvement candidates surfaced
1. Add verify between batch issues — Issue 起票候補.

### Conclusion
Session completed normally with one structural gap identified.
DRAFT_EOF

    run bash "$SCRIPT" "abc-999" --narrative-draft "$BATS_TEST_TMPDIR/draft-fixture.md" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]

    # LLM draft marker must appear in the report
    grep -q "\[LLM draft" "$OUTPUT_PATH"
}

@test "full mode: auto-session-report-published event is emitted after --narrative-draft" {
    # Create a minimal draft file
    cat > "$BATS_TEST_TMPDIR/draft-fixture.md" << 'DRAFT_EOF'
### What worked
1. Session ran without errors.

### Limits and gaps
1. No gaps identified.

### Improvement candidates surfaced
1. None.

### Conclusion
Clean session.
DRAFT_EOF

    run bash "$SCRIPT" "abc-999" --output "$OUTPUT_PATH" --narrative-draft "$BATS_TEST_TMPDIR/draft-fixture.md" --no-github
    [ "$status" -eq 0 ]

    # auto-session-report-published event must be appended to AUTO_EVENTS_LOG
    grep -q "auto-session-report-published" "$AUTO_EVENTS_LOG"
}

@test "full mode: classification markers appear in narrative draft" {
    # Generate report then apply a draft containing all 3 classification markers
    run bash "$SCRIPT" "abc-999" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]
    [ -f "$OUTPUT_PATH" ]

    cat > "$BATS_TEST_TMPDIR/draft-fixture.md" << 'DRAFT_EOF'
### What worked
1. Sequential batch execution held with no state corruption.

### Limits and gaps
1. In-flight route demotion is not supported.
2. Recovery sub-agent trace is not surfaced in the recovery log.

### Improvement candidates surfaced
1. In-flight route demotion — 凍結推奨（trigger: orchestrator complexity budget review）: M→XS re-judge could switch to patch route but adds orchestrator complexity.
2. Recovery log sub-agent entry — 既存 #316 に統合提案: Add source=recovery-sub-agent key to log entries.
3. Batch verify gap — Issue 起票候補: Invoke /verify per child issue from parent after each run-auto-sub.sh.

### Conclusion
The session completed with 3 improvement candidates surfaced, one existing and two new.
DRAFT_EOF

    run bash "$SCRIPT" "abc-999" --narrative-draft "$BATS_TEST_TMPDIR/draft-fixture.md" --output "$OUTPUT_PATH" --no-github
    [ "$status" -eq 0 ]

    # All 3 classification markers must appear in the report
    grep -q "既存 #" "$OUTPUT_PATH"
    grep -q "Issue 起票候補" "$OUTPUT_PATH"
    grep -q "凍結推奨" "$OUTPUT_PATH"
}
