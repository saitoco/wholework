#!/usr/bin/env bats

# Tests for skills/code/SKILL.md structural content
# Verifies always-pr spec is present in Step 0 Route Detection (Issue #783)

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/code/SKILL.md"

# Extract Step 0 section: from "### Step 0:" to the next "### " heading
step0_section() {
    awk '/^### Step 0:/{found=1} found && /^### / && !/^### Step 0:/{exit} found{print}' "$1"
}

# Extract Follow-up Issue Creation section: from "#### Follow-up Issue Creation" to the next heading
followup_issue_section() {
    awk '/^#### Follow-up Issue Creation/{found=1; next} found && /^#{1,4} /{exit} found{print}' "$1"
}

@test "Step 0 section contains always-pr keyword" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"always-pr"* ]]
}

@test "Step 0 section contains ALWAYS_PR variable" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"ALWAYS_PR"* ]]
}

@test "Step 0 section references detect-config-markers.md" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"detect-config-markers.md"* ]]
}

@test "Step 0 section describes pr route forced when ALWAYS_PR=true" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"pr route"* ]]
    [[ "$output" == *"ALWAYS_PR=true"* ]]
}

@test "Step 0 section describes --patch flag warning when ALWAYS_PR=true" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"--patch"* ]]
    [[ "$output" == *"ignored"* ]] || [[ "$output" == *"Warning"* ]]
}

@test "Follow-up Issue Creation section contains open-issue duplicate check" {
    run followup_issue_section "$SKILL_FILE"
    [[ "$output" == *"gh issue list"* ]]
}
