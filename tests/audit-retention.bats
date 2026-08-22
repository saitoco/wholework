#!/usr/bin/env bats

# Tests for scripts/compute-escalation-level.sh

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/compute-escalation-level.sh"
RECOVERY_SCRIPT="$PROJECT_ROOT/scripts/collect-recovery-candidates.sh"
APPLY_RETIRE_SCRIPT="$PROJECT_ROOT/scripts/apply-verify-retire.sh"

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

# ---------------------------------------------------------------------------
# apply-verify-retire.sh (Issue #1271: phase/verify Level 3 auto-retire)
# Mocks: gh (via PATH prepend), sibling scripts (via WHOLEWORK_SCRIPT_DIR).
# WHOLEWORK_SCRIPT_DIR is exported only inside this helper, not in a global
# setup(), so the pre-existing tests above (which never call this helper)
# are unaffected.
# ---------------------------------------------------------------------------

setup_retire_mocks() {
  MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
  mkdir -p "$MOCK_DIR"
  export PATH="$MOCK_DIR:$PATH"
  export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

  cp "$PROJECT_ROOT/scripts/compute-escalation-level.sh" "$MOCK_DIR/compute-escalation-level.sh"
  cp "$PROJECT_ROOT/scripts/get-config-value.sh" "$MOCK_DIR/get-config-value.sh"

  echo '{"comments":[]}' > "$BATS_TEST_TMPDIR/fixture-comments.json"
  echo "OPEN" > "$BATS_TEST_TMPDIR/fixture-state.txt"

  cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
if [ "\$1" = "issue" ] && [ "\$2" = "view" ]; then
  if [[ "\$*" == *"--json comments"* ]]; then
    ARGS=("\$@")
    JQEXPR=""
    for i in "\${!ARGS[@]}"; do
      if [ "\${ARGS[\$i]}" = "--jq" ]; then JQEXPR="\${ARGS[\$((i+1))]}"; fi
    done
    jq -r "\$JQEXPR" "$BATS_TEST_TMPDIR/fixture-comments.json"
    exit 0
  fi
  if [[ "\$*" == *"--json state"* ]]; then
    cat "$BATS_TEST_TMPDIR/fixture-state.txt"
    exit 0
  fi
  cat "$BATS_TEST_TMPDIR/fixture-body.md"
  exit 0
fi
if [ "\$1" = "issue" ] && [ "\$2" = "close" ]; then
  echo "\$*" >> "$BATS_TEST_TMPDIR/close-calls.log"
  exit 0
fi
echo "unhandled gh call: \$*" >&2
exit 1
MOCK
  chmod +x "$MOCK_DIR/gh"

  cat > "$MOCK_DIR/gh-issue-edit.sh" <<MOCK
#!/bin/bash
cp "\$2" "$BATS_TEST_TMPDIR/new-body.md"
echo "\$*" >> "$BATS_TEST_TMPDIR/edit-calls.log"
exit 0
MOCK
  chmod +x "$MOCK_DIR/gh-issue-edit.sh"

  cat > "$MOCK_DIR/gh-issue-comment.sh" <<MOCK
#!/bin/bash
cp "\$2" "$BATS_TEST_TMPDIR/comment.md"
exit 0
MOCK
  chmod +x "$MOCK_DIR/gh-issue-comment.sh"

  cat > "$MOCK_DIR/gh-label-transition.sh" <<MOCK
#!/bin/bash
echo "\$*" >> "$BATS_TEST_TMPDIR/label-calls.log"
exit 0
MOCK
  chmod +x "$MOCK_DIR/gh-label-transition.sh"
}

no_l0_writes() {
  [ ! -f "$BATS_TEST_TMPDIR/new-body.md" ]
  [ ! -f "$BATS_TEST_TMPDIR/edit-calls.log" ]
  [ ! -f "$BATS_TEST_TMPDIR/comment.md" ]
  [ ! -f "$BATS_TEST_TMPDIR/label-calls.log" ]
  [ ! -f "$BATS_TEST_TMPDIR/close-calls.log" ]
}

# --- required case 1: Level 3 x L2/L3 -> action=retire, retire executed ---

@test "apply-verify-retire: Level 3 (dwell 90) + AUTONOMY_TIER=L2 -> action=retire, retires observation/opportunistic" {
  setup_retire_mocks
  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

- [ ] obs condition <!-- verify-type: observation event=auto-run -->
- [ ] manual condition <!-- verify-type: manual -->

## Related
BODY

  AUTONOMY_TIER=L2 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 90
  [ "$status" -eq 0 ]
  [[ "$output" == *"action=retire"* ]]
  [[ "$output" == *"retired=1"* ]]
  [[ "$output" == *"remaining=1"* ]]
  [[ "$output" == *"transitioned=false"* ]]

  [ -f "$BATS_TEST_TMPDIR/edit-calls.log" ]
  [ -f "$BATS_TEST_TMPDIR/comment.md" ]
  grep -q "type=verify-ac-retired" "$BATS_TEST_TMPDIR/comment.md"
  grep -q "### Retired Post-merge Conditions" "$BATS_TEST_TMPDIR/new-body.md"
  grep -q -- "- \[ \] manual condition" "$BATS_TEST_TMPDIR/new-body.md"
  ! grep -q "obs condition <!--" "$BATS_TEST_TMPDIR/new-body.md"
  [ ! -f "$BATS_TEST_TMPDIR/label-calls.log" ]
}

@test "apply-verify-retire: Level 3 (dwell 200) + AUTONOMY_TIER=L3 -> action=retire (tier L3 also retires)" {
  setup_retire_mocks
  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

- [ ] opp condition <!-- verify-type: opportunistic -->

## Related
BODY

  AUTONOMY_TIER=L3 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 200
  [ "$status" -eq 0 ]
  [[ "$output" == *"action=retire"* ]]
  [[ "$output" == *"retired=1"* ]]
  [[ "$output" == *"remaining=0"* ]]
  [[ "$output" == *"transitioned=true"* ]]

  [ -f "$BATS_TEST_TMPDIR/label-calls.log" ]
  grep -q "42 done" "$BATS_TEST_TMPDIR/label-calls.log"
  [ -f "$BATS_TEST_TMPDIR/close-calls.log" ]
}

# --- required case 2: Level 3 x L1 -> action=propose, no L0 writes ---

@test "apply-verify-retire: Level 3 (dwell 95) + AUTONOMY_TIER=L1 -> action=propose, no L0 writes" {
  setup_retire_mocks
  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

- [ ] obs condition <!-- verify-type: observation -->

## Related
BODY

  AUTONOMY_TIER=L1 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 95
  [ "$status" -eq 0 ]
  [ "$output" = "action=propose" ]
  no_l0_writes
}

# --- required case 3: Level <=2 -> action=none regardless of tier, no retire ---

@test "apply-verify-retire: Level 2 (dwell 89) + AUTONOMY_TIER=L3 -> action=none, no retire" {
  setup_retire_mocks
  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

- [ ] obs condition <!-- verify-type: observation -->

## Related
BODY

  AUTONOMY_TIER=L3 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 89
  [ "$status" -eq 0 ]
  [ "$output" = "action=none" ]
  no_l0_writes
}

@test "apply-verify-retire: Level 1 (dwell 30) + AUTONOMY_TIER=L2 -> action=none, no retire" {
  setup_retire_mocks
  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

- [ ] obs condition <!-- verify-type: observation -->

## Related
BODY

  AUTONOMY_TIER=L2 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 30
  [ "$status" -eq 0 ]
  [ "$output" = "action=none" ]
  no_l0_writes
}

# --- additional case: verify-type restriction (manual/auto never retired) ---

@test "apply-verify-retire: manual/auto-only Post-merge -> retired=0 (verify-type scope)" {
  setup_retire_mocks
  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

- [ ] manual condition <!-- verify-type: manual -->
- [ ] auto condition <!-- verify: command "true" -->

## Related
BODY

  AUTONOMY_TIER=L2 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 95
  [ "$status" -eq 0 ]
  [[ "$output" == *"action=retire"* ]]
  [[ "$output" == *"retired=0"* ]]
  no_l0_writes
}

# --- additional case: fenced code block sample is never a retire target ---

@test "apply-verify-retire: fenced sample checkbox is excluded from retire targets" {
  setup_retire_mocks
  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

- [ ] manual condition <!-- verify-type: manual -->
```
- [ ] sample fenced checkbox <!-- verify-type: observation -->
```

## Related
BODY

  AUTONOMY_TIER=L2 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 95
  [ "$status" -eq 0 ]
  [[ "$output" == *"retired=0"* ]]
  no_l0_writes
}

# --- additional case: idempotency (0 target on a re-run) ---

@test "apply-verify-retire: already-retired issue (0 unchecked observation/opportunistic) -> retired=0, idempotent" {
  setup_retire_mocks
  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

すべての post-merge 条件は #1271 の自動 retire で退避済み (下記 `### Retired Post-merge Conditions` を参照)。

### Retired Post-merge Conditions

- ~~obs condition~~ — **retired (auto, dwell 90d)**: 90 日間 event が発火せず、または発火しても判定に至らなかった (verify-type: observation, 最終 dispatch: none)

## Related
BODY

  AUTONOMY_TIER=L2 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 120
  [ "$status" -eq 0 ]
  [[ "$output" == *"retired=0"* ]]
  no_l0_writes
}

# --- additional case: fail-closed when compute-escalation-level.sh fails ---

@test "apply-verify-retire: compute-escalation-level.sh failure -> fail-closed action=none" {
  setup_retire_mocks
  cat > "$MOCK_DIR/compute-escalation-level.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
  chmod +x "$MOCK_DIR/compute-escalation-level.sh"

  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

- [ ] obs condition <!-- verify-type: observation -->

## Related
BODY

  AUTONOMY_TIER=L3 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 95
  [ "$status" -eq 0 ]
  [[ "$output" == *"action=none"* ]]
  [[ "$output" == *"Warning: compute-escalation-level.sh failed"* ]]
  no_l0_writes
}

# --- additional case: argument validation ---

@test "apply-verify-retire: missing --issue exits 1" {
  run bash "$APPLY_RETIRE_SCRIPT" --dwell 90
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error"* ]]
}

@test "apply-verify-retire: non-numeric --dwell exits 1" {
  run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error"* ]]
}

@test "apply-verify-retire: unknown option exits 1" {
  run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 90 --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Error: unknown option"* ]]
}

# --- additional case: body write-back failure is fail-open, no comment/label ---

@test "apply-verify-retire: gh-issue-edit.sh failure -> fail-open, no comment/label transition" {
  setup_retire_mocks
  cat > "$MOCK_DIR/gh-issue-edit.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
  chmod +x "$MOCK_DIR/gh-issue-edit.sh"

  cat > "$BATS_TEST_TMPDIR/fixture-body.md" <<'BODY'
## Acceptance Criteria

### Post-merge

- [ ] obs condition <!-- verify-type: observation -->

## Related
BODY

  AUTONOMY_TIER=L2 run bash "$APPLY_RETIRE_SCRIPT" --issue 42 --dwell 95
  [ "$status" -eq 0 ]
  [[ "$output" == *"action=retire"* ]]
  [[ "$output" == *"retired=0"* ]]
  [ ! -f "$BATS_TEST_TMPDIR/comment.md" ]
  [ ! -f "$BATS_TEST_TMPDIR/label-calls.log" ]
}
