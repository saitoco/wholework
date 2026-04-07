#!/usr/bin/env bats

# Tests for gh-issue-comment.sh
# Mock external commands (gh) by placing them at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/gh-issue-comment.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Record file for verifying gh calls
    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [[ "\$1" == "repo" && "\$2" == "view" ]]; then
    echo "owner/repo"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "success: post comment via file path argument" {
    echo "test comment body" > "$BATS_TEST_TMPDIR/comment.md"
    run bash "$SCRIPT" 123 "$BATS_TEST_TMPDIR/comment.md"
    [ "$status" -eq 0 ]
    grep -q "issue comment 123 --body test comment body" "$GH_CALL_LOG"
}

@test "success: {REPO} placeholder is replaced with actual repo name" {
    echo "See {REPO} for details" > "$BATS_TEST_TMPDIR/comment.md"
    run bash "$SCRIPT" 456 "$BATS_TEST_TMPDIR/comment.md"
    [ "$status" -eq 0 ]
    # gh repo view should have been called
    grep -q "repo view" "$GH_CALL_LOG"
    # The comment body should have {REPO} replaced with owner/repo
    grep -q "issue comment 456 --body See owner/repo for details" "$GH_CALL_LOG"
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

@test "error: gh issue comment fails with context message" {
    MOCK_DIR2="$BATS_TEST_TMPDIR/mocks_fail"
    mkdir -p "$MOCK_DIR2"
    cat > "$MOCK_DIR2/gh" <<MOCK
#!/bin/bash
if [[ "\$1" == "issue" && "\$2" == "comment" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR2/gh"
    echo "test comment body" > "$BATS_TEST_TMPDIR/comment.md"
    run env PATH="$MOCK_DIR2:$PATH" bash "$SCRIPT" 456 "$BATS_TEST_TMPDIR/comment.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed to post comment"* ]]
}
