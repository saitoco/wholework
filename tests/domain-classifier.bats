#!/usr/bin/env bats

# Shallow tests for domain-classifier module documentation.
# LLM responses are not mocked; tests confirm that classification contract
# terms are present in modules/domain-classifier.md.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
DOMAIN_CLASSIFIER="$PROJECT_ROOT/modules/domain-classifier.md"

@test "domain-classifier: applies_to_proposals input key is documented" {
    grep -q "applies_to_proposals" "$DOMAIN_CLASSIFIER"
}

@test "domain-classifier: file_patterns input sub-key is documented" {
    grep -q "file_patterns" "$DOMAIN_CLASSIFIER"
}

@test "domain-classifier: content_keywords input sub-key is documented" {
    grep -q "content_keywords" "$DOMAIN_CLASSIFIER"
}

@test "domain-classifier: rewrite_target output key is documented" {
    grep -q "rewrite_target" "$DOMAIN_CLASSIFIER"
}

@test "domain-classifier: ambiguous domain value is documented" {
    grep -q "ambiguous" "$DOMAIN_CLASSIFIER"
}

@test "domain-classifier: none domain value is documented" {
    grep -q "none" "$DOMAIN_CLASSIFIER"
}

@test "domain-classifier: priority rule is documented (priority or both)" {
    grep -qiE "priority|both" "$DOMAIN_CLASSIFIER"
}

@test "domain-classifier: wildcard resolution rule is documented" {
    grep -qiE "wildcard|\\\*" "$DOMAIN_CLASSIFIER"
}

@test "domain-classifier: Input section exists" {
    grep -q "^## Input" "$DOMAIN_CLASSIFIER"
}

@test "domain-classifier: Output section exists" {
    grep -q "^## Output" "$DOMAIN_CLASSIFIER"
}
