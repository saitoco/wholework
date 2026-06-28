#!/usr/bin/env bats
# Structural regression tests for verify command heuristic guidelines.
PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
VERIFY_PATTERNS="$PROJECT_ROOT/modules/verify-patterns.md"

@test "verify-heuristics: non-contiguous heuristic section exists in verify-patterns.md" {
    grep -q "non-contiguous" "$VERIFY_PATTERNS"
}

@test "verify-heuristics: contiguous sub-string guidance is documented" {
    grep -q "contiguous" "$VERIFY_PATTERNS"
}

@test "verify-heuristics: git -C example is present in verify-patterns.md" {
    grep -q 'git -C' "$VERIFY_PATTERNS"
}
