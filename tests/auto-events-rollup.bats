#!/usr/bin/env bats

# Tests for scripts/auto-events-rollup.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/auto-events-rollup.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
    mkdir -p .tmp docs/reports
}

teardown() {
    cd /
}

# (a) Empty input: output file generated with 4 required sections
@test "auto-events-rollup: empty input produces report with all 4 sections" {
    run bash "$SCRIPT" --date 2026-06-14 --input .tmp/missing.jsonl --output-dir docs/reports
    [ "$status" -eq 0 ]
    [ -f "docs/reports/auto-events-rollup-2026-06-14.md" ]

    grep -q "## Sessions" "docs/reports/auto-events-rollup-2026-06-14.md"
    grep -q "## Phase Distribution" "docs/reports/auto-events-rollup-2026-06-14.md"
    grep -q "## Recovery Tier Invocations" "docs/reports/auto-events-rollup-2026-06-14.md"
    grep -q "## Anomalies" "docs/reports/auto-events-rollup-2026-06-14.md"
}

# (a) Empty input: frontmatter fields present
@test "auto-events-rollup: empty input has required frontmatter fields" {
    run bash "$SCRIPT" --date 2026-06-14 --input .tmp/missing.jsonl --output-dir docs/reports
    [ "$status" -eq 0 ]

    grep -q "^type: report" "docs/reports/auto-events-rollup-2026-06-14.md"
    grep -q "^description:" "docs/reports/auto-events-rollup-2026-06-14.md"
    grep -q "^generated_by: scripts/auto-events-rollup.sh" "docs/reports/auto-events-rollup-2026-06-14.md"
    grep -q "^generated_at:" "docs/reports/auto-events-rollup-2026-06-14.md"
}

# (b) Single session rollup: Sessions table has exactly one data row
@test "auto-events-rollup: single session produces one Sessions row" {
    cat > .tmp/events.jsonl << 'EOF'
{"ts":"2026-06-14T07:01:38Z","issue":626,"event":"sub_start","size":"S"}
{"ts":"2026-06-14T07:02:00Z","issue":626,"event":"phase_start","phase":"spec"}
{"ts":"2026-06-14T07:20:00Z","issue":626,"event":"phase_complete","phase":"spec"}
{"ts":"2026-06-14T07:20:05Z","issue":626,"event":"phase_start","phase":"code"}
{"ts":"2026-06-14T07:35:00Z","issue":626,"event":"phase_complete","phase":"code"}
{"ts":"2026-06-14T07:36:09Z","issue":626,"event":"sub_complete","exit_code":"0"}
EOF

    run bash "$SCRIPT" --date 2026-06-14 --input .tmp/events.jsonl --output-dir docs/reports
    [ "$status" -eq 0 ]
    [ -f "docs/reports/auto-events-rollup-2026-06-14.md" ]

    # The Sessions table should have exactly one data row (containing #626)
    session_rows=$(grep "^| #626" "docs/reports/auto-events-rollup-2026-06-14.md" | wc -l | tr -d ' ')
    [ "$session_rows" -eq 1 ]

    # Outcome should be success
    grep -q "success" "docs/reports/auto-events-rollup-2026-06-14.md"

    # Phases should show spec->code
    grep -q "spec.*code" "docs/reports/auto-events-rollup-2026-06-14.md"
}

# (c) Multi-session aggregation: multiple issues appear in Sessions table
@test "auto-events-rollup: multi-session aggregation includes all issues" {
    cat > .tmp/events.jsonl << 'EOF'
{"ts":"2026-06-14T07:01:38Z","issue":626,"event":"sub_start","size":"S"}
{"ts":"2026-06-14T07:01:45Z","issue":626,"event":"phase_start","phase":"spec"}
{"ts":"2026-06-14T07:15:00Z","issue":626,"event":"phase_complete","phase":"spec"}
{"ts":"2026-06-14T07:36:09Z","issue":626,"event":"sub_complete","exit_code":"0"}
{"ts":"2026-06-14T08:00:00Z","issue":627,"event":"sub_start","size":"M"}
{"ts":"2026-06-14T08:00:10Z","issue":627,"event":"phase_start","phase":"spec"}
{"ts":"2026-06-14T08:20:00Z","issue":627,"event":"phase_complete","phase":"spec"}
{"ts":"2026-06-14T08:20:05Z","issue":627,"event":"phase_start","phase":"code"}
{"ts":"2026-06-14T09:10:00Z","issue":627,"event":"phase_complete","phase":"code"}
{"ts":"2026-06-14T09:15:00Z","issue":627,"event":"recovery","phase":"code","tier":"1","result":"recovered"}
{"ts":"2026-06-14T09:20:00Z","issue":627,"event":"sub_complete","exit_code":"0"}
EOF

    run bash "$SCRIPT" --date 2026-06-14 --input .tmp/events.jsonl --output-dir docs/reports
    [ "$status" -eq 0 ]

    grep -q "^| #626" "docs/reports/auto-events-rollup-2026-06-14.md"
    grep -q "^| #627" "docs/reports/auto-events-rollup-2026-06-14.md"

    # Issue 627 had 1 recovery, issue 626 had none (shown as em-dash)
    grep "^| #627" "docs/reports/auto-events-rollup-2026-06-14.md" | grep -q "| 1 |"
    grep "^| #626" "docs/reports/auto-events-rollup-2026-06-14.md" | grep -q "^| #626"

    # Phase Distribution should have spec and code entries
    grep -q "| spec |" "docs/reports/auto-events-rollup-2026-06-14.md"
    grep -q "| code |" "docs/reports/auto-events-rollup-2026-06-14.md"

    # Recovery tier 1 should appear
    grep -q "| 1 |" "docs/reports/auto-events-rollup-2026-06-14.md"
}

# (e) phase_start/phase_complete only (no sub_*) produces session row
@test "auto-events-rollup: phase_start/phase_complete only (no sub_*) produces session row" {
    cat > .tmp/events.jsonl << 'EOF'
{"ts":"2026-06-14T08:00:00Z","issue":684,"event":"phase_start","phase":"code-patch"}
{"ts":"2026-06-14T08:30:00Z","issue":684,"event":"phase_complete","phase":"code-patch"}
EOF

    run bash "$SCRIPT" --date 2026-06-14 --input .tmp/events.jsonl --output-dir docs/reports
    [ "$status" -eq 0 ]
    [ -f "docs/reports/auto-events-rollup-2026-06-14.md" ]

    # Sessions table should have a row for #684
    grep -q "^| #684" "docs/reports/auto-events-rollup-2026-06-14.md"

    # Size should be "-" (no sub_start)
    grep "^| #684" "docs/reports/auto-events-rollup-2026-06-14.md" | grep -q "| - |"

    # Outcome should be success (phase_complete present)
    grep "^| #684" "docs/reports/auto-events-rollup-2026-06-14.md" | grep -q "success"

    # Phase column should show code-patch
    grep "^| #684" "docs/reports/auto-events-rollup-2026-06-14.md" | grep -q "code-patch"
}

# (f) phase_start without phase_complete produces incomplete outcome
@test "auto-events-rollup: phase_start without phase_complete produces incomplete outcome" {
    cat > .tmp/events.jsonl << 'EOF'
{"ts":"2026-06-14T09:00:00Z","issue":685,"event":"phase_start","phase":"code-pr"}
EOF

    run bash "$SCRIPT" --date 2026-06-14 --input .tmp/events.jsonl --output-dir docs/reports
    [ "$status" -eq 0 ]
    [ -f "docs/reports/auto-events-rollup-2026-06-14.md" ]

    # Sessions table should have a row for #685
    grep -q "^| #685" "docs/reports/auto-events-rollup-2026-06-14.md"

    # Outcome should be incomplete (no phase_complete)
    grep "^| #685" "docs/reports/auto-events-rollup-2026-06-14.md" | grep -q "incomplete"
}

# (g) session scope: Phases/Recoveries columns are isolated per session_id
@test "auto-events-rollup: session scope prevents Phases cross-contamination between sessions" {
    cat > .tmp/events.jsonl << 'EOF'
{"ts":"2026-06-14T08:00:00Z","issue":699,"session_id":"session_a","event":"phase_start","phase":"spec"}
{"ts":"2026-06-14T08:10:00Z","issue":699,"session_id":"session_a","event":"phase_complete","phase":"spec"}
{"ts":"2026-06-14T09:00:00Z","issue":699,"session_id":"session_b","event":"phase_start","phase":"code"}
{"ts":"2026-06-14T09:30:00Z","issue":699,"session_id":"session_b","event":"phase_complete","phase":"code"}
EOF

    run bash "$SCRIPT" --date 2026-06-14 --input .tmp/events.jsonl --output-dir docs/reports
    [ "$status" -eq 0 ]
    [ -f "docs/reports/auto-events-rollup-2026-06-14.md" ]

    # Two rows should exist for issue #699 (one per session)
    rows=$(grep "^| #699" "docs/reports/auto-events-rollup-2026-06-14.md" | wc -l | tr -d ' ')
    [ "$rows" -eq 2 ]

    # Neither row should contain the cross-contaminated "spec→code" value
    run grep "^| #699" "docs/reports/auto-events-rollup-2026-06-14.md"
    [[ "$output" != *"spec→code"* ]]

    # One row should show "spec" only and the other "code" only
    grep "^| #699" "docs/reports/auto-events-rollup-2026-06-14.md" | grep -q "| spec |"
    grep "^| #699" "docs/reports/auto-events-rollup-2026-06-14.md" | grep -q "| code |"
}

# (h) auto-commit: git commit is called after successful rollup
@test "auto-events-rollup: git commit is called after successful rollup" {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks_rollup"
    GIT_LOG="$BATS_TEST_TMPDIR/git-calls-rollup.log"
    mkdir -p "$MOCK_DIR"
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "git \$*" >> "$GIT_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > .tmp/events_ac.jsonl << 'EOF'
{"ts":"2026-06-14T07:01:38Z","issue":824,"event":"sub_start","size":"M"}
{"ts":"2026-06-14T07:36:09Z","issue":824,"event":"sub_complete","exit_code":"0"}
EOF

    PATH="$MOCK_DIR:$PATH" run bash "$SCRIPT" --date 2026-06-14 --input .tmp/events_ac.jsonl --output-dir docs/reports
    [ "$status" -eq 0 ]
    [ -f "$GIT_LOG" ]
    grep -q "commit" "$GIT_LOG"
}

# (d) Cleanup rotation: target date entries removed, other dates preserved
@test "auto-events-rollup: cleanup removes target date entries and preserves others" {
    cat > .tmp/events.jsonl << 'EOF'
{"ts":"2026-06-13T10:00:00Z","issue":600,"event":"sub_start","size":"S"}
{"ts":"2026-06-13T10:30:00Z","issue":600,"event":"sub_complete","exit_code":"0"}
{"ts":"2026-06-14T07:01:38Z","issue":626,"event":"sub_start","size":"S"}
{"ts":"2026-06-14T07:36:09Z","issue":626,"event":"sub_complete","exit_code":"0"}
{"ts":"2026-06-15T09:00:00Z","issue":640,"event":"sub_start","size":"M"}
EOF

    run bash "$SCRIPT" --date 2026-06-14 --input .tmp/events.jsonl --output-dir docs/reports --cleanup
    [ "$status" -eq 0 ]
    [ -f "docs/reports/auto-events-rollup-2026-06-14.md" ]

    # Target date entries should be removed
    run grep "\"ts\":\"2026-06-14" .tmp/events.jsonl
    [ "$status" -ne 0 ]

    # Other dates should be preserved
    grep -q "\"ts\":\"2026-06-13" .tmp/events.jsonl
    grep -q "\"ts\":\"2026-06-15" .tmp/events.jsonl
}
