#!/usr/bin/env bats

# Shallow tests for visual-diff-adapter module documentation.
# LLM responses are not mocked; tests confirm that required sections and
# contract terms are present in modules/visual-diff-adapter.md.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
ADAPTER_FILE="$PROJECT_ROOT/modules/visual-diff-adapter.md"

@test "visual-diff-adapter: ## Purpose section exists" {
    grep -q "^## Purpose" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: ## Input section exists" {
    grep -q "^## Input" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: ## Processing Steps section exists" {
    grep -q "^## Processing Steps" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: ## Output section exists" {
    grep -q "^## Output" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: capability gate documented" {
    grep -q "HAS_VISUAL_DIFF_CAPABILITY" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: pixelmatch dependency documented" {
    grep -q "pixelmatch" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: sharp dependency documented" {
    grep -q "sharp" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: 3-panel composite documented" {
    grep -q "3-panel" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: frontend-visual-review sub-agent dispatch documented" {
    grep -q "frontend-visual-review" "$ADAPTER_FILE"
}

@test "visual-diff-adapter: Playwright tool detection documented" {
    grep -q "Playwright" "$ADAPTER_FILE"
}
