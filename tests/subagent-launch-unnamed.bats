#!/usr/bin/env bats

# Regression guard for unnamed sub-agent launches (Issue #1525, follow-up of #1522).
#
# With agent teams enabled in an interactive session, an Agent/Task launch that carries a
# `name` starts an in-process teammate. Its result goes to the main session instead of back to
# the launching orchestrator, which can neither receive nor stop it when it is itself a forked
# sub-agent. #1522 removed every explicit name from:
#   - skills/review/SKILL.md: the Step 10 sub-agents (review-light, review-spec, review-bug,
#     bug-verify) and the Parser/Validator Edge Case Pre-check measurement sub-agents (edge-case)
#   - modules/verify-executor.md: the rubric grader
# These tests fail when an explicit name comes back in either file.
#
# skills/issue/SKILL.md Step 12a is deliberately not scanned: its named investigation agents
# (scope / risk / precedent) are intended (#1521).
#
# The tests validate documentation text only; no LLM response is mocked.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REVIEW_SKILL="$PROJECT_ROOT/skills/review/SKILL.md"
VERIFY_EXECUTOR="$PROJECT_ROOT/modules/verify-executor.md"

# Explicit-name shapes (ERE, matched per line):
# 1. a `name` argument with a quoted value: name="x" or name='x'. The left boundary keeps
#    identifiers such as job_name="x" out, and a jq comparison such as .name=="x" has no quote
#    right after its first "=".
NAME_ARG_DQ='(^|[^[:alnum:]_])name[[:space:]]*=[[:space:]]*"'
NAME_ARG_SQ="(^|[^[:alnum:]_])name[[:space:]]*=[[:space:]]*'"
# 2. the names used before #1522, "<label>-$NUMBER". Result files are named
#    .tmp/subagent-result-$NUMBER-<label>.md (the number comes first), so they do not match.
OLD_NAMES='(review-light|review-spec|review-bug-diff|review-bug-security|bug-verify|edge-case|rubric-grader)-\$NUMBER'
# 3. TaskStop addressed by a literal name; the unnamed form is TaskStop(task_id: "<agent ID>")
NAMED_STOP='TaskStop\(task_id: "[^<]'

# explicit_name_lines FILE
#   Prints "LINE:text" for each line of FILE that carries an explicit sub-agent name.
#   Status: 0 = none found, 1 = found, 2 = FILE missing or empty, or grep failed (fail closed,
#   so that a moved or truncated target never passes as "no names").
explicit_name_lines() {
    local file="$1" hits="" rc=0
    if [ ! -s "$file" ]; then
        echo "explicit_name_lines: $file is missing or empty" >&2
        return 2
    fi
    hits="$(grep -a -n -E -e "$NAME_ARG_DQ" -e "$NAME_ARG_SQ" -e "$OLD_NAMES" -e "$NAMED_STOP" "$file")" || rc=$?
    case "$rc" in
        0) printf '%s\n' "$hits"; return 1 ;;
        1) return 0 ;;
        *) echo "explicit_name_lines: grep failed on $file (status $rc)" >&2; return 2 ;;
    esac
}

# copy_with_line SRC LINE
#   Copies SRC into the test's temp dir, appends LINE, and prints the copy's path.
copy_with_line() {
    local copy
    copy="$BATS_TEST_TMPDIR/$(basename "$1")"
    cp "$1" "$copy"
    printf '%s\n' "$2" >> "$copy"
    printf '%s\n' "$copy"
}

# The two helpers judge only the appended LINE, never the whole file, so that a real regression
# in the current files fails the two "current files" tests alone and does not cascade into
# these detector tests.

# assert_flagged FILE LINE: FILE with LINE appended reports LINE.
assert_flagged() {
    local mutant
    mutant="$(copy_with_line "$1" "$2")"
    run explicit_name_lines "$mutant"
    echo "$output"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$2"* ]] || false
}

# assert_not_flagged FILE LINE: FILE with LINE appended does not report LINE.
assert_not_flagged() {
    local mutant
    mutant="$(copy_with_line "$1" "$2")"
    run explicit_name_lines "$mutant"
    echo "$output"
    [ "$status" -ne 2 ]
    [[ "$output" != *"$2"* ]] || false
}

# --- the current files -------------------------------------------------------------------

@test "review SKILL.md: no Step 10 sub-agent launch carries an explicit name" {
    run explicit_name_lines "$REVIEW_SKILL"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "verify-executor.md: the rubric grader launch carries no explicit name" {
    run explicit_name_lines "$VERIFY_EXECUTOR"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "the scanned files still hold the sub-agent launches this guard covers" {
    # Reference point for the two checks above: without it, a launch section moved to another
    # file would leave them passing against text that no longer contains any launch.
    grep -q 'subagent_type=' "$REVIEW_SKILL"
    grep -q 'Grader sub-agent name and stop' "$VERIFY_EXECUTOR"
}

# --- a reintroduced name is reported (the pre-#1522 forms) -----------------------------------

@test "review SKILL.md: a reintroduced review-light name is detected" {
    assert_flagged "$REVIEW_SKILL" '     name="review-light-$NUMBER",'
}

@test "review SKILL.md: a reintroduced review-spec name is detected" {
    assert_flagged "$REVIEW_SKILL" '     name="review-spec-$NUMBER",'
}

@test "review SKILL.md: reintroduced review-bug names are detected" {
    assert_flagged "$REVIEW_SKILL" '     name="review-bug-diff-$NUMBER",'
    assert_flagged "$REVIEW_SKILL" '     name="review-bug-security-$NUMBER",'
}

@test "review SKILL.md: a reintroduced bug-verify name is detected" {
    assert_flagged "$REVIEW_SKILL" '     name="bug-verify-$NUMBER-{n}",'
}

@test "review SKILL.md: a reintroduced edge-case name is detected" {
    assert_flagged "$REVIEW_SKILL" 'launch a Task sub-agent in parallel, each with an explicit `name="edge-case-$NUMBER-{n}"` (`{n}` = 1 or 2)'
}

@test "verify-executor.md: a reintroduced rubric-grader name is detected" {
    assert_flagged "$VERIFY_EXECUTOR" '- **Name**: `rubric-grader-$NUMBER`, where `$NUMBER` is the calling skill number.'
    assert_flagged "$VERIFY_EXECUTOR" 'TaskStop(task_id: "rubric-grader-$NUMBER")'
}

# --- each rule is live on its own -----------------------------------------------------------

@test "detects any quoted name argument, not only the pre-1522 names" {
    assert_flagged "$REVIEW_SKILL" '     name="my-reviewer",'
    assert_flagged "$REVIEW_SKILL" "     name='my-reviewer',"
    assert_flagged "$VERIFY_EXECUTOR" 'launch the grader with name = "my-grader"'
}

@test "detects a pre-1522 name written without a name argument" {
    assert_flagged "$REVIEW_SKILL" 'Stop `review-light-$NUMBER` as soon as its result is in hand.'
    assert_flagged "$VERIFY_EXECUTOR" 'Give each grader `rubric-grader-$NUMBER-{n}` so that each can be stopped on its own.'
}

@test "detects TaskStop addressed by a literal name instead of the agent ID" {
    assert_flagged "$REVIEW_SKILL" 'TaskStop(task_id: "my-reviewer")'
    assert_flagged "$VERIFY_EXECUTOR" 'TaskStop(task_id: "grader-1")'
}

# --- explanatory text and look-alikes are not reported --------------------------------------

@test "does not flag text that says no name is passed" {
    assert_not_flagged "$REVIEW_SKILL" 'Every Task in Step 10 is launched **without a `name`**.'
    assert_not_flagged "$REVIEW_SKILL" 'Never add a `name` to a Step 10 launch, not even to make a later TaskStop easier.'
    assert_not_flagged "$VERIFY_EXECUTOR" '- **Name**: none. Do not pass a `name` to the grader Agent/Task call.'
}

@test "does not flag look-alike text" {
    assert_not_flagged "$VERIFY_EXECUTOR" 'TaskStop(task_id: "<agent ID>")'
    assert_not_flagged "$REVIEW_SKILL" 'Result file: .tmp/subagent-result-$NUMBER-review-light.md'
    assert_not_flagged "$REVIEW_SKILL" 'Result file: .tmp/subagent-result-$NUMBER-edge-case-{n}.md'
    assert_not_flagged "$VERIFY_EXECUTOR" 'Result file: .tmp/subagent-result-$NUMBER-rubric-grader-{n}.md'
    assert_not_flagged "$VERIFY_EXECUTOR" "--jq '.[] | select(.name==\"<job_name>\") | .state'"
    assert_not_flagged "$VERIFY_EXECUTOR" 'job_name="Run bats tests"'
    assert_not_flagged "$REVIEW_SKILL" 'SKILL_NAME="review"'
    assert_not_flagged "$REVIEW_SKILL" 'name: review'
}

# --- the check itself fails closed ----------------------------------------------------------

@test "a missing or empty target file fails the check instead of passing it" {
    run explicit_name_lines "$BATS_TEST_TMPDIR/does-not-exist.md"
    [ "$status" -eq 2 ]
    : > "$BATS_TEST_TMPDIR/empty.md"
    run explicit_name_lines "$BATS_TEST_TMPDIR/empty.md"
    [ "$status" -eq 2 ]
}
