#!/usr/bin/env bats

# Tests for gh-pr-merge-status.sh
# Mock gh command via PATH

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/gh-pr-merge-status.sh"

setup() {
    cd "$PROJECT_ROOT"

    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
}

make_gh_mock() {
    local mergeable="$1"
    local state="$2"
    # Use printf to expand variables properly
    printf '#!/bin/bash\necho '"'"'{"mergeable": "%s", "mergeStateStatus": "%s"}'"'"'\n' "$mergeable" "$state" > "$MOCK_DIR/gh"
    chmod +x "$MOCK_DIR/gh"
}

@test "error: no arguments exits with code 1" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error" ]]
}

@test "error: non-numeric PR number exits with code 1" {
    run bash "$SCRIPT" "abc"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error" ]]
}

@test "success: --help exits with code 0 and shows usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage" ]]
}

@test "success: MERGEABLE + CLEAN returns mergeable true with reason clean" {
    make_gh_mock "MERGEABLE" "CLEAN"
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mergeable": true'* ]]
    [[ "$output" == *'"reason": "clean"'* ]]
    [[ "$output" == *'"ci_status": "success"'* ]]
    [[ "$output" == *'"review_status": "approved"'* ]]
}

@test "success: MERGEABLE + HAS_HOOKS returns mergeable true with reason has_hooks" {
    make_gh_mock "MERGEABLE" "HAS_HOOKS"
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mergeable": true'* ]]
    [[ "$output" == *'"reason": "has_hooks"'* ]]
    [[ "$output" == *'"ci_status": "success"'* ]]
    [[ "$output" == *'"review_status": "approved"'* ]]
}

@test "success: CONFLICTING returns mergeable false with reason conflicts" {
    make_gh_mock "CONFLICTING" "BLOCKED"
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mergeable": false'* ]]
    [[ "$output" == *'"reason": "conflicts"'* ]]
}

@test "success: BLOCKED state returns mergeable false with reason review_pending" {
    make_gh_mock "MERGEABLE" "BLOCKED"
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mergeable": false'* ]]
    [[ "$output" == *'"reason": "review_pending"'* ]]
    [[ "$output" == *'"review_status": "pending"'* ]]
}

@test "success: UNSTABLE state returns mergeable false with reason ci_failing" {
    make_gh_mock "MERGEABLE" "UNSTABLE"
    run bash "$SCRIPT" "123"
    [ "$status" -eq 0 ]
    [[ "$output" == *'"mergeable": false'* ]]
    [[ "$output" == *'"reason": "ci_failing"'* ]]
    [[ "$output" == *'"ci_status": "failing"'* ]]
}
