#!/usr/bin/env bats
# Tests for scripts/validate-recovery-plan.sh
# Bash 3.2+ compatible (no associative arrays, no mapfile)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/validate-recovery-plan.sh"

setup() {
  PLAN_FILE="$BATS_TEST_TMPDIR/plan.json"
}

@test "orchestration-recovery: valid plan with retry action passes" {
  echo '{"action":"retry","rationale":"transient failure, retry safe","steps":[]}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 0 ]
}

@test "orchestration-recovery: valid plan with abort action passes" {
  echo '{"action":"abort","rationale":"unrecoverable state","steps":[]}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 0 ]
}

@test "orchestration-recovery: missing action key fails" {
  echo '{"rationale":"no action key","steps":[]}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 1 ]
}

@test "orchestration-recovery: missing rationale key fails" {
  echo '{"action":"skip","steps":[]}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 1 ]
}

@test "orchestration-recovery: missing steps key fails" {
  echo '{"action":"recover","rationale":"push branch"}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 1 ]
}

@test "orchestration-recovery: invalid action value fails" {
  echo '{"action":"destroy","rationale":"bad action","steps":[]}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 1 ]
}

@test "orchestration-recovery: forbidden op force_push fails" {
  echo '{"action":"recover","rationale":"push fix","steps":[{"op":"force_push","detail":"origin main"}]}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 1 ]
}

@test "orchestration-recovery: forbidden op reset_hard fails" {
  echo '{"action":"recover","rationale":"reset attempt","steps":[{"op":"reset_hard","detail":"HEAD~1"}]}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 1 ]
}

@test "orchestration-recovery: step count exceeds limit fails" {
  echo '{"action":"recover","rationale":"too many steps","steps":[{"op":"push_branch"},{"op":"create_pr"},{"op":"transition_label"},{"op":"extract_pr_number"},{"op":"wait_ci"},{"op":"noop"}]}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 1 ]
}

@test "orchestration-recovery: empty steps array passes" {
  echo '{"action":"skip","rationale":"phase already complete","steps":[]}' > "$PLAN_FILE"
  run bash "$SCRIPT" "$PLAN_FILE"
  [ "$status" -eq 0 ]
}
