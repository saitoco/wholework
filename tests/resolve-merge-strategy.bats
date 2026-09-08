#!/usr/bin/env bats

# Tests for scripts/resolve-merge-strategy.sh (Issue #1457)

bats_require_minimum_version 1.5.0

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/resolve-merge-strategy.sh"

setup() {
    WORK_DIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "flag mode: merge-strategy merge resolves to --merge" {
    printf 'merge-strategy: merge\n' > .wholework.yml
    run bash "$SCRIPT" --flag
    [ "$status" -eq 0 ]
    [ "$output" = "--merge" ]
}

@test "flag mode: unset merge-strategy falls back to --squash" {
    run bash "$SCRIPT" --flag
    [ "$status" -eq 0 ]
    [ "$output" = "--squash" ]
}

@test "flag mode: merge-strategy rebase resolves to --rebase" {
    printf 'merge-strategy: rebase\n' > .wholework.yml
    run bash "$SCRIPT" --flag
    [ "$status" -eq 0 ]
    [ "$output" = "--rebase" ]
}

@test "invalid merge-strategy falls back to squash and warns on stderr" {
    printf 'merge-strategy: bogus\n' > .wholework.yml
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "squash" ]
    [[ "$stderr" == *"invalid merge-strategy"* ]] || false
    [[ "$stderr" == *"bogus"* ]] || false
}

@test "empty merge-strategy falls back to squash and warns on stderr" {
    # A quoted single-space value survives get-config-value.sh's own
    # empty-value default substitution (its `[ -z "$VALUE" ]` check only
    # matches zero-length strings), so it reaches this script as a
    # non-matching "blank" value instead of being silently replaced by the
    # "squash" default before we ever see it. This is the only way to
    # observe a genuinely blank raw value materialize the warning path.
    printf 'merge-strategy: " "\n' > .wholework.yml
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "squash" ]
    [[ "$stderr" == *"invalid merge-strategy"* ]] || false
}

@test "merge-strategy value with special characters falls back to squash" {
    printf 'merge-strategy: ">&2"; touch pwned #\n' > .wholework.yml
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "squash" ]
    [ ! -e pwned ]
}

@test "merge-strategy value with a trailing carriage return is accepted" {
    printf 'merge-strategy: merge\r\n' > .wholework.yml
    run bash "$SCRIPT" --flag
    [ "$status" -eq 0 ]
    [ "$output" = "--merge" ]
}

@test "get-config-value failure falls back to squash (fail-closed)" {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "squash" ]
}

@test "name mode: merge-strategy merge prints the bare strategy name" {
    printf 'merge-strategy: merge\n' > .wholework.yml
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "merge" ]
}

@test "help: --help outputs usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || false
}

@test "error: unknown argument" {
    run --separate-stderr bash "$SCRIPT" --bogus
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"unknown argument"* ]] || false
}
