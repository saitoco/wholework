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

# Extract Step 11 section: from "### Step 11:" to the next "### " heading
step11_section() {
    awk '/^### Step 11:/{found=1} found && /^### / && !/^### Step 11:/{exit} found{print}' "$1"
}

@test "Step 11 patch route commit template includes closes NUMBER inline" {
    run step11_section "$SKILL_FILE"
    [[ "$output" == *'(closes #$NUMBER)'* ]]
}

@test "Step 11 patch route includes commit subject issue-number guard" {
    run step11_section "$SKILL_FILE"
    [[ "$output" == *'missing #$NUMBER reference'* ]]
}

# Extract Step 9 section: from "### Step 9:" to the next "### " heading
step9_section() {
    awk '/^### Step 9:/{found=1} found && /^### / && !/^### Step 9:/{exit} found{print}' "$1"
}

# Extract Behavioral Change Detection subsection: from "#### Behavioral Change Detection"
# to the next heading (any level)
behavioral_change_detection_section() {
    awk '/^#### Behavioral Change Detection/{found=1; next} found && /^#{1,4} /{exit} found{print}' "$1"
}

@test "Step 9 section states execution surface constraint (run_in_background) at a branch-independent position" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *"run_in_background"* ]]
}

@test "Behavioral Change Detection subsection does not restate the execution surface constraint" {
    run behavioral_change_detection_section "$SKILL_FILE"
    [[ "$output" != *"run_in_background"* ]]
}

@test "Step 9 full-suite override uses the parallel bats form" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *"bats --jobs"* ]]
}

@test "Step 9 full-suite override keeps the portable nproc/sysctl job-count form" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *'nproc 2>/dev/null || sysctl -n hw.logicalcpu'* ]]
}

@test "Step 9 full-suite override does not invoke the serial whole-suite form" {
    run step9_section "$SKILL_FILE"
    # `bats tests/` alone would exceed the tool's 10-minute ceiling and be
    # auto-backgrounded (Issue #1213). Only the --jobs form may appear as a
    # runnable command; prose may still mention the directory. Match on
    # trimmed line content rather than exact indentation so a Markdown
    # reformat cannot silently defeat this negative assertion.
    run bash -c 'printf "%s\n" "$1" | sed "s/^[[:space:]]*//" | grep -qx "bats tests/"' _ "$output"
    [ "$status" -ne 0 ]
}

@test "Step 9 full-suite override resolves the job count as a separate literal step (no inline command substitution)" {
    run step9_section "$SKILL_FILE"
    [[ "$output" != *'bats --jobs $('* ]]
    [[ "$output" == *"bats --jobs <N> tests/"* ]]
}

@test "Step 9 execution surface constraint states the tool timeout ceiling" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *"600000"* ]]
    [[ "$output" == *"ceiling"* ]]
}

@test "Step 9 execution surface constraint states that exceeding the ceiling backgrounds the command" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *"moved to the background"* ]]
}
