#!/usr/bin/env bats

# Tests for skills/code/SKILL.md structural content
# Verifies always-pr spec is present in Step 0 Route Detection (Issue #783)

SKILL_FILE="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/code/SKILL.md"

load 'helpers/markdown-section'

# Extract Step 0 section: from "### Step 0:" to the next heading of level 3 or higher
step0_section() {
    md_section "$1" "### Step 0:"
}

# Extract Follow-up Issue Creation section: from "#### Follow-up Issue Creation" to the next heading of level 4 or higher
followup_issue_section() {
    md_section "$1" "#### Follow-up Issue Creation"
}

@test "Step 0 section contains always-pr keyword" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"always-pr"* ]]
}

@test "Step 0 section contains ALWAYS_PR variable" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"ALWAYS_PR"* ]]
}

@test "Step 0 section references detect-config-markers.md" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"detect-config-markers.md"* ]]
}

@test "Step 0 section describes pr route forced when ALWAYS_PR=true" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"pr route"* ]]
    [[ "$output" == *"ALWAYS_PR=true"* ]]
}

@test "Step 0 section describes --patch flag warning when ALWAYS_PR=true" {
    run step0_section "$SKILL_FILE"
    [[ "$output" == *"--patch"* ]]
    [[ "$output" == *"ignored"* ]] || [[ "$output" == *"Warning"* ]]
}

@test "Follow-up Issue Creation section contains open-issue duplicate check" {
    run followup_issue_section "$SKILL_FILE"
    [[ "$output" == *"gh issue list"* ]]
}

# Extract Step 8 section: from "### Step 8:" to the next heading of level 3 or higher
step8_section() {
    md_section "$1" "### Step 8:"
}

@test "Step 8 section describes patch route final-step commit deferral and pr route exclusion" {
    run step8_section "$SKILL_FILE"
    [[ "$output" == *"patch route"* ]]
    [[ "$output" == *"final Implementation Step"* ]]
    [[ "$output" == *"does not apply to pr route"* ]]
}

# Extract Step 11 section: from "### Step 11:" to the next heading of level 3 or higher
step11_section() {
    md_section "$1" "### Step 11:"
}

@test "Step 11 patch route commit template includes closes NUMBER inline" {
    run step11_section "$SKILL_FILE"
    [[ "$output" == *'(closes #$NUMBER)'* ]]
}

@test "Step 11 patch route includes commit subject issue-number guard" {
    run step11_section "$SKILL_FILE"
    [[ "$output" == *'missing #$NUMBER reference'* ]]
}

@test "Step 11 patch route documents closes as reconcile-phase-state.sh completion signal" {
    run step11_section "$SKILL_FILE"
    [[ "$output" == *"reconcile-phase-state.sh"* ]]
    [[ "$output" == *"_completion_code_patch"* ]]
    [[ "$output" == *"silent no-op"* ]]
}

@test "Step 11 patch route documents push-state-dependent closes fallback (amend vs empty commit)" {
    run step11_section "$SKILL_FILE"
    [[ "$output" == *"--amend"* ]]
    [[ "$output" == *"--allow-empty"* ]]
}

# Extract Step 9 section: from "### Step 9:" to the next heading of level 3 or higher
step9_section() {
    md_section "$1" "### Step 9:"
}

# Extract Behavioral Change Detection subsection: from "#### Behavioral Change Detection"
# to the next heading of level 4 or higher
behavioral_change_detection_section() {
    md_section "$1" "#### Behavioral Change Detection"
}

@test "Step 9 section states execution surface constraint (run_in_background) at a branch-independent position" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *"run_in_background"* ]]
}

@test "Behavioral Change Detection subsection does not restate the execution surface constraint" {
    # Plain assignment (not run) so a missing heading fails the test (Issue #1516)
    section="$(behavioral_change_detection_section "$SKILL_FILE")"
    [[ "$section" != *"run_in_background"* ]]
}

@test "Step 9 full-suite override uses the parallel bats form" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *"bats --jobs"* ]]
}

@test "Step 9 full-suite override keeps the portable nproc/sysctl job-count form" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *'nproc 2>/dev/null || sysctl -n hw.logicalcpu'* ]]
}

@test "Step 9 full-suite override does not invoke the serial whole-suite form" {
    # Plain assignment (not run) so a missing heading fails the test (Issue #1516)
    section="$(step9_section "$SKILL_FILE")"
    # `bats tests/` alone would exceed the tool's 10-minute ceiling and be
    # auto-backgrounded (Issue #1213). Only the --jobs form may appear as a
    # runnable command; prose may still mention the directory. Match on
    # trimmed line content rather than exact indentation so a Markdown
    # reformat cannot silently defeat this negative assertion.
    run bash -c 'printf "%s\n" "$1" | sed "s/^[[:space:]]*//" | grep -qx "bats tests/"' _ "$section"
    [ "$status" -ne 0 ]
}

@test "Step 9 full-suite override resolves the job count as a separate literal step (no inline command substitution)" {
    # Plain assignment (not run) so a missing heading fails the test (Issue #1516)
    section="$(step9_section "$SKILL_FILE")"
    [[ "$section" != *'bats --jobs $('* ]]
    [[ "$section" == *"bats --jobs <N> tests/"* ]]
}

@test "Step 9 execution surface constraint states the tool timeout ceiling" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *"600000"* ]]
    [[ "$output" == *"ceiling"* ]]
}

@test "Step 9 execution surface constraint states that exceeding the ceiling backgrounds the command" {
    run step9_section "$SKILL_FILE"
    [[ "$output" == *"moved to the background"* ]]
}

# Extract New Verification-Test Pre-implementation FAIL Check subsection: from its heading
# to the next heading of level 4 or higher
new_verification_test_fail_check_section() {
    md_section "$1" "#### New Verification-Test Pre-implementation FAIL Check"
}

@test "code skill documents New Verification-Test Pre-implementation FAIL Check heading" {
    grep -q '^#### New Verification-Test Pre-implementation FAIL Check' "$SKILL_FILE"
}

@test "New Verification-Test Pre-implementation FAIL Check identifies string-matching assert targets" {
    run new_verification_test_fail_check_section "$SKILL_FILE"
    [[ "$output" == *"file_contains"* ]]
    [[ "$output" == *"Target identification"* ]]
}

@test "New Verification-Test Pre-implementation FAIL Check describes handling of unintended PASS" {
    run new_verification_test_fail_check_section "$SKILL_FILE"
    [[ "$output" == *"Handling unintended PASS"* ]]
    [[ "$output" == *"more specific string"* ]] || [[ "$output" == *"section-level extraction"* ]]
}

@test "New Verification-Test Pre-implementation FAIL Check records result in Code Retrospective" {
    run new_verification_test_fail_check_section "$SKILL_FILE"
    [[ "$output" == *"Code Retrospective"* ]]
    [[ "$output" == *"pre-implementation FAIL"* ]]
}

# Extract Step 10 section: from "### Step 10:" to the next heading of level 3 or higher
step10_section() {
    md_section "$1" "### Step 10:"
}

@test "Step 10 Patch route verify command check fires for both patch and operate route" {
    run step10_section "$SKILL_FILE"
    [[ "$output" == *'If ROUTE is `patch` or `operate`'* ]]
}

@test "Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route" {
    run step10_section "$SKILL_FILE"
    [[ "$output" == *"Step 10 runs before the commit or PR that would produce a CI run"* ]]
}

# Language convention pre-commit check (Issue #1484)
LANG_CHECK_DOC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/skills/code/language-convention-check.md"

@test "Step 9 reads language-convention-check.md only when check-language-convention.py exists" {
    run step9_section "$SKILL_FILE"
    echo "$output" | grep -qF 'If `scripts/check-language-convention.py` exists, Read' || false
    echo "$output" | grep -qF 'skills/code/language-convention-check.md' || false
}

@test "SKILL.md allowed-tools pre-approves git merge-base for the language convention check" {
    head -6 "$SKILL_FILE" | grep -qF 'git merge-base:*' || false
}

@test "language-convention-check.md is a code Domain file gated on scripts/check-language-convention.py" {
    head -8 "$LANG_CHECK_DOC" | grep -qF 'type: domain' || false
    head -8 "$LANG_CHECK_DOC" | grep -qF 'skill: code' || false
    head -8 "$LANG_CHECK_DOC" | grep -qF 'file_exists_any: [scripts/check-language-convention.py]' || false
}

@test "language-convention-check.md skips the whole check when check-language-convention.py is absent" {
    grep -qF 'skip this entire check' "$LANG_CHECK_DOC" || false
}

@test "language-convention-check.md runs the CI-equivalent diff form over skills/ modules/ scripts/" {
    grep -qF 'git diff -U100000 <base> -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py' "$LANG_CHECK_DOC" || false
}

@test "language-convention-check.md diffs from the merge base against the working tree so uncommitted changes are included" {
    grep -qF 'git merge-base "origin/$BASE_BRANCH" HEAD' "$LANG_CHECK_DOC" || false
    grep -qF 'uncommitted' "$LANG_CHECK_DOC" || false
}

@test "language-convention-check.md resolves the merge base as a separate literal step (no inline command substitution)" {
    run grep -F '$(git merge-base' "$LANG_CHECK_DOC"
    [ "$status" -ne 0 ]
}

@test "language-convention-check.md registers untracked new files with intent-to-add before diffing" {
    grep -qF 'git add -N' "$LANG_CHECK_DOC" || false
}

@test "language-convention-check.md requires fixing violations before committing" {
    grep -qF 'before committing' "$LANG_CHECK_DOC" || false
}

# bats-absent CI confirmation for patch route (Issue #1490)
# (step10_section is defined above)

# Extract Step 14 section: from "### Step 14:" to the next heading of level 3 or higher
step14_section() {
    md_section "$1" "### Step 14:"
}

@test "SKILL.md allowed-tools pre-approves gh run list, gh run watch and git rev-parse for the bats CI confirmation" {
    head -6 "$SKILL_FILE" | grep -qF 'gh run list:*' || false
    head -6 "$SKILL_FILE" | grep -qF 'gh run watch:*' || false
    head -6 "$SKILL_FILE" | grep -qF 'git rev-parse:*' || false
}

@test "Step 10 excludes bats command ACs when bats is absent on patch route" {
    section="$(step10_section "$SKILL_FILE")"
    printf '%s\n' "$section" | grep -qF 'bats-absent AC exclusion' || false
    printf '%s\n' "$section" | grep -qF 'command -v bats' || false
    printf '%s\n' "$section" | grep -qF 'BATS_DEFERRED_ACS' || false
}

@test "Step 10 bats-absent exclusion leaves the AC unchecked and rejects approximations as evidence" {
    section="$(step10_section "$SKILL_FILE")"
    printf '%s\n' "$section" | grep -qF 'do not check it off' || false
    printf '%s\n' "$section" | grep -qF 'is not evidence for the AC' || false
}

@test "Step 10 CI AC exclusion places the patch route push in Step 14" {
    section="$(step10_section "$SKILL_FILE")"
    printf '%s\n' "$section" | grep -qF 'the push happens in Step 14' || false
}

@test "Step 14 documents the CI-based bats AC confirmation with gh run list and gh run watch" {
    section="$(step14_section "$SKILL_FILE")"
    printf '%s\n' "$section" | grep -qF 'CI-based bats AC confirmation' || false
    printf '%s\n' "$section" | grep -qF 'gh run watch <run-id> --compact --interval 30' || false
    printf '%s\n' "$section" | grep -qF 'BATS_DEFERRED_ACS' || false
}

@test "Step 14 CI confirmation resolves the pushed head SHA as a separate literal step" {
    section="$(step14_section "$SKILL_FILE")"
    printf '%s\n' "$section" | grep -qF 'git rev-parse origin/$BASE_BRANCH' || false
    if printf '%s\n' "$section" | grep -qF '$(git rev-parse'; then
        false
    fi
}

@test "Step 14 CI confirmation filters the run by workflow, commit and push event" {
    section="$(step14_section "$SKILL_FILE")"
    printf '%s\n' "$section" | grep -qF 'gh run list --workflow=<workflow-file> --commit <SHA> --event push' || false
}

@test "Step 14 CI confirmation reads the bats job conclusion rather than the workflow level result" {
    section="$(step14_section "$SKILL_FILE")"
    printf '%s\n' "$section" | grep -qF 'select(.name == "<bats job name>")' || false
    printf '%s\n' "$section" | grep -qF 'Only a completed job with conclusion' || false
}

@test "Step 14 CI confirmation defers to verify when CI is still running and handles CI failure without exiting" {
    section="$(step14_section "$SKILL_FILE")"
    printf '%s\n' "$section" | grep -qF 'Still running or unknown' || false
    printf '%s\n' "$section" | grep -qF 'deferred to /verify' || false
    printf '%s\n' "$section" | grep -qF 'CI failure' || false
    printf '%s\n' "$section" | grep -qF 'do not exit non-zero' || false
}

@test "Step 14 CI confirmation runs after the push and before the Implementation Complete comment" {
    section="$(step14_section "$SKILL_FILE")"
    ci_line="$(printf '%s\n' "$section" | grep -nF 'CI-based bats AC confirmation' | head -1 | cut -d: -f1)"
    comment_line="$(printf '%s\n' "$section" | grep -nF 'Implementation Complete comment (patch route, before label transition)' | head -1 | cut -d: -f1)"
    [ -n "$ci_line" ] || false
    [ -n "$comment_line" ] || false
    [ "$ci_line" -lt "$comment_line" ] || false
}
