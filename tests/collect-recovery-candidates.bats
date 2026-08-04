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

@test "cause grouping: same symptom with 2 distinct causes -> counted and grouped separately" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: manual-recovery-review-rerun

### Diagnosis
- cause: dirty-guard
- first dirty-guard occurrence

## 2026-06-02 10:00 UTC: manual-recovery-review-rerun

### Diagnosis
- cause: dirty-guard
- second dirty-guard occurrence

## 2026-06-03 10:00 UTC: manual-recovery-review-rerun

### Diagnosis
- cause: workflow-wait
- first workflow-wait occurrence

## 2026-06-04 10:00 UTC: manual-recovery-review-rerun

### Diagnosis
- cause: workflow-wait
- second workflow-wait occurrence

FIXTURE_EOF

  # threshold=2: each cause-specific group meets the threshold on its own.
  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 2
  [ "$status" -eq 0 ]
  echo "$output" | grep -E $'^manual-recovery-review-rerun/dirty-guard\t2$'
  echo "$output" | grep -E $'^manual-recovery-review-rerun/workflow-wait\t2$'
  # The plain (cause-less) symptom-short key never appears -- every entry in this fixture
  # carries a cause line, so counts are never merged into the bare symptom-short.
  ! echo "$output" | grep -E $'^manual-recovery-review-rerun\t'

  # threshold=3: merged (4) would clear the bar, but each cause-specific group (2) does not --
  # this proves cause-separation, not merging, is what determines inclusion.
  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "cause grouping: entries without a cause line keep the plain symptom-short key (backward compat)" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: manual-recovery-push-only

### Diagnosis
- Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: push-only)

## 2026-06-02 10:00 UTC: manual-recovery-push-only

### Diagnosis
- Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: push-only)

## 2026-06-03 10:00 UTC: manual-recovery-push-only

### Diagnosis
- Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: push-only)

FIXTURE_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3
  [ "$status" -eq 0 ]
  echo "$output" | grep -E $'^manual-recovery-push-only\t3$'
}

@test "duplicate check: bare group-key not excluded by a cause-suffixed sibling issue title" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: manual-recovery-review-rerun

- Cause: first occurrence (no cause line)

## 2026-06-02 10:00 UTC: manual-recovery-review-rerun

- Cause: second occurrence (no cause line)

## 2026-06-03 10:00 UTC: manual-recovery-review-rerun

- Cause: third occurrence (no cause line)

FIXTURE_EOF

  ISSUES_JSON_FILE="$BATS_TEST_TMPDIR/issues.json"
  cat > "$ISSUES_JSON_FILE" << 'JSON_EOF'
[{"number": 999, "title": "recoveries: manual-recovery-review-rerun/dirty-guard"}]
JSON_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3 --issues-json "$ISSUES_JSON_FILE"
  [ "$status" -eq 0 ]
  # The bare group-key must still appear -- it must NOT be treated as a duplicate of
  # the cause-suffixed sibling title just because it is a string prefix of it.
  echo "$output" | grep -E $'^manual-recovery-review-rerun\t3$'
}

@test "duplicate check: bare group-key IS excluded by an exact-matching issue title" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: manual-recovery-review-rerun

- Cause: first occurrence

## 2026-06-02 10:00 UTC: manual-recovery-review-rerun

- Cause: second occurrence

## 2026-06-03 10:00 UTC: manual-recovery-review-rerun

- Cause: third occurrence

FIXTURE_EOF

  ISSUES_JSON_FILE="$BATS_TEST_TMPDIR/issues.json"
  cat > "$ISSUES_JSON_FILE" << 'JSON_EOF'
[{"number": 999, "title": "recoveries: manual-recovery-review-rerun"}]
JSON_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3 --issues-json "$ISSUES_JSON_FILE"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF "manual-recovery-review-rerun"
}

@test "wrapper-retry-on-kill: H2 entries detected by frequency parser" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: wrapper-retry-on-kill

### Context
- Issue #100, phase: code-patch
- Source: retry-on-kill.sh
- Wrapper: run-code.sh, exit code: 0

### Outcome
- success

## 2026-06-02 10:00 UTC: wrapper-retry-on-kill

### Context
- Issue #200, phase: code-pr
- Source: retry-on-kill.sh
- Wrapper: run-code.sh, exit code: 0

### Outcome
- success

## 2026-06-03 10:00 UTC: wrapper-retry-on-kill

### Context
- Issue #300, phase: review
- Source: retry-on-kill.sh
- Wrapper: run-review.sh, exit code: 0

### Outcome
- success

FIXTURE_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3
  [ "$status" -eq 0 ]
  echo "$output" | grep -E $'^wrapper-retry-on-kill\t3$'
}
