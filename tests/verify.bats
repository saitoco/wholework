#!/usr/bin/env bats

# Tests for /verify Step 2 base branch checkout worktree context guard (Issue #1000)
# Structural tests: verify that skills/verify/SKILL.md Step 2 runs the
# foreign-worktree guard ahead of the base branch checkout.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SKILL_FILE="$PROJECT_ROOT/skills/verify/SKILL.md"

# Extract the "### Step 2: Detect and Update Base Branch" section from SKILL.md.
# The section ends at the next level-3 (### Step ) heading.
step2_section() {
    awk '/^### Step 2: Detect and Update Base Branch/{found=1} /^### Step / && !/Step 2: Detect and Update Base Branch/{found=0} found{print}' "$SKILL_FILE"
}

# Extract the "### Step 5: Verify Each Condition (Pre-merge Only)" section from SKILL.md.
# The section ends at the next level-3 (### Step ) heading.
step5_section() {
    awk '/^### Step 5: /{found=1} /^### Step / && !/Step 5: /{found=0} found{print}' "$SKILL_FILE"
}

# Extract the "#### Step 8c: Observation Post-merge Conditions" section from SKILL.md.
# The section ends at the next heading (level-3 or level-4).
step8c_section() {
    awk '/^#### Step 8c: /{found=1} (/^#### / || /^### /) && !/Step 8c: /{found=0} found{print}' "$SKILL_FILE"
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

@test "Step 5 pre-merge-preview AC skip rule delegates to resolve-preview-ac-fallback.sh" {
    step5_section | grep -q -F "resolve-preview-ac-fallback.sh"
}

@test "Step 5 pre-merge-preview AC skip rule documents latest-wins resolution" {
    step5_section | grep -q -F "latest-wins"
}

@test "Step 5 pre-merge-preview AC skip rule applies to manual subcase without automatic fallback" {
    step5_section | grep -q -F "verify-type: manual"
    step5_section | grep -q -F "no automatic fallback exists"
}

@test "Step 5 pre-merge-preview AC skip rule checks for a Review Response Summary via reconcile-phase-state.sh" {
    step5_section | grep -q -F "Review Response Summary"
    step5_section | grep -q -F "reconcile-phase-state.sh"
}

@test "Step 8c: fired observation ACs are evaluated, not always SKIPPED" {
    step8c_section | grep -q -F "Match found"
    step8c_section | grep -q -F "Proceed to evidence collection"
}

@test "Step 8c: unfired observation ACs still record SKIPPED" {
    step8c_section | grep -q -F "No match"
    step8c_section | grep -q -F "waiting for event=<event-name>"
}

@test "Step 8c: judgment covers PASS/FAIL/UNCERTAIN/SKIPPED" {
    step8c_section | grep -q -F "**PASS**"
    step8c_section | grep -q -F "**FAIL**"
    step8c_section | grep -q -F "**UNCERTAIN**"
    step8c_section | grep -q -F "**SKIPPED**"
}

@test "Step 8c: evidence collection lists auto logs, auto-events.jsonl, and opportunistic-search.sh" {
    step8c_section | grep -q -F "/auto"
    step8c_section | grep -q -F "auto-events.jsonl"
    step8c_section | grep -q -F "opportunistic-search.sh --event"
}

@test "Step 8c: gh issue view failure is not silently treated as unfired" {
    step8c_section | grep -q -F "GH_EXIT"
    step8c_section | grep -q -F "could not confirm fired status"
}

@test "Step 8c: fired-event match is anchored to the backtick-quoted token" {
    step8c_section | grep -q -F '\`${EVENT_NAME}\` detected'
}

@test "verify-executor.md: observation row branches on fired status instead of always SKIPPED" {
    run grep -F "Branches on whether the specified" "$PROJECT_ROOT/modules/verify-executor.md"
    [ "$status" -eq 0 ]
    ! grep -q -F "Skip during normal \`/verify\` run" "$PROJECT_ROOT/modules/verify-executor.md"
}
