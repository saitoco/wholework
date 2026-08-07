#!/usr/bin/env bats

# Shallow tests for ci-failure-classifier module documentation.
# LLM responses are not mocked; tests confirm required sections, signature
# coverage, and that skills/verify/SKILL.md does not duplicate the table.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
CLASSIFIER="$PROJECT_ROOT/modules/ci-failure-classifier.md"
VERIFY_SKILL="$PROJECT_ROOT/skills/verify/SKILL.md"

@test "ci-failure-classifier: module has the 4 standard sections" {
    grep -q "## Purpose" "$CLASSIFIER"
    grep -q "## Input" "$CLASSIFIER"
    grep -q "## Processing Steps" "$CLASSIFIER"
    grep -q "## Output" "$CLASSIFIER"
}

@test "ci-failure-classifier: signature table covers all 7 known patterns" {
    grep -q "steps: \[\]" "$CLASSIFIER"
    grep -q "cancelled" "$CLASSIFIER"
    grep -q "shutdown signal" "$CLASSIFIER"
    grep -q "ECONNREFUSED" "$CLASSIFIER"
    grep -q "workflow run" "$CLASSIFIER"
    grep -q "Set up job" "$CLASSIFIER"
    grep -q "queued" "$CLASSIFIER"
}

@test "ci-failure-classifier: verify SKILL.md does not duplicate the signature table" {
    ! grep -q "The runner has received a shutdown signal" "$VERIFY_SKILL"
    grep -q "modules/ci-failure-classifier.md" "$VERIFY_SKILL"
}
