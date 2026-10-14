#!/usr/bin/env bats

# Tests for the patch-route `github_check` branch-filter form documented in
# modules/verify-classifier.md (SSoT) and propagated to skills/issue/SKILL.md,
# skills/verify/SKILL.md, modules/verify-patterns.md, and
# skills/issue/spec-test-guidelines.md. Confirms these templates use
# --branch=main (not a literal --commit=<SHA>, which always returns an empty
# result — see modules/verify-classifier.md § Patch Route CI Verification
# Note), plus verify-executor.md html_check assertions and the headSha
# run/commit correspondence check of the `gh run list` github_check
# (Issue #1526).

load 'helpers/markdown-section'

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
VERIFY_CLASSIFIER="$PROJECT_ROOT/modules/verify-classifier.md"
SPEC_TEST_GUIDELINES="$PROJECT_ROOT/skills/issue/spec-test-guidelines.md"
VERIFY_EXECUTOR="$PROJECT_ROOT/modules/verify-executor.md"
VERIFY_PATTERNS="$PROJECT_ROOT/modules/verify-patterns.md"
ISSUE_SKILL="$PROJECT_ROOT/skills/issue/SKILL.md"
VERIFY_SKILL="$PROJECT_ROOT/skills/verify/SKILL.md"

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

@test "spec-test-guidelines: patch route templates do not use --commit=\$(git rev-parse HEAD)" {
    ! grep -q -- '--commit=$(git rev-parse HEAD)' "$SPEC_TEST_GUIDELINES"
}

@test "verify-patterns: patch route --branch=main filter is present" {
    grep -q -- "--branch=main" "$VERIFY_PATTERNS"
}

@test "issue-skill: --branch=main filter is present in patch route example" {
    grep -q -- "--branch=main" "$ISSUE_SKILL"
}

@test "verify-skill: --branch=main filter is present in patch route example" {
    grep -q -- "--branch=main" "$VERIFY_SKILL"
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

@test "verify-executor: CI Reference Fallback converts SUCCESS to PASS only when identity is confirmed" {
    grep -q "identity is confirmed (Step 2a)" "$VERIFY_EXECUTOR"
    grep -q -- "→ \*\*PASS\*\* (detail: record the confirmed signal and reasoning" "$VERIFY_EXECUTOR"
}

@test "verify-executor: CI Reference Fallback falls back to UNCERTAIN when identity is unconfirmed" {
    grep -q "but identity could not be confirmed" "$VERIFY_EXECUTOR"
    grep -q "could not be confirmed to cover the AC's verification target" "$VERIFY_EXECUTOR"
}

@test "verify-executor: CI Reference Fallback lists the three identity confirmation signals" {
    grep -q "Run command containment" "$VERIFY_EXECUTOR"
    grep -q "Exact job name match" "$VERIFY_EXECUTOR"
    grep -q "Execution target path containment" "$VERIFY_EXECUTOR"
}

@test "verify-executor: gh run list section documents the headSha run/commit correspondence check" {
    section="$(md_section "$VERIFY_EXECUTOR" '### github_check: `gh run list` In-Progress Detection Constraint')"
    printf '%s' "$section" | grep -qF 'headSha' || false
    printf '%s' "$section" | grep -qF 'Run/commit correspondence check' || false
    printf '%s' "$section" | grep -qF 'closes #<ISSUE_NUMBER>([^0-9]|$)' || false
    printf '%s' "$section" | grep -qF 'compare/<IMPL_SHA>...<RUN_HEAD_SHA>' || false
    printf '%s' "$section" | grep -qF 'PENDING'
}

@test "verify-executor: github_check table row points to the run/commit correspondence check" {
    row="$(grep -F '| `github_check "gh_command" "expected_value"` |' "$VERIFY_EXECUTOR")"
    [ -n "$row" ]
    printf '%s' "$row" | grep -qF 'Run/commit correspondence check'
}

@test "verify-executor: only one heading contains gh run list (section_contains heading match stays unambiguous)" {
    count="$(grep -cE '^#+ .*gh run list' "$VERIFY_EXECUTOR")"
    [ "$count" -eq 1 ]
}

@test "verify-classifier: Patch Route CI Verification Note points to the run/commit correspondence check" {
    section="$(md_section "$VERIFY_CLASSIFIER" '### Patch Route CI Verification Note')"
    printf '%s' "$section" | grep -qF 'Run/commit correspondence check' || false
    printf '%s' "$section" | grep -qF 'headSha'
}
