#!/usr/bin/env bats

# Tests for /verify Step 2 base branch checkout worktree context guard (Issue #1000)
# Structural tests: verify that skills/verify/SKILL.md Step 2 runs the
# foreign-worktree guard ahead of the base branch checkout.

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/verify/SKILL.md"

# Extract the "### Step 2: Detect and Update Base Branch" section from SKILL.md.
# The section ends at the next level-3 (### Step ) heading.
step2_section() {
    awk '/^### Step 2: Detect and Update Base Branch/{found=1} /^### Step / && !/Step 2: Detect and Update Base Branch/{found=0} found{print}' "$SKILL_FILE"
}

@test "Step 2 guard: detect-foreign-worktree.sh runs before base branch checkout" {
    guard_line=$(step2_section | grep -n -F "detect-foreign-worktree.sh" | head -1 | cut -d: -f1)
    checkout_line=$(step2_section | grep -n -F 'git checkout "${BASE_BRANCH}"' | head -1 | cut -d: -f1)
    [ -n "$guard_line" ]
    [ -n "$checkout_line" ]
    [ "$guard_line" -lt "$checkout_line" ]
}

@test "Step 2 guard: all three worktree contexts are enumerated" {
    step2_section | grep -q "none"
    step2_section | grep -q "own"
    step2_section | grep -q "foreign"
}

@test "Step 2 guard: foreign branch exits the caller worktree session" {
    step2_section | grep -q -F 'ExitWorktree(action: "keep")'
}

@test "Step 2 guard: foreign branch skips checkout and pull" {
    step2_section | grep -q -F "do not run"
    step2_section | grep -q -F "git checkout"
}
