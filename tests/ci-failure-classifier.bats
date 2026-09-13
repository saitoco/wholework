#!/usr/bin/env bats

# Shallow tests for ci-failure-classifier module documentation.
# LLM responses are not mocked; tests confirm required sections, signature
# coverage, and that skills/verify/SKILL.md does not duplicate the table.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
CLASSIFIER="$PROJECT_ROOT/modules/ci-failure-classifier.md"
VERIFY_SKILL="$PROJECT_ROOT/skills/verify/SKILL.md"
VERIFY_EXECUTOR="$PROJECT_ROOT/modules/verify-executor.md"
AUTO_SKILL="$PROJECT_ROOT/skills/auto/SKILL.md"
RUN_REVIEW="$PROJECT_ROOT/scripts/run-review.sh"

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
    if grep -q "The runner has received a shutdown signal" "$VERIFY_SKILL"; then false; fi
    grep -q "modules/ci-failure-classifier.md" "$VERIFY_SKILL"
}

@test "ci-failure-classifier: verify-executor.md does not duplicate the signature table" {
    if grep -q "The runner has received a shutdown signal" "$VERIFY_EXECUTOR"; then false; fi
    grep -q "modules/ci-failure-classifier.md" "$VERIFY_EXECUTOR"
}

@test "ci-failure-classifier: no-ci-configured verdict is defined with pull_request trigger detection" {
    grep -q "no-ci-configured" "$CLASSIFIER"
    grep -q "pull_request_target" "$CLASSIFIER"
    grep -q "detect-pr-ci-workflows.sh" "$CLASSIFIER"
}

@test "ci-failure-classifier: auto SKILL.md pr route item 8 handles no-ci-configured" {
    grep -q "no-ci-configured" "$AUTO_SKILL"
}

@test "ci-failure-classifier: run-review.sh uses the shared PR-trigger workflow detection" {
    grep -q "detect-pr-ci-workflows.sh" "$RUN_REVIEW"
}
