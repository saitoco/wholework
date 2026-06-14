#!/usr/bin/env bats

# Tests for auto-checkpoint.sh BATCH_ID namespacing (Issue #627)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/auto-checkpoint.sh"

setup() {
    export BATS_TMPDIR="${BATS_TEST_TMPDIR}"
    cd "$BATS_TEST_TMPDIR"
}

teardown() {
    cd /
    rm -rf "$BATS_TEST_TMPDIR/.tmp"
}

@test "parallel write non-collision: two BATCH_IDs maintain independent state files" {
    run bash "$SCRIPT" write_batch "batch-a" "101 102" "" ""
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" write_batch "batch-b" "201 202 203" "" ""
    [ "$status" -eq 0 ]

    [ -f ".tmp/auto-batch-state-batch-a.json" ]
    [ -f ".tmp/auto-batch-state-batch-b.json" ]

    remaining_a=$(jq '.remaining | length' .tmp/auto-batch-state-batch-a.json)
    [ "$remaining_a" = "2" ]

    remaining_b=$(jq '.remaining | length' .tmp/auto-batch-state-batch-b.json)
    [ "$remaining_b" = "3" ]

    run bash "$SCRIPT" update_batch "batch-a" 101 complete
    [ "$status" -eq 0 ]

    remaining_a_after=$(jq '.remaining | length' .tmp/auto-batch-state-batch-a.json)
    [ "$remaining_a_after" = "1" ]

    remaining_b_unchanged=$(jq '.remaining | length' .tmp/auto-batch-state-batch-b.json)
    [ "$remaining_b_unchanged" = "3" ]

    active_ids=$(bash "$SCRIPT" list_active_batches)
    [[ "$active_ids" == *"batch-a"* ]]
    [[ "$active_ids" == *"batch-b"* ]]
}

@test "resume restoration: read_batch returns correct remaining after updates" {
    run bash "$SCRIPT" write_batch "resume-test" "301 302 303" "" ""
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" update_batch "resume-test" 301 complete
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" update_batch "resume-test" 302 fail
    [ "$status" -eq 0 ]

    run bash "$SCRIPT" read_batch "resume-test"
    [ "$status" -eq 0 ]
    [ "$output" = "303" ]

    completed=$(jq '.completed[0]' .tmp/auto-batch-state-resume-test.json)
    [ "$completed" = "301" ]

    failed=$(jq '.failed[0]' .tmp/auto-batch-state-resume-test.json)
    [ "$failed" = "302" ]
}

@test "backward compat: omitted BATCH_ID uses existing .tmp/auto-batch-state.json path" {
    run bash "$SCRIPT" write_batch "500 501 502" "" ""
    [ "$status" -eq 0 ]
    [ -f ".tmp/auto-batch-state.json" ]
    [ ! -f ".tmp/auto-batch-state-default.json" ]

    run bash "$SCRIPT" read_batch
    [ "$status" -eq 0 ]
    [[ "$output" == *"500"* ]]
    [[ "$output" == *"501"* ]]
    [[ "$output" == *"502"* ]]

    run bash "$SCRIPT" update_batch 500 complete
    [ "$status" -eq 0 ]

    completed=$(jq '.completed[0]' .tmp/auto-batch-state.json)
    [ "$completed" = "500" ]

    run bash "$SCRIPT" delete_batch
    [ "$status" -eq 0 ]
    [ ! -f ".tmp/auto-batch-state.json" ]

    active_ids=$(bash "$SCRIPT" list_active_batches)
    [[ "$active_ids" != *"default"* ]]
}
