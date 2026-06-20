#!/usr/bin/env bats

# Direct unit tests for scripts/collect-recovery-candidates.sh
# Covers: empty log, below-threshold skip, filed-mark exclusion, normal detection.
# All tests use inline fixtures via BATS_TEST_TMPDIR (no external fixture dependencies).

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/collect-recovery-candidates.sh"

setup() {
  RECOVERY_FILE="$BATS_TEST_TMPDIR/recovery.md"
}

@test "empty log: no entries -> empty output and exit 0" {
  touch "$RECOVERY_FILE"

  run bash "$SCRIPT" "$RECOVERY_FILE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "below threshold: single entry count=1 with threshold=3 -> no output" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: some-symptom-short

- Cause: something happened
- Recovery: fix applied

FIXTURE_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "exclusion: filed improvement candidate mark -> symptom excluded from output" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: repeated-symptom

- Cause: first occurrence

## 2026-06-02 10:00 UTC: repeated-symptom

- 起票済み #123
- Cause: second occurrence (filed)

## 2026-06-03 10:00 UTC: repeated-symptom

- Cause: third occurrence

FIXTURE_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 1
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF "repeated-symptom"
}

@test "normal detection: count >= threshold and no exclusion -> appears in output" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: target-symptom

- Cause: first

## 2026-06-02 10:00 UTC: target-symptom

- Cause: second

## 2026-06-03 10:00 UTC: target-symptom

- Cause: third

FIXTURE_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "target-symptom"
  echo "$output" | grep -E $'^target-symptom\t3$'
}
