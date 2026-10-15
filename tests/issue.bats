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

@test "issue skill Step 4 documents manual preview-tier AC tag convention" {
    grep -q 'ac-tier: preview --> <!-- verify-type: manual' "$PROJECT_ROOT/skills/issue/SKILL.md"
}

@test "issue skill Step 4 documents skill self-update propagation check" {
    grep -q 'check-skill-change-observation-ac.sh' "$PROJECT_ROOT/skills/issue/SKILL.md"
    grep -q 'session=next' "$PROJECT_ROOT/skills/issue/SKILL.md"
}

@test "issue skill Step 4 documents checkbox format convention and detection script" {
    grep -q 'check-ac-checkbox-format.sh' "$PROJECT_ROOT/skills/issue/SKILL.md"
    grep -q 'Checkbox format for Pre-merge / Post-merge condition lines' "$PROJECT_ROOT/skills/issue/SKILL.md"
}

@test "issue skill Existing Issue Refinement runs AC verify command audit regardless of triaged" {
    grep -q 'AC Verify Command Integrity Audit' "$PROJECT_ROOT/skills/issue/SKILL.md"
    grep -q 'skill-dev-verify-audit.md' "$PROJECT_ROOT/skills/issue/SKILL.md"
    grep -q 'regardless of whether the .triaged. label is present or absent' "$PROJECT_ROOT/skills/issue/SKILL.md"
}

# Content-assertion tests for the observation event name vocabulary check (added for #1527).
# The vocabulary table lives only in modules/verify-classifier.md; the /issue procedure must
# point at it instead of restating its values. Guards against accidental removal or a pasted copy.

@test "issue skill Step 4 documents observation event name vocabulary check" {
    grep -qi 'event name vocabulary check' "$PROJECT_ROOT/skills/issue/SKILL.md"
    grep -q 'Tag Extraction Rule' "$PROJECT_ROOT/skills/issue/SKILL.md"
}

@test "issue skill does not restate the event vocabulary table held by verify-classifier" {
    grep -q 'pr-review-light' "$PROJECT_ROOT/modules/verify-classifier.md"
    run grep -q 'pr-review-light' "$PROJECT_ROOT/skills/issue/SKILL.md"
    [ "$status" -eq 1 ]
}
