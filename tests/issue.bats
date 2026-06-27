#!/usr/bin/env bats
# Content-assertion tests for /issue skill pre-merge-preview tier guidance.
# These tests verify that the required keywords and tags exist in the skill files
# (script/content layer). The actual LLM-driven classification behavior is covered
# by post-merge observation ACs.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

@test "issue skill Step 4 documents pre-merge-preview tier" {
    grep -q 'pre-merge-preview' "$PROJECT_ROOT/skills/issue/SKILL.md"
}

@test "issue skill Step 4 tags preview-tier ACs with ac-tier preview" {
    grep -q 'ac-tier: preview' "$PROJECT_ROOT/skills/issue/SKILL.md"
}

@test "issue skill Step 4 auto-appends PREVIEW_URL when-guard" {
    grep -q 'test -n .*PREVIEW_URL' "$PROJECT_ROOT/skills/issue/SKILL.md"
}

@test "detect-config-markers documents pr-preview capability" {
    grep -q 'pr-preview' "$PROJECT_ROOT/modules/detect-config-markers.md" && grep -q 'HAS_PR_PREVIEW_CAPABILITY' "$PROJECT_ROOT/modules/detect-config-markers.md"
}
