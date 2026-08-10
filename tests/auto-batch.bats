#!/usr/bin/env bats

# Tests for /auto --batch List mode verify orchestration (Issue #615)
# Structural tests: verify that skills/auto/SKILL.md contains required content
# in the "### List mode" section.

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/auto/SKILL.md"

# Extract the "### List mode (--batch N1 N2 ...)" section from SKILL.md
list_mode_section() {
    awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' "$SKILL_FILE"
}

# Extract the "### Count mode (--batch N)" section from SKILL.md
count_mode_section() {
    awk '/^### Count mode/{found=1} /^### / && !/Count mode/{found=0} found{print}' "$SKILL_FILE"
}

# Extract the "### Until mode (--batch --until <query>)" section from SKILL.md
until_mode_section() {
    awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' "$SKILL_FILE"
}

@test "List mode section: wholework:verify Skill invocation present" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'wholework:verify'"
    [ "$status" -eq 0 ]
}

@test "List mode section: phase/verify label check present" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'phase/verify'"
    [ "$status" -eq 0 ]
}

@test "List mode section: non-interactive skip behavior present" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'non-interactive'"
    [ "$status" -eq 0 ]
}

@test "List mode section: blocked-by check present" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'blocked'"
    [ "$status" -eq 0 ]
}

@test "List mode section: get-blocked-by.sh referenced (GraphQL read window)" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'get-blocked-by.sh'"
    [ "$status" -eq 0 ]
}

@test "List mode section: body grep read path removed" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'json body'"
    [ "$status" -ne 0 ]
}

@test "List mode section: phase/done gate condition present" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'phase/done'"
    [ "$status" -eq 0 ]
}

@test "List mode section: --batch --resume in blocked warning present" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q -- '--batch --resume'"
    [ "$status" -eq 0 ]
}

@test "List mode section: Issue Retrospective Transcription reference present" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'Step 4b'"
    [ "$status" -eq 0 ]
}

@test "List mode section: AUTO_STOP_AT retained for verify gate" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'AUTO_STOP_AT'"
    [ "$status" -eq 0 ]
}

@test "List mode section: auto-stop-at merge skip behavior present" {
    run bash -c "awk '/^### List mode/{found=1} /^### / && !/List mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'auto-stop-at=merge'"
    [ "$status" -eq 0 ]
}

@test "Count mode section: Issue Retrospective Transcription reference present" {
    run bash -c "awk '/^### Count mode/{found=1} /^### / && !/Count mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'Step 4b'"
    [ "$status" -eq 0 ]
}

@test "Until mode section: resolve-batch-query.sh referenced" {
    run bash -c "awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'resolve-batch-query.sh'"
    [ "$status" -eq 0 ]
}

@test "Until mode section: --max-rounds default of 3 documented" {
    run bash -c "awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'default.*\`3\`'"
    [ "$status" -eq 0 ]
}

@test "Until mode section: write_batch reused" {
    run bash -c "awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'write_batch'"
    [ "$status" -eq 0 ]
}

@test "Until mode section: delete_batch reused" {
    run bash -c "awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'delete_batch'"
    [ "$status" -eq 0 ]
}

@test "Until mode section: PROCESSED exclusion across rounds described" {
    run bash -c "awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'PROCESSED'"
    [ "$status" -eq 0 ]
}

@test "Until mode section: --checkin-per-round ignored in non-interactive mode" {
    run bash -c "awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' '$SKILL_FILE' | grep -q -- '--checkin-per-round ignored in non-interactive mode'"
    [ "$status" -eq 0 ]
}

@test "Until mode section: List mode reused for per-round Issue processing" {
    run bash -c "awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}' '$SKILL_FILE' | grep -q 'List mode'"
    [ "$status" -eq 0 ]
}

@test "Until mode section is inserted between List mode and Resume mode" {
    run bash -c "grep -n '^### List mode\|^### Until mode\|^### Resume mode' '$SKILL_FILE'"
    [ "$status" -eq 0 ]
    list_line=$(echo "$output" | grep '### List mode' | cut -d: -f1)
    until_line=$(echo "$output" | grep '### Until mode' | cut -d: -f1)
    resume_line=$(echo "$output" | grep '### Resume mode' | cut -d: -f1)
    [ "$list_line" -lt "$until_line" ]
    [ "$until_line" -lt "$resume_line" ]
}
