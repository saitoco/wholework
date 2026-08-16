#!/usr/bin/env bats
# Content-assertion tests for /spec skill's tag/enum semantic extension consumer sweep
# (added for #1073). Guards the new Step 10 procedure against accidental removal or drift.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SKILL_FILE="$PROJECT_ROOT/skills/spec/SKILL.md"
}

@test "spec skill documents tag/enum semantic extension consumer sweep" {
    grep -q 'Tag/enum semantic extension consumer sweep' "$SKILL_FILE"
}

@test "spec skill records grep pattern and target directories for the sweep" {
    grep -q "grep -rn '<value>' skills/ modules/ scripts/" "$SKILL_FILE"
}

@test "spec skill shows exhaustive-declaration verification AC example" {
    grep -q 'caller 一覧が' "$SKILL_FILE"
}

@test "spec skill differentiates the sweep from Rename-type and Steering Docs sync checks" {
    grep -q 'the string is unchanged but the conditions under which it is valid widen' "$SKILL_FILE"
}

# Content-assertion tests for the Steering Docs sync candidate check gate/cross-search
# extension to modules/ (added for #1089). Guards against the gate silently reverting to
# excluding modules/*.md-only changes, and against the cross-search target directory list
# dropping modules/ again.

@test "spec skill Steering Docs sync candidate check gate covers modules/ changes" {
    grep -q 'SKILL.md, `modules/`, or `scripts/`' "$SKILL_FILE"
}

@test "spec skill Steering Docs sync candidate check searches modules/ in cross-search" {
    grep -q 'grep -rn "<keyword>" docs/ tests/ scripts/ modules/' "$SKILL_FILE"
}

# Content-assertion tests for the New test case requirement for new branch logic check
# (added for #1096). Guards the new Step 10 procedure against accidental removal or drift.

@test "spec skill documents new test case requirement for new branch logic" {
    grep -q 'New test case requirement for new branch logic' "$SKILL_FILE"
}

@test "spec skill new test case requirement requests explicit new test case wording" {
    grep -q '新規テストケース' "$SKILL_FILE"
}

@test "spec skill new test case requirement records to Notes section when SPEC_DEPTH=light" {
    grep -q 'SPEC_DEPTH=light`, Step 13 itself is skipped' "$SKILL_FILE"
}
