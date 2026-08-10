#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Tests for check-premise-expiry.sh
# Uses a disposable git repository per test (git init -q + git add, no commit —
# confirmed via manual verification that `git grep` works on the index without
# a commit, so `git config user.*` setup is unnecessary here).

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-premise-expiry.sh"

setup() {
    REPO="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO/sub"
    git init -q "$REPO"
    echo "token here" > "$REPO/sub/a.txt"
    echo "no match" > "$REPO/sub/b.txt"
    git -C "$REPO" add -A
    cd "$REPO"
}

write_body() {
    printf '%s\n' "$1" > "$REPO/body.md"
}

@test "grep_count negative case: absent term holds -> exit 0, empty stdout" {
    write_body '<!-- premise: grep_count "absent-term-zzz" "sub/" -eq 0 -->'
    run "$SCRIPT" body.md
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "grep_count positive case: present term expires -> exit 2, EXPIRED with count" {
    write_body '<!-- premise: grep_count "token" "sub/" -eq 0 -->'
    run "$SCRIPT" body.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"EXPIRED: grep_count \"token\" \"sub/\" -eq 0 (actual: 1)"* ]]
}

@test "file_exists holds when path exists -> exit 0" {
    write_body '<!-- premise: file_exists "sub/a.txt" -->'
    run "$SCRIPT" body.md
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "file_exists expires when path is missing -> exit 2, actual not found" {
    write_body '<!-- premise: file_exists "sub/nope.txt" -->'
    run "$SCRIPT" body.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"EXPIRED: file_exists \"sub/nope.txt\" (actual: not found)"* ]]
}

@test "file_not_exists holds when path is missing -> exit 0" {
    write_body '<!-- premise: file_not_exists "sub/nope.txt" -->'
    run "$SCRIPT" body.md
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "file_not_exists expires when path exists -> exit 2, actual exists" {
    write_body '<!-- premise: file_not_exists "sub/a.txt" -->'
    run "$SCRIPT" body.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"EXPIRED: file_not_exists \"sub/a.txt\" (actual: exists)"* ]]
}

@test "zero markers in body -> exit 0, empty stdout" {
    write_body '## Background

No premise markers here.'
    run "$SCRIPT" body.md
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "usage error: missing argument -> exit 1" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "usage error: file does not exist -> exit 1" {
    run "$SCRIPT" nonexistent-body.md
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "fail-open: nonexistent path in grep_count -> exit 0, UNEVALUABLE not EXPIRED" {
    write_body '<!-- premise: grep_count "token" "nosuchdir/" -eq 0 -->'
    run --separate-stderr "$SCRIPT" body.md
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"UNEVALUABLE: grep_count \"token\" \"nosuchdir/\" -eq 0 (reason: path not found: nosuchdir/)"* ]]
}

@test "fail-open: unsupported expression type -> exit 0, UNEVALUABLE" {
    write_body '<!-- premise: unsupported_type "foo" -->'
    run --separate-stderr "$SCRIPT" body.md
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"UNEVALUABLE: unsupported_type \"foo\" (reason: unsupported expression)"* ]]
}

@test "multiple markers, only one expires -> exit 2, stdout has only the expired line" {
    write_body '<!-- premise: grep_count "absent-term-zzz" "sub/" -eq 0 -->
<!-- premise: grep_count "token" "sub/" -eq 0 -->
<!-- premise: file_exists "sub/a.txt" -->'
    run "$SCRIPT" body.md
    [ "$status" -eq 2 ]
    [ "$(printf '%s\n' "$output" | grep -c '^EXPIRED:')" -eq 1 ]
    [[ "$output" == *"EXPIRED: grep_count \"token\" \"sub/\" -eq 0 (actual: 1)"* ]]
}

@test "fail-open: empty paths in grep_count -> exit 0, UNEVALUABLE as malformed, not a repo-wide scan" {
    write_body '<!-- premise: grep_count "token" "" -eq 0 -->'
    run --separate-stderr "$SCRIPT" body.md
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"UNEVALUABLE: grep_count \"token\" \"\" -eq 0 (reason: malformed expression)"* ]]
}

@test "marker prefix tolerates no space after <!-- -> still parsed" {
    write_body '<!--premise: file_exists "sub/nope.txt" -->'
    run "$SCRIPT" body.md
    [ "$status" -eq 2 ]
    [[ "$output" == *"EXPIRED: file_exists \"sub/nope.txt\" (actual: not found)"* ]]
}

@test "fail-open: marker-shaped comment with bare '>' does not fully match -> exit 0, UNEVALUABLE, not silently dropped" {
    write_body '<!-- premise: grep_count "a>b" "sub/" -eq 0 -->'
    run --separate-stderr "$SCRIPT" body.md
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"UNEVALUABLE: (unparsed premise marker) (reason: marker-shaped comment did not fully match"* ]]
}
