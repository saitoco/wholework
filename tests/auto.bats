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
