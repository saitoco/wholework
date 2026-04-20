#!/usr/bin/env bats

# Shallow tests for doc-checker module documentation.
# LLM responses are not mocked; tests confirm that document references and
# contract terms are present in modules/doc-checker.md.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
DOC_CHECKER="$PROJECT_ROOT/modules/doc-checker.md"

@test "doc-checker: README.md, CLAUDE.md, and workflow.md are referenced" {
    grep -q "README.md" "$DOC_CHECKER"
    grep -q "CLAUDE.md" "$DOC_CHECKER"
    grep -q "workflow.md" "$DOC_CHECKER"
}

@test "doc-checker: missed updates contract term is documented" {
    grep -q "missed updates" "$DOC_CHECKER"
}

@test "doc-checker: command example contract term is documented" {
    grep -q "command example" "$DOC_CHECKER"
}
