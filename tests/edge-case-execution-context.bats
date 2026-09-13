#!/usr/bin/env bats

# Structural regression tests for the Parser/Validator Edge Case Pre-check's
# execution-context (CWD) axis, added in Issue #1470 to close the detection
# gap that let scripts/detect-pr-ci-workflows.sh's CWD-dependent bug (#1463)
# pass the pre-check's fixture-execution sub-agent unnoticed.

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/review/SKILL.md"

@test "review SKILL.md: Parser/Validator Edge Case Pre-check documents the execution context axis" {
    grep -q "Execution context axis" "$SKILL_FILE"
}

@test "review SKILL.md: Edge Case Pre-check re-executes fixtures from a non-repository-root CWD" {
    grep -q "CWD other than the repository root" "$SKILL_FILE"
}
