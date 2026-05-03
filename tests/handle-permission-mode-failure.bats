#!/usr/bin/env bats

# Tests for handle-permission-mode-failure.sh

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/handle-permission-mode-failure.sh"

@test "permission-mode auto: elapsed=5 exit=1 prints diagnostic to stderr" {
    bash "$SCRIPT" 1 5 auto 2>"$BATS_TEST_TMPDIR/stderr"
    [ -s "$BATS_TEST_TMPDIR/stderr" ]
}

@test "permission-mode auto: elapsed=60 exit=1 no diagnostic (long elapsed)" {
    bash "$SCRIPT" 1 60 auto 2>"$BATS_TEST_TMPDIR/stderr"
    [ ! -s "$BATS_TEST_TMPDIR/stderr" ]
}

@test "permission-mode bypass: elapsed=5 exit=1 no diagnostic" {
    bash "$SCRIPT" 1 5 bypass 2>"$BATS_TEST_TMPDIR/stderr"
    [ ! -s "$BATS_TEST_TMPDIR/stderr" ]
}

@test "permission-mode auto: elapsed=5 exit=0 no diagnostic (success case)" {
    bash "$SCRIPT" 0 5 auto 2>"$BATS_TEST_TMPDIR/stderr"
    [ ! -s "$BATS_TEST_TMPDIR/stderr" ]
}
