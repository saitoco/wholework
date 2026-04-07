#!/usr/bin/env bats

# Tests for gh-issue-edit.sh
# Mock external commands (gh) by placing them at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/gh-issue-edit.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Record file for verifying gh calls
    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    # Mock body file for checkbox mode tests
    MOCK_BODY_FILE="$BATS_TEST_TMPDIR/mock_body.txt"
    export MOCK_BODY_FILE

    # Captured body file written by gh issue edit --body-file
    CAPTURED_BODY_FILE="$BATS_TEST_TMPDIR/captured_body.txt"
    export CAPTURED_BODY_FILE

    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [[ "\$1" == "issue" && "\$2" == "view" ]]; then
    cat "$MOCK_BODY_FILE"
    exit 0
fi
if [[ "\$1" == "issue" && "\$2" == "edit" ]]; then
    for arg in "\$@"; do
        if [[ -f "\$arg" ]]; then
            cp "\$arg" "$CAPTURED_BODY_FILE"
            break
        fi
    done
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "success: edit issue body via file path argument" {
    echo "updated body text" > "$BATS_TEST_TMPDIR/body.md"
    run bash "$SCRIPT" 123 "$BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 0 ]
    grep -q "issue edit 123 --body updated body text" "$GH_CALL_LOG"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "error: missing file path argument" {
    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
}

@test "error: invalid issue number (non-numeric)" {
    echo "body" > "$BATS_TEST_TMPDIR/body.md"
    run bash "$SCRIPT" abc "$BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"issue number must be a positive integer"* ]]
}

@test "error: file not found" {
    run bash "$SCRIPT" 123 "$BATS_TEST_TMPDIR/nonexistent.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"file not found"* ]]
}

@test "error: empty file" {
    echo -n "" > "$BATS_TEST_TMPDIR/empty.md"
    run bash "$SCRIPT" 123 "$BATS_TEST_TMPDIR/empty.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty body"* ]]
}

@test "checkbox: --help contains checkbox description" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"checkbox"* ]]
}

@test "checkbox: --checkbox 1 --check updates first unchecked" {
    cat > "$MOCK_BODY_FILE" <<'BODY'
- [ ] First
- [x] Second
- [ ] Third
BODY
    run bash "$SCRIPT" 123 --checkbox 1 --check
    [ "$status" -eq 0 ]
    [[ "$(cat "$CAPTURED_BODY_FILE")" == *"- [x] First"* ]]
    [[ "$(cat "$CAPTURED_BODY_FILE")" == *"- [x] Second"* ]]
}

@test "checkbox: --checkbox 1,3 --check updates multiple checkboxes" {
    cat > "$MOCK_BODY_FILE" <<'BODY'
- [ ] First
- [x] Second
- [ ] Third
BODY
    run bash "$SCRIPT" 123 --checkbox 1,3 --check
    [ "$status" -eq 0 ]
    [[ "$(cat "$CAPTURED_BODY_FILE")" == *"- [x] First"* ]]
    [[ "$(cat "$CAPTURED_BODY_FILE")" == *"- [x] Third"* ]]
}

@test "checkbox: --checkbox 2 --uncheck reverts checked to unchecked" {
    cat > "$MOCK_BODY_FILE" <<'BODY'
- [ ] First
- [x] Second
- [ ] Third
BODY
    run bash "$SCRIPT" 123 --checkbox 2 --uncheck
    [ "$status" -eq 0 ]
    [[ "$(cat "$CAPTURED_BODY_FILE")" == *"- [ ] Second"* ]]
}

@test "checkbox: index out of range fails with error" {
    cat > "$MOCK_BODY_FILE" <<'BODY'
- [ ] First
- [ ] Second
BODY
    run bash "$SCRIPT" 123 --checkbox 5 --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of range"* ]]
}

@test "checkbox: missing --check or --uncheck fails" {
    cat > "$MOCK_BODY_FILE" <<'BODY'
- [ ] First
BODY
    run bash "$SCRIPT" 123 --checkbox 1
    [ "$status" -eq 1 ]
}

@test "error: gh issue edit fails with context message" {
    MOCK_DIR2="$BATS_TEST_TMPDIR/mocks_fail"
    mkdir -p "$MOCK_DIR2"
    cat > "$MOCK_DIR2/gh" <<MOCK
#!/bin/bash
if [[ "\$1" == "issue" && "\$2" == "edit" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR2/gh"
    echo "updated body text" > "$BATS_TEST_TMPDIR/body.md"
    run env PATH="$MOCK_DIR2:$PATH" bash "$SCRIPT" 789 "$BATS_TEST_TMPDIR/body.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed to update"* ]]
}

# --- checkbox mode tests ---

setup_checkbox_mock() {
    local mock_dir="$1"
    local issue_body="$2"
    local edit_log="$3"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/gh" <<MOCK
#!/bin/bash
if [[ "\$1" == "issue" && "\$2" == "view" ]]; then
    echo '$issue_body'
    exit 0
fi
if [[ "\$1" == "issue" && "\$2" == "edit" ]]; then
    shift 2
    # read the file argument after --body-file and record it
    while [[ \$# -gt 0 ]]; do
        if [[ "\$1" == "--body-file" ]]; then
            cp "\$2" "$edit_log"
            shift 2
        else
            shift
        fi
    done
    exit 0
fi
exit 0
MOCK
    chmod +x "$mock_dir/gh"
}

@test "checkbox: check single checkbox" {
    MOCK_DIR_CB="$BATS_TEST_TMPDIR/mocks_cb"
    EDIT_LOG="$BATS_TEST_TMPDIR/edited_body.txt"
    ISSUE_BODY="## Acceptance criteria
- [ ] Item 1
- [ ] Item 2
- [ ] Item 3"
    setup_checkbox_mock "$MOCK_DIR_CB" "$ISSUE_BODY" "$EDIT_LOG"
    run env PATH="$MOCK_DIR_CB:$PATH" bash "$SCRIPT" 123 --checkbox 2 --check
    [ "$status" -eq 0 ]
    result=$(cat "$EDIT_LOG")
    [[ "$result" == *"- [ ] Item 1"* ]]
    [[ "$result" == *"- [x] Item 2"* ]]
    [[ "$result" == *"- [ ] Item 3"* ]]
}

@test "checkbox: check multiple checkboxes" {
    MOCK_DIR_CB="$BATS_TEST_TMPDIR/mocks_cb_multi"
    EDIT_LOG="$BATS_TEST_TMPDIR/edited_body_multi.txt"
    ISSUE_BODY="## Acceptance criteria
- [ ] Item 1
- [ ] Item 2
- [ ] Item 3"
    setup_checkbox_mock "$MOCK_DIR_CB" "$ISSUE_BODY" "$EDIT_LOG"
    run env PATH="$MOCK_DIR_CB:$PATH" bash "$SCRIPT" 123 --checkbox 1,3 --check
    [ "$status" -eq 0 ]
    result=$(cat "$EDIT_LOG")
    [[ "$result" == *"- [x] Item 1"* ]]
    [[ "$result" == *"- [ ] Item 2"* ]]
    [[ "$result" == *"- [x] Item 3"* ]]
}

@test "checkbox: uncheck a checked checkbox" {
    MOCK_DIR_CB="$BATS_TEST_TMPDIR/mocks_cb_uncheck"
    EDIT_LOG="$BATS_TEST_TMPDIR/edited_body_uncheck.txt"
    ISSUE_BODY="## Acceptance criteria
- [x] Item 1
- [x] Item 2"
    setup_checkbox_mock "$MOCK_DIR_CB" "$ISSUE_BODY" "$EDIT_LOG"
    run env PATH="$MOCK_DIR_CB:$PATH" bash "$SCRIPT" 123 --checkbox 1 --uncheck
    [ "$status" -eq 0 ]
    result=$(cat "$EDIT_LOG")
    [[ "$result" == *"- [ ] Item 1"* ]]
    [[ "$result" == *"- [x] Item 2"* ]]
}

@test "checkbox: error when no index specified" {
    run bash "$SCRIPT" 123 --checkbox
    [ "$status" -eq 1 ]
    [[ "$output" == *"please specify indices"* ]]
}

@test "checkbox: error when no action specified" {
    MOCK_DIR_CB="$BATS_TEST_TMPDIR/mocks_cb_noact"
    EDIT_LOG="$BATS_TEST_TMPDIR/edited_body_noact.txt"
    ISSUE_BODY="- [ ] Item 1"
    setup_checkbox_mock "$MOCK_DIR_CB" "$ISSUE_BODY" "$EDIT_LOG"
    run env PATH="$MOCK_DIR_CB:$PATH" bash "$SCRIPT" 123 --checkbox 1
    [ "$status" -eq 1 ]
    [[ "$output" == *"--check or --uncheck"* ]]
}

@test "checkbox: error when index is non-numeric" {
    run bash "$SCRIPT" 123 --checkbox abc --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integers"* ]]
}

@test "help: --help shows checkbox mode description" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"checkbox"* ]]
}
