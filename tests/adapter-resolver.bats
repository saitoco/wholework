#!/usr/bin/env bats

# Shallow tests for adapter-resolver module documentation.
# LLM responses are not mocked; tests confirm that required sections and
# contract terms are present in modules/adapter-resolver.md.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
ADAPTER_RESOLVER="$PROJECT_ROOT/modules/adapter-resolver.md"

@test "adapter-resolver: ## Purpose section exists" {
    grep -q "## Purpose" "$ADAPTER_RESOLVER"
}

@test "adapter-resolver: ## Input section exists" {
    grep -q "## Input" "$ADAPTER_RESOLVER"
}

@test "adapter-resolver: ## Processing Steps section exists" {
    grep -q "## Processing Steps" "$ADAPTER_RESOLVER"
}

@test "adapter-resolver: ## Output section exists" {
    grep -q "## Output" "$ADAPTER_RESOLVER"
}

@test "adapter-resolver: capability contract term is documented" {
    grep -q "capability" "$ADAPTER_RESOLVER"
}

@test "adapter-resolver: 3-layer or resolution order contract term is documented" {
    grep -qE "3-layer|resolution order" "$ADAPTER_RESOLVER"
}
