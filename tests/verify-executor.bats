#!/usr/bin/env bats

# Tests for verify-executor.md commit-filter documentation and bash subshell expansion.
# Confirms that github_check templates use --commit=$(git rev-parse HEAD) to pin
# CI run lookup to a specific commit, avoiding concurrent-push interference.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
VERIFY_CLASSIFIER="$PROJECT_ROOT/modules/verify-classifier.md"
SPEC_TEST_GUIDELINES="$PROJECT_ROOT/skills/issue/spec-test-guidelines.md"
VERIFY_EXECUTOR="$PROJECT_ROOT/modules/verify-executor.md"

@test "verify-classifier: --commit filter is present in patch route template" {
    grep -q -- "--commit" "$VERIFY_CLASSIFIER"
}

@test "verify-classifier: patch route template uses git rev-parse HEAD" {
    grep -q "git rev-parse HEAD" "$VERIFY_CLASSIFIER"
}

@test "spec-test-guidelines: --commit filter is present in patch route template" {
    grep -q -- "--commit" "$SPEC_TEST_GUIDELINES"
}

@test "spec-test-guidelines: both patch route template occurrences use --commit" {
    count=$(grep -c -- "--commit" "$SPEC_TEST_GUIDELINES")
    [ "$count" -ge 2 ]
}

@test "bash subshell: \$(git rev-parse HEAD) expands to a 40-char hex SHA" {
    result=$(bash -c 'git -C "'"$PROJECT_ROOT"'" rev-parse HEAD')
    [ "${#result}" -eq 40 ]
    [[ "$result" =~ ^[0-9a-f]{40}$ ]]
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
