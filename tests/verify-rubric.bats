#!/usr/bin/env bats

# Shallow tests for rubric verify command documentation.
# LLM responses are not mocked; tests confirm that required documentation
# is present in modules/verify-executor.md and related files.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
VERIFY_EXECUTOR="$PROJECT_ROOT/modules/verify-executor.md"
VERIFY_PATTERNS="$PROJECT_ROOT/modules/verify-patterns.md"

@test "verify-executor: rubric command row exists in translation table" {
    grep -q 'rubric "text"' "$VERIFY_EXECUTOR"
}

@test "verify-executor: adversarial stance is documented" {
    grep -q "adversarial" "$VERIFY_EXECUTOR"
}

@test "verify-executor: PASS FAIL UNCERTAIN return values documented with gap description" {
    grep -qE "PASS.*FAIL.*UNCERTAIN|FAIL.*gap" "$VERIFY_EXECUTOR"
}

@test "verify-executor: safe mode returns UNCERTAIN for rubric" {
    grep -qE "rubric.*safe.*UNCERTAIN|safe.*rubric.*UNCERTAIN|safe mode.*rubric|rubric.*returns UNCERTAIN in safe mode" "$VERIFY_EXECUTOR"
}

@test "verify-executor: Spec files not passed to grader" {
    grep -q "Spec files are not passed to the grader" "$VERIFY_EXECUTOR"
}

@test "verify-executor: Rubric Command Semantics section exists" {
    grep -q "Rubric Command Semantics" "$VERIFY_EXECUTOR"
}

@test "verify-patterns: rubric selection guideline exists" {
    grep -q "rubric" "$VERIFY_PATTERNS"
}

@test "verify-patterns: section 9 rubric vs hard-pattern exists" {
    grep -qE "rubric.*hard-pattern|hard-pattern.*rubric" "$VERIFY_PATTERNS"
}
