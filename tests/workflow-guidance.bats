#!/usr/bin/env bats

# Structural regression tests for skills/review/workflow-guidance.md.
# The embedded Inline Workflow Script is a markdown literal — invisible to
# lint, CI static analysis, and normal test runners (same constraint as
# tests/visual-diff-adapter.bats). These tests grep-guard the pipeline
# structure so the adversarial-verify stage cannot silently regress into
# returning an unexecuted thunk array again (#1010: pipeline's second stage
# returned thunks with no parallel()/await wrapping them, so the verify
# agents never ran and findings were silently dropped to confirmed: []).

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
GUIDANCE_FILE="$PROJECT_ROOT/skills/review/workflow-guidance.md"

@test "workflow-guidance: ## Inline Workflow Script section exists" {
    grep -q "^## Inline Workflow Script" "$GUIDANCE_FILE"
}

@test "workflow-guidance: verify stage thunk array is executed via parallel()" {
    grep -q "return parallel(finderResult.findings.map(finding =>" "$GUIDANCE_FILE"
}
