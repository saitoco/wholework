#!/usr/bin/env bats

# Shallow tests for domain-loader module documentation.
# LLM responses are not mocked; tests confirm that discovery/loading contract
# terms are present in modules/domain-loader.md.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
DOMAIN_LOADER="$PROJECT_ROOT/modules/domain-loader.md"

@test "domain-loader: .wholework/domains/ path is documented" {
    grep -q "\.wholework/domains/" "$DOMAIN_LOADER"
}

@test "domain-loader: Markdown file type is documented" {
    grep -q "Markdown" "$DOMAIN_LOADER"
}

@test "domain-loader: discovery contract term is documented (Glob, Discover, or load)" {
    grep -qiE "Glob|Discover|load" "$DOMAIN_LOADER"
}
