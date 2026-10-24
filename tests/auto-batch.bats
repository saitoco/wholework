#!/usr/bin/env bats

# Tests for /auto --batch List mode verify orchestration (Issue #615)
# Structural tests: verify that skills/auto/SKILL.md contains required content
# in the "### List mode" section.

# Issue #1545: assignee handling in Count/List/Until/Resume modes (structural tests at the end of
# this file). The exclusion logic itself is tested in tests/filter-other-assignees.bats and
# tests/resolve-batch-query.bats; these tests only pin what SKILL.md tells the LLM to do.

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

# Extract the "### Resume mode (--batch --resume)" section from SKILL.md
resume_mode_section() {
    md_section "$SKILL_FILE" "### Resume mode"
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
    # Plain assignment (not run) so a missing heading fails the test (Issue #1516)
    section="$(list_mode_section)"
    run grep -q 'json body' <<< "$section"
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

# --- Assignee handling (Issue #1545) ---

@test "Count mode section: candidates pass through filter-other-assignees.sh with assignees and createdAt" {
    section="$(count_mode_section)"
    [ -n "$section" ]
    line="$(printf '%s\n' "$section" | grep 'gh issue list --state open --label triaged')"
    [[ "$line" == *"assignees"* ]] || false
    [[ "$line" == *"createdAt"* ]] || false
    [[ "$line" == *"filter-other-assignees.sh"* ]] || false
}

@test "Count mode section: backward compatibility sentence mentions the assignee exception and the Japanese original is gone" {
    section="$(count_mode_section)"
    [ -n "$section" ]
    run grep -q 'is never a candidate' <<< "$section"
    [ "$status" -eq 0 ]
    run grep -q '後方互換で維持する' <<< "$section"
    [ "$status" -ne 0 ]
}

@test "Count mode section: fail-closed behavior when the executing user is unknown is described" {
    section="$(count_mode_section)"
    [ -n "$section" ]
    run grep -q 'fail-closed' <<< "$section"
    [ "$status" -eq 0 ]
}

@test "Count mode section: command failure stops Count mode without an unfiltered fallback" {
    section="$(count_mode_section)"
    [ -n "$section" ]
    run grep -q 'stop Count mode without processing any Issue' <<< "$section"
    [ "$status" -eq 0 ]
    run grep -q 'do not fall back to an unfiltered list' <<< "$section"
    [ "$status" -eq 0 ]
}

@test "Count mode section: filtering criteria for Size and createdAt are unchanged" {
    section="$(count_mode_section)"
    [ -n "$section" ]
    run grep -q 'Sort by `createdAt` descending (newest first) and select the top N' <<< "$section"
    [ "$status" -eq 0 ]
}

@test "List mode section: Assignee warning block uses gh-issue-assignee.sh status and does not exclude" {
    section="$(list_mode_section)"
    [ -n "$section" ]
    run grep -q 'Assignee warning' <<< "$section"
    [ "$status" -eq 0 ]
    run grep -q 'gh-issue-assignee.sh status' <<< "$section"
    [ "$status" -eq 0 ]
    run grep -q 'never excluded because of its assignee' <<< "$section"
    [ "$status" -eq 0 ]
}

@test "List mode section: Assignee warning block comes before Process each Issue" {
    section="$(list_mode_section)"
    [ -n "$section" ]
    warn_line="$(printf '%s\n' "$section" | grep -n 'Assignee warning' | head -1 | cut -d: -f1)"
    process_line="$(printf '%s\n' "$section" | grep -n 'Process each Issue in' | head -1 | cut -d: -f1)"
    [ -n "$warn_line" ]
    [ -n "$process_line" ]
    [ "$warn_line" -lt "$process_line" ]
}

@test "Until mode section: exclusion happens inside resolve-batch-query.sh and the List mode warning is not applied" {
    section="$(until_mode_section)"
    [ -n "$section" ]
    run grep -q 'resolve-batch-query.sh' <<< "$section"
    [ "$status" -eq 0 ]
    run grep -q 'Assignee warning' <<< "$section"
    [ "$status" -eq 0 ]
    run grep -q 'intentionally not applied' <<< "$section"
    [ "$status" -eq 0 ]
}

@test "Until mode section: step 4 relays the script stderr" {
    section="$(until_mode_section)"
    [ -n "$section" ]
    run grep -q "Relay the script's stderr" <<< "$section"
    [ "$status" -eq 0 ]
}

@test "Resume mode section: Assignee warning of List mode is run against REMAINING" {
    section="$(resume_mode_section)"
    [ -n "$section" ]
    run grep -q 'Assignee warning' <<< "$section"
    [ "$status" -eq 0 ]
    run grep -q 'REMAINING' <<< "$section"
    [ "$status" -eq 0 ]
    run grep -q 'do NOT call `write_batch` again' <<< "$section"
    [ "$status" -eq 0 ]
}
