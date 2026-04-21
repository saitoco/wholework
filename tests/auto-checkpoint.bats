#!/usr/bin/env bats

# Tests for scripts/auto-checkpoint.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/auto-checkpoint.sh"

setup() {
    export BATS_TMPDIR="${BATS_TEST_TMPDIR}"
    cd "$BATS_TEST_TMPDIR"
}

teardown() {
    cd /
    rm -rf "$BATS_TEST_TMPDIR/.tmp"
}

@test "single checkpoint write and read: schema integrity" {
    run bash "$SCRIPT" write_single 42 3
    [ "$status" -eq 0 ]

    [ -f ".tmp/auto-state-42.json" ]

    schema_version=$(jq -r '.schema_version' .tmp/auto-state-42.json)
    [ "$schema_version" = "v1" ]

    issue_number=$(jq -r '.issue_number' .tmp/auto-state-42.json)
    [ "$issue_number" = "42" ]

    count=$(jq -r '.verify_iteration_count' .tmp/auto-state-42.json)
    [ "$count" = "3" ]

    last_update=$(jq -r '.last_update' .tmp/auto-state-42.json)
    [[ "$last_update" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]

    run bash "$SCRIPT" read_single 42
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "stale detection: mismatched issue_number is discarded" {
    bash "$SCRIPT" write_single 99 5

    run bash "$SCRIPT" read_single 100
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "batch checkpoint: remaining/completed/failed transitions" {
    run bash "$SCRIPT" write_batch "101 102 103 104 105" "" ""
    [ "$status" -eq 0 ]
    [ -f ".tmp/auto-batch-state.json" ]

    schema_version=$(jq -r '.schema_version' .tmp/auto-batch-state.json)
    [ "$schema_version" = "v1" ]

    mode=$(jq -r '.mode' .tmp/auto-batch-state.json)
    [ "$mode" = "list" ]

    remaining_count=$(jq '.remaining | length' .tmp/auto-batch-state.json)
    [ "$remaining_count" = "5" ]

    run bash "$SCRIPT" update_batch 101 complete
    [ "$status" -eq 0 ]
    remaining_after=$(jq '.remaining | length' .tmp/auto-batch-state.json)
    [ "$remaining_after" = "4" ]
    completed_count=$(jq '.completed | length' .tmp/auto-batch-state.json)
    [ "$completed_count" = "1" ]
    completed_first=$(jq -r '.completed[0]' .tmp/auto-batch-state.json)
    [ "$completed_first" = "101" ]

    run bash "$SCRIPT" update_batch 102 fail
    [ "$status" -eq 0 ]
    failed_count=$(jq '.failed | length' .tmp/auto-batch-state.json)
    [ "$failed_count" = "1" ]
    failed_first=$(jq -r '.failed[0]' .tmp/auto-batch-state.json)
    [ "$failed_first" = "102" ]

    run bash "$SCRIPT" read_batch
    [ "$status" -eq 0 ]
    [[ "$output" == *"103"* ]]
    [[ "$output" == *"104"* ]]
    [[ "$output" == *"105"* ]]
    [[ "$output" != *"101"* ]]
    [[ "$output" != *"102"* ]]
}

@test "atomic write: partial write leaves original file intact" {
    bash "$SCRIPT" write_single 77 1

    original_count=$(jq -r '.verify_iteration_count' .tmp/auto-state-77.json)
    [ "$original_count" = "1" ]

    echo '{"broken":' > .tmp/auto-state-77.json.tmp

    run bash "$SCRIPT" write_single 77 2
    [ "$status" -eq 0 ]

    [ -f ".tmp/auto-state-77.json" ]
    [ ! -f ".tmp/auto-state-77.json.tmp" ]

    updated_count=$(jq -r '.verify_iteration_count' .tmp/auto-state-77.json)
    [ "$updated_count" = "2" ]
}

@test "cleanup: delete_single removes checkpoint file" {
    bash "$SCRIPT" write_single 55 4
    [ -f ".tmp/auto-state-55.json" ]

    run bash "$SCRIPT" delete_single 55
    [ "$status" -eq 0 ]
    [ ! -f ".tmp/auto-state-55.json" ]

    run bash "$SCRIPT" delete_single 55
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" read_single 55
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}
