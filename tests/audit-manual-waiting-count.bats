#!/usr/bin/env bats

# Tests for /audit Manual Waiting Count: preview-ac-unverified marker resolution (Issue #1371)
# Structural tests: verify that skills/audit/SKILL.md contains required content
# in the "#### Manual Waiting Count" section.

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/audit/SKILL.md"

load 'helpers/markdown-section'

# Extract the "#### Manual Waiting Count" section from SKILL.md.
# The section ends at the next heading of level 4 or higher (#### , ### , ## , # ).
manual_waiting_count_section() {
    md_section "$SKILL_FILE" "#### Manual Waiting Count"
}

@test "Manual Waiting Count: preview-ac-unverified marker resolution present" {
    manual_waiting_count_section | grep -q "preview-ac-unverified"
}

@test "Manual Waiting Count: N1+N2+N3+N4=N invariant present" {
    manual_waiting_count_section | grep -q "N1 + N2 + N3 + N4 = N"
}

@test "Manual Waiting Count: resolve-preview-ac-fallback.sh gh failure treated as exit code 2 undetermined" {
    manual_waiting_count_section | grep -q "exit code 2"
}
