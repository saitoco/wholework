#!/usr/bin/env bats

# Structural tests for Decomposition File Mode in skills/issue/SKILL.md.
# These tests verify that the required keywords and procedures are documented
# in the SKILL.md file without executing LLM logic or calling external APIs.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SKILL_FILE="$PROJECT_ROOT/skills/issue/SKILL.md"

@test "decomposition: SKILL.md contains --from-decomposition-file option" {
    grep -q -- "--from-decomposition-file" "$SKILL_FILE"
}

@test "decomposition: SKILL.md contains circular dependency DFS detection" {
    grep -qE "DFS|circular" "$SKILL_FILE"
}

@test "decomposition: SKILL.md contains skeleton body generation for missing fields" {
    grep -q "skeleton" "$SKILL_FILE"
}

@test "decomposition: SKILL.md contains add-sub-issue and add-blocked-by GraphQL calls" {
    grep -q "add-sub-issue" "$SKILL_FILE"
    grep -q "add-blocked-by" "$SKILL_FILE"
}
