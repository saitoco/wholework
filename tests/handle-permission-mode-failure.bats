#!/usr/bin/env bats

# Tests for handle-permission-mode-failure.sh

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/handle-permission-mode-failure.sh"

@test "elapsed=5 exit=1 prints diagnostic to stderr" {
    bash "$SCRIPT" 1 5 2>"$BATS_TEST_TMPDIR/stderr"
    [ -s "$BATS_TEST_TMPDIR/stderr" ]
}

@test "elapsed=60 exit=1 no diagnostic (long elapsed)" {
    bash "$SCRIPT" 1 60 2>"$BATS_TEST_TMPDIR/stderr"
    [ ! -s "$BATS_TEST_TMPDIR/stderr" ]
}

@test "elapsed=5 exit=0 no diagnostic (success case)" {
    bash "$SCRIPT" 0 5 2>"$BATS_TEST_TMPDIR/stderr"
    [ ! -s "$BATS_TEST_TMPDIR/stderr" ]
}
