#!/usr/bin/env bats

# Tests for /verify Step 2 base branch checkout worktree context guard (Issue #1000)
# Structural tests: verify that skills/verify/SKILL.md Step 2 runs the
# foreign-worktree guard ahead of the base branch checkout.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SKILL_FILE="$PROJECT_ROOT/skills/verify/SKILL.md"

load 'helpers/markdown-section'

# Extract the "### Step 2: Detect and Update Base Branch" section from SKILL.md.
# The section ends at the next heading of level 3 or higher.
step2_section() {
    md_section "$SKILL_FILE" "### Step 2: Detect and Update Base Branch"
}

# Extract the "### Step 5: Verify Each Condition (Pre-merge Only)" section from SKILL.md.
# The section ends at the next heading of level 3 or higher.
step5_section() {
    md_section "$SKILL_FILE" "### Step 5: "
}

# Extract the "#### Step 8c: Observation Post-merge Conditions" section from SKILL.md.
# The section ends at the next heading of level 4 or higher.
step8c_section() {
    md_section "$SKILL_FILE" "#### Step 8c: "
}

# Extract the "### Step 6: Update Pre-merge Checkboxes (Immediate Lock-in)" section from SKILL.md.
# The section ends at the next heading of level 3 or higher.
step6_section() {
    md_section "$SKILL_FILE" "### Step 6: "
}

# Extract the "#### Step 8a: Auto-verify Post-merge Conditions with Hints" section from SKILL.md.
# The section ends at the next heading of level 4 or higher.
step8a_section() {
    md_section "$SKILL_FILE" "#### Step 8a: "
}

# Extract the "#### Step 8b: Manual Post-merge Conditions" section from SKILL.md.
# The section ends at the next heading of level 4 or higher.
step8b_section() {
    md_section "$SKILL_FILE" "#### Step 8b: "
}

# Extract the "### Step 9: Post Comment on Issue" section from SKILL.md.
# The section ends at the next heading of level 3 or higher.
step9_section() {
    md_section "$SKILL_FILE" "### Step 9: "
}

# Extract the "### Step 1: Check Working Directory Safety" section from SKILL.md.
# The section ends at the next heading of level 3 or higher.
step1_section() {
    md_section "$SKILL_FILE" "### Step 1: "
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

@test "Step 8c: session=next resolves to SKIPPED instead of UNCERTAIN" {
    step8c_section | grep -q -F "session=next"
    step8c_section | grep -q -F "skill self-update not yet propagated (session=next)"
}

@test "Step 5 already-checked AC skip rule: checked pre-merge AC is excluded and recorded SKIPPED" {
    step5_section | grep -q -F "Already-checked AC skip rule"
    step5_section | grep -q -F "already checked; skipped by default"
}

@test "Step 5 already-checked AC skip rule: unchecked pre-merge AC is still processed as usual" {
    step5_section | grep -q -F "Conditions still at \`- [ ]\` are processed as usual"
}

@test "Step 8a already-checked AC skip rule: checked post-merge+hint AC is excluded and recorded SKIPPED" {
    step8a_section | grep -q -F "already checked; skipped by default"
}

@test "Step 8a already-checked AC skip rule: only unchecked post-merge+hint AC is auto-verified" {
    step8a_section | grep -q -F "still \`- [ ]\` (unchecked)"
}

@test "Step 6 Re-runs description no longer re-verifies already-checked conditions" {
    if step6_section | grep -q -F "Re-verify even if already checked"; then false; fi
    step6_section | grep -q -F "skipped by default"
    step6_section | grep -q -F "Only conditions still at \`- [ ]\` are (re-)verified"
}

@test "Step 8b: records executability judgment via verify-executability-marker.sh vocabulary" {
    step8b_section | grep -q -F "verify-executability"
}

@test "Step 8b: emits verify_executability event" {
    step8b_section | grep -q -F "verify_executability"
}

@test "Step 8b: judgment recording (1b) precedes the 2a AskUserQuestion branch" {
    record_line=$(step8b_section | grep -n -F "1b. Record the judgment" | head -1 | cut -d: -f1)
    branch_line=$(step8b_section | grep -n -F "2a. If executable" | head -1 | cut -d: -f1)
    [ -n "$record_line" ]
    [ -n "$branch_line" ]
    [ "$record_line" -lt "$branch_line" ]
}

@test "Step 8b: recording happens in both branches, independent of AskUserQuestion" {
    step8b_section | grep -q -F "independent of whether \`AskUserQuestion\` is invoked"
}

@test "Step 9: embeds executability markers via verify-executability-marker.sh, no new comment" {
    step9_section | grep -q -F "verify-executability-marker.sh"
    step9_section | grep -q -F "Do not post these markers as a separate comment"
}

@test "skill-body-lines marker stays in sync with wc -l (Issue #1447)" {
    marker_value=$(grep "skill-body-lines:" "$SKILL_FILE" | head -1 | grep -o '[0-9]\+')
    actual_lines=$(wc -l < "$SKILL_FILE")
    [ -n "$marker_value" ]
    [ "$marker_value" -eq "$actual_lines" ]
}

@test "skill-body-sha marker stays in sync with computed hash (Issue #1468)" {
    marker_value=$(grep -m1 '<!-- skill-body-sha: ' "$SKILL_FILE" | grep -oE '[0-9a-f]{8}')
    actual_hash=$(grep -v '<!-- skill-body-' "$SKILL_FILE" | shasum -a 256 | cut -c1-8)
    [ -n "$marker_value" ]
    [ "$marker_value" = "$actual_hash" ]
}

@test "Step 1: self-consistency check block precedes check-verify-dirty.sh invocation (Issue #1447)" {
    self_check_line=$(step1_section | grep -n -F "Self-consistency check" | head -1 | cut -d: -f1)
    dirty_classifier_line=$(step1_section | grep -n -F "check-verify-dirty.sh" | head -1 | cut -d: -f1)
    [ -n "$self_check_line" ]
    [ -n "$dirty_classifier_line" ]
    [ "$self_check_line" -lt "$dirty_classifier_line" ]
}

@test "Step 9: inserts stale skill body warning as visible Markdown when STALE_SKILL_BODY_DETECTED is true (Issue #1447)" {
    step9_section | grep -q -F "STALE_SKILL_BODY_DETECTED"
    step9_section | grep -q -F "stale skill body warning"
}
