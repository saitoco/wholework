#!/usr/bin/env bats

# Tests for should-stop-at-phase.sh

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/should-stop-at-phase.sh"

setup() {
    WORK_DIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR"
}

teardown() {
    rm -rf "$WORK_DIR"
}

@test "should-stop-at-phase: stop-at=code, completed=code -> stop" {
    run bash "$SCRIPT" code code
    [ "$status" -eq 0 ]
}

@test "should-stop-at-phase: stop-at=spec, completed=code -> stop" {
    run bash "$SCRIPT" code spec
    [ "$status" -eq 0 ]
}

@test "should-stop-at-phase: stop-at=review, completed=code -> continue" {
    run bash "$SCRIPT" code review
    [ "$status" -eq 1 ]
}

@test "should-stop-at-phase: stop-at=review, completed=review -> stop" {
    run bash "$SCRIPT" review review
    [ "$status" -eq 0 ]
}

@test "should-stop-at-phase: stop-at=merge, completed=review -> continue" {
    run bash "$SCRIPT" review merge
    [ "$status" -eq 1 ]
}

@test "should-stop-at-phase: stop-at=verify, completed=merge -> continue" {
    run bash "$SCRIPT" merge verify
    [ "$status" -eq 1 ]
}

@test "should-stop-at-phase: unknown stop-at value falls back to verify" {
    run bash "$SCRIPT" review bogus
    [ "$status" -eq 1 ]
}

@test "should-stop-at-phase: empty stop-at value falls back to verify" {
    run bash "$SCRIPT" review ""
    [ "$status" -eq 1 ]
}

@test "should-stop-at-phase: stop-at read from .wholework.yml when omitted" {
    export WHOLEWORK_SCRIPT_DIR="$PROJECT_ROOT/scripts"
    export WHOLEWORK_CONFIG_PATH="$BATS_TEST_TMPDIR/.wholework.yml"
    printf 'auto-stop-at: review\n' > "$WHOLEWORK_CONFIG_PATH"
    run bash "$SCRIPT" review
    [ "$status" -eq 0 ]
    unset WHOLEWORK_SCRIPT_DIR
    unset WHOLEWORK_CONFIG_PATH
}

@test "should-stop-at-phase: missing config falls back to verify" {
    export WHOLEWORK_SCRIPT_DIR="$PROJECT_ROOT/scripts"
    export WHOLEWORK_CONFIG_PATH="/dev/null"
    run bash "$SCRIPT" review
    [ "$status" -eq 1 ]
    unset WHOLEWORK_SCRIPT_DIR
    unset WHOLEWORK_CONFIG_PATH
}

@test "should-stop-at-phase: unknown completed phase exits 2" {
    run bash "$SCRIPT" bogus verify
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown completed phase"* ]] || false
}

@test "should-stop-at-phase: no arguments exits 2" {
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
}
