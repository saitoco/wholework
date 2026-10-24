#!/usr/bin/env bats

# Structural tests for the assignee check (Issue #1544).
# The procedure itself is LLM-driven, so these tests check the wiring (module sections,
# call positions in each SKILL.md, allowed-tools, --assign) and the fixed wording.

load 'helpers/markdown-section'

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    MODULE="$PROJECT_ROOT/modules/assignee-check.md"
    ISSUE_SKILL="$PROJECT_ROOT/skills/issue/SKILL.md"
    SPEC_SKILL="$PROJECT_ROOT/skills/spec/SKILL.md"
    CODE_SKILL="$PROJECT_ROOT/skills/code/SKILL.md"
    LABEL_FIXED='**Assignee check (run before Step 2'
    MODULE_PATH='${CLAUDE_PLUGIN_ROOT}/modules/assignee-check.md'
}

# Print the line number of the first line that contains the literal string $2 in file $1.
first_line() {
    grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1
}

# Print the Existing Issue Refinement part of the /issue skill (everything from its heading
# to the next level-2 heading).
issue_existing_section() {
    md_section "$ISSUE_SKILL" "## Existing Issue Refinement"
}

@test "module: assignee-check.md has the four standard sections" {
    [ -f "$MODULE" ]
    grep -qxF '# assignee-check' "$MODULE"
    grep -qxF '## Purpose' "$MODULE"
    grep -qxF '## Input' "$MODULE"
    grep -qxF '## Processing Steps' "$MODULE"
    grep -qxF '## Output' "$MODULE"
}

@test "module: reads the status and reassigns through gh-issue-assignee.sh" {
    grep -qF '${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh status $ISSUE_NUMBER' "$MODULE"
    grep -qF '${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh reassign $ISSUE_NUMBER' "$MODULE"
}

@test "module: covers every status word and every reassign result word" {
    local word missing=""
    for word in unassigned self other unknown assigned unchanged disabled failed; do
        grep -qw -- "$word" "$MODULE" || missing="$missing $word"
    done
    if [ -n "$missing" ]; then
        echo "missing words:$missing"
        false
    fi
}

@test "module: offers the three choices in the specified order" {
    local a b c
    a=$(first_line "$MODULE" '"自分に付け替えて続ける"')
    b=$(first_line "$MODULE" '"付け替えずに続ける"')
    c=$(first_line "$MODULE" '"中止"')
    [ -n "$a" ]
    [ -n "$b" ]
    [ -n "$c" ]
    [ "$a" -lt "$b" ]
    [ "$b" -lt "$c" ]
}

@test "module: skips the takeover in a non-interactive run with the standard warning" {
    grep -qF 'NON_INTERACTIVE' "$MODULE"
    grep -qF '[non-interactive mode] Skipping high-stakes action:' "$MODULE"
}

@test "module: abort stops the calling skill before any later step" {
    grep -qF 'Do not run any later step' "$MODULE"
}

@test "ambiguity-detector: lists the assignee takeover as a High-Stakes Decision" {
    local file="$PROJECT_ROOT/modules/ambiguity-detector.md"
    grep -qF 'Assignee takeover' "$file"
    grep -F 'Assignee takeover' "$file" | grep -qF 'modules/assignee-check.md'
}

@test "skill: issue calls the assignee check in Existing Issue Refinement Step 1" {
    local section
    section=$(md_section "$ISSUE_SKILL" "### Step 1: Fetch Issue Information" 3)
    [ -n "$section" ]
    echo "$section" | grep -qF -- "$LABEL_FIXED"
    echo "$section" | grep -qF -- "$MODULE_PATH"
    echo "$section" | grep -qF '"自分に付け替えて続ける"'
    echo "$section" | grep -qF '"付け替えずに続ける"'
    echo "$section" | grep -qF '"中止"'
}

@test "skill: spec calls the assignee check in Step 1" {
    local section
    section=$(md_section "$SPEC_SKILL" "### Step 1: Fetch Issue Information")
    [ -n "$section" ]
    echo "$section" | grep -qF -- "$LABEL_FIXED"
    echo "$section" | grep -qF -- "$MODULE_PATH"
    echo "$section" | grep -qF '"自分に付け替えて続ける"'
    echo "$section" | grep -qF '"付け替えずに続ける"'
    echo "$section" | grep -qF '"中止"'
}

@test "skill: code calls the assignee check in Step 1" {
    local section
    section=$(md_section "$CODE_SKILL" "### Step 1: Fetch Issue Info")
    [ -n "$section" ]
    echo "$section" | grep -qF -- "$LABEL_FIXED"
    echo "$section" | grep -qF -- "$MODULE_PATH"
    echo "$section" | grep -qF '"自分に付け替えて続ける"'
    echo "$section" | grep -qF '"付け替えずに続ける"'
    echo "$section" | grep -qF '"中止"'
}

@test "skill: the assignee check comes before the first side effect in issue, spec, and code" {
    local check step
    # /issue: the existing-issue part starts after the New Issue Creation part, so compare
    # line numbers within the Existing Issue Refinement section.
    local existing
    existing="$BATS_TEST_TMPDIR/issue-existing.md"
    issue_existing_section > "$existing"
    check=$(first_line "$existing" "$LABEL_FIXED")
    step=$(first_line "$existing" '### Step 2: Auto-chain to triage')
    [ -n "$check" ]
    [ -n "$step" ]
    [ "$check" -lt "$step" ]

    check=$(first_line "$SPEC_SKILL" "$LABEL_FIXED")
    step=$(first_line "$SPEC_SKILL" '### Step 2: Worktree Entry')
    [ -n "$check" ]
    [ -n "$step" ]
    [ "$check" -lt "$step" ]

    check=$(first_line "$CODE_SKILL" "$LABEL_FIXED")
    step=$(first_line "$CODE_SKILL" '### Step 2: Worktree Entry')
    [ -n "$check" ]
    [ -n "$step" ]
    [ "$check" -lt "$step" ]
}

@test "skill: issue, spec, and code allow gh-issue-assignee.sh" {
    local file
    for file in "$ISSUE_SKILL" "$SPEC_SKILL" "$CODE_SKILL"; do
        grep -E '^allowed-tools:' "$file" | grep -qF '${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-assignee.sh:*'
    done
}

@test "skill: the start-of-phase label transition passes --assign in issue, spec, and code" {
    local section
    section=$(md_section "$ISSUE_SKILL" "### Step 3: Label Transition")
    echo "$section" | grep -qF 'gh-label-transition.sh $NUMBER issue --assign'

    section=$(md_section "$SPEC_SKILL" "### Step 3: Label Transition")
    echo "$section" | grep -qF 'gh-label-transition.sh $NUMBER spec --assign'

    section=$(md_section "$CODE_SKILL" "### Step 4: Create Branch & Label Transition")
    echo "$section" | grep -qF 'gh-label-transition.sh $NUMBER code --assign'
}

@test "skill: only one label transition per skill passes --assign" {
    local file count
    for file in "$ISSUE_SKILL" "$SPEC_SKILL" "$CODE_SKILL"; do
        count=$(grep -cE 'gh-label-transition\.sh \$NUMBER [a-z]+ --assign' "$file" || true)
        [ "$count" -eq 1 ]
    done
}

@test "skill: issue New Issue Creation does not assign and does not run the assignee check" {
    local section_file="$BATS_TEST_TMPDIR/issue-new.md"
    md_section "$ISSUE_SKILL" "## New Issue Creation" > "$section_file"
    [ -s "$section_file" ]
    run grep -F -- '--assign' "$section_file"
    [ "$status" -eq 1 ]
    run grep -F 'assignee-check.md' "$section_file"
    [ "$status" -eq 1 ]
}

@test "docs: workflow.md Label Management describes the assignee role split and the start-time behavior" {
    local section
    section=$(md_section "$PROJECT_ROOT/docs/workflow.md" "## Label Management")
    [ -n "$section" ]
    echo "$section" | grep -qF 'assignee'
    echo "$section" | grep -qF 'auto-assign'
    echo "$section" | grep -qF 'modules/assignee-check.md'
}

@test "docs: ja workflow.md ラベル管理 mentions the assignee" {
    local section
    section=$(md_section "$PROJECT_ROOT/docs/ja/workflow.md" "## ラベル管理")
    [ -n "$section" ]
    echo "$section" | grep -qF 'assignee'
}

@test "docs: structure.md and its ja mirror list modules/assignee-check.md" {
    grep -qF 'modules/assignee-check.md' "$PROJECT_ROOT/docs/structure.md"
    grep -qF 'modules/assignee-check.md' "$PROJECT_ROOT/docs/ja/structure.md"
}

@test "run-issue: the phase/issue label backfill does not assign" {
    run grep -F -- '--assign' "$PROJECT_ROOT/scripts/run-issue.sh"
    [ "$status" -eq 1 ]
}
