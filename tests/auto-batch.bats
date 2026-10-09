#!/usr/bin/env bats

# Tests for /auto --batch List mode verify orchestration (Issue #615)
# Structural tests: verify that skills/auto/SKILL.md contains required content
# in the "### List mode" section.

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/auto/SKILL.md"

load 'helpers/markdown-section'

# Extract the "### List mode (--batch N1 N2 ...)" section from SKILL.md
list_mode_section() {
    md_section "$SKILL_FILE" "### List mode"
}

# Extract the "### Count mode (--batch N)" section from SKILL.md
count_mode_section() {
    md_section "$SKILL_FILE" "### Count mode"
}

# Extract the "### Until mode (--batch --until <query>)" section from SKILL.md
until_mode_section() {
    md_section "$SKILL_FILE" "### Until mode"
}

@test "List mode section: wholework:verify Skill invocation present" {
    run grep -q 'wholework:verify' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "List mode section: phase/verify label check present" {
    run grep -q 'phase/verify' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "List mode section: non-interactive skip behavior present" {
    run grep -q 'non-interactive' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "List mode section: blocked-by check present" {
    run grep -q 'blocked' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "List mode section: get-blocked-by.sh referenced (GraphQL read window)" {
    run grep -q 'get-blocked-by.sh' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "List mode section: body grep read path removed" {
    run grep -q 'json body' <<< "$(list_mode_section)"
    [ "$status" -ne 0 ]
}

@test "List mode section: phase/done gate condition present" {
    run grep -q 'phase/done' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "List mode section: --batch --resume in blocked warning present" {
    run grep -q -- '--batch --resume' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "List mode section: Issue Retrospective Transcription reference present" {
    run grep -q 'Step 4b' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "List mode section: AUTO_STOP_AT retained for verify gate" {
    run grep -q 'AUTO_STOP_AT' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "List mode section: auto-stop-at merge skip behavior present" {
    run grep -q 'auto-stop-at=merge' <<< "$(list_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Count mode section: Issue Retrospective Transcription reference present" {
    run grep -q 'Step 4b' <<< "$(count_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Count mode section: wholework:verify Skill invocation present" {
    run grep -q 'wholework:verify' <<< "$(count_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Count mode section: phase/verify label check present" {
    run grep -q 'phase/verify' <<< "$(count_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Count mode section: AUTO_STOP_AT retained for verify gate" {
    run grep -q 'AUTO_STOP_AT' <<< "$(count_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Count mode section: auto-stop-at merge skip behavior present" {
    run grep -q 'auto-stop-at=merge' <<< "$(count_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Count mode section: non-interactive skip behavior present" {
    run grep -q 'non-interactive' <<< "$(count_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Until mode section: resolve-batch-query.sh referenced" {
    run grep -q 'resolve-batch-query.sh' <<< "$(until_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Until mode section: --max-rounds default of 3 documented" {
    run grep -q 'default.*`3`' <<< "$(until_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Until mode section: write_batch reused" {
    run grep -q 'write_batch' <<< "$(until_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Until mode section: delete_batch reused" {
    run grep -q 'delete_batch' <<< "$(until_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Until mode section: PROCESSED exclusion across rounds described" {
    run grep -q 'PROCESSED' <<< "$(until_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Until mode section: --checkin-per-round ignored in non-interactive mode" {
    run grep -q -- '--checkin-per-round ignored in non-interactive mode' <<< "$(until_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Until mode section: List mode reused for per-round Issue processing" {
    run grep -q 'List mode' <<< "$(until_mode_section)"
    [ "$status" -eq 0 ]
}

@test "Until mode section: round-ordering.md referenced between ROUND_LIST recording and write_batch" {
    run grep -n 'Record the output as .ROUND_LIST.\|round-ordering.md\|auto-checkpoint.sh write_batch' <<< "$(until_mode_section)"
    [ "$status" -eq 0 ]
    record_line=$(echo "$output" | grep 'Record the output' | head -1 | cut -d: -f1)
    ordering_line=$(echo "$output" | grep 'round-ordering.md' | head -1 | cut -d: -f1)
    write_batch_line=$(echo "$output" | grep 'auto-checkpoint.sh write_batch' | head -1 | cut -d: -f1)
    [ "$record_line" -le "$ordering_line" ]
    [ "$ordering_line" -lt "$write_batch_line" ]
}

@test "Until mode section: triage insertion between step 2 and step 3" {
    run grep -n 'wholework:triage\|resolve-batch-query.sh --query' <<< "$(until_mode_section)"
    [ "$status" -eq 0 ]
    triage_line=$(echo "$output" | grep 'wholework:triage' | head -1 | cut -d: -f1)
    query_line=$(echo "$output" | grep 'resolve-batch-query.sh --query' | head -1 | cut -d: -f1)
    [ "$triage_line" -lt "$query_line" ]
}

@test "Until mode section: triage insertion adopted-approach rationale present" {
    run grep -q 'Adopted approach' <<< "$(until_mode_section)"
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
