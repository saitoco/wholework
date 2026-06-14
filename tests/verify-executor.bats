#!/usr/bin/env bats

# Tests for verify-executor.md commit-filter documentation and bash subshell expansion.
# Confirms that github_check templates use --commit=$(git rev-parse HEAD) to pin
# CI run lookup to a specific commit, avoiding concurrent-push interference.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
VERIFY_CLASSIFIER="$PROJECT_ROOT/modules/verify-classifier.md"
SPEC_TEST_GUIDELINES="$PROJECT_ROOT/skills/issue/spec-test-guidelines.md"

@test "verify-classifier: --commit filter is present in patch route template" {
    grep -q -- "--commit" "$VERIFY_CLASSIFIER"
}

@test "verify-classifier: patch route template uses git rev-parse HEAD" {
    grep -q "git rev-parse HEAD" "$VERIFY_CLASSIFIER"
}

@test "spec-test-guidelines: --commit filter is present in patch route template" {
    grep -q -- "--commit" "$SPEC_TEST_GUIDELINES"
}

@test "spec-test-guidelines: both patch route template occurrences use --commit" {
    count=$(grep -c -- "--commit" "$SPEC_TEST_GUIDELINES")
    [ "$count" -ge 2 ]
}

@test "bash subshell: \$(git rev-parse HEAD) expands to a 40-char hex SHA" {
    result=$(bash -c 'git -C "'"$PROJECT_ROOT"'" rev-parse HEAD')
    [ "${#result}" -eq 40 ]
    [[ "$result" =~ ^[0-9a-f]{40}$ ]]
}
