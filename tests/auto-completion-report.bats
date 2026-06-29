#!/usr/bin/env bats

# Tests for /auto --batch Completion Report: pending manual confirmation section (Issue #823)
# Structural tests: verify that skills/auto/SKILL.md contains required content
# in the "### Batch Completion Report" section.

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/auto/SKILL.md"

# Extract the "### Batch Completion Report" section from SKILL.md.
# The section ends at the next level-2 (## ) heading (## Notes).
batch_completion_section() {
    awk '/^### Batch Completion Report/{found=1} /^## / && !/Batch Completion Report/{found=0} found{print}' "$SKILL_FILE"
}

@test "Batch Completion Report: Pending manual confirmation block present" {
    batch_completion_section | grep -q "Pending manual confirmation"
}

@test "Batch Completion Report: verify-type classification present" {
    batch_completion_section | grep -q "verify-type"
}

@test "Batch Completion Report: phase/verify label check present" {
    batch_completion_section | grep -q "phase/verify"
}

@test "Batch Completion Report: Recommended next action guidance present" {
    batch_completion_section | grep -q "Recommended next action"
}
