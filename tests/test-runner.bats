#!/usr/bin/env bats

# Shallow tests for test-runner module documentation.
# LLM responses are not mocked; tests confirm that required sections and
# contract terms are present in modules/test-runner.md.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TEST_RUNNER="$PROJECT_ROOT/modules/test-runner.md"

@test "test-runner: ## Purpose section exists" {
    grep -q "## Purpose" "$TEST_RUNNER"
}

@test "test-runner: ## Input section exists" {
    grep -q "## Input" "$TEST_RUNNER"
}

@test "test-runner: ## Processing Steps section exists" {
    grep -q "## Processing Steps" "$TEST_RUNNER"
}

@test "test-runner: ## Output Format section exists" {
    grep -q "## Output Format" "$TEST_RUNNER"
}

@test "test-runner: PASS condition is documented" {
    grep -q "PASS" "$TEST_RUNNER"
}

@test "test-runner: FAIL condition is documented" {
    grep -q "FAIL" "$TEST_RUNNER"
}
