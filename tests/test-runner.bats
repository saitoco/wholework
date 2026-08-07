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

@test "test-runner: parallel bats form is prescribed for whole-suite runs" {
    grep -q -F "bats --jobs" "$TEST_RUNNER"
}

@test "test-runner: job count uses the portable nproc/sysctl form" {
    grep -q -F 'nproc 2>/dev/null || sysctl -n hw.logicalcpu' "$TEST_RUNNER"
}

@test "test-runner: Step 2 states the 600000 ms tool timeout ceiling" {
    grep -q -F "600000" "$TEST_RUNNER"
}

@test "test-runner: exceeding the ceiling is documented as auto-backgrounding" {
    grep -q -F "moved to the background" "$TEST_RUNNER"
}

@test "test-runner: serial fallback is documented for missing GNU parallel" {
    grep -q -F "Fallback when \`--jobs\` is unavailable" "$TEST_RUNNER"
    grep -q -F "not a test failure" "$TEST_RUNNER"
}

@test "test-runner: missing-parallel fallback shards rather than re-running one serial whole-suite command" {
    grep -q -F "sharded serial batches" "$TEST_RUNNER"
}

@test "test-runner: job count is resolved as a separate literal step, not inline command substitution" {
    run grep -F 'bats --jobs $(nproc' "$TEST_RUNNER"
    [ "$status" -ne 0 ]
    grep -q -F "bats --jobs <N> tests/" "$TEST_RUNNER"
}
