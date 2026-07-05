#!/usr/bin/env bats

# Tests for /review Opportunistic Verification --context-file wiring (Issue #942)
# Structural tests: verify that skills/review/SKILL.md contains the required
# --context-file wiring in the "## Opportunistic Verification" section.

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/review/SKILL.md"

# Extract the "## Opportunistic Verification" section from SKILL.md.
# The section ends at the next level-2 (## ) heading (## Completion Report).
opportunistic_verification_section() {
    awk '/^## Opportunistic Verification/{found=1} /^## / && !/Opportunistic Verification/{found=0} found{print}' "$SKILL_FILE"
}

@test "Opportunistic Verification: DESIGN_FILE_PATH resolution present" {
    opportunistic_verification_section | grep -q "DESIGN_FILE_PATH"
}

@test "Opportunistic Verification: pr-review-full call passes --context-file" {
    opportunistic_verification_section | grep -q -- "--event pr-review-full --context-file"
}

@test "Opportunistic Verification: pr-review-light call passes --context-file" {
    opportunistic_verification_section | grep -q -- "--event pr-review-light --context-file"
}
