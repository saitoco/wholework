#!/usr/bin/env bats

# Shallow tests for rubric safe-mode dispatch in /review path.
# Confirms documentation state: grader runs in safe mode, consistent with always_allow permission.
# LLM responses are not mocked; tests validate documentation structure only.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
VERIFY_EXECUTOR="$PROJECT_ROOT/modules/verify-executor.md"
VERIFY_PATTERNS="$PROJECT_ROOT/modules/verify-patterns.md"

@test "verify-executor: rubric translation table row is Mode-independent" {
    grep -q "Mode-independent" "$VERIFY_EXECUTOR"
}

@test "verify-executor: Rubric Command Semantics section mentions always_allow for safe mode" {
    awk '/Rubric Command Semantics/{f=1; next} f && /^### /{exit} f' "$VERIFY_EXECUTOR" | grep -q "always_allow"
}

@test "verify-executor: rubric safe mode behavior does not say returns UNCERTAIN in safe mode" {
    if grep -q "returns UNCERTAIN in safe mode" "$VERIFY_EXECUTOR"; then
        echo "Found deprecated text 'returns UNCERTAIN in safe mode' in verify-executor.md"
        return 1
    fi
}

@test "verify-patterns: section 9 mentions /review pre-merge rubric dispatch" {
    awk '/When to Use.*rubric/,/^## /' "$VERIFY_PATTERNS" | grep -q "/review"
}
