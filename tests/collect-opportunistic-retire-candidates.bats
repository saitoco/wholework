#!/usr/bin/env bats

# Direct unit tests for scripts/collect-opportunistic-retire-candidates.sh
# Covers: missing SESSIONS_DIR, trailing-SKIP-streak detection, PASS/FAIL reset,
# threshold filtering, sort order, and non-target event filtering.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/collect-opportunistic-retire-candidates.sh"

setup() {
  SESSIONS_DIR="$BATS_TEST_TMPDIR/sessions"
}

_write_events() {
  local session="$1" file="$2"
  mkdir -p "$SESSIONS_DIR/$session"
  cat > "$SESSIONS_DIR/$session/events.jsonl"
}

@test "missing SESSIONS_DIR -> empty output and exit 0" {
  run bash "$SCRIPT" "$SESSIONS_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "empty SESSIONS_DIR (no events.jsonl) -> empty output and exit 0" {
  mkdir -p "$SESSIONS_DIR"
  run bash "$SCRIPT" "$SESSIONS_DIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "single group, all SKIP, count >= threshold -> included in output" {
  _write_events "session-a" << 'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":100,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"3"}
{"ts":"2026-08-02T10:00:00Z","issue":100,"event":"opportunistic_verify_result","skill":"/code","result":"SKIP","ac_index":"3"}
{"ts":"2026-08-03T10:00:00Z","issue":100,"event":"opportunistic_verify_result","skill":"/review","result":"SKIP","ac_index":"3"}
FIXTURE_EOF

  run bash "$SCRIPT" "$SESSIONS_DIR" --threshold 3
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE $'^100\t3\t/review\t3\t3$'
}

@test "trailing SKIP reset by a later PASS -> trailing_skip is 0 and excluded even at threshold 1" {
  _write_events "session-a" << 'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":200,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"5"}
{"ts":"2026-08-02T10:00:00Z","issue":200,"event":"opportunistic_verify_result","skill":"/code","result":"SKIP","ac_index":"5"}
{"ts":"2026-08-03T10:00:00Z","issue":200,"event":"opportunistic_verify_result","skill":"/review","result":"PASS","ac_index":"5"}
FIXTURE_EOF

  run bash "$SCRIPT" "$SESSIONS_DIR" --threshold 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "trailing SKIP reset by a later FAIL -> trailing_skip is 0 and excluded" {
  _write_events "session-a" << 'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":201,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"1"}
{"ts":"2026-08-02T10:00:00Z","issue":201,"event":"opportunistic_verify_result","skill":"/code","result":"FAIL","ac_index":"1"}
FIXTURE_EOF

  run bash "$SCRIPT" "$SESSIONS_DIR" --threshold 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "below --threshold -> excluded from output" {
  _write_events "session-a" << 'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":300,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"2"}
{"ts":"2026-08-02T10:00:00Z","issue":300,"event":"opportunistic_verify_result","skill":"/code","result":"SKIP","ac_index":"2"}
FIXTURE_EOF

  run bash "$SCRIPT" "$SESSIONS_DIR" --threshold 5
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "multiple groups -> sorted by trailing_skip_count descending" {
  _write_events "session-a" << 'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":400,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"1"}
{"ts":"2026-08-02T10:00:00Z","issue":400,"event":"opportunistic_verify_result","skill":"/code","result":"SKIP","ac_index":"1"}
{"ts":"2026-08-01T10:00:00Z","issue":401,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"1"}
{"ts":"2026-08-02T10:00:00Z","issue":401,"event":"opportunistic_verify_result","skill":"/code","result":"SKIP","ac_index":"1"}
{"ts":"2026-08-03T10:00:00Z","issue":401,"event":"opportunistic_verify_result","skill":"/review","result":"SKIP","ac_index":"1"}
{"ts":"2026-08-04T10:00:00Z","issue":401,"event":"opportunistic_verify_result","skill":"/verify","result":"SKIP","ac_index":"1"}
FIXTURE_EOF

  run bash "$SCRIPT" "$SESSIONS_DIR" --threshold 1
  [ "$status" -eq 0 ]
  first_line="$(echo "$output" | sed -n '1p')"
  second_line="$(echo "$output" | sed -n '2p')"
  echo "$first_line" | grep -qE $'^401\t1\t/verify\t4\t4$'
  echo "$second_line" | grep -qE $'^400\t1\t/code\t2\t2$'
}

@test "non-target events mixed in the log are ignored" {
  _write_events "session-a" << 'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":500,"event":"phase_start","skill":"/spec"}
{"ts":"2026-08-01T10:00:01Z","issue":500,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"1"}
{"ts":"2026-08-01T10:00:02Z","issue":500,"event":"phase_complete","skill":"/spec"}
FIXTURE_EOF

  run bash "$SCRIPT" "$SESSIONS_DIR" --threshold 1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE $'^500\t1\t/spec\t1\t1$'
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "--threshold=N equals form is accepted" {
  _write_events "session-a" << 'FIXTURE_EOF'
{"ts":"2026-08-01T10:00:00Z","issue":600,"event":"opportunistic_verify_result","skill":"/spec","result":"SKIP","ac_index":"1"}
FIXTURE_EOF

  run bash "$SCRIPT" "$SESSIONS_DIR" --threshold=1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE $'^600\t1\t/spec\t1\t1$'
}
