#!/usr/bin/env bats

# Tests for scripts/push-to-base.sh
# Uses real git (bare origin with a pre-receive hook that can reject updates to main) and a
# `gh` mock on PATH that records its argv and imitates a squash merge on the bare origin.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/push-to-base.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    # No resolve-merge-strategy.sh here: the script must fall back to --squash.
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    export WHOLEWORK_PUSH_RETRY_INTERVAL=0

    ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    CLONE="$BATS_TEST_TMPDIR/clone"
    REJECT_FLAG="$BATS_TEST_TMPDIR/reject-main"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    export GH_ORIGIN="$ORIGIN"
    export GH_STATE_DIR="$BATS_TEST_TMPDIR/gh-state"
    mkdir -p "$GH_STATE_DIR"
    unset GH_MERGE_FAIL

    git init --bare -q "$ORIGIN"
    git clone -q "$ORIGIN" "$CLONE" 2>/dev/null
    (
        cd "$CLONE"
        git config user.email test@test.com
        git config user.name test
        git checkout -q -B main
        echo base > base.txt
        git add base.txt
        git commit -q -m "base"
        git push -q origin main
    )

    # Rejects updates of refs/heads/main while the flag file exists (imitates a ruleset).
    cat > "$ORIGIN/hooks/pre-receive" <<HOOK
#!/bin/bash
while read old new ref; do
  if [ "\$ref" = "refs/heads/main" ] && [ -f "$REJECT_FLAG" ]; then
    echo "remote: error: GH013: Repository rule violations found for refs/heads/main." >&2
    exit 1
  fi
done
exit 0
HOOK
    chmod +x "$ORIGIN/hooks/pre-receive"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GH_LOG"
if [[ "$1" == "pr" && "$2" == "create" ]]; then
    while [[ $# -gt 0 ]]; do
        [[ "$1" == "--head" ]] && echo "$2" > "$GH_STATE_DIR/head"
        shift
    done
    echo "https://github.com/o/r/pull/1"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "merge" ]]; then
    if [[ -n "${GH_MERGE_FAIL:-}" ]]; then
        echo "merge blocked by required checks" >&2
        exit 1
    fi
    head=$(cat "$GH_STATE_DIR/head")
    new=$(git --git-dir "$GH_ORIGIN" commit-tree "refs/heads/$head^{tree}" -p refs/heads/main -m "squash merge")
    git --git-dir "$GH_ORIGIN" update-ref refs/heads/main "$new"
    git --git-dir "$GH_ORIGIN" update-ref -d "refs/heads/$head"
    echo merged > "$GH_STATE_DIR/state"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "view" ]]; then
    [[ -f "$GH_STATE_DIR/state" ]] && echo MERGED || echo OPEN
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_DIR" 2>/dev/null || true
}

# Add a commit touching $1 on the branch currently checked out in $CLONE.
_commit_file() {
    (
        cd "$CLONE"
        echo "$1" > "$1"
        git add "$1"
        git commit -q -m "add $1"
    )
}

@test "direct push succeeds: result=direct and gh is never called" {
    _commit_file feature.txt

    run bash -c "cd '$CLONE' && bash '$SCRIPT'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"push-to-base: result=direct"* ]]
    [ ! -s "$GH_LOG" ]
    git --git-dir "$ORIGIN" cat-file -e main:feature.txt
}

@test "non-fast-forward rejection exits 1 without creating a PR" {
    OTHER="$BATS_TEST_TMPDIR/other"
    git clone -q "$ORIGIN" "$OTHER" 2>/dev/null
    (
        cd "$OTHER"
        git config user.email test@test.com
        git config user.name test
        git checkout -q main
        echo other > other.txt
        git add other.txt
        git commit -q -m "other"
        git push -q origin main
    )
    _commit_file feature.txt

    run bash -c "cd '$CLONE' && bash '$SCRIPT'"
    [ "$status" -eq 1 ]
    [[ "$output" != *"result="* ]]
    [ ! -s "$GH_LOG" ]
    [ -z "$(git -C "$CLONE" branch --list 'wholework-record/*')" ]
    [ "$(git --git-dir "$ORIGIN" for-each-ref --format='%(refname)' refs/heads)" = "refs/heads/main" ]
}

@test "remote rejection lands the commits through a record PR and exits 0" {
    _commit_file feature.txt
    touch "$REJECT_FLAG"

    run bash -c "cd '$CLONE' && bash '$SCRIPT'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"push-to-base: result=record-pr url=https://github.com/o/r/pull/1"* ]]
    git --git-dir "$ORIGIN" cat-file -e main:feature.txt
    # The record branch is gone locally and on the remote.
    [ -z "$(git -C "$CLONE" branch --list 'wholework-record/*')" ]
    [ "$(git --git-dir "$ORIGIN" for-each-ref --format='%(refname)' refs/heads)" = "refs/heads/main" ]
    grep -q "pr create --base main --head wholework-record/main-" "$GH_LOG"
    grep -q -- "--squash" "$GH_LOG"
    grep -q -- "--match-head-commit" "$GH_LOG"
}

@test "record PR merge failure exits 2 and keeps the local record branch" {
    _commit_file feature.txt
    touch "$REJECT_FLAG"
    export GH_MERGE_FAIL=1
    before=$(git --git-dir "$ORIGIN" rev-parse main)

    run bash -c "cd '$CLONE' && bash '$SCRIPT'"
    [ "$status" -eq 2 ]
    [[ "$output" == *"https://github.com/o/r/pull/1"* ]]
    [[ "$output" != *"result=record-pr"* ]]
    [ "$(git --git-dir "$ORIGIN" rev-parse main)" = "$before" ]
    [ -n "$(git -C "$CLONE" branch --list 'wholework-record/*')" ]
}

@test "--ref HEAD pushes a worktree branch tip to main" {
    (
        cd "$CLONE"
        git checkout -q -b feat
    )
    _commit_file feature.txt

    run bash -c "cd '$CLONE' && bash '$SCRIPT' --ref HEAD --base main"
    [ "$status" -eq 0 ]
    [[ "$output" == *"push-to-base: result=direct"* ]]
    [ "$(git --git-dir "$ORIGIN" rev-parse main)" = "$(git -C "$CLONE" rev-parse feat)" ]
}

@test "missing option value or invalid ref exits 2" {
    run bash -c "cd '$CLONE' && bash '$SCRIPT' --ref"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]

    run bash -c "cd '$CLONE' && bash '$SCRIPT' --base"
    [ "$status" -eq 2 ]

    run bash -c "cd '$CLONE' && bash '$SCRIPT' --bogus"
    [ "$status" -eq 2 ]

    run bash -c "cd '$CLONE' && bash '$SCRIPT' --ref no-such-ref --base main"
    [ "$status" -eq 2 ]
    [ ! -s "$GH_LOG" ]

    run bash -c "cd '$CLONE' && bash '$SCRIPT' --base 'bad..name'"
    [ "$status" -eq 2 ]
}
