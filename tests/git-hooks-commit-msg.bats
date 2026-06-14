#!/usr/bin/env bats

# Tests for scripts/git-hooks/commit-msg

HOOK="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/git-hooks/commit-msg"

setup() {
    COMMIT_MSG_FILE="$BATS_TEST_TMPDIR/COMMIT_EDITMSG"
}

@test "commit-msg: signed commit passes" {
    printf "feat: add feature\n\nSigned-off-by: Alice <alice@example.com>\n" > "$COMMIT_MSG_FILE"
    run bash "$HOOK" "$COMMIT_MSG_FILE"
    [ "$status" -eq 0 ]
}

@test "commit-msg: unsigned commit fails" {
    printf "feat: add feature\n" > "$COMMIT_MSG_FILE"
    run bash "$HOOK" "$COMMIT_MSG_FILE"
    [ "$status" -eq 1 ]
}

@test "commit-msg: error output mentions Signed-off-by" {
    printf "feat: add feature\n" > "$COMMIT_MSG_FILE"
    run bash "$HOOK" "$COMMIT_MSG_FILE"
    [[ "$output" == *"Signed-off-by"* ]]
}
