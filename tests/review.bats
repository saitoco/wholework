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

# Extract the "## Step 8: Static Acceptance Criteria Verification" section from SKILL.md.
# The section ends at the next level-2 (## ) heading (## Step 9: CI Status Check).
step8_section() {
    awk '/^## Step 8: Static Acceptance Criteria Verification/{found=1} /^## Step 9/{found=0} found{print}' "$SKILL_FILE"
}

# Extract the "## Step 9: CI Status Check" section from SKILL.md.
# The section ends at the next level-2 (## ) heading (## Step 10: Multi-perspective Code Review).
step9_section() {
    awk '/^## Step 9: CI Status Check/{found=1} /^## Step 10/{found=0} found{print}' "$SKILL_FILE"
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

@test "Opportunistic Verification: worktree exit precondition is asserted" {
    opportunistic_verification_section | grep -q -F "detect-foreign-worktree.sh"
}

@test "Opportunistic Verification: all three worktree contexts are enumerated" {
    opportunistic_verification_section | grep -q "none"
    opportunistic_verification_section | grep -q "own"
    opportunistic_verification_section | grep -q "foreign"
}

@test "Worktree Exit section precedes Opportunistic Verification" {
    exit_line=$(grep -n -F "## Worktree Exit (push-and-remove)" "$SKILL_FILE" | head -1 | cut -d: -f1)
    verify_line=$(grep -n -F "## Opportunistic Verification" "$SKILL_FILE" | head -1 | cut -d: -f1)
    [ -n "$exit_line" ]
    [ -n "$verify_line" ]
    [ "$exit_line" -lt "$verify_line" ]
}

@test "Step 8: FAIL Blocking Behavior heading and REQUEST_CHANGES mentioned" {
    step8_section | grep -q "FAIL Blocking Behavior"
    step8_section | grep -q "REQUEST_CHANGES"
}

@test "Step 8: preview-ac-unverified marker posts on every run, not only when UNCERTAIN set is non-empty" {
    step8_section | grep -q -F "type=preview-ac-unverified"
    step8_section | grep -q -F "post this marker on every run of this step"
}

@test "Step 8: preview-ac-unverified marker documents the ac=none sentinel" {
    step8_section | grep -q -F "the literal none when the set is empty"
}

@test "Step 9: Blocking by default mentioned" {
    step9_section | grep -q "Blocking by default"
}
