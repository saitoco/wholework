#!/usr/bin/env bats

# Tests for scripts/phase-work-dir.sh
# The base directory is isolated with XDG_CACHE_HOME / HOME, and a mock `stat`
# makes the tmpfs guard deterministic even when the host /tmp is tmpfs.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/phase-work-dir.sh"

setup() {
    export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"

    MOCK_DIR="$BATS_TEST_TMPDIR/mock"
    mkdir -p "$MOCK_DIR"
    cat > "$MOCK_DIR/stat" <<'EOF'
#!/bin/bash
if [ "$1" = "-f" ] && [ "$2" = "-c" ] && [ "$3" = "%T" ]; then
    echo "${MOCK_FS_TYPE:-ext4}"
    exit 0
fi
exec /usr/bin/stat "$@"
EOF
    chmod +x "$MOCK_DIR/stat"
    export PATH="$MOCK_DIR:$PATH"

    REPO="$BATS_TEST_TMPDIR/work/proj"
    mkdir -p "$REPO"
    git init -q "$REPO"
    git -C "$REPO" config user.email "test@example.com"
    git -C "$REPO" config user.name "Test"
    git -C "$REPO" commit -q --allow-empty -m init
    cd "$REPO"
}

# --- path ----------------------------------------------------------------------

@test "path prints issue-N-phase under the work base" {
    run "$SCRIPT" path 1540 spec
    [ "$status" -eq 0 ]
    case "$output" in
        "$XDG_CACHE_HOME"/wholework/work/*/issue-1540-spec) ;;
        *) echo "unexpected path: $output"; false ;;
    esac
}

@test "path does not create anything" {
    run "$SCRIPT" path 1540 spec
    [ "$status" -eq 0 ]
    [ ! -e "$XDG_CACHE_HOME" ]
}

@test "path falls back to HOME/.cache when XDG_CACHE_HOME is unset" {
    unset XDG_CACHE_HOME
    run "$SCRIPT" path 1540 spec
    [ "$status" -eq 0 ]
    case "$output" in
        "$HOME"/.cache/wholework/work/*/issue-1540-spec) ;;
        *) echo "unexpected path: $output"; false ;;
    esac
}

@test "path falls back to HOME/.cache when XDG_CACHE_HOME is empty" {
    export XDG_CACHE_HOME=""
    run "$SCRIPT" path 1540 spec
    [ "$status" -eq 0 ]
    case "$output" in
        "$HOME"/.cache/wholework/work/*/issue-1540-spec) ;;
        *) echo "unexpected path: $output"; false ;;
    esac
}

@test "path ignores a relative XDG_CACHE_HOME" {
    export XDG_CACHE_HOME="relative/cache"
    run "$SCRIPT" path 1540 spec
    [ "$status" -eq 0 ]
    case "$output" in
        "$HOME"/.cache/wholework/work/*/issue-1540-spec) ;;
        *) echo "unexpected path: $output"; false ;;
    esac
}

@test "path strips trailing slashes from XDG_CACHE_HOME" {
    export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache//"
    run "$SCRIPT" path 1540 spec
    [ "$status" -eq 0 ]
    case "$output" in
        "$BATS_TEST_TMPDIR"/cache/wholework/work/*/issue-1540-spec) ;;
        *) echo "unexpected path: $output"; false ;;
    esac
}

@test "path fails when neither XDG_CACHE_HOME nor HOME is usable" {
    unset XDG_CACHE_HOME
    export HOME=""
    run "$SCRIPT" path 1540 spec
    [ "$status" -eq 1 ]
}

@test "path rejects a cache directory with a dot-dot component" {
    export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache/../escape"
    run "$SCRIPT" path 1540 spec
    [ "$status" -eq 1 ]
}

@test "path rejects a cache directory that resolves to root" {
    export XDG_CACHE_HOME="/"
    run "$SCRIPT" path 1540 spec
    [ "$status" -eq 1 ]
}

@test "path is the same from a worktree and from the main checkout" {
    run "$SCRIPT" path 1540 code
    [ "$status" -eq 0 ]
    main_path="$output"

    git worktree add -q -b wt-branch "$BATS_TEST_TMPDIR/wt"
    cd "$BATS_TEST_TMPDIR/wt"
    run "$SCRIPT" path 1540 code
    [ "$status" -eq 0 ]
    [ "$output" = "$main_path" ]
}

@test "path differs between repositories that share a directory name" {
    run "$SCRIPT" path 1540 code
    [ "$status" -eq 0 ]
    first="$output"

    other="$BATS_TEST_TMPDIR/other/proj"
    mkdir -p "$other"
    git init -q "$other"
    cd "$other"
    run "$SCRIPT" path 1540 code
    [ "$status" -eq 0 ]
    [ "$output" != "$first" ]
}

@test "path differs between separate-git-dir repositories that share a git dir parent" {
    mkdir -p "$BATS_TEST_TMPDIR/gd" "$BATS_TEST_TMPDIR/sep"
    git init -q --separate-git-dir="$BATS_TEST_TMPDIR/gd/a.git" "$BATS_TEST_TMPDIR/sep/a"
    git init -q --separate-git-dir="$BATS_TEST_TMPDIR/gd/b.git" "$BATS_TEST_TMPDIR/sep/b"
    cd "$BATS_TEST_TMPDIR/sep/a"
    run "$SCRIPT" path 5 spec
    [ "$status" -eq 0 ]
    first="$output"
    cd "$BATS_TEST_TMPDIR/sep/b"
    run "$SCRIPT" path 5 spec
    [ "$status" -eq 0 ]
    [ "$output" != "$first" ]
}

@test "path differs between bare repositories that share a parent directory" {
    mkdir -p "$BATS_TEST_TMPDIR/bare"
    git init -q --bare "$BATS_TEST_TMPDIR/bare/foo.git"
    git init -q --bare "$BATS_TEST_TMPDIR/bare/bar.git"
    cd "$BATS_TEST_TMPDIR/bare/foo.git"
    run "$SCRIPT" path 7 code
    [ "$status" -eq 0 ]
    first="$output"
    cd "$BATS_TEST_TMPDIR/bare/bar.git"
    run "$SCRIPT" path 7 code
    [ "$status" -eq 0 ]
    [ "$output" != "$first" ]
}

@test "path is not redirected by CDPATH" {
    run "$SCRIPT" path 1540 code
    [ "$status" -eq 0 ]
    expected="$output"
    mkdir -p "$BATS_TEST_TMPDIR/cdpath/.git"
    CDPATH="$BATS_TEST_TMPDIR/cdpath" run "$SCRIPT" path 1540 code
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test "path works outside a git repository" {
    plain="$BATS_TEST_TMPDIR/plain"
    mkdir -p "$plain"
    cd "$plain"
    run "$SCRIPT" path 1540 code
    [ "$status" -eq 0 ]
    case "$output" in
        */issue-1540-code) ;;
        *) echo "unexpected path: $output"; false ;;
    esac
}

# --- create --------------------------------------------------------------------

@test "create makes an owner-only directory and prints the path" {
    run "$SCRIPT" path 1540 spec
    expected="$output"
    run "$SCRIPT" create 1540 spec
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
    [ -d "$expected" ]
    [ "$(stat -c %a "$expected")" = "700" ]
}

@test "create is idempotent and keeps existing content" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    echo "keep" > "$dir/file.txt"
    run "$SCRIPT" create 1540 spec
    [ "$status" -eq 0 ]
    [ "$(cat "$dir/file.txt")" = "keep" ]
}

@test "create refuses a tmpfs base and creates nothing" {
    export MOCK_FS_TYPE="tmpfs"
    run "$SCRIPT" create 1540 spec
    [ "$status" -eq 1 ]
    [ ! -e "$XDG_CACHE_HOME/wholework" ]
}

@test "create refuses a ramfs base" {
    export MOCK_FS_TYPE="ramfs"
    run "$SCRIPT" create 1540 spec
    [ "$status" -eq 1 ]
}

@test "create refuses when the target is a symbolic link" {
    run "$SCRIPT" path 1540 spec
    dir="$output"
    mkdir -p "$(dirname "$dir")" "$BATS_TEST_TMPDIR/elsewhere"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$dir"
    run "$SCRIPT" create 1540 spec
    [ "$status" -eq 1 ]
}

# --- sweep ---------------------------------------------------------------------

@test "sweep removes the leftover of the same issue and phase" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    mkdir -p "$dir/repo-copy/node_modules"
    echo "x" > "$dir/repo-copy/node_modules/file"
    run "$SCRIPT" sweep 1540 spec
    [ "$status" -eq 0 ]
    [ ! -e "$dir" ]
    echo "$output" | grep -q "removed leftover"
}

@test "sweep keeps other phases and issues and warns with path and size" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    run "$SCRIPT" create 1540 code
    other_phase="$output"
    run "$SCRIPT" create 1541 spec
    other_issue="$output"
    run "$SCRIPT" sweep 1540 spec
    [ "$status" -eq 0 ]
    [ ! -e "$dir" ]
    [ -d "$other_phase" ]
    [ -d "$other_issue" ]
    echo "$output" | grep -q "$other_phase"
    echo "$output" | grep -q "$other_issue"
    echo "$output" | grep -qE "(KiB|MiB|GiB|size unknown)"
}

@test "sweep does not delete a same-named directory of another repository" {
    run "$SCRIPT" path 1540 spec
    mine="$output"
    other_key="$(dirname "$mine")"
    foreign="$(dirname "$other_key")/other-12345/issue-1540-spec"
    mkdir -p "$foreign"
    run "$SCRIPT" sweep 1540 spec
    [ "$status" -eq 0 ]
    [ -d "$foreign" ]
    echo "$output" | grep -q "$foreign"
}

@test "sweep prints nothing when there is no leftover" {
    run "$SCRIPT" create 1540 spec
    run "$SCRIPT" clean 1540 spec
    run "$SCRIPT" sweep 1540 spec
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "sweep succeeds when the base directory does not exist" {
    run "$SCRIPT" sweep 1540 spec
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "sweep caps warnings at 20 and summarizes the rest" {
    run "$SCRIPT" path 1540 spec
    key_dir="$(dirname "$output")"
    i=1
    while [ "$i" -le 22 ]; do
        mkdir -p "$key_dir/issue-$((2000 + i))-spec"
        i=$((i + 1))
    done
    run "$SCRIPT" sweep 1540 spec
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | grep -c "not removed")" -eq 20 ]
    echo "$output" | grep -q "2 more directories not shown"
}

@test "sweep leaves non issue directories and files alone" {
    run "$SCRIPT" path 1540 spec
    key_dir="$(dirname "$output")"
    mkdir -p "$key_dir/notes" "$key_dir/../stray-dir"
    echo "x" > "$key_dir/issue-file.txt"
    run "$SCRIPT" sweep 1540 spec
    [ "$status" -eq 0 ]
    [ -d "$key_dir/notes" ]
    [ -d "$key_dir/../stray-dir" ]
    [ -f "$key_dir/issue-file.txt" ]
    if echo "$output" | grep -q "notes"; then
        echo "non-issue directory was reported"
        false
    fi
}

# --- clean ---------------------------------------------------------------------

@test "clean removes the work directory" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    echo "x" > "$dir/file"
    run "$SCRIPT" clean 1540 spec
    [ "$status" -eq 0 ]
    [ ! -e "$dir" ]
}

@test "clean succeeds when the directory does not exist" {
    run "$SCRIPT" clean 1540 spec
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "clean leaves sibling directories" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    run "$SCRIPT" create 1540 code
    sibling="$output"
    run "$SCRIPT" clean 1540 spec
    [ "$status" -eq 0 ]
    [ ! -e "$dir" ]
    [ -d "$sibling" ]
}

@test "clean removes a read-only tree" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    mkdir -p "$dir/ro/sub"
    echo "x" > "$dir/ro/sub/file"
    chmod -R a-w "$dir/ro"
    run "$SCRIPT" clean 1540 spec
    [ "$status" -eq 0 ]
    [ ! -e "$dir" ]
}

@test "clean removes a symbolic link without touching its target" {
    run "$SCRIPT" path 1540 spec
    dir="$output"
    mkdir -p "$(dirname "$dir")" "$BATS_TEST_TMPDIR/elsewhere"
    echo "precious" > "$BATS_TEST_TMPDIR/elsewhere/file"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$dir"
    run "$SCRIPT" clean 1540 spec
    [ "$status" -eq 0 ]
    [ ! -L "$dir" ]
    [ "$(cat "$BATS_TEST_TMPDIR/elsewhere/file")" = "precious" ]
}

@test "sweep removes a symbolic link without touching its target" {
    run "$SCRIPT" path 1540 spec
    dir="$output"
    mkdir -p "$(dirname "$dir")" "$BATS_TEST_TMPDIR/elsewhere"
    echo "precious" > "$BATS_TEST_TMPDIR/elsewhere/file"
    ln -s "$BATS_TEST_TMPDIR/elsewhere" "$dir"
    run "$SCRIPT" sweep 1540 spec
    [ "$status" -eq 0 ]
    [ ! -L "$dir" ]
    [ "$(cat "$BATS_TEST_TMPDIR/elsewhere/file")" = "precious" ]
}

@test "clean exits 2 with a warning when rm fails" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    FAIL_DIR="$BATS_TEST_TMPDIR/failrm"
    mkdir -p "$FAIL_DIR"
    printf '#!/bin/bash\nexit 1\n' > "$FAIL_DIR/rm"
    chmod +x "$FAIL_DIR/rm"
    PATH="$FAIL_DIR:$PATH" run "$SCRIPT" clean 1540 spec
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "WARNING"
    [ -d "$dir" ]
}

@test "sweep exits 2 with a warning when rm fails" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    FAIL_DIR="$BATS_TEST_TMPDIR/failrm"
    mkdir -p "$FAIL_DIR"
    printf '#!/bin/bash\nexit 1\n' > "$FAIL_DIR/rm"
    chmod +x "$FAIL_DIR/rm"
    PATH="$FAIL_DIR:$PATH" run "$SCRIPT" sweep 1540 spec
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "could not remove"
    [ -d "$dir" ]
}

# --- input validation ----------------------------------------------------------

@test "invalid issue numbers are rejected and nothing is removed" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    for bad in "" 0 01 -5 "1 2" $'1\n2' $'1\r' "../1" "1;rm" "１２３" 1234567890 "1*"; do
        run "$SCRIPT" clean "$bad" spec
        [ "$status" -eq 1 ]
        run "$SCRIPT" sweep "$bad" spec
        [ "$status" -eq 1 ]
        run "$SCRIPT" create "$bad" spec
        [ "$status" -eq 1 ]
        run "$SCRIPT" path "$bad" spec
        [ "$status" -eq 1 ]
    done
    [ -d "$dir" ]
}

@test "invalid phases are rejected and nothing is removed" {
    run "$SCRIPT" create 1540 spec
    dir="$output"
    long="abcdefghijklmnopqrstuvwxyzabcdefg"
    for bad in "" Spec -spec 1spec "a/b" ".." "a.b" "a b" $'a\nb' $'a\rb' "ａｂｃ" "日本語" "$long"; do
        run "$SCRIPT" clean 1540 "$bad"
        [ "$status" -eq 1 ]
        run "$SCRIPT" sweep 1540 "$bad"
        [ "$status" -eq 1 ]
        run "$SCRIPT" create 1540 "$bad"
        [ "$status" -eq 1 ]
    done
    [ -d "$dir" ]
}

@test "phases with digits and hyphens are accepted" {
    run "$SCRIPT" path 1540 review-2
    [ "$status" -eq 0 ]
    case "$output" in
        */issue-1540-review-2) ;;
        *) echo "unexpected path: $output"; false ;;
    esac
}

@test "unknown subcommand and wrong argument counts exit 1" {
    run "$SCRIPT" remove 1540 spec
    [ "$status" -eq 1 ]
    run "$SCRIPT" path 1540
    [ "$status" -eq 1 ]
    run "$SCRIPT" path 1540 spec extra
    [ "$status" -eq 1 ]
    run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "help exits 0 and prints usage" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Usage:"
    run "$SCRIPT" -h
    [ "$status" -eq 0 ]
}

@test "error messages do not echo control characters or long input" {
    long="$(printf 'x%.0s' $(seq 1 200))"
    run "$SCRIPT" path 1540 $'a\033[31m'"$long"
    [ "$status" -eq 1 ]
    if printf '%s' "$output" | grep -q "$(printf '\033')"; then
        echo "control character leaked"
        false
    fi
    if printf '%s' "$output" | grep -q "$long"; then
        echo "long input leaked"
        false
    fi
}
