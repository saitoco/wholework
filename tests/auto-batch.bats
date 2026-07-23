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
