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

@test "exclusion: filed improvement candidate mark -> only entries after the filed entry are counted" {
  # No --issues-json is passed, so the degrade path applies: the group's own latest
  # 起票済み entry timestamp (2026-06-02) becomes the cutoff. Entries at or before it
  # (06-01, 06-02) are excluded; only the 06-03 entry -- filed after the fix -- is counted.
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
  echo "$output" | grep -E $'^repeated-symptom\t1$'
}

@test "entry-unit exclusion: closed issue -- entries after closedAt are counted" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: post-close-recurrence

- Cause: occurrence before the fix (excluded)

## 2026-06-05 10:00 UTC: post-close-recurrence

- Cause: first recurrence after the fix

## 2026-06-06 10:00 UTC: post-close-recurrence

- Cause: second recurrence after the fix

## 2026-06-07 10:00 UTC: post-close-recurrence

- Cause: third recurrence after the fix

FIXTURE_EOF

  ISSUES_JSON_FILE="$BATS_TEST_TMPDIR/issues.json"
  cat > "$ISSUES_JSON_FILE" << 'JSON_EOF'
[{"number": 500, "title": "recoveries: post-close-recurrence", "state": "CLOSED", "closedAt": "2026-06-03T00:00:00Z"}]
JSON_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3 --issues-json "$ISSUES_JSON_FILE"
  [ "$status" -eq 0 ]
  # Only the 3 post-closedAt entries count -- the pre-closedAt entry is dropped, so the
  # group clears the threshold on recurrence alone, not on the original occurrence.
  echo "$output" | grep -E $'^post-close-recurrence\t3$'
}

@test "entry-unit exclusion: an entry auto-stamped with the filed marker by run-auto-sub.sh's closed-issue fallback is still counted when it falls after closedAt" {
  # run-auto-sub.sh's _find_known_recoveries_issue() resolves closed issues too (open ->
  # closed fallback), so a genuinely new post-fix entry can be auto-stamped 起票済み #N even
  # though the symptom already recurred. The 起票済み marker must NOT by itself exclude the
  # entry -- only its timestamp relative to closedAt decides that (Issue #1152 AC #2).
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: stamped-recurrence

- 起票済み #600
- Cause: occurrence that triggered the original filing (excluded, before closedAt)

## 2026-06-10 10:00 UTC: stamped-recurrence

- 起票済み #600
- Cause: first recurrence after the fix (auto-stamped by run-auto-sub.sh, but still new)

## 2026-06-11 10:00 UTC: stamped-recurrence

- 起票済み #600
- Cause: second recurrence after the fix

## 2026-06-12 10:00 UTC: stamped-recurrence

- 起票済み #600
- Cause: third recurrence after the fix

FIXTURE_EOF

  ISSUES_JSON_FILE="$BATS_TEST_TMPDIR/issues.json"
  cat > "$ISSUES_JSON_FILE" << 'JSON_EOF'
[{"number": 600, "title": "recoveries: stamped-recurrence", "state": "CLOSED", "closedAt": "2026-06-03T00:00:00Z"}]
JSON_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3 --issues-json "$ISSUES_JSON_FILE"
  [ "$status" -eq 0 ]
  # All 4 entries carry 起票済み #600, yet the 3 entries after closedAt are still counted --
  # proving the cutoff, not the marker, drives exclusion.
  echo "$output" | grep -E $'^stamped-recurrence\t3$'
}

@test "entry-unit exclusion: closed issue -- entries at or before closedAt are excluded" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: pre-close-only

- Cause: first occurrence

## 2026-06-02 10:00 UTC: pre-close-only

- Cause: second occurrence

## 2026-06-03 10:00 UTC: pre-close-only

- Cause: third occurrence

FIXTURE_EOF

  ISSUES_JSON_FILE="$BATS_TEST_TMPDIR/issues.json"
  cat > "$ISSUES_JSON_FILE" << 'JSON_EOF'
[{"number": 501, "title": "recoveries: pre-close-only", "state": "CLOSED", "closedAt": "2026-06-10T00:00:00Z"}]
JSON_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 1 --issues-json "$ISSUES_JSON_FILE"
  [ "$status" -eq 0 ]
  # All 3 entries predate closedAt, so nothing clears even threshold=1 -- the resolved
  # symptom does not resurface just because its fix Issue exists.
  [ -z "$output" ]
}

@test "entry-unit exclusion: open issue -- every entry in the group is excluded" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: open-issue-symptom

- Cause: first occurrence

## 2026-06-02 10:00 UTC: open-issue-symptom

- Cause: second occurrence

## 2026-06-03 10:00 UTC: open-issue-symptom

- Cause: third occurrence

FIXTURE_EOF

  ISSUES_JSON_FILE="$BATS_TEST_TMPDIR/issues.json"
  cat > "$ISSUES_JSON_FILE" << 'JSON_EOF'
[{"number": 502, "title": "recoveries: open-issue-symptom", "state": "OPEN", "closedAt": ""}]
JSON_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 1 --issues-json "$ISSUES_JSON_FILE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--with-tracking: appends tracked:#N / untracked as a 3rd column; default output is unchanged" {
  cat > "$RECOVERY_FILE" << 'FIXTURE_EOF'
## 2026-06-01 10:00 UTC: tracked-symptom

- Cause: first

## 2026-06-02 10:00 UTC: tracked-symptom

- Cause: second

## 2026-06-03 10:00 UTC: tracked-symptom

- Cause: third

## 2026-06-01 10:00 UTC: untracked-symptom

- Cause: first

## 2026-06-02 10:00 UTC: untracked-symptom

- Cause: second

## 2026-06-03 10:00 UTC: untracked-symptom

- Cause: third

FIXTURE_EOF

  ISSUES_JSON_FILE="$BATS_TEST_TMPDIR/issues.json"
  cat > "$ISSUES_JSON_FILE" << 'JSON_EOF'
[{"number": 503, "title": "recoveries: tracked-symptom", "state": "CLOSED", "closedAt": "2026-05-01T00:00:00Z"}]
JSON_EOF

  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3 --issues-json "$ISSUES_JSON_FILE" --with-tracking
  [ "$status" -eq 0 ]
  echo "$output" | grep -E $'^tracked-symptom\t3\ttracked:#503$'
  echo "$output" | grep -E $'^untracked-symptom\t3\tuntracked$'

  # Default (no --with-tracking): output stays the 2-column <group-key>\t<count> format.
  run bash "$SCRIPT" "$RECOVERY_FILE" --threshold 3 --issues-json "$ISSUES_JSON_FILE"
  [ "$status" -eq 0 ]
  echo "$output" | grep -E $'^tracked-symptom\t3$'
  echo "$output" | grep -E $'^untracked-symptom\t3$'
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
[{"number": 999, "title": "recoveries: manual-recovery-review-rerun/dirty-guard", "state": "OPEN", "closedAt": ""}]
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
[{"number": 999, "title": "recoveries: manual-recovery-review-rerun", "state": "OPEN", "closedAt": ""}]
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
