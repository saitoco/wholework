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
    ! grep -q "merge test-branch --ff-only" "$GIT_LOG"
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
    ! grep -q "merge test-branch --ff-only" "$GIT_LOG"
    ! grep -qE "^rebase " "$GIT_LOG"
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
    ! grep -qE "^rebase origin/main" "$GIT_LOG"
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
    ! grep -q "rebase origin/main" "$GIT_LOG"
    ! grep -qE "\-C .+ rebase" "$GIT_LOG"
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
