#!/usr/bin/env bats

# Direct unit tests for scripts/validate-recovery-plan.sh
# Covers all 5 safety checks: valid plan, missing required key, action enum,
# forbidden op, and steps length limit. Also covers invalid JSON input.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/validate-recovery-plan.sh"

@test "valid plan: all safety checks pass -> exit 0" {
  run bash "$SCRIPT" <<< '{"action":"skip","rationale":"nothing to do","steps":[]}'
  [ "$status" -eq 0 ]
}

@test "missing required key: no action field -> exit 1" {
  run bash "$SCRIPT" <<< '{"rationale":"test","steps":[]}'
  [ "$status" -ne 0 ]
}

@test "action enum: unrecognized value -> exit 1" {
  run bash "$SCRIPT" <<< '{"action":"destroy","rationale":"test","steps":[]}'
  [ "$status" -ne 0 ]
}

@test "forbidden op: force_push in op field -> exit 1" {
  run bash "$SCRIPT" <<< '{"action":"recover","rationale":"test","steps":[{"op":"force_push","description":"push"}]}'
  [ "$status" -ne 0 ]
}

@test "steps limit exceeded: 6 entries -> exit 1" {
  run bash "$SCRIPT" <<< '{"action":"retry","rationale":"test","steps":[{"op":"log"},{"op":"log"},{"op":"log"},{"op":"log"},{"op":"log"},{"op":"log"}]}'
  [ "$status" -ne 0 ]
}

@test "invalid JSON: not parseable -> exit 1" {
  run bash "$SCRIPT" <<< 'not-valid-json'
  [ "$status" -ne 0 ]
}
