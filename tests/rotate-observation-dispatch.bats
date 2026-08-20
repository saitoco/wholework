#!/usr/bin/env bats

# Tests for rotate-observation-dispatch.sh
# Covers: (a) first run with no cursor file, (b) mid-value cursor rotation,
# (c) wrap-around when the cursor is at or beyond the max candidate,
# (d) fail-open continuation when the cursor file cannot be written,
# (e) empty stdin leaves the cursor file untouched.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/rotate-observation-dispatch.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
}

@test "first run (no cursor file): dispatches the ascending head, capped at threshold" {
    CURSOR_FILE="$BATS_TEST_TMPDIR/cursor"

    run bash -c "printf '478\n562\n589\n590\n724\n900\n' | \"$SCRIPT\" --threshold 5 --cursor-file \"$CURSOR_FILE\""
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '478\n562\n589\n590\n724')" ]
    [ "$(cat "$CURSOR_FILE")" = "724" ]
}

@test "cursor at a mid-value: candidates greater than cursor come first, then wrap, capped at threshold" {
    CURSOR_FILE="$BATS_TEST_TMPDIR/cursor"
    printf '724\n' > "$CURSOR_FILE"

    run bash -c "printf '478\n562\n589\n590\n724\n900\n1000\n1100\n' | \"$SCRIPT\" --threshold 5 --cursor-file \"$CURSOR_FILE\""
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '900\n1000\n1100\n478\n562')" ]
    [ "$(cat "$CURSOR_FILE")" = "562" ]
}

@test "cursor at or beyond the max candidate: wraps around to the original ascending order" {
    CURSOR_FILE="$BATS_TEST_TMPDIR/cursor"
    printf '9999\n' > "$CURSOR_FILE"

    run bash -c "printf '478\n562\n589\n590\n724\n' | \"$SCRIPT\" --threshold 5 --cursor-file \"$CURSOR_FILE\""
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '478\n562\n589\n590\n724')" ]
    [ "$(cat "$CURSOR_FILE")" = "724" ]
}

@test "cursor write failure: dispatch set still printed to stdout, exit code stays 0" {
    CURSOR_FILE="/no_such_root_dir_xyz/cursor"

    run bash -c "printf '478\n562\n' | \"$SCRIPT\" --threshold 5 --cursor-file \"$CURSOR_FILE\""
    [ "$status" -eq 0 ]
    echo "$output" | grep -qx "478"
    echo "$output" | grep -qx "562"
    [ ! -e "$CURSOR_FILE" ]
}

@test "empty stdin: no output, exit code 0, cursor file untouched" {
    CURSOR_FILE="$BATS_TEST_TMPDIR/cursor"
    printf '100\n' > "$CURSOR_FILE"

    run bash -c "printf '' | \"$SCRIPT\" --threshold 5 --cursor-file \"$CURSOR_FILE\""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(cat "$CURSOR_FILE")" = "100" ]
}

@test "missing --threshold is a hard error" {
    run bash -c "printf '1\n' | \"$SCRIPT\""
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "threshold"
}

@test "non-numeric --threshold is a hard error" {
    run bash -c "printf '1\n' | \"$SCRIPT\" --threshold abc"
    [ "$status" -eq 1 ]
}

@test "--threshold 0 is a hard error" {
    run bash -c "printf '1\n' | \"$SCRIPT\" --threshold 0"
    [ "$status" -eq 1 ]
}
