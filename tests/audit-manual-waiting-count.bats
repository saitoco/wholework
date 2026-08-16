#!/usr/bin/env bats

# Tests for /audit Manual Waiting Count: preview-ac-unverified marker resolution (Issue #1371)
# Structural tests: verify that skills/audit/SKILL.md contains required content
# in the "#### Manual Waiting Count" section.

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/audit/SKILL.md"

# Extract the "#### Manual Waiting Count" section from SKILL.md.
# The section ends at the next level-4 (#### ) or level-3 (### ) heading.
manual_waiting_count_section() {
    awk '/^#### Manual Waiting Count/{found=1} /^#### / && !/Manual Waiting Count/{found=0} /^### / {found=0} found{print}' "$SKILL_FILE"
}

@test "Manual Waiting Count: preview-ac-unverified marker resolution present" {
    manual_waiting_count_section | grep -q "preview-ac-unverified"
}

@test "Manual Waiting Count: N1+N2+N3+N4=N invariant present" {
    manual_waiting_count_section | grep -q "N1 + N2 + N3 + N4 = N"
}
