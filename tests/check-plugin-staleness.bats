#!/usr/bin/env bats

# Tests for check-plugin-staleness.sh
# Uses real git repositories (bare upstream + clones); git is mocked only for the
# two git-failure cases.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-plugin-staleness.sh"

setup() {
    UPSTREAM="$BATS_TEST_TMPDIR/upstream.git"
    SEED="$BATS_TEST_TMPDIR/seed"
    WORK="$BATS_TEST_TMPDIR/work"

    git init -q --bare -b main "$UPSTREAM"

    git init -q -b main "$SEED"
    configure_repo "$SEED"
    local i
    for i in 1 2 3 4 5; do
        echo "$i" > "$SEED/file.txt"
        git -C "$SEED" add -A
        git -C "$SEED" commit -q -m "commit $i"
    done
    git -C "$SEED" remote add origin "$UPSTREAM"
    git -C "$SEED" push -q origin main

    git clone -q "$UPSTREAM" "$WORK"
    configure_repo "$WORK"
    WORK="$(cd "$WORK" && pwd -P)"
}

configure_repo() {
    git -C "$1" config user.email "test@example.com"
    git -C "$1" config user.name "Test"
    git -C "$1" config commit.gpgsign false
}

# Make the work clone N commits behind its upstream (the remote-tracking ref stays put).
make_behind() {
    git -C "$WORK" reset -q --hard "HEAD~$1"
}

# Clone the work clone into $1 and make that clone one commit behind its upstream (the work clone).
make_behind_clone() {
    git clone -q "$WORK" "$1"
    configure_repo "$1"
    git -C "$1" reset -q --hard HEAD~1
}

# Push N new commits to the upstream from a separate clone.
push_upstream_commits() {
    local n="$1" pusher="$BATS_TEST_TMPDIR/pusher" i
    git clone -q "$UPSTREAM" "$pusher"
    configure_repo "$pusher"
    for i in $(seq "$n"); do
        git -C "$pusher" commit -q --allow-empty -m "upstream $i"
    done
    git -C "$pusher" push -q origin HEAD:main
}

@test "behind upstream: prints one behind=N line with upstream and root" {
    make_behind 3
    run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ "$output" = "behind=3 upstream=origin/main root=$WORK" ]
    [ -z "$stderr" ]
}

@test "in sync with upstream: prints nothing" {
    run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}

@test "ahead of upstream only: prints nothing" {
    git -C "$WORK" commit -q --allow-empty -m "local only"
    run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}

@test "diverged: counts only the upstream-side commits" {
    git -C "$WORK" commit -q --allow-empty -m "local only"
    push_upstream_commits 2
    git -C "$WORK" fetch -q
    run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ "$output" = "behind=2 upstream=origin/main root=$WORK" ]
}

@test "does not fetch: a stale remote-tracking ref hides new upstream commits until an explicit fetch" {
    push_upstream_commits 2

    run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    git -C "$WORK" fetch -q
    run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ "$output" = "behind=2 upstream=origin/main root=$WORK" ]
}

@test "read-only: HEAD, remote-tracking ref and worktree state are unchanged" {
    make_behind 2
    echo "dirty" > "$WORK/untracked.txt"
    local head_before ref_before status_before
    head_before="$(git -C "$WORK" rev-parse HEAD)"
    ref_before="$(git -C "$WORK" rev-parse refs/remotes/origin/main)"
    status_before="$(git -C "$WORK" status --porcelain)"

    run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]

    [ "$(git -C "$WORK" rev-parse HEAD)" = "$head_before" ]
    [ "$(git -C "$WORK" rev-parse refs/remotes/origin/main)" = "$ref_before" ]
    [ "$(git -C "$WORK" status --porcelain)" = "$status_before" ]
}

@test "detached HEAD: prints nothing" {
    make_behind 2
    git -C "$WORK" checkout -q --detach
    run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}

@test "branch without upstream: prints nothing" {
    make_behind 2
    git -C "$WORK" branch -q --unset-upstream
    run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}

@test "plain directory outside any repository: prints nothing" {
    local plain="$BATS_TEST_TMPDIR/plain"
    mkdir -p "$plain"
    run --separate-stderr "$SCRIPT" "$plain"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}

@test "directory nested inside a behind repository: prints nothing" {
    make_behind 2
    mkdir -p "$WORK/nested/dir"
    run --separate-stderr "$SCRIPT" "$WORK/nested/dir"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}

@test "nonexistent, empty-string and oversized path arguments print nothing and exit 0" {
    run --separate-stderr "$SCRIPT" "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    local long
    long="$(printf 'a%.0s' $(seq 5000))"
    run --separate-stderr "$SCRIPT" "$BATS_TEST_TMPDIR/$long"
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    # An empty string falls back to the default root (this repository), so only the
    # exit code and the one-line-at-most contract can be asserted.
    run --separate-stderr "$SCRIPT" ""
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -le 1 ]
}

@test "root with space, quote, dollar, newline and multibyte characters: one shell-quoted line that round-trips" {
    local name dest expected line got
    for name in 'with space' 'q"uote' 'dol$lar' 'gt>sign' $'new\nline' $'car\rriage' 'マルチバイト'; do
        dest="$BATS_TEST_TMPDIR/$name"
        make_behind_clone "$dest"
        expected="$(cd "$dest" && pwd -P)"

        run --separate-stderr "$SCRIPT" "$dest"
        [ "$status" -eq 0 ]
        [ "${#lines[@]}" -eq 1 ]

        line="${output#*root=}"
        eval "got=$line"
        [ "$got" = "$expected" ]
        rm -rf "$dest"
    done
}

@test "symlinked plugin root: reports the physical path" {
    make_behind 3
    ln -s "$WORK" "$BATS_TEST_TMPDIR/link"
    run --separate-stderr "$SCRIPT" "$BATS_TEST_TMPDIR/link"
    [ "$status" -eq 0 ]
    [ "$output" = "behind=3 upstream=origin/main root=$WORK" ]
}

@test "default root is the parent directory of the script itself" {
    make_behind 3
    mkdir -p "$WORK/scripts"
    cp "$SCRIPT" "$WORK/scripts/check-plugin-staleness.sh"
    run --separate-stderr "$WORK/scripts/check-plugin-staleness.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "behind=3 upstream=origin/main root=$WORK" ]
}

@test "git failure: a fake git that exits 1 prints nothing" {
    make_behind 2
    local bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\nexit 1\n' > "$bin/git"
    chmod +x "$bin/git"

    PATH="$bin:$PATH" run --separate-stderr "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}

@test "non-numeric or negative count from git prints nothing" {
    make_behind 2
    local bin="$BATS_TEST_TMPDIR/bin" value
    mkdir -p "$bin"
    for value in abc -3 ''; do
        cat > "$bin/git" <<FAKE
#!/bin/sh
# git -C <dir> rev-parse --show-toplevel
if [ "\$4" = "--show-toplevel" ]; then
    printf '%s\n' "\$2"
    exit 0
fi
printf '%s\n' '$value'
exit 0
FAKE
        chmod +x "$bin/git"

        PATH="$bin:$PATH" run --separate-stderr "$SCRIPT" "$WORK"
        [ "$status" -eq 0 ]
        [ -z "$output" ]
        [ -z "$stderr" ]
    done
}

@test "no git on PATH: prints nothing and exits 0" {
    make_behind 2
    local empty="$BATS_TEST_TMPDIR/empty-path"
    mkdir -p "$empty"
    # Narrow PATH only for the script: bats' own `run` needs mktemp on the real PATH.
    run --separate-stderr env PATH="$empty" "$BASH" "$SCRIPT" "$WORK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -z "$stderr" ]
}
