#!/usr/bin/env bats

# Tests for worktree-merge-push.sh
# Mocks get-config-value.sh via WHOLEWORK_SCRIPT_DIR, and git via PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/worktree-merge-push.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    mkdir -p "$BATS_TEST_TMPDIR/test-repo"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    unset WHOLEWORK_PATCH_LOCK_TIMEOUT
    unset WHOLEWORK_PATCH_LOCK_LOG_INTERVAL

    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    # WHOLEWORK_SCRIPT_DIR points at $MOCK_DIR, so the real push helper must be there too.
    cp "$(dirname "$SCRIPT")/push-to-base.sh" "$MOCK_DIR/push-to-base.sh"
}

teardown() {
    rm -rf "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" 2>/dev/null || true
    rm -rf "$MOCK_DIR" 2>/dev/null || true
}

@test "lock dir is created during execution and released after with --from" {
    LOCK_CHECK_FILE="$BATS_TEST_TMPDIR/lock_check.txt"
    export LOCK_CHECK_FILE

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "push" ]]; then
    [ -d "${BATS_TEST_TMPDIR}/test-repo/.tmp/claude-auto-patch-lock" ] && echo "LOCK_EXISTS" > "\$LOCK_CHECK_FILE" || true
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]

    [ -f "$LOCK_CHECK_FILE" ]
    grep -q "LOCK_EXISTS" "$LOCK_CHECK_FILE"
    [ ! -d "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" ]
}

@test "stale PID is reclaimed and lock is acquired" {
    bash -c 'exit 0' &
    DEAD_PID=$!
    wait "$DEAD_PID" 2>/dev/null || true

    LOCK_DIR="$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"
    mkdir -p "$LOCK_DIR"
    echo "$DEAD_PID" > "$LOCK_DIR/pid"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stale lock detected"* ]]
    grep -q "push origin main" "$GIT_LOG"
}

@test "diagnostic log is output when waiting for a live lock holder" {
    LOCK_DIR="$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"
    mkdir -p "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    export WHOLEWORK_PATCH_LOCK_TIMEOUT=4
    export WHOLEWORK_PATCH_LOCK_LOG_INTERVAL=2

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 1 ]
    [[ "$output" == *"waiting for lock held by pid="* ]]
    [[ "$output" == *"Patch lock acquisition timeout"* ]]
}

@test "timeout is read from .wholework.yml via get-config-value.sh" {
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "patch-lock-timeout" ]]; then
    echo "5"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    LOCK_DIR="$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock"
    mkdir -p "$LOCK_DIR"
    echo "$$" > "$LOCK_DIR/pid"

    unset WHOLEWORK_PATCH_LOCK_TIMEOUT
    export WHOLEWORK_PATCH_LOCK_LOG_INTERVAL=2

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Patch lock acquisition timeout (5s)"* ]]
}

@test "default timeout is 300 seconds" {
    grep -q -- ':-300}' "$SCRIPT"
}

@test "--from triggers checkout-less ref-fetch (primary path)" {
    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    grep -q "fetch . test-branch:main" "$GIT_LOG"
    grep -q "push origin main" "$GIT_LOG"
    ! grep -q "merge test-branch --ff-only" "$GIT_LOG"
}

@test "--from with ref-fetch rejected while base is checked out locally merges in place" {
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    exit 1
fi
if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
    echo "main"
    exit 0
fi
if [[ "\$1" == "merge" ]]; then
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"checked out here; merging in place"* ]]
    grep -q "merge test-branch --ff-only" "$GIT_LOG"
    grep -q "push origin main" "$GIT_LOG"
    ! grep -q "pull --rebase" "$GIT_LOG"
}

@test "--from with base checked out and diverged triggers true-side worktree rebase fallback" {
    WORKTREE_PATH="$BATS_TEST_TMPDIR/fake-worktree"
    mkdir -p "$WORKTREE_PATH"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    exit 1
fi
if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
    echo "main"
    exit 0
fi
if [[ "\$1" == "merge" ]]; then
    COUNT_FILE="${BATS_TEST_TMPDIR}/merge_count"
    count=0
    [ -f "\$COUNT_FILE" ] && count=\$(cat "\$COUNT_FILE")
    count=\$((count + 1))
    echo "\$count" > "\$COUNT_FILE"
    [ "\$count" -eq 1 ] && exit 1
    exit 0
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf "worktree ${WORKTREE_PATH}\nbranch refs/heads/test-branch\n\n"
    exit 0
fi
# git -C <path> rebase main
if [[ "\$1" == "-C" && "\$3" == "rebase" ]]; then
    exit 0
fi
# merge-base --is-ancestor: return 1 (not ancestor) so rebase runs
if [[ "\$1" == "merge-base" && "\$2" == "--is-ancestor" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FF merge failed while main is checked out"* ]]
    grep -q -- "-C ${WORKTREE_PATH} rebase main" "$GIT_LOG"
    if grep -q -- "-C ${WORKTREE_PATH} rebase origin/main" "$GIT_LOG"; then false; fi
    merge_count=$(grep -c "merge test-branch --ff-only" "$GIT_LOG")
    [ "$merge_count" -eq 2 ]
    grep -q "push origin main" "$GIT_LOG"
}

@test "--from with base checked out, diverged, and rebase conflict aborts and exits non-zero" {
    WORKTREE_PATH="$BATS_TEST_TMPDIR/fake-worktree"
    mkdir -p "$WORKTREE_PATH"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    exit 1
fi
if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
    echo "main"
    exit 0
fi
if [[ "\$1" == "merge" ]]; then
    exit 1
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf "worktree ${WORKTREE_PATH}\nbranch refs/heads/test-branch\n\n"
    exit 0
fi
# git -C <path> rebase main fails (conflict)
if [[ "\$1" == "-C" && "\$3" == "rebase" && "\$4" != "--abort" ]]; then
    exit 1
fi
if [[ "\$1" == "merge-base" && "\$2" == "--is-ancestor" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Rebase of test-branch onto main failed with conflicts"* ]]
    grep -q -- "-C ${WORKTREE_PATH} rebase --abort" "$GIT_LOG"
    ! grep -q "push" "$GIT_LOG"
}

@test "--base targets non-main branch" {
    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch --base release/v1"
    [ "$status" -eq 0 ]
    grep -q "push origin release/v1" "$GIT_LOG"
}

@test "--from with base-diverged triggers worktree rebase fallback" {
    WORKTREE_PATH="$BATS_TEST_TMPDIR/fake-worktree"
    mkdir -p "$WORKTREE_PATH"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
    echo "other-branch"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    COUNT_FILE="${BATS_TEST_TMPDIR}/fetch_count"
    count=0
    [ -f "\$COUNT_FILE" ] && count=\$(cat "\$COUNT_FILE")
    count=\$((count + 1))
    echo "\$count" > "\$COUNT_FILE"
    [ "\$count" -eq 1 ] && exit 1
    exit 0
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf "worktree ${WORKTREE_PATH}\nbranch refs/heads/test-branch\n\n"
    exit 0
fi
# git -C <path> rebase origin/main
if [[ "\$1" == "-C" && "\$3" == "rebase" ]]; then
    exit 0
fi
# merge-base --is-ancestor: return 1 (not ancestor) so rebase runs
if [[ "\$1" == "merge-base" && "\$2" == "--is-ancestor" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"base may have diverged"* ]]
    grep -q "worktree list --porcelain" "$GIT_LOG"
    grep -q -- "-C ${WORKTREE_PATH} rebase origin/main" "$GIT_LOG"
    grep -q "push origin main" "$GIT_LOG"
    if grep -q "merge test-branch --ff-only" "$GIT_LOG"; then false; fi
    fetch_count=$(grep -c "fetch . test-branch:main" "$GIT_LOG")
    [ "$fetch_count" -eq 2 ]
}

@test "--from with base-diverged and rebase conflict aborts and exits non-zero" {
    WORKTREE_PATH="$BATS_TEST_TMPDIR/fake-worktree"
    mkdir -p "$WORKTREE_PATH"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
    echo "other-branch"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    exit 1
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf "worktree ${WORKTREE_PATH}\nbranch refs/heads/test-branch\n\n"
    exit 0
fi
# git -C <path> rebase origin/main fails (conflict)
if [[ "\$1" == "-C" && "\$3" == "rebase" && "\$4" != "--abort" ]]; then
    exit 1
fi
# merge-base --is-ancestor: return 1 (not ancestor) so rebase runs
if [[ "\$1" == "merge-base" && "\$2" == "--is-ancestor" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Rebase"*"failed with conflicts"* ]]
    ! grep -q "push" "$GIT_LOG"
}

@test "--from with foreign checkout and no worktree found aborts without touching shared directory" {
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
    echo "some-other-session-branch"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    exit 1
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf ""
    exit 0
fi
if [[ "\$1" == "merge-base" && "\$2" == "--is-ancestor" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot locate a worktree"* ]]
    if grep -q "merge test-branch --ff-only" "$GIT_LOG"; then false; fi
    if grep -qE "^rebase " "$GIT_LOG"; then false; fi
    ! grep -q "push" "$GIT_LOG"
}

@test "push race: push fails once then succeeds after fetch-rebase retry" {
    WORKTREE_PATH="$BATS_TEST_TMPDIR/fake-worktree"
    mkdir -p "$WORKTREE_PATH"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "push" ]]; then
    COUNT_FILE="${BATS_TEST_TMPDIR}/push_count"
    count=0
    [ -f "\$COUNT_FILE" ] && count=\$(cat "\$COUNT_FILE")
    count=\$((count + 1))
    echo "\$count" > "\$COUNT_FILE"
    [ "\$count" -eq 1 ] && exit 1
    exit 0
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf "worktree ${WORKTREE_PATH}\nbranch refs/heads/test-branch\n\n"
    exit 0
fi
if [[ "\$1" == "-C" && "\$3" == "rebase" ]]; then
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"retry 1/3"* ]]
    grep -q "fetch origin main" "$GIT_LOG"
    push_count=$(grep -c "push origin main" "$GIT_LOG")
    [ "$push_count" -eq 2 ]
}

@test "push race with --from uses worktree-scoped rebase, not a bare rebase" {
    WORKTREE_PATH="$BATS_TEST_TMPDIR/fake-worktree"
    mkdir -p "$WORKTREE_PATH"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "push" ]]; then
    COUNT_FILE="${BATS_TEST_TMPDIR}/push_count"
    count=0
    [ -f "\$COUNT_FILE" ] && count=\$(cat "\$COUNT_FILE")
    count=\$((count + 1))
    echo "\$count" > "\$COUNT_FILE"
    [ "\$count" -eq 1 ] && exit 1
    exit 0
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf "worktree ${WORKTREE_PATH}\nbranch refs/heads/test-branch\n\n"
    exit 0
fi
if [[ "\$1" == "-C" && "\$3" == "rebase" ]]; then
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    grep -q -- "-C ${WORKTREE_PATH} rebase origin/main" "$GIT_LOG"
    if grep -qE "^rebase origin/main" "$GIT_LOG"; then false; fi
    grep -q -- "fetch . +test-branch:main" "$GIT_LOG"
}

@test "push race with --from: retry ref-fetch succeeds via force refspec despite local base being stale" {
    # Uses real git (not the PATH mock) to reproduce the actual non-fast-forward
    # rejection a plain (non-force) ref-to-ref fetch hits here: local $BASE_BRANCH in
    # the shared dir still holds the pre-race value, while the worktree's rebased
    # branch descends from the newly-fetched origin/$BASE_BRANCH instead.
    rm -f "$MOCK_DIR/git"

    REAL_ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    SHARED="$BATS_TEST_TMPDIR/test-repo"
    WT="$BATS_TEST_TMPDIR/wt-feature"
    OTHER="$BATS_TEST_TMPDIR/other-session"

    git init --bare -q "$REAL_ORIGIN"

    git clone -q "$REAL_ORIGIN" "$SHARED"
    cd "$SHARED"
    git config user.email test@test.com
    git config user.name test
    # Force the branch name regardless of the runner's init.defaultBranch config.
    git checkout -q -B main
    echo base > base.txt
    git add base.txt
    git commit -q -m "base"
    git push -q origin main

    git worktree add -q -b test-branch "$WT" main
    cd "$WT"
    git config user.email test@test.com
    git config user.name test
    echo feature > feature.txt
    git add feature.txt
    git commit -q -m "feature work"

    # Primary merge path pre-condition: local main already fast-forwarded to the
    # worktree branch tip, and main is not checked out in the shared dir.
    cd "$SHARED"
    git checkout -q -b some-other-branch
    git fetch . test-branch:main

    # Concurrent session pushes to origin after our local main was set, so our
    # eventual `git push origin main` below is rejected as non-fast-forward.
    git clone -q "$REAL_ORIGIN" "$OTHER"
    cd "$OTHER"
    git config user.email test@test.com
    git config user.name test
    git checkout -q main
    echo other > other.txt
    git add other.txt
    git commit -q -m "other session work"
    git push -q origin main

    cd "$SHARED"
    run bash "$SCRIPT" --from test-branch
    [ "$status" -eq 0 ]
    [[ "$output" == *"retry 1/3"* ]]
}

# Real-git fixture for a push race while BASE_BRANCH (main) is checked out in the shared dir:
# origin + shared clone on main + worktree branch "test-branch" with one commit + another
# session that already pushed a commit touching $1 to origin/main. Leaves cwd in $SHARED.
setup_checked_out_base_race() {
    local other_file="$1"
    rm -f "$MOCK_DIR/git"
    REAL_ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    SHARED="$BATS_TEST_TMPDIR/test-repo"
    WT="$BATS_TEST_TMPDIR/wt-feature"
    OTHER="$BATS_TEST_TMPDIR/other-session"

    git init --bare -q "$REAL_ORIGIN"
    git clone -q "$REAL_ORIGIN" "$SHARED"
    cd "$SHARED"
    git config user.email test@test.com
    git config user.name test
    # Force the branch name regardless of the runner's init.defaultBranch config.
    git checkout -q -B main
    echo base > base.txt
    echo notes > notes.txt
    git add base.txt notes.txt
    git commit -q -m "base"
    git push -q origin main

    git worktree add -q -b test-branch "$WT" main
    cd "$WT"
    echo feature > feature.txt
    git add feature.txt
    git commit -q -m "feature work"

    git clone -q "$REAL_ORIGIN" "$OTHER"
    cd "$OTHER"
    git config user.email test@test.com
    git config user.name test
    git checkout -q main
    echo other >> "$other_file"
    git add "$other_file"
    git commit -q -m "other session work"
    git push -q origin main

    cd "$SHARED"
}

@test "push race with --from while base is checked out in the shared dir: retry resets base in place and keeps uncommitted edits" {
    setup_checked_out_base_race other.txt
    echo "local edit" >> notes.txt

    run bash "$SCRIPT" --from test-branch
    [ "$status" -eq 0 ]
    [[ "$output" == *"retry 1/3"* ]] || false
    [[ "$output" == *"resetting it onto test-branch in place"* ]] || false

    # Base moved onto the rebased branch and was pushed; index and worktree follow HEAD.
    [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
    [ "$(git rev-parse main)" = "$(git rev-parse test-branch)" ]
    [ "$(git -C "$REAL_ORIGIN" rev-parse main)" = "$(git rev-parse test-branch)" ]
    run git -C "$REAL_ORIGIN" log --format=%s main
    [[ "$output" == *"feature work"* ]] || false
    [[ "$output" == *"other session work"* ]] || false
    [ -f other.txt ]

    # The unrelated uncommitted edit survived and nothing else is pending.
    grep -q "local edit" notes.txt
    run git status --porcelain
    [ "$output" = " M notes.txt" ]

    # The caller's cleanup (worktree-lifecycle Exit step 4) still succeeds: base == branch tip.
    git worktree remove "$WT"
    git branch -d test-branch
}

@test "push race with --from while base is checked out: aborts and leaves local state intact when uncommitted edits conflict with the reset" {
    setup_checked_out_base_race notes.txt
    echo "local edit" >> notes.txt
    pre_from=$(git rev-parse test-branch)
    pre_origin=$(git -C "$REAL_ORIGIN" rev-parse main)

    run bash "$SCRIPT" --from test-branch
    [ "$status" -ne 0 ]
    [[ "$output" == *"git reset --keep of main onto test-branch failed"* ]] || false
    grep -q "local edit" notes.txt
    [ "$(git rev-parse main)" = "$pre_from" ]
    [ "$(git -C "$REAL_ORIGIN" rev-parse main)" = "$pre_origin" ]
    [ ! -d "$SHARED/.tmp/claude-auto-patch-lock" ]
}

@test "push race with --from: retry ref-fetch rejected while the shared dir is on another branch does not reset and aborts" {
    WORKTREE_PATH="$BATS_TEST_TMPDIR/fake-worktree"
    mkdir -p "$WORKTREE_PATH"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
    echo "some-other-session-branch"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    COUNT_FILE="${BATS_TEST_TMPDIR}/fetch_count"
    count=0
    [ -f "\$COUNT_FILE" ] && count=\$(cat "\$COUNT_FILE")
    count=\$((count + 1))
    echo "\$count" > "\$COUNT_FILE"
    # 1st: primary ref-fetch rejected; 2nd: succeeds after the ancestry check; 3rd+: retry-scoped ref-fetch rejected
    [ "\$count" -eq 1 ] && exit 1
    [ "\$count" -ge 3 ] && exit 1
    exit 0
fi
if [[ "\$1" == "push" ]]; then
    exit 1
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf "worktree ${WORKTREE_PATH}\nbranch refs/heads/test-branch\n\n"
    exit 0
fi
if [[ "\$1" == "merge-base" && "\$2" == "--is-ancestor" ]]; then
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ref-fetch retry after push-rebase failed"* ]] || false
    if grep -qE "^reset" "$GIT_LOG"; then false; fi
    push_count=$(grep -c "push origin main" "$GIT_LOG")
    [ "$push_count" -eq 1 ]
}

@test "push race with --from: retry loop aborts when no worktree is found for rebase" {
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    exit 0
fi
if [[ "\$1" == "push" ]]; then
    exit 1
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf ""
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot locate a worktree"* ]]
    push_count=$(grep -c "push origin main" "$GIT_LOG")
    [ "$push_count" -eq 1 ]
}

@test "push race with --from: retry loop aborts when the retry-scoped rebase conflicts" {
    WORKTREE_PATH="$BATS_TEST_TMPDIR/fake-worktree"
    mkdir -p "$WORKTREE_PATH"

    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    exit 0
fi
if [[ "\$1" == "push" ]]; then
    exit 1
fi
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    printf "worktree ${WORKTREE_PATH}\nbranch refs/heads/test-branch\n\n"
    exit 0
fi
if [[ "\$1" == "-C" && "\$3" == "rebase" && "\$4" != "--abort" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Rebase during push retry failed with conflicts"* ]]
    grep -q -- "-C ${WORKTREE_PATH} rebase --abort" "$GIT_LOG"
    push_count=$(grep -c "push origin main" "$GIT_LOG")
    [ "$push_count" -eq 1 ]
}

@test "is-ancestor true: rebase is skipped when branch already contains origin base" {
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "rev-parse" && "\$2" == "--abbrev-ref" ]]; then
    echo "other-branch"
    exit 0
fi
if [[ "\$1" == "fetch" && "\$2" == "." ]]; then
    COUNT_FILE="${BATS_TEST_TMPDIR}/fetch_count"
    count=0
    [ -f "\$COUNT_FILE" ] && count=\$(cat "\$COUNT_FILE")
    count=\$((count + 1))
    echo "\$count" > "\$COUNT_FILE"
    [ "\$count" -eq 1 ] && exit 1
    exit 0
fi
# merge-base --is-ancestor: return 0 (ancestor=true) so rebase is skipped
if [[ "\$1" == "merge-base" && "\$2" == "--is-ancestor" ]]; then
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"is-ancestor=true"* ]]
    if grep -q "rebase origin/main" "$GIT_LOG"; then false; fi
    if grep -qE "\-C .+ rebase" "$GIT_LOG"; then false; fi
    grep -q "push origin main" "$GIT_LOG"
    fetch_count=$(grep -c "fetch . test-branch:main" "$GIT_LOG")
    [ "$fetch_count" -eq 2 ]
}

@test "max-retry exhaustion: push always fails and script exits with error" {
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "push" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT'"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Error"* ]]
    [[ "$output" == *"3 retries"* ]]
}

@test "conflict markers cause abort with non-zero exit and no push" {
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "\$@" >> "$GIT_LOG"
if [[ "\$1" == "rev-parse" && "\$2" == "--show-toplevel" ]]; then
    echo "${BATS_TEST_TMPDIR}/test-repo"
    exit 0
fi
if [[ "\$1" == "grep" ]]; then
    echo "conflict.txt"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash -c "cd '$BATS_TEST_TMPDIR/test-repo' && bash '$SCRIPT' --from test-branch"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Conflict markers remain"* ]]
    ! grep -q "push" "$GIT_LOG"
}

# --- Direct push rejected by a remote rule (phase-record PR fallback) ---
#
# Real-git fixture: a bare origin whose pre-receive hook rejects updates of refs/heads/main
# while $REJECT_FLAG exists (a server-side "[remote rejected]", unlike the client-side
# non-fast-forward "[rejected]"), a shared clone with main checked out, and a worktree on
# branch test-branch holding one feature commit. `gh` is a PATH mock that records its argv and
# imitates a squash merge on the bare origin.
_setup_rejecting_origin() {
    rm -f "$MOCK_DIR/git"

    REAL_ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    SHARED="$BATS_TEST_TMPDIR/test-repo"
    WT="$BATS_TEST_TMPDIR/wt-feature"
    REJECT_FLAG="$BATS_TEST_TMPDIR/reject-main"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    export GH_ORIGIN="$REAL_ORIGIN"
    export GH_STATE_DIR="$BATS_TEST_TMPDIR/gh-state"
    mkdir -p "$GH_STATE_DIR"
    unset GH_MERGE_FAIL
    export WHOLEWORK_PUSH_RETRY_INTERVAL=0

    git init --bare -q "$REAL_ORIGIN"
    git clone -q "$REAL_ORIGIN" "$SHARED" 2>/dev/null
    cd "$SHARED"
    git config user.email test@test.com
    git config user.name test
    git checkout -q -B main
    echo base > base.txt
    git add base.txt
    git commit -q -m "base"
    git push -q origin main

    git worktree add -q -b test-branch "$WT" main
    cd "$WT"
    git config user.email test@test.com
    git config user.name test
    echo feature > feature.txt
    git add feature.txt
    git commit -q -m "feature work"
    cd "$SHARED"

    cat > "$REAL_ORIGIN/hooks/pre-receive" <<HOOK
#!/bin/bash
while read old new ref; do
  if [ "\$ref" = "refs/heads/main" ] && [ -f "$REJECT_FLAG" ]; then
    echo "remote: error: GH013: Repository rule violations found for refs/heads/main." >&2
    exit 1
  fi
done
exit 0
HOOK
    chmod +x "$REAL_ORIGIN/hooks/pre-receive"

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
}

@test "push rejected by a remote rule: lands via record PR and realigns local base and from-branch to origin" {
    _setup_rejecting_origin
    touch "$REJECT_FLAG"

    run bash "$SCRIPT" --from test-branch
    [ "$status" -eq 0 ]
    [[ "$output" == *"landed via phase-record PR"* ]]

    git --git-dir "$REAL_ORIGIN" cat-file -e main:feature.txt
    [ "$(git rev-parse main)" = "$(git --git-dir "$REAL_ORIGIN" rev-parse main)" ]
    [ "$(git rev-parse test-branch)" = "$(git --git-dir "$REAL_ORIGIN" rev-parse main)" ]
    # The caller's cleanup (Exit: merge-to-main step 4) goes through unchanged.
    git worktree remove "$WT"
    git branch -d test-branch
}

@test "push rejected by a remote rule and record PR cannot be merged: exits non-zero and local base is not left ahead" {
    _setup_rejecting_origin
    touch "$REJECT_FLAG"
    export GH_MERGE_FAIL=1

    run bash "$SCRIPT" --from test-branch
    [ "$status" -ne 0 ]
    [[ "$output" == *"https://github.com/o/r/pull/1"* ]]

    [ "$(git rev-parse main)" = "$(git --git-dir "$REAL_ORIGIN" rev-parse main)" ]
    # The feature commit is still reachable from the worktree branch.
    git cat-file -e test-branch:feature.txt
}

@test "direct push allowed: pushes base directly without creating a record PR or branch" {
    _setup_rejecting_origin

    run bash "$SCRIPT" --from test-branch
    [ "$status" -eq 0 ]

    [ ! -s "$GH_LOG" ]
    [ "$(git --git-dir "$REAL_ORIGIN" for-each-ref --format='%(refname)' refs/heads)" = "refs/heads/main" ]
    [ "$(git --git-dir "$REAL_ORIGIN" rev-parse main)" = "$(git rev-parse test-branch)" ]
}
