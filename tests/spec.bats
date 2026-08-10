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
