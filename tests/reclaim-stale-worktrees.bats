#!/usr/bin/env bats

# Tests for reclaim-stale-worktrees.sh
# Uses real git worktrees (no git binary mocking); mocks gh via PATH.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/reclaim-stale-worktrees.sh"

setup() {
    MAIN_REPO="$BATS_TEST_TMPDIR/main"
    git init -q -b main "$MAIN_REPO"
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

    # Real bare repo used as `origin`, for remote branch reclaim tests.
    ORIGIN_REPO="$BATS_TEST_TMPDIR/origin.git"
    git init -q --bare -b main "$ORIGIN_REPO"
    git -C "$MAIN_REPO" remote add origin "$ORIGIN_REPO"
    git -C "$MAIN_REPO" push -q origin main

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
    body=""
    title=""
    baseref="main"
    [ -f "$MOCK_STATE_DIR/pr-$num-state" ] && state="$(cat "$MOCK_STATE_DIR/pr-$num-state")"
    [ -f "$MOCK_STATE_DIR/pr-$num-headrefoid" ] && href="$(cat "$MOCK_STATE_DIR/pr-$num-headrefoid")"
    [ -f "$MOCK_STATE_DIR/pr-$num-body" ] && body="$(cat "$MOCK_STATE_DIR/pr-$num-body")"
    python3 - "$state" "$href" "$body" "$title" "$baseref" <<'PY'
import json, sys
state, href, body, title, baseref = sys.argv[1:6]
print(json.dumps({"state": state, "headRefOid": href, "body": body, "title": title, "baseRefName": baseref}))
PY
    exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "list" ]; then
    search=""
    prev=""
    for arg in "$@"; do
        if [ "$prev" = "--search" ]; then
            search="$arg"
        fi
        prev="$arg"
    done
    num="$(echo "$search" | grep -oE '[0-9]+' | head -1)"
    [ -n "$num" ] && [ -f "$MOCK_STATE_DIR/closes-search-$num" ] && cat "$MOCK_STATE_DIR/closes-search-$num"
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

# mock_closes_pr <issue_num> <pr_num> <state> [headRefOid]
# Makes `gh pr list --search "closes #<issue_num>" --state merged` return
# <pr_num> as a candidate, and makes its (mocked) PR body resolve back to
# <issue_num> via gh-extract-issue-from-pr.sh, so
# resolve_merged_pr_head_ref_oid() in the script under test accepts it as a
# match (mirrors kind=issue branches created by /code pr route, whose
# "<phase>+issue-N" name does not itself carry a PR number).
mock_closes_pr() {
    local issue_num="$1" pr_num="$2" state="$3" href="${4:-}"
    echo "$pr_num" >> "$MOCK_DIR/gh-state/closes-search-$issue_num"
    echo "closes #$issue_num" > "$MOCK_DIR/gh-state/pr-$pr_num-body"
    mock_pr "$pr_num" "$state" "$href"
}

# push_remote_branch <branch>
# Creates <branch> at the current main HEAD (trivially an ancestor of main),
# pushes it to origin, then deletes the local branch -- simulating an orphan
# remote-only branch with no local worktree/branch checkout.
push_remote_branch() {
    local branch="$1"
    git -C "$MAIN_REPO" branch "$branch"
    git -C "$MAIN_REPO" push -q origin "$branch"
    git -C "$MAIN_REPO" branch -D "$branch"
}

# push_remote_branch_with_commit <branch>
# Same as push_remote_branch, but the branch carries one extra commit not
# merged into main (so it is NOT an ancestor of main). Sets
# $REMOTE_BRANCH_SHA to the pushed commit's SHA for headRefOid-matching tests.
push_remote_branch_with_commit() {
    local branch="$1"
    git -C "$MAIN_REPO" checkout -q -b "$branch"
    echo "change for $branch" >> "$MAIN_REPO/file.txt"
    git -C "$MAIN_REPO" add -A
    git -C "$MAIN_REPO" commit -q -m "commit for $branch"
    REMOTE_BRANCH_SHA="$(git -C "$MAIN_REPO" rev-parse HEAD)"
    git -C "$MAIN_REPO" push -q origin "$branch"
    git -C "$MAIN_REPO" checkout -q main
    git -C "$MAIN_REPO" branch -D "$branch"
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

    if git -C "$MAIN_REPO" worktree list | grep -q "wt1006"; then false; fi
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
    if git -C "$MAIN_REPO" branch -d worktree-code+pr-1149 2>/dev/null; then false; fi

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (worktree+branch): 1"* ]]
    [[ "$output" == *"warned (branch tip diverges): 0"* ]]

    if git -C "$MAIN_REPO" worktree list | grep -q "wt1149"; then false; fi
    ! git -C "$MAIN_REPO" branch --list 'worktree-code+pr-1149' | grep -q "worktree-code+pr-1149"
}

@test "worktree removed but branch delete rejected (unmerged, no closes-PR found for headRefOid fallback) is reported separately, not double-counted as reclaimed (worktree+branch)" {
    mock_issue 5000 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-5000 "$BATS_TEST_TMPDIR/wt5000"
    (
        cd "$BATS_TEST_TMPDIR/wt5000"
        echo "unmerged change" >> file.txt
        git add -A
        git commit -q -m "unmerged commit"
    )

    # sanity: plain -d must fail (branch not fully merged into main); issue kind has no -D fallback
    if git -C "$MAIN_REPO" branch -d worktree-code+issue-5000 2>/dev/null; then false; fi

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (worktree only, branch retained): 1"* ]]
    [[ "$output" == *"warned (branch tip diverges): 1"* ]]
    [[ "$output" != *"reclaimed (worktree+branch): 1"* ]]

    if git -C "$MAIN_REPO" worktree list | grep -q "wt5000"; then false; fi
    git -C "$MAIN_REPO" branch --list 'worktree-code+issue-5000' | grep -q "worktree-code+issue-5000"
}

@test "squash-merged issue-kind branch (git branch -d rejected) is safely -D deleted via matching closes-PR headRefOid (regression for #1355 verify FAIL)" {
    mock_issue 6000 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-6000 "$BATS_TEST_TMPDIR/wt6000"
    (
        cd "$BATS_TEST_TMPDIR/wt6000"
        echo "unmerged change" >> file.txt
        git add -A
        git commit -q -m "unmerged commit"
    )
    tip_sha="$(git -C "$BATS_TEST_TMPDIR/wt6000" rev-parse HEAD)"
    mock_closes_pr 6000 6100 MERGED "$tip_sha"

    # sanity: plain -d must fail (branch not fully merged into main)
    if git -C "$MAIN_REPO" branch -d worktree-code+issue-6000 2>/dev/null; then false; fi

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (worktree+branch): 1"* ]]
    [[ "$output" == *"warned (branch tip diverges): 0"* ]]

    if git -C "$MAIN_REPO" worktree list | grep -q "wt6000"; then false; fi
    ! git -C "$MAIN_REPO" branch --list 'worktree-code+issue-6000' | grep -q "worktree-code+issue-6000"
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

@test "remote reclaim: default (no args) is dry-run, reports without deleting (AC1)" {
    mock_issue 1006 CLOSED
    push_remote_branch "worktree-code+issue-1006"

    cd "$MAIN_REPO"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"would delete (remote): worktree-code+issue-1006 (issue #1006, completed)"* ]]
    [[ "$output" == *"[dry-run] No remote changes made. Re-run with --apply-remote to perform remote reclaim."* ]]

    git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+issue-1006' | grep -q worktree-code+issue-1006
}

@test "remote reclaim: --apply-remote deletes a completed Issue's remote branch (AC1, AC2)" {
    mock_issue 1006 CLOSED
    push_remote_branch "worktree-code+issue-1006"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (remote branch): 1"* ]]

    run git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+issue-1006'
    [ -z "$output" ]
}

@test "remote reclaim: --apply-remote alone does not trigger local worktree/branch removal (independent flags)" {
    mock_issue 1006 CLOSED
    push_remote_branch "worktree-code+issue-1006"
    mock_issue 1007 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-1007 "$BATS_TEST_TMPDIR/wt1007"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]

    git -C "$MAIN_REPO" worktree list | grep -q "wt1007"
    git -C "$MAIN_REPO" branch --list 'worktree-code+issue-1007' | grep -q "worktree-code+issue-1007"
}

@test "remote reclaim: branch with a live local checkout is excluded (concurrent-session guard equivalent)" {
    mock_issue 1006 CLOSED
    git -C "$MAIN_REPO" worktree add -q -b worktree-code+issue-1006 "$BATS_TEST_TMPDIR/wt1006"
    git -C "$MAIN_REPO" push -q origin worktree-code+issue-1006

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"excluded (remote, local checkout present): 1"* ]]
    [[ "$output" == *"worktree-code+issue-1006 (local checkout present)"* ]]

    git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+issue-1006' | grep -q worktree-code+issue-1006
}

@test "remote reclaim: kind=issue branch merged into main (ancestor) is reclaimed" {
    mock_issue 2006 CLOSED
    push_remote_branch "worktree-code+issue-2006"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (remote branch): 1"* ]]

    run git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+issue-2006'
    [ -z "$output" ]
}

@test "remote reclaim: kind=issue branch not merged into main is warned, not deleted (safety guard rejection)" {
    mock_issue 3006 CLOSED
    push_remote_branch_with_commit "worktree-code+issue-3006"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"warned (remote, unmerged/diverged): 1"* ]]
    [[ "$output" == *"worktree-code+issue-3006 (not an ancestor of origin/main)"* ]]

    git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+issue-3006' | grep -q worktree-code+issue-3006
}

@test "remote reclaim: kind=issue branch not ancestor of main but matches closes-PR headRefOid is reclaimed (squash-merge fallback, regression for #1355 verify FAIL)" {
    mock_issue 7006 CLOSED
    push_remote_branch_with_commit "worktree-code+issue-7006"
    mock_closes_pr 7006 7100 MERGED "$REMOTE_BRANCH_SHA"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (remote branch): 1"* ]]

    run git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+issue-7006'
    [ -z "$output" ]
}

@test "remote reclaim: kind=issue branch with closes-PR but diverging headRefOid falls back to ancestor check and is warned (safety guard rejection)" {
    mock_issue 7007 CLOSED
    push_remote_branch_with_commit "worktree-code+issue-7007"
    mock_closes_pr 7007 7101 MERGED "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"warned (remote, unmerged/diverged): 1"* ]]

    git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+issue-7007' | grep -q worktree-code+issue-7007
}

@test "remote reclaim: kind=pr branch matching MERGED PR headRefOid is reclaimed (squash-merge case)" {
    push_remote_branch_with_commit "worktree-code+pr-4149"
    mock_pr 4149 MERGED "$REMOTE_BRANCH_SHA"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (remote branch): 1"* ]]

    run git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+pr-4149'
    [ -z "$output" ]
}

@test "remote reclaim: kind=pr branch diverging from MERGED PR headRefOid is warned, not deleted (safety guard rejection)" {
    push_remote_branch_with_commit "worktree-code+pr-4150"
    mock_pr 4150 MERGED "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"warned (remote, unmerged/diverged): 1"* ]]
    [[ "$output" == *"worktree-code+pr-4150 (branch tip diverges from merged PR head, or no merged PR found)"* ]]

    git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+pr-4150' | grep -q worktree-code+pr-4150
}

@test "remote reclaim: open Issue's remote branch is left untouched (not completed)" {
    mock_issue 5006 OPEN
    push_remote_branch "worktree-code+issue-5006"

    cd "$MAIN_REPO"
    run "$SCRIPT" --apply-remote
    [ "$status" -eq 0 ]
    [[ "$output" == *"reclaimed (remote branch): 0"* ]]

    git ls-remote --heads "$ORIGIN_REPO" 'worktree-code+issue-5006' | grep -q worktree-code+issue-5006
}
