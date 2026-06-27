#!/usr/bin/env bats

# Tests for skills/auto/SKILL.md structural content
# Verifies route demotion spec is present in Step 3a (Issue #616)

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/auto/SKILL.md"

# Extract Step 3a section: from "### Step 3a:" to the next "### " heading
step3a_section() {
    awk '/^### Step 3a:/{found=1} found && /^### / && !/^### Step 3a:/{exit} found{print}' "$1"
}

@test "Step 3a section contains route demotion" {
    run step3a_section "$SKILL_FILE"
    [[ "$output" == *"route demotion"* ]]
}

@test "Step 3a section contains Post-spec route demotion log message" {
    run step3a_section "$SKILL_FILE"
    [[ "$output" == *"Post-spec route demotion"* ]]
}

# Extract Step 2a section: from "### Step 2a:" to the next "### " heading
step2a_section() {
    awk '/^### Step 2a:/{found=1} found && /^### / && !/^### Step 2a:/{exit} found{print}' "$1"
}

@test "Step 2a fix-cycle section exists in SKILL.md" {
    run step2a_section "$SKILL_FILE"
    [ -n "$output" ]
}

@test "Step 2a section contains fix-cycle keyword" {
    run step2a_section "$SKILL_FILE"
    [[ "$output" == *"fix-cycle"* ]]
}

@test "Step 2a section describes skipping issue and spec phases" {
    run step2a_section "$SKILL_FILE"
    [[ "$output" == *"run-issue.sh"* ]] || [[ "$output" == *"issue/spec"* ]]
    [[ "$output" == *"run-code.sh"* ]]
}

@test "Step 2a section references verify-fail marker" {
    run step2a_section "$SKILL_FILE"
    [[ "$output" == *"verify-fail"* ]]
}
