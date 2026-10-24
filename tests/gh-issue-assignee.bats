#!/usr/bin/env bats

# Tests for gh-issue-assignee.sh
# gh is replaced by a stub placed at the front of PATH; the real get-config-value.sh is used.

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/gh-issue-assignee.sh"

load 'helpers/markdown-section'

EMPTY_JSON='{"assignees":[]}'
ME_JSON='{"assignees":[{"id":"U_dummy","login":"me","name":"Me","databaseId":1}]}'
OTHERS_JSON='{"assignees":[{"id":"U_dummy","login":"alice","name":"Alice","databaseId":2},{"id":"BOT_dummy","login":"Copilot","name":"","databaseId":3}]}'
COPILOT_JSON='{"assignees":[{"id":"BOT_dummy","login":"Copilot","name":"","databaseId":3}]}'
ME_AND_ALICE_JSON='{"assignees":[{"id":"U_dummy","login":"me","name":"Me","databaseId":1},{"id":"U_dummy2","login":"alice","name":"Alice","databaseId":2}]}'
BRACKET_JSON='{"assignees":[{"id":"BOT_dummy","login":"dependabot[bot]","name":"","databaseId":4}]}'

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    export GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export VIEW_COUNT="$BATS_TEST_TMPDIR/view_count"
    : > "$GH_CALL_LOG"

    export MOCK_ME="me"
    export MOCK_VIEW_1="$EMPTY_JSON"
    export MOCK_VIEW_2=""
    export MOCK_VIEW_FAIL=""
    export MOCK_WRITE_FAIL=""
    export WHOLEWORK_CONFIG_PATH=/dev/null

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$*" >> "$GH_CALL_LOG"
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
    [ -n "${MOCK_ME:-}" ] || exit 1
    echo "$MOCK_ME"
    exit 0
fi
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    [ "${MOCK_VIEW_FAIL:-}" = "1" ] && exit 1
    n=0
    [ -f "$VIEW_COUNT" ] && n=$(cat "$VIEW_COUNT")
    n=$((n + 1))
    echo "$n" > "$VIEW_COUNT"
    if [ "$n" -ge 2 ] && [ -n "${MOCK_VIEW_2:-}" ]; then
        echo "$MOCK_VIEW_2"
    else
        echo "$MOCK_VIEW_1"
    fi
    exit 0
fi
case "$*" in
    *"-X POST"*|*"-X PATCH"*)
        [ "${MOCK_WRITE_FAIL:-}" = "1" ] && exit 1
        echo '{}'
        exit 0
        ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

disable_auto_assign() {
    printf 'auto-assign: false\n' > "$BATS_TEST_TMPDIR/wholework.yml"
    export WHOLEWORK_CONFIG_PATH="$BATS_TEST_TMPDIR/wholework.yml"
}

# Count recorded gh calls matching a fixed string
count_calls() {
    local n
    n=$(grep -c -F -- "$1" "$GH_CALL_LOG" || true)
    echo "$n"
}

# ---------------------------------------------------------------- status

@test "status: unassigned issue prints unassigned" {
    export MOCK_VIEW_1="$EMPTY_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$status" -eq 0 ]
    [ "$output" = "unassigned" ]
}

@test "status: only the executing user prints self" {
    export MOCK_VIEW_1="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$status" -eq 0 ]
    [ "$output" = "self" ]
}

@test "status: another member prints other and lists the logins on stderr" {
    export MOCK_VIEW_1="$OTHERS_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
    [[ "$stderr" == *"Info: issue #42 is assigned to: alice, Copilot"* ]]
}

@test "status: a bot only is treated as other" {
    export MOCK_VIEW_1="$COPILOT_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$output" = "other" ]
}

@test "status: executing user plus another member prints other" {
    export MOCK_VIEW_1="$ME_AND_ALICE_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$output" = "other" ]
}

@test "status: login comparison ignores case" {
    export MOCK_ME="ME"
    export MOCK_VIEW_1="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$output" = "self" ]
}

@test "status: login with brackets is not glob-expanded and counts as other" {
    export MOCK_VIEW_1="$BRACKET_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$output" = "other" ]
    [[ "$stderr" == *"dependabot[bot]"* ]]
}

@test "status: auto-assign false does not change the judgement" {
    disable_auto_assign
    export MOCK_VIEW_1="$OTHERS_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$output" = "other" ]
}

@test "status: unknown executing user and unassigned issue prints unassigned" {
    export MOCK_ME=""
    export MOCK_VIEW_1="$EMPTY_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$status" -eq 0 ]
    [ "$output" = "unassigned" ]
}

@test "status: unknown executing user and assigned issue prints other even for a matching login" {
    export MOCK_ME=""
    export MOCK_VIEW_1="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
    [[ "$stderr" == *"could not be identified"* ]]
}

@test "status: malformed executing user login is treated as unidentified" {
    export MOCK_ME="not a login!"
    export MOCK_VIEW_1="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$output" = "other" ]
}

@test "status: read failure prints unknown with exit 0" {
    export MOCK_VIEW_FAIL=1
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
    [[ "$stderr" == *"Warning: could not read the assignees of issue #42; status is unknown"* ]]
}

@test "status: malformed JSON prints unknown" {
    export MOCK_VIEW_1="not json"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "status: empty output from gh prints unknown" {
    export MOCK_VIEW_1=""
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$status" -eq 0 ]
    [ "$output" = "unknown" ]
}

@test "status: never calls a write endpoint" {
    export MOCK_VIEW_1="$OTHERS_JSON"
    run --separate-stderr bash "$SCRIPT" status 42
    [ "$(count_calls '-X POST')" -eq 0 ]
    [ "$(count_calls '-X PATCH')" -eq 0 ]
}

# ---------------------------------------------------------------- assign

@test "assign: unassigned issue adds the executing user once" {
    export MOCK_VIEW_1="$EMPTY_JSON"
    export MOCK_VIEW_2="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$status" -eq 0 ]
    [ "$output" = "assigned" ]
    [ "$(count_calls '-X POST')" -eq 1 ]
    grep -q -F -- 'repos/{owner}/{repo}/issues/42/assignees -X POST -f assignees[]=me' "$GH_CALL_LOG"
    [ "$(count_calls '-X PATCH')" -eq 0 ]
    [ -z "$stderr" ]
}

@test "assign: never uses gh issue edit" {
    export MOCK_VIEW_1="$EMPTY_JSON"
    export MOCK_VIEW_2="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$(count_calls 'issue edit')" -eq 0 ]
}

@test "assign: only the executing user assigned makes no write" {
    export MOCK_VIEW_1="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$output" = "unchanged" ]
    [ "$(count_calls '-X POST')" -eq 0 ]
    [ "$(count_calls '-X PATCH')" -eq 0 ]
}

@test "assign: another member assigned is left alone without a warning" {
    export MOCK_VIEW_1="$OTHERS_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$status" -eq 0 ]
    [ "$output" = "unchanged" ]
    [ "$(count_calls '-X POST')" -eq 0 ]
    [ "$(count_calls '-X PATCH')" -eq 0 ]
    [ -z "$stderr" ]
}

@test "assign: auto-assign false calls gh not at all and prints disabled" {
    disable_auto_assign
    export MOCK_VIEW_1="$EMPTY_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$status" -eq 0 ]
    [ "$output" = "disabled" ]
    [ ! -s "$GH_CALL_LOG" ]
}

@test "assign: auto-assign false is case-insensitive" {
    printf 'auto-assign: False\n' > "$BATS_TEST_TMPDIR/wholework.yml"
    export WHOLEWORK_CONFIG_PATH="$BATS_TEST_TMPDIR/wholework.yml"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$output" = "disabled" ]
}

@test "assign: auto-assign true or another value keeps assignment enabled" {
    printf 'auto-assign: true\n' > "$BATS_TEST_TMPDIR/wholework.yml"
    export WHOLEWORK_CONFIG_PATH="$BATS_TEST_TMPDIR/wholework.yml"
    export MOCK_VIEW_1="$EMPTY_JSON"
    export MOCK_VIEW_2="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$output" = "assigned" ]
}

@test "assign: add API failure prints failed with a warning and exit 0" {
    export MOCK_VIEW_1="$EMPTY_JSON"
    export MOCK_WRITE_FAIL=1
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
    [[ "$stderr" == *"Warning: failed to update the assignee of issue #42 (no permission or API error); continuing"* ]]
}

@test "assign: another member found on re-read warns about simultaneous start" {
    export MOCK_VIEW_1="$EMPTY_JSON"
    export MOCK_VIEW_2="$ME_AND_ALICE_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$status" -eq 0 ]
    [ "$output" = "assigned" ]
    [[ "$stderr" == *"Warning: issue #42 is also assigned to: alice. Another member may have started this Issue at about the same time"* ]]
}

@test "assign: executing user missing on re-read prints failed with a warning" {
    export MOCK_VIEW_1="$EMPTY_JSON"
    export MOCK_VIEW_2="$EMPTY_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
    [[ "$stderr" == *"Warning: @me is not an assignee of issue #42 after the update"* ]]
}

@test "assign: re-read failure still reports assigned with a warning" {
    # View succeeds the first time only: a stub that fails from the 2nd call on
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$*" >> "$GH_CALL_LOG"
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
    echo "me"
    exit 0
fi
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    n=0
    [ -f "$VIEW_COUNT" ] && n=$(cat "$VIEW_COUNT")
    n=$((n + 1))
    echo "$n" > "$VIEW_COUNT"
    [ "$n" -ge 2 ] && exit 1
    echo '{"assignees":[]}'
    exit 0
fi
echo '{}'
exit 0
MOCK
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$status" -eq 0 ]
    [ "$output" = "assigned" ]
    [[ "$stderr" == *"could not re-read the assignees of issue #42"* ]]
}

@test "assign: unknown executing user writes nothing and prints failed" {
    export MOCK_ME=""
    export MOCK_VIEW_1="$EMPTY_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
    [[ "$stderr" == *"Warning: could not identify the executing user (gh api user failed); skipping the assignee update for issue #42"* ]]
    [ "$(count_calls '-X POST')" -eq 0 ]
}

@test "assign: unknown executing user with an existing assignee prints unchanged" {
    export MOCK_ME=""
    export MOCK_VIEW_1="$OTHERS_JSON"
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$output" = "unchanged" ]
    [ -z "$stderr" ]
}

@test "assign: read failure writes nothing and prints failed" {
    export MOCK_VIEW_FAIL=1
    run --separate-stderr bash "$SCRIPT" assign 42
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
    [[ "$stderr" == *"could not read the assignees of issue #42; skipping the assignee update"* ]]
    [ "$(count_calls '-X POST')" -eq 0 ]
}

# ---------------------------------------------------------------- reassign

@test "reassign: another member assigned is replaced by the executing user only" {
    export MOCK_VIEW_1="$OTHERS_JSON"
    export MOCK_VIEW_2="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" reassign 42
    [ "$status" -eq 0 ]
    [ "$output" = "assigned" ]
    [ "$(count_calls '-X PATCH')" -eq 1 ]
    grep -q -F -- 'repos/{owner}/{repo}/issues/42 -X PATCH -f assignees[]=me' "$GH_CALL_LOG"
    [ "$(count_calls '-X POST')" -eq 0 ]
    [ -z "$stderr" ]
}

@test "reassign: executing user plus another member is replaced" {
    export MOCK_VIEW_1="$ME_AND_ALICE_JSON"
    export MOCK_VIEW_2="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" reassign 42
    [ "$output" = "assigned" ]
    [ "$(count_calls '-X PATCH')" -eq 1 ]
}

@test "reassign: only the executing user assigned makes no write" {
    export MOCK_VIEW_1="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" reassign 42
    [ "$output" = "unchanged" ]
    [ "$(count_calls '-X PATCH')" -eq 0 ]
    [ "$(count_calls '-X POST')" -eq 0 ]
}

@test "reassign: unassigned issue uses the add API instead of replacing" {
    export MOCK_VIEW_1="$EMPTY_JSON"
    export MOCK_VIEW_2="$ME_JSON"
    run --separate-stderr bash "$SCRIPT" reassign 42
    [ "$output" = "assigned" ]
    [ "$(count_calls '-X POST')" -eq 1 ]
    [ "$(count_calls '-X PATCH')" -eq 0 ]
}

@test "reassign: auto-assign false prints disabled and calls gh not at all" {
    disable_auto_assign
    export MOCK_VIEW_1="$OTHERS_JSON"
    run --separate-stderr bash "$SCRIPT" reassign 42
    [ "$output" = "disabled" ]
    [ ! -s "$GH_CALL_LOG" ]
}

@test "reassign: replace API failure prints failed with exit 0" {
    export MOCK_VIEW_1="$OTHERS_JSON"
    export MOCK_WRITE_FAIL=1
    run --separate-stderr bash "$SCRIPT" reassign 42
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
    [[ "$stderr" == *"Warning: failed to update the assignee of issue #42"* ]]
}

@test "reassign: another member still present after the replace warns" {
    export MOCK_VIEW_1="$OTHERS_JSON"
    export MOCK_VIEW_2="$ME_AND_ALICE_JSON"
    run --separate-stderr bash "$SCRIPT" reassign 42
    [ "$output" = "assigned" ]
    [[ "$stderr" == *"also assigned to: alice"* ]]
}

@test "reassign: unknown executing user writes nothing and prints failed" {
    export MOCK_ME=""
    export MOCK_VIEW_1="$OTHERS_JSON"
    run --separate-stderr bash "$SCRIPT" reassign 42
    [ "$status" -eq 0 ]
    [ "$output" = "failed" ]
    [[ "$stderr" == *"could not identify the executing user"* ]]
    [ "$(count_calls '-X PATCH')" -eq 0 ]
    [ "$(count_calls '-X POST')" -eq 0 ]
}

# ---------------------------------------------------------------- usage

@test "usage: no arguments exits 1" {
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "usage: unknown subcommand exits 1" {
    run --separate-stderr bash "$SCRIPT" bogus 42
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"unknown subcommand"* ]]
}

@test "usage: missing issue number exits 1" {
    run --separate-stderr bash "$SCRIPT" status
    [ "$status" -eq 1 ]
}

@test "usage: non-numeric, zero and zero-padded issue numbers exit 1" {
    run --separate-stderr bash "$SCRIPT" status abc
    [ "$status" -eq 1 ]
    run --separate-stderr bash "$SCRIPT" status 0
    [ "$status" -eq 1 ]
    run --separate-stderr bash "$SCRIPT" status 007
    [ "$status" -eq 1 ]
}

@test "usage: extra arguments exit 1" {
    run --separate-stderr bash "$SCRIPT" status 42 extra
    [ "$status" -eq 1 ]
}

@test "usage: --help exits 0 and shows the result vocabulary" {
    run --separate-stderr bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"unassigned | self | other | unknown"* ]] || false
    [[ "$output" == *"assigned | unchanged | disabled | failed"* ]] || false
}

# ---------------------------------------------------------------- docs

@test "docs: detect-config-markers.md defines auto-assign in the table, the parsing rules and the output format" {
    local f="$PROJECT_ROOT/modules/detect-config-markers.md"
    grep -q '^| `auto-assign` | `HAS_AUTO_ASSIGN` | `true` |' "$f"
    grep -q '^- `auto-assign` defaults to true' "$f"
    grep -q '^HAS_AUTO_ASSIGN: false if auto-assign: false' "$f"
}

@test "docs: customization guide has auto-assign in the sample and the key table" {
    local f="$PROJECT_ROOT/docs/guide/customization.md"
    grep -q '^auto-assign:' "$f"
    grep -q '^| `auto-assign` | boolean | `true` |' "$f"
}

@test "docs: L0 Surface SSoT table lists Assignees" {
    run md_section "$PROJECT_ROOT/modules/l0-surfaces.md" "## L0 Surface SSoT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"| Assignees |"* ]] || false
}

@test "docs: autonomy-tier.md documents the tier-independent assignee exception" {
    run md_section "$PROJECT_ROOT/modules/autonomy-tier.md" "### Tier-independent L0 write: assignee assignment"
    [ "$status" -eq 0 ]
    [[ "$output" == *"L1"* ]] || false
    [[ "$output" == *"phase/*"* ]] || false
    [[ "$output" == *"auto-assign: false"* ]] || false
}
