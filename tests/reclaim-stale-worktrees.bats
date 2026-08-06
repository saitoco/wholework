#!/usr/bin/env bats

# Tests for reclaim-stale-worktrees.sh
# Uses real git worktrees (no git binary mocking); mocks gh via PATH.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/reclaim-stale-worktrees.sh"

setup() {
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

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
MOCK_STATE_DIR="$(dirname "$0")/gh-state"
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
    num="$3"
    if [ -f "$MOCK_STATE_DIR/issue-$num-state" ]; then
        cat "$MOCK_STATE_DIR/issue-$num-state"
    else
        echo "OPEN"
    fi
    exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    num="$3"
    state="OPEN"
    href=""
    [ -f "$MOCK_STATE_DIR/pr-$num-state" ] && state="$(cat "$MOCK_STATE_DIR/pr-$num-state")"
    [ -f "$MOCK_STATE_DIR/pr-$num-headrefoid" ] && href="$(cat "$MOCK_STATE_DIR/pr-$num-headrefoid")"
    printf '{"state":"%s","headRefOid":"%s"}\n' "$state" "$href"
    exit 0
fi
echo "Error: unexpected gh mock invocation: $*" >&2
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"
    mkdir -p "$MOCK_DIR/gh-state"
}

# mock_issue <number> <state>  (e.g. mock_issue 1006 CLOSED)
mock_issue() {
    echo "$2" > "$MOCK_DIR/gh-state/issue-$1-state"
}

# mock_pr <number> <state> [headRefOid]  (e.g. mock_pr 1149 MERGED abcdef)
mock_pr() {
    echo "$2" > "$MOCK_DIR/gh-state/pr-$1-state"
    echo "${3:-}" > "$MOCK_DIR/gh-state/pr-$1-headrefoid"
}

@test "default (no args) is dry-run: no worktree or branch is removed" {
    mock_issue 1006 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-1006 "$BATS_TEST_TMPDIR/wt1006"

    cd "$MAIN_REPO"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] No changes made. Re-run with --apply to perform reclaim."* ]]
    [[ "$output" == *"would reclaim: $BATS_TEST_TMPDIR/wt1006"* ]]

    # nothing was actually removed
    git -C "$MAIN_REPO" worktree list | grep -q "wt1006"
    git -C "$MAIN_REPO" branch --list 'worktree-code+issue-1006' | grep -q "worktree-code+issue-1006"
}

@test "completed Issue (CLOSED) + clean worktree is deleted with --apply" {
    mock_issue 1006 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-1006 "$BATS_TEST_TMPDIR/wt1006"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (worktree+branch): 1"* ]]

    ! git -C "$MAIN_REPO" worktree list | grep -q "wt1006"
    ! git -C "$MAIN_REPO" branch --list 'worktree-code+issue-1006' | grep -q "worktree-code+issue-1006"
}

@test "locked worktree whose HEAD matches main HEAD is excluded even with --apply (AC2)" {
    mock_issue 1006 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-1006 "$BATS_TEST_TMPDIR/wt1006"
    git -C "$MAIN_REPO" worktree lock "$BATS_TEST_TMPDIR/wt1006"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"excluded (concurrent-session-guard): 1"* ]]

    # still present -- excluded from reclaim
    git -C "$MAIN_REPO" worktree list | grep -q "wt1006"
    git -C "$MAIN_REPO" branch --list 'worktree-code+issue-1006' | grep -q "worktree-code+issue-1006"
}

@test "worktree with uncommitted changes is not deleted, reported as warning (AC4)" {
    mock_issue 1006 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-1006 "$BATS_TEST_TMPDIR/wt1006"
    echo "dirty" >> "$BATS_TEST_TMPDIR/wt1006/file.txt"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"warned (uncommitted changes): 1"* ]]
    [[ "$output" == *"uncommitted changes: 1 files"* ]]

    git -C "$MAIN_REPO" worktree list | grep -q "wt1006"
    git -C "$MAIN_REPO" branch --list 'worktree-code+issue-1006' | grep -q "worktree-code+issue-1006"
}

@test "squash-merged branch (git branch -d rejected) is safely -D deleted via matching headRefOid (AC3)" {
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+pr-1149 "$BATS_TEST_TMPDIR/wt1149"
    (
        cd "$BATS_TEST_TMPDIR/wt1149"
        echo "unmerged change" >> file.txt
        git add -A
        git commit -q -m "unmerged commit"
    )
    tip_sha="$(git -C "$BATS_TEST_TMPDIR/wt1149" rev-parse HEAD)"
    mock_pr 1149 MERGED "$tip_sha"

    # sanity: plain -d must fail (branch not fully merged into main)
    ! git -C "$MAIN_REPO" branch -d worktree-code+pr-1149 2>/dev/null

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (worktree+branch): 1"* ]]
    [[ "$output" == *"warned (branch tip diverges): 0"* ]]

    ! git -C "$MAIN_REPO" worktree list | grep -q "wt1149"
    ! git -C "$MAIN_REPO" branch --list 'worktree-code+pr-1149' | grep -q "worktree-code+pr-1149"
}

@test "worktree removed but branch delete rejected (unmerged, no -D fallback for issue kind) is reported separately, not double-counted as reclaimed (worktree+branch)" {
    mock_issue 5000 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-5000 "$BATS_TEST_TMPDIR/wt5000"
    (
        cd "$BATS_TEST_TMPDIR/wt5000"
        echo "unmerged change" >> file.txt
        git add -A
        git commit -q -m "unmerged commit"
    )

    # sanity: plain -d must fail (branch not fully merged into main); issue kind has no -D fallback
    ! git -C "$MAIN_REPO" branch -d worktree-code+issue-5000 2>/dev/null

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (worktree only, branch retained): 1"* ]]
    [[ "$output" == *"warned (branch tip diverges): 1"* ]]
    [[ "$output" != *"reclaimed (worktree+branch): 1"* ]]

    ! git -C "$MAIN_REPO" worktree list | grep -q "wt5000"
    git -C "$MAIN_REPO" branch --list 'worktree-code+issue-5000' | grep -q "worktree-code+issue-5000"
}

@test "orphan branch (no worktree directory) is reclaimed via the same completion check (AC3)" {
    git -C "$MAIN_REPO" branch worktree-code+issue-2000
    mock_issue 2000 CLOSED

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (orphan branch only): 1"* ]]

    ! git -C "$MAIN_REPO" branch --list 'worktree-code+issue-2000' | grep -q "worktree-code+issue-2000"
}

@test "worktree/branch not matching current naming convention is skipped as unrecognized" {
    mock_issue 56 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b issue-56-configurable-paths "$BATS_TEST_TMPDIR/wt-old"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped (unrecognized): 1"* ]]

    git -C "$MAIN_REPO" worktree list | grep -q "wt-old"
    git -C "$MAIN_REPO" branch --list 'issue-56-configurable-paths' | grep -q "issue-56-configurable-paths"
}

@test "prunable entry (worktree directory already gone) is reclaimed via git worktree prune" {
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-3000 "$BATS_TEST_TMPDIR/wt3000"
    rm -rf "$BATS_TEST_TMPDIR/wt3000"

    cd "$MAIN_REPO"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"pruned: 1"* ]]

    ! git -C "$MAIN_REPO" worktree list --porcelain | grep -q "wt3000"
}

@test "open Issue worktree is left untouched (not completed, not reported)" {
    mock_issue 4000 OPEN
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-4000 "$BATS_TEST_TMPDIR/wt4000"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (worktree+branch): 0"* ]]

    git -C "$MAIN_REPO" worktree list | grep -q "wt4000"
    git -C "$MAIN_REPO" branch --list 'worktree-code+issue-4000' | grep -q "worktree-code+issue-4000"
}
