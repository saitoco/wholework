#!/usr/bin/env bats

# Shallow tests for operate route documentation (Issue #995).
# LLM responses are not mocked; tests confirm that the operate route branch
# is documented in the relevant modules/skills, following the same
# "grep the module documentation" pattern as tests/size-workflow-table.bats.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SIZE_WORKFLOW_TABLE="$PROJECT_ROOT/modules/size-workflow-table.md"
SPEC_SKILL="$PROJECT_ROOT/skills/spec/SKILL.md"
CODE_SKILL="$PROJECT_ROOT/skills/code/SKILL.md"
AUTO_SKILL="$PROJECT_ROOT/skills/auto/SKILL.md"
AUTONOMY_TIER="$PROJECT_ROOT/modules/autonomy-tier.md"
PHASE_STATE="$PROJECT_ROOT/modules/phase-state.md"

@test "size-workflow-table: operate route is documented" {
    grep -q "operate route" "$SIZE_WORKFLOW_TABLE"
}

@test "size-workflow-table: diff-less axis is orthogonal to Size" {
    grep -qi "orthogonal" "$SIZE_WORKFLOW_TABLE"
}

@test "spec skill: ROUTE=operate determination is documented" {
    grep -q "ROUTE=operate" "$SPEC_SKILL"
}

@test "code skill: operate route execution branch is documented" {
    grep -q "Operate Route: External Operation Execution" "$CODE_SKILL"
}

@test "code skill: operate route execution log is documented" {
    grep -q "Operate Route: Execution Log" "$CODE_SKILL"
}

@test "auto skill: operate route is documented in Route-Phase Matrix" {
    grep -q "operate (diff-less)" "$AUTO_SKILL"
}

@test "autonomy-tier: operate route external system write gate is documented" {
    grep -q "External System Write (operate route)" "$AUTONOMY_TIER"
}

@test "phase-state: operate route completion signature is documented (Issue #998)" {
    grep -q "Operate Route Completion Signature" "$PHASE_STATE"
}

@test "code skill: L1 advisory execution-plan marker feeds the completion signature (Issue #998)" {
    grep -q "type=execution-plan" "$CODE_SKILL"
}
