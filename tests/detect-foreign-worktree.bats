#!/usr/bin/env bats

# Tests for detect-foreign-worktree.sh
# Uses real git worktrees (no git binary mocking).

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/detect-foreign-worktree.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"

    MAIN_REPO="$BATS_TEST_TMPDIR/main"
    git init -q "$MAIN_REPO"
    git -C "$MAIN_REPO" config user.email "test@example.com"
    git -C "$MAIN_REPO" config user.name "Test"
    (
        cd "$MAIN_REPO"
        echo "init" > file.txt
        git add -A
        git commit -q -m init
    )
    # Resolve to the real path (e.g. macOS /tmp -> /private/tmp) so it matches
    # what `git worktree list` reports.
    MAIN_REPO="$(cd "$MAIN_REPO" && pwd -P)"
}

@test "not in a worktree -> none" {
    cd "$MAIN_REPO"
    run "$SCRIPT" verify/issue-794
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]
}

@test "in own matching worktree -> own" {
    OWN_WORKTREE="$BATS_TEST_TMPDIR/own_wt"
    git -C "$MAIN_REPO" worktree add -q -b worktree-verify+issue-794 "$OWN_WORKTREE"

    cd "$OWN_WORKTREE"
    run "$SCRIPT" verify/issue-794
    [ "$status" -eq 0 ]
    [ "$output" = "own" ]
}

@test "in a foreign worktree -> foreign + main repo root" {
    FOREIGN_WORKTREE="$BATS_TEST_TMPDIR/foreign_wt"
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-902 "$FOREIGN_WORKTREE"

    cd "$FOREIGN_WORKTREE"
    run "$SCRIPT" verify/issue-794
    [ "$status" -eq 0 ]

    set -- $output
    [ "$1" = "foreign" ]
    [ "$2" = "$MAIN_REPO" ]
}

@test "missing argument -> usage error" {
    cd "$MAIN_REPO"
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}
