#!/usr/bin/env bats

# Tests for verify-executor.md branch-filter documentation.
# Confirms that patch route github_check templates use --branch=main (not
# --commit=$(git rev-parse HEAD), which always returns an empty result for the
# implementation commit — see modules/verify-classifier.md § Patch Route CI
# Verification Note).

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
VERIFY_CLASSIFIER="$PROJECT_ROOT/modules/verify-classifier.md"
SPEC_TEST_GUIDELINES="$PROJECT_ROOT/skills/issue/spec-test-guidelines.md"
VERIFY_EXECUTOR="$PROJECT_ROOT/modules/verify-executor.md"

@test "verify-classifier: --branch=main filter is present in patch route template" {
    grep -q -- "--branch=main" "$VERIFY_CLASSIFIER"
}

@test "verify-classifier: patch route template does not use --commit=\$(git rev-parse HEAD)" {
    ! grep -q -- '--commit=$(git rev-parse HEAD)' "$VERIFY_CLASSIFIER"
}

@test "spec-test-guidelines: --branch=main filter is present in patch route template" {
    grep -q -- "--branch=main" "$SPEC_TEST_GUIDELINES"
}

@test "spec-test-guidelines: both patch route template occurrences use --branch=main" {
    count=$(grep -c -- "--branch=main" "$SPEC_TEST_GUIDELINES")
    [ "$count" -ge 2 ]
}

@test "verify-executor: html_check uses html-selector-match.py" {
    grep -q "html-selector-match.py" "$VERIFY_EXECUTOR"
}

@test "verify-executor: html_check no longer gates on which pup" {
    ! grep -q "If pup exists, run" "$VERIFY_EXECUTOR"
}

@test "verify-executor: html_check documents combinator support" {
    grep -q "combinator" "$VERIFY_EXECUTOR"
}

# Regression guard: the html_check row is edited by both the Basic Auth work
# (#1074, which injects credentials via a curl --config file rather than argv)
# and the combinator work (#1069). A merge that resolves that row by taking one
# side wholesale silently drops the other. Pin both on the same line.
@test "verify-executor: html_check row keeps both Basic Auth --config and combinator support" {
    row=$(grep -- '^| `html_check ' "$VERIFY_EXECUTOR")
    [ -n "$row" ]
    printf '%s' "$row" | grep -q -- '--config "\$config_file"'
    printf '%s' "$row" | grep -q "combinator"
}

@test "verify-executor: html_check row declares a 30s execution timeout" {
    row=$(grep -- '^| `html_check ' "$VERIFY_EXECUTOR")
    [ -n "$row" ]
    printf '%s' "$row" | grep -q "html-selector-match\.py.*30"
}

@test "verify-executor: every curl-based URL command keeps the Basic Auth --config hook" {
    for cmd in http_status html_check api_check http_header http_redirect; do
        row=$(grep -- "^| \`$cmd " "$VERIFY_EXECUTOR")
        [ -n "$row" ]
        printf '%s' "$row" | grep -q -- '--config "\$config_file"'
    done
}
