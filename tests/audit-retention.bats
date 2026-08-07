#!/usr/bin/env bats

# Tests for scripts/compute-escalation-level.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/compute-escalation-level.sh"
RECOVERY_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/collect-recovery-candidates.sh"

# --- verify type ---

@test "verify: 29 days returns level 0" {
  run bash "$SCRIPT" verify 29
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "verify: 30 days returns level 1" {
  run bash "$SCRIPT" verify 30
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "verify: 59 days returns level 1" {
  run bash "$SCRIPT" verify 59
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "verify: 60 days returns level 2" {
  run bash "$SCRIPT" verify 60
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "verify: 89 days returns level 2" {
  run bash "$SCRIPT" verify 89
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "verify: 90 days returns level 3" {
  run bash "$SCRIPT" verify 90
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "verify: 0 days returns level 0" {
  run bash "$SCRIPT" verify 0
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# --- icebox type ---

@test "icebox: 89 days returns level 0" {
  run bash "$SCRIPT" icebox 89
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "icebox: 90 days returns level 1" {
  run bash "$SCRIPT" icebox 90
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "icebox: 179 days returns level 1" {
  run bash "$SCRIPT" icebox 179
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "icebox: 180 days returns level 2" {
  run bash "$SCRIPT" icebox 180
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "icebox: 0 days returns level 0" {
  run bash "$SCRIPT" icebox 0
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# --- error handling ---

@test "invalid type exits with status 1" {
  run bash "$SCRIPT" unknown 10
  [ "$status" -eq 1 ]
}

@test "missing arguments exits with status 1" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

@test "non-numeric days exits with status 1" {
  run bash "$SCRIPT" verify abc
  [ "$status" -eq 1 ]
}

# --- Section 10: Recovery Candidate Frequency (--issues-json consumption) ---

@test "Section 10 collector call: closed-tracked group-key surfaces as Recurring after fix" {
  RECOVERY_FILE="$BATS_TEST_TMPDIR/recovery.md"
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: manual-recovery-respawn

- Cause: first

## 2026-06-02 10:00 UTC: manual-recovery-respawn

- Cause: second

## 2026-06-03 10:00 UTC: manual-recovery-respawn

- Cause: third

FIXTURE_EOF

  ISSUES_JSON_FILE="$BATS_TEST_TMPDIR/audit-recovery-issues.json"
  cat > "$ISSUES_JSON_FILE" << 'JSON_EOF'
[{"number": 1014, "title": "recoveries: manual-recovery-respawn", "state": "CLOSED", "closedAt": "2026-05-01T00:00:00Z"}]
JSON_EOF

  # Same invocation shape as skills/audit/SKILL.md Section 10 step 2:
  # --threshold 1 --with-tracking --issues-json <all-state issues file>.
  run bash "$RECOVERY_SCRIPT" "$RECOVERY_FILE" --threshold 1 --with-tracking --issues-json "$ISSUES_JSON_FILE"
  [ "$status" -eq 0 ]
  # 3rd column must be tracked:#1014:closed (not the degrade-path bare "tracked:#1014")
  # so Section 10 step 4's "Recurring after fix" metric counts this group-key.
  echo "$output" | grep -E $'^manual-recovery-respawn\t3\ttracked:#1014:closed$'
}
