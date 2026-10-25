#!/usr/bin/env bats

# Tests for scripts/wait-subagent-results.sh (Issue #1551).
# The script waits on the clock ($SECONDS), so `sleep` is deliberately not mocked: a mocked
# sleep would make the clock-bounded loop spin. Slow cases use --interval 1 and a 2-3 second
# timeout.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/wait-subagent-results.sh"

# last_stderr_line: print the final line of the captured stderr.
last_stderr_line() {
    printf '%s\n' "$stderr" | tail -n 1
}

# summary_seconds: print N of "... ready after Ns (limit Ls)" from the last stderr line.
summary_seconds() {
    last_stderr_line | sed -E 's/.* after ([0-9]+)s .*/\1/'
}

make_ready() {
    local f
    for f in "$@"; do
        printf 'result\n' > "$f"
    done
}

@test "usage: all files ready from the start exits 0 with ready lines in argument order" {
    make_ready "$BATS_TEST_TMPDIR/a.md" "$BATS_TEST_TMPDIR/b.md" "$BATS_TEST_TMPDIR/c.md"
    run --separate-stderr bash "$SCRIPT" 5 "$BATS_TEST_TMPDIR/c.md" "$BATS_TEST_TMPDIR/a.md" "$BATS_TEST_TMPDIR/b.md"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "ready $BATS_TEST_TMPDIR/c.md" ]
    [ "${lines[1]}" = "ready $BATS_TEST_TMPDIR/a.md" ]
    [ "${lines[2]}" = "ready $BATS_TEST_TMPDIR/b.md" ]
    [ "$(last_stderr_line)" = "wait-subagent-results: 3/3 ready after 0s (limit 5s)" ]
}

@test "timeout: partly missing files exit 2 after the limit with mixed lines in argument order" {
    make_ready "$BATS_TEST_TMPDIR/a.md" "$BATS_TEST_TMPDIR/c.md"
    run --separate-stderr bash "$SCRIPT" --interval 1 2 "$BATS_TEST_TMPDIR/a.md" "$BATS_TEST_TMPDIR/b.md" "$BATS_TEST_TMPDIR/c.md"
    [ "$status" -eq 2 ]
    [ "${lines[0]}" = "ready $BATS_TEST_TMPDIR/a.md" ]
    [ "${lines[1]}" = "missing $BATS_TEST_TMPDIR/b.md" ]
    [ "${lines[2]}" = "ready $BATS_TEST_TMPDIR/c.md" ]
    n="$(summary_seconds)"
    [ "$n" -ge 2 ]
    [ "$n" -lt 6 ]
    [[ "$(last_stderr_line)" == "wait-subagent-results: 2/3 ready after "* ]] || false
}

@test "appearing file: a file created during the wait ends it early with exit 0" {
    ( sleep 1; printf 'result\n' > "$BATS_TEST_TMPDIR/late.md" ) &
    bg=$!
    run --separate-stderr bash "$SCRIPT" --interval 1 8 "$BATS_TEST_TMPDIR/late.md"
    wait "$bg"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "ready $BATS_TEST_TMPDIR/late.md" ]
    n="$(summary_seconds)"
    [ "$n" -lt 8 ]
}

@test "empty file counts as missing" {
    : > "$BATS_TEST_TMPDIR/empty.md"
    run --separate-stderr bash "$SCRIPT" 0 "$BATS_TEST_TMPDIR/empty.md"
    [ "$status" -eq 2 ]
    [ "${lines[0]}" = "missing $BATS_TEST_TMPDIR/empty.md" ]
}

@test "directory path counts as missing" {
    mkdir -p "$BATS_TEST_TMPDIR/adir"
    run --separate-stderr bash "$SCRIPT" 0 "$BATS_TEST_TMPDIR/adir"
    [ "$status" -eq 2 ]
    [ "${lines[0]}" = "missing $BATS_TEST_TMPDIR/adir" ]
}

@test "timeout 0 checks once without sleeping" {
    start="$SECONDS"
    run --separate-stderr bash "$SCRIPT" 0 "$BATS_TEST_TMPDIR/absent.md"
    [ "$status" -eq 2 ]
    [ $((SECONDS - start)) -lt 2 ]
    [ "$(last_stderr_line)" = "wait-subagent-results: 0/1 ready after 0s (limit 0s)" ]
}

@test "no arguments exits 1 with usage on stderr and empty stdout" {
    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [[ "$stderr" == *"Usage: wait-subagent-results.sh"* ]] || false
}

@test "timeout without files exits 1" {
    run --separate-stderr bash "$SCRIPT" 5
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [[ "$stderr" == *"Usage:"* ]] || false
}

@test "invalid timeout values exit 1" {
    local bad
    for bad in "abc" "-3" "1.5" ""; do
        run --separate-stderr bash "$SCRIPT" "$bad" "$BATS_TEST_TMPDIR/x.md"
        [ "$status" -eq 1 ]
        [ -z "$output" ]
    done
}

@test "invalid --interval and unknown options exit 1" {
    run --separate-stderr bash "$SCRIPT" --interval
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    run --separate-stderr bash "$SCRIPT" --interval 0 5 "$BATS_TEST_TMPDIR/x.md"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    run --separate-stderr bash "$SCRIPT" --interval abc 5 "$BATS_TEST_TMPDIR/x.md"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    run --separate-stderr bash "$SCRIPT" --bogus 5 "$BATS_TEST_TMPDIR/x.md"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "timeout above 540 is clamped; a leading zero is read as decimal" {
    make_ready "$BATS_TEST_TMPDIR/a.md"
    run --separate-stderr bash "$SCRIPT" 99999999999999999999 "$BATS_TEST_TMPDIR/a.md"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"clamped to 540"* ]] || false
    [ "$(last_stderr_line)" = "wait-subagent-results: 1/1 ready after 0s (limit 540s)" ]
    run --separate-stderr bash "$SCRIPT" 541 "$BATS_TEST_TMPDIR/a.md"
    [[ "$stderr" == *"timeout 541 clamped to 540"* ]] || false
    run --separate-stderr bash "$SCRIPT" 010 "$BATS_TEST_TMPDIR/a.md"
    [ "$status" -eq 0 ]
    [ "$(last_stderr_line)" = "wait-subagent-results: 1/1 ready after 0s (limit 10s)" ]
    [[ "$stderr" != *"clamped"* ]] || false
}

@test "paths with spaces, angle brackets, quotes, and multibyte characters are printed as given" {
    local p1="$BATS_TEST_TMPDIR/with space.md"
    local p2="$BATS_TEST_TMPDIR/a>b.md"
    local p3="$BATS_TEST_TMPDIR/q\"uote.md"
    local p4="$BATS_TEST_TMPDIR/日本語.md"
    make_ready "$p1" "$p3" "$p4"
    run --separate-stderr bash "$SCRIPT" 0 "$p1" "$p2" "$p3" "$p4"
    [ "$status" -eq 2 ]
    [ "${lines[0]}" = "ready $p1" ]
    [ "${lines[1]}" = "missing $p2" ]
    [ "${lines[2]}" = "ready $p3" ]
    [ "${lines[3]}" = "ready $p4" ]
}

@test "a path containing a newline exits 1" {
    run --separate-stderr bash "$SCRIPT" 0 "$BATS_TEST_TMPDIR/a
b.md"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
    [[ "$stderr" == *"newline"* ]] || false
}

@test "the check interval never exceeds the remaining time" {
    start="$SECONDS"
    run --separate-stderr bash "$SCRIPT" --interval 5 1 "$BATS_TEST_TMPDIR/absent.md"
    [ "$status" -eq 2 ]
    [ $((SECONDS - start)) -lt 3 ]
}

@test "duplicate paths are printed once per argument" {
    make_ready "$BATS_TEST_TMPDIR/a.md"
    run --separate-stderr bash "$SCRIPT" 0 "$BATS_TEST_TMPDIR/a.md" "$BATS_TEST_TMPDIR/a.md"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "ready $BATS_TEST_TMPDIR/a.md" ]
    [ "${lines[1]}" = "ready $BATS_TEST_TMPDIR/a.md" ]
    [ "$(last_stderr_line)" = "wait-subagent-results: 2/2 ready after 0s (limit 0s)" ]
}
