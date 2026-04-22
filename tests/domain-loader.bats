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

@test "domain-loader: load_when evaluation is documented" {
    grep -q "load_when" "$DOMAIN_LOADER"
}

@test "domain-loader: all typed keys are documented" {
    grep -q "file_exists_any" "$DOMAIN_LOADER"
    grep -q "marker" "$DOMAIN_LOADER"
    grep -q "capability" "$DOMAIN_LOADER"
    grep -q "arg_starts_with" "$DOMAIN_LOADER"
    grep -q "spec_depth" "$DOMAIN_LOADER"
}

@test "domain-loader: AND semantics is documented" {
    grep -q "AND" "$DOMAIN_LOADER"
}

@test "domain-loader: unconditional load for files without frontmatter is documented" {
    grep -q "unconditional" "$DOMAIN_LOADER"
}

@test "domain-loader: skill field array handling is documented" {
    grep -q "array" "$DOMAIN_LOADER"
}
