#!/usr/bin/env bats

# Tests for get-blocked-by.sh
# Mock gh-graphql.sh via MOCK_DIR pattern (WHOLEWORK_SCRIPT_DIR), same pattern as set-blocked-by.bats

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/get-blocked-by.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
    export WHOLEWORK_CONFIG_PATH=/dev/null

    cat > "$MOCK_DIR/gh-graphql.sh" << 'MOCK_EOF'
#!/bin/bash
ARGS="$*"

get_num() {
    local prev=""
    for a in "$@"; do
        if [[ "$prev" == "-F" && "$a" == num=* ]]; then
            echo "${a#num=}"
            return
        fi
        prev="$a"
    done
}

if [[ "$ARGS" == "--query get-blocked-by "* ]]; then
    NUM=$(get_num "$@")
    case "$NUM" in
        100) : ;; # no blockers -> empty output
        200) printf '10\tCLOSED\n20\tCLOSED\n' ;;
        300) printf '10\tCLOSED\n30\tOPEN\n' ;;
        *) : ;;
    esac
    exit 0
fi

if [[ "$ARGS" == "--query get-open-issues-blocked-by "* ]]; then
    if [[ "$ARGS" == *"-F cursor="* ]]; then
        cat <<'JSON'
{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"number":50,"blockedBy":{"nodes":[{"number":51,"state":"OPEN"}]}}]}}}}
JSON
    else
        cat <<'JSON'
{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":true,"endCursor":"CURSOR1"},"nodes":[{"number":40,"blockedBy":{"nodes":[{"number":41,"state":"CLOSED"}]}},{"number":42,"blockedBy":{"nodes":[]}}]}}}}
JSON
    fi
    exit 0
fi

exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh-graphql.sh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "--help shows usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
    [[ "$output" == *"issue-number must be a positive integer"* ]]
}

@test "error: unknown option" {
    run bash "$SCRIPT" --bogus
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown argument"* ]]
}

@test "error: --limit non-numeric" {
    run bash "$SCRIPT" --all --limit abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"--limit must be a positive integer"* ]]
}

@test "single issue: no blockers -> exit 0, empty output" {
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "single issue: all blockers CLOSED -> exit 0, tab-separated output" {
    run bash "$SCRIPT" 200
    [ "$status" -eq 0 ]
    [[ "$output" == *$'10\tCLOSED'* ]]
    [[ "$output" == *$'20\tCLOSED'* ]]
}

@test "single issue: OPEN blocker present -> exit 2, all blockers listed" {
    run bash "$SCRIPT" 300
    [ "$status" -eq 2 ]
    [[ "$output" == *$'10\tCLOSED'* ]]
    [[ "$output" == *$'30\tOPEN'* ]]
}

@test "--all: TSV 3-column output" {
    run bash "$SCRIPT" --all
    [ "$status" -eq 0 ]
    [[ "$output" == *$'40\t41\tCLOSED'* ]]
}

@test "--all: hasNextPage true reads second page" {
    run bash "$SCRIPT" --all
    [ "$status" -eq 0 ]
    [[ "$output" == *$'50\t51\tOPEN'* ]]
}

@test "--all: OPEN blocker present still exits 0" {
    run bash "$SCRIPT" --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"OPEN"* ]]
}
