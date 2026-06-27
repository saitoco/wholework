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

# Tests for auto-stop-at / --stop-at support (Issue #783)

@test "SKILL.md contains stop-at keyword" {
    grep -qE "stop-at|stop_at" "$SKILL_FILE"
}

@test "SKILL.md contains auto-stop-at keyword" {
    grep -q "auto-stop-at" "$SKILL_FILE"
}

@test "SKILL.md contains EFFECTIVE_STOP_AT variable" {
    grep -q "EFFECTIVE_STOP_AT" "$SKILL_FILE"
}

# Extract Step 2 section: from "### Step 2:" to the next "### " heading
step2_section() {
    awk '/^### Step 2:/{found=1} found && /^### / && !/^### Step 2:/{exit} found{print}' "$1"
}

@test "Step 2 section describes stop-at flag parsing" {
    run step2_section "$SKILL_FILE"
    [[ "$output" == *"stop-at"* ]]
}

@test "Step 2 section lists valid stop-at enum values spec, code, review, merge" {
    run step2_section "$SKILL_FILE"
    [[ "$output" == *"spec"* ]]
    [[ "$output" == *"code"* ]]
    [[ "$output" == *"review"* ]]
    [[ "$output" == *"merge"* ]]
}

# Extract Step 5 section: from "### Step 5:" to the next "### " heading
step5_section() {
    awk '/^### Step 5:/{found=1} found && /^### / && !/^### Step 5:/{exit} found{print}' "$1"
}

@test "Step 5 section contains next-action guidance for stop-at" {
    run step5_section "$SKILL_FILE"
    [[ "$output" == *"/merge"* ]] || [[ "$output" == *"Next"* ]]
}

@test "Step 5 section contains STOPPED_AT variable reference" {
    run step5_section "$SKILL_FILE"
    [[ "$output" == *"STOPPED_AT"* ]]
}
