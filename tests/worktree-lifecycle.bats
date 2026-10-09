#!/usr/bin/env bats

# Structure tests for the ExitWorktree rejection handling (Issue #1512).
# The Exit failure handling procedure is LLM-executed prose, so these tests
# confirm that the module and the three context: fork skills carry the
# required branches, contract terms and ordering; they do not execute it.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
MODULE="$PROJECT_ROOT/modules/worktree-lifecycle.md"
CODE_SKILL="$PROJECT_ROOT/skills/code/SKILL.md"
REVIEW_SKILL="$PROJECT_ROOT/skills/review/SKILL.md"
MERGE_SKILL="$PROJECT_ROOT/skills/merge/SKILL.md"

# Extract a section: from a line starting with $2 to the next heading of the
# same or a higher level (level given by $3, the number of leading '#').
# Usage: section FILE HEADING_PREFIX LEVEL
section() {
    awk -v prefix="$2" -v level="$3" '
        index($0, prefix) == 1 { found = 1; print; next }
        found {
            match($0, /^#+/)
            if (RLENGTH > 0 && RLENGTH <= level && substr($0, RLENGTH + 1, 1) == " ") exit
            print
        }
    ' "$1"
}

failure_section() {
    section "$MODULE" "### Exit failure handling" 3
}

# Line number of the first line in stdin matching the fixed string $1
line_of() {
    grep -nF -- "$1" | head -1 | cut -d: -f1
}

@test "worktree-lifecycle: Exit failure handling section exists with Steps A to D" {
    s="$(failure_section)"
    [ -n "$s" ]
    printf '%s\n' "$s" | grep -qF '**Step A'
    printf '%s\n' "$s" | grep -qF '**Step B'
    printf '%s\n' "$s" | grep -qF '**Step C'
    printf '%s\n' "$s" | grep -qF '**Step D'
}

@test "worktree-lifecycle: Exit failure handling quotes the cwd override error" {
    s="$(failure_section)"
    printf '%s\n' "$s" | grep -qF 'cwd override'
    printf '%s\n' "$s" | grep -qF 'ExitWorktree cannot be called from a subagent'
}

@test "worktree-lifecycle: both Exit sections reference Exit failure handling" {
    m="$(section "$MODULE" "### Exit: merge-to-main" 3)"
    p="$(section "$MODULE" "### Exit: push-and-remove" 3)"
    printf '%s\n' "$m" | grep -qF 'Exit failure handling'
    printf '%s\n' "$p" | grep -qF 'Exit failure handling'
}

@test "worktree-lifecycle: one-line warning wording is gone from the module" {
    run grep -c 'Please remove manually' "$MODULE"
    [ "$output" = "0" ]
    run grep -c 'Failed to remove worktree' "$MODULE"
    [ "$output" = "0" ]
}

@test "worktree-lifecycle: Step A verifies with detect-foreign-worktree.sh and treats non-none as failure" {
    s="$(failure_section)"
    a="$(printf '%s\n' "$s" | awk '/\*\*Step A/{f=1} /\*\*Step B/{f=0} f{print}')"
    printf '%s\n' "$a" | grep -qF 'detect-foreign-worktree.sh'
    printf '%s\n' "$a" | grep -qF '`none`'
    printf '%s\n' "$a" | grep -qF 'treat it as a failure'
}

@test "worktree-lifecycle: Step B retries exactly once" {
    s="$(failure_section)"
    b="$(printf '%s\n' "$s" | awk '/\*\*Step B/{f=1} /\*\*Step C/{f=0} f{print}')"
    printf '%s\n' "$b" | grep -qF 'exactly once'
    printf '%s\n' "$b" | grep -qF 'Do not repeat it a second time'
}

@test "worktree-lifecycle: Step C uses keep then git worktree remove and git branch -D" {
    s="$(failure_section)"
    c="$(printf '%s\n' "$s" | awk '/\*\*Step C/{f=1} /\*\*Step D/{f=0} f{print}')"
    printf '%s\n' "$c" | grep -qF 'ExitWorktree(action: "keep")'
    printf '%s\n' "$c" | grep -qF 'git worktree remove --force "$WORKTREE_PATH"'
    printf '%s\n' "$c" | grep -qF 'git branch -D "$WORKTREE_BRANCH"'
    k="$(printf '%s\n' "$c" | line_of 'ExitWorktree(action: "keep")')"
    r="$(printf '%s\n' "$c" | line_of 'git worktree remove --force')"
    [ "$k" -lt "$r" ]
}

@test "worktree-lifecycle: Step D sets WORKTREE_LEFTOVER and never deletes the worktree it stands in" {
    s="$(failure_section)"
    d="$(printf '%s\n' "$s" | awk '/\*\*Step D/{f=1} /\*\*Leftover worktree report/{f=0} f{print}')"
    printf '%s\n' "$d" | grep -qF 'WORKTREE_LEFTOVER=true'
    printf '%s\n' "$d" | grep -qF 'Do not delete the worktree the session stands in'
}

@test "worktree-lifecycle: Leftover worktree report has Path, Checked-out branch and Recovery" {
    s="$(failure_section)"
    printf '%s\n' "$s" | grep -qF '1. Path: <WORKTREE_PATH>'
    printf '%s\n' "$s" | grep -qF '2. Checked-out branch:'
    printf '%s\n' "$s" | grep -qF '3. Recovery (run in the parent session, in this order):'
}

@test "worktree-lifecycle: recovery order is keep, then worktree remove, then branch -D" {
    s="$(failure_section)"
    rec="$(printf '%s\n' "$s" | awk '/3\. Recovery/{f=1} f{print}')"
    k="$(printf '%s\n' "$rec" | line_of 'ExitWorktree(action: "keep")')"
    r="$(printf '%s\n' "$rec" | line_of 'git worktree remove "<WORKTREE_PATH>"')"
    b="$(printf '%s\n' "$rec" | line_of 'git branch -D "<WORKTREE_BRANCH>"')"
    [ -n "$k" ]
    [ -n "$r" ]
    [ -n "$b" ]
    [ "$k" -lt "$r" ]
    [ "$r" -lt "$b" ]
}

@test "worktree-lifecycle: Output section lists WORKTREE_LEFTOVER" {
    o="$(section "$MODULE" "## Output" 2)"
    printf '%s\n' "$o" | grep -qF 'WORKTREE_LEFTOVER'
    printf '%s\n' "$o" | grep -qF 'WORKTREE_PATH'
    printf '%s\n' "$o" | grep -qF 'WORKTREE_BRANCH'
}

@test "worktree-lifecycle: code Step 14 references Exit failure handling and the Leftover worktree report" {
    s="$(section "$CODE_SKILL" "### Step 14:" 3)"
    printf '%s\n' "$s" | grep -qF 'Exit failure handling'
    printf '%s\n' "$s" | grep -qF 'Leftover worktree report'
}

@test "worktree-lifecycle: review Worktree Exit references Exit failure handling and the Leftover worktree report" {
    s="$(section "$REVIEW_SKILL" "## Worktree Exit (push-and-remove)" 2)"
    printf '%s\n' "$s" | grep -qF 'Exit failure handling'
    printf '%s\n' "$s" | grep -qF 'Leftover worktree report'
}

@test "worktree-lifecycle: merge Step 7 references Exit failure handling and the Leftover worktree report" {
    s="$(section "$MERGE_SKILL" "### Step 7:" 3)"
    printf '%s\n' "$s" | grep -qF 'Exit failure handling'
    printf '%s\n' "$s" | grep -qF 'Leftover worktree report'
}

@test "worktree-lifecycle: Completion Report of code, review and merge references the Leftover worktree report" {
    for f in "$CODE_SKILL" "$REVIEW_SKILL" "$MERGE_SKILL"; do
        s="$(section "$f" "## Completion Report" 2)"
        printf '%s\n' "$s" | grep -qF 'Leftover worktree report'
    done
}

@test "worktree-lifecycle: review Opportunistic Verification skips on WORKTREE_LEFTOVER" {
    s="$(section "$REVIEW_SKILL" "## Opportunistic Verification" 2)"
    printf '%s\n' "$s" | grep -qF 'WORKTREE_LEFTOVER'
    printf '%s\n' "$s" | grep -qF 'Skipping Opportunistic Verification'
}

@test "worktree-lifecycle: code Step 15 skips on WORKTREE_LEFTOVER" {
    s="$(section "$CODE_SKILL" "### Step 15:" 3)"
    printf '%s\n' "$s" | grep -qF 'WORKTREE_LEFTOVER'
}
