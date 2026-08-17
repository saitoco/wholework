#!/usr/bin/env bats

# Tests for scripts/detect-unrecorded-kills.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/detect-unrecorded-kills.sh"

setup() {
    EVENTS_FILE="$BATS_TEST_TMPDIR/auto-events.jsonl"
    RECOVERIES_FILE="$BATS_TEST_TMPDIR/orchestration-recoveries.md"
    : > "$EVENTS_FILE"
    : > "$RECOVERIES_FILE"
}

@test "error: missing required arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "error: events file not found" {
    run bash "$SCRIPT" "$BATS_TEST_TMPDIR/nonexistent.jsonl" "$RECOVERIES_FILE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"File not found"* ]]
}

@test "error: recoveries file not found" {
    run bash "$SCRIPT" "$EVENTS_FILE" "$BATS_TEST_TMPDIR/nonexistent.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"File not found"* ]]
}

@test "error: non-numeric --window" {
    run bash "$SCRIPT" "$EVENTS_FILE" "$RECOVERIES_FILE" --window abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"--window"* ]]
}

@test "no anomalies: clean phase_start/wrapper_exit/phase_complete pair produces no output" {
    cat > "$EVENTS_FILE" <<'JSON'
{"ts":"2026-08-16T06:30:47Z","issue":1000,"event":"phase_start","session_id":"a","phase":"review","spawn_detach":"0"}
{"ts":"2026-08-16T06:40:00Z","issue":1000,"event":"wrapper_exit","session_id":"a","phase":"review","exit_code":"0"}
{"ts":"2026-08-16T06:40:01Z","issue":1000,"event":"phase_complete","session_id":"a","phase":"review"}
JSON
    run bash "$SCRIPT" "$EVENTS_FILE" "$RECOVERIES_FILE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "no anomalies: single phase_start with no subsequent respawn produces no output" {
    cat > "$EVENTS_FILE" <<'JSON'
{"ts":"2026-08-16T06:30:47Z","issue":1000,"event":"phase_start","session_id":"a","phase":"review","spawn_detach":"0"}
JSON
    run bash "$SCRIPT" "$EVENTS_FILE" "$RECOVERIES_FILE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "respawn detection: backfilled phase_complete between phase_starts suppresses the signal" {
    cat > "$EVENTS_FILE" <<'JSON'
{"ts":"2026-08-16T06:30:47Z","issue":1000,"event":"phase_start","session_id":"a","phase":"review","spawn_detach":"0"}
{"ts":"2026-08-16T06:40:01Z","issue":1000,"event":"phase_complete","session_id":"a","phase":"review","backfilled":true}
{"ts":"2026-08-16T06:45:00Z","issue":1000,"event":"phase_start","session_id":"b","phase":"review","spawn_detach":"0"}
JSON
    run bash "$SCRIPT" "$EVENTS_FILE" "$RECOVERIES_FILE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "respawn detection: manual_intervention between phase_starts suppresses the signal" {
    cat > "$EVENTS_FILE" <<'JSON'
{"ts":"2026-08-16T06:30:47Z","issue":1000,"event":"phase_start","session_id":"a","phase":"code-patch","spawn_detach":"0"}
{"ts":"2026-08-16T06:40:01Z","issue":1000,"event":"manual_intervention","session_id":"a","recovery_target":"code-patch","wrapper_exit_code":"unknown"}
{"ts":"2026-08-16T06:45:00Z","issue":1000,"event":"phase_start","session_id":"b","phase":"code-patch","spawn_detach":"1"}
JSON
    run bash "$SCRIPT" "$EVENTS_FILE" "$RECOVERIES_FILE"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "respawn detection: a terminal event for a different (issue, phase) does not suppress the signal" {
    cat > "$EVENTS_FILE" <<'JSON'
{"ts":"2026-08-16T06:30:47Z","issue":1000,"event":"phase_start","session_id":"a","phase":"review","spawn_detach":"0"}
{"ts":"2026-08-16T06:40:01Z","issue":1000,"event":"wrapper_exit","session_id":"a","phase":"merge","exit_code":"0"}
{"ts":"2026-08-16T06:45:00Z","issue":1000,"event":"phase_start","session_id":"b","phase":"review","spawn_detach":"0"}
JSON
    run bash "$SCRIPT" "$EVENTS_FILE" "$RECOVERIES_FILE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Issue #1000, phase: review"* ]]
    [[ "$output" == *"recorded: no"* ]]
}

@test "2026-08-16 07:09Z burst: unrecorded kill detected, recorded kills marked yes, 3 signals bundled into one burst" {
    # Recorded kill 2 (Issue #1365 code-pr, Issue #1381 code-patch) + unrecorded kill 1
    # (Issue #1273 review) + 3 near-simultaneous respawns, matching the real burst this
    # Issue is derived from (docs/reports/external-kill-investigation.md 2026-08-16 07:09Z).
    cat > "$EVENTS_FILE" <<'JSON'
{"ts":"2026-08-16T06:30:47Z","issue":1273,"event":"phase_start","session_id":"58212-a","phase":"review","spawn_detach":"0"}
{"ts":"2026-08-16T07:09:24Z","issue":1273,"event":"phase_start","session_id":"58212-b","phase":"review","spawn_detach":"0"}
{"ts":"2026-08-16T06:45:34Z","issue":1365,"event":"phase_start","session_id":"78405-a","phase":"code-pr","spawn_detach":"0"}
{"ts":"2026-08-16T07:09:32Z","issue":1365,"event":"phase_start","session_id":"78405-b","phase":"code-pr","spawn_detach":"1"}
{"ts":"2026-08-16T06:46:11Z","issue":1381,"event":"phase_start","session_id":"11685-a","phase":"code-patch","spawn_detach":"0"}
{"ts":"2026-08-16T07:09:40Z","issue":1381,"event":"phase_start","session_id":"11685-b","phase":"code-patch","spawn_detach":"1"}
JSON
    cat > "$RECOVERIES_FILE" <<'MD'
---
type: report
---

# Orchestration Recovery Log

## 2026-08-16 07:10 UTC: manual-recovery-respawn

### Context
- Issue #1365, phase: code-pr
- Source: parent-session-manual-recovery

## 2026-08-16 07:11 UTC: manual-recovery-respawn

### Context
- Issue #1381, phase: code-patch
- Source: parent-session-manual-recovery
MD

    run bash "$SCRIPT" "$EVENTS_FILE" "$RECOVERIES_FILE" --window 120
    [ "$status" -eq 0 ]

    # (a) the unrecorded kill (#1273) is reported as recorded=no
    [[ "$output" == *"Issue #1273, phase: review"*"recorded: no"* ]]

    # recorded kills are correctly marked recorded=yes
    [[ "$output" == *"Issue #1365, phase: code-pr"*"recorded: yes"* ]]
    [[ "$output" == *"Issue #1381, phase: code-patch"*"recorded: yes"* ]]

    # (b) all 3 signals are bundled into a single burst of concurrency 3
    burst_lines=$(echo "$output" | grep -c "^## Burst:")
    [ "$burst_lines" -eq 1 ]
    [[ "$output" == *"concurrency=3"* ]]
}

@test "--window: respawns farther apart than window are reported as separate bursts" {
    cat > "$EVENTS_FILE" <<'JSON'
{"ts":"2026-08-16T06:30:47Z","issue":2001,"event":"phase_start","session_id":"a","phase":"review","spawn_detach":"0"}
{"ts":"2026-08-16T07:00:00Z","issue":2001,"event":"phase_start","session_id":"b","phase":"review","spawn_detach":"0"}
{"ts":"2026-08-16T06:45:34Z","issue":2002,"event":"phase_start","session_id":"c","phase":"code-pr","spawn_detach":"0"}
{"ts":"2026-08-16T07:10:00Z","issue":2002,"event":"phase_start","session_id":"d","phase":"code-pr","spawn_detach":"0"}
JSON
    run bash "$SCRIPT" "$EVENTS_FILE" "$RECOVERIES_FILE" --window 60
    [ "$status" -eq 0 ]
    burst_lines=$(echo "$output" | grep -c "^## Burst:")
    [ "$burst_lines" -eq 2 ]
    [[ "$output" == *"concurrency=1"* ]]
}
