#!/usr/bin/env bats

# Tests for scripts/detect-wrapper-anomaly.sh

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/detect-wrapper-anomaly.sh"

setup() {
    LOG_FILE="$BATS_TEST_TMPDIR/wrapper.log"
}

@test "error: missing required arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "error: log file not found" {
    run bash "$SCRIPT" --log "/nonexistent/path.log" --exit-code 1 --issue 99 --phase code
    [ "$status" -eq 1 ]
    [[ "$output" == *"log file not found"* ]]
}

@test "no match: empty output for unrecognized log content" {
    echo "Everything went fine, no issues detected." > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 99 --phase code
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "PR extraction failure: detects Could not retrieve PR number" {
    echo "Error: Could not retrieve PR number from branch worktree-code+issue-308" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 308 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" == *"pr-extraction-failure"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
    [[ "$output" == *"### Improvement Proposals"* ]]
    [[ "$output" == *"#311"* ]]
}

@test "patch lock timeout: detects Patch lock acquisition timeout" {
    echo "Patch lock acquisition timeout after 300s. Another process may hold the lock." > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 42 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" == *"patch-lock-timeout"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
    [[ "$output" == *"### Improvement Proposals"* ]]
    [[ "$output" == *"patch-lock-timeout"* ]]
}

@test "DCO missing: detects ERROR: missing sign-off" {
    echo "ERROR: missing sign-off" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 77 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" == *"dco-missing"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
    [[ "$output" == *"### Improvement Proposals"* ]]
    [[ "$output" == *"git commit -s"* ]]
}

@test "watchdog kill: detects watchdog: kill and state not reached" {
    echo "watchdog: kill and state not reached after 1800s" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 143 --issue 308 --phase review
    [ "$status" -eq 0 ]
    [[ "$output" == *"watchdog-kill"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
    [[ "$output" == *"### Improvement Proposals"* ]]
    [[ "$output" == *"#308"* ]]
}

@test "output includes phase and exit code in anomaly description" {
    echo "Could not retrieve PR number" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 2 --issue 99 --phase merge
    [ "$status" -eq 0 ]
    [[ "$output" == *"merge"* ]]
    [[ "$output" == *"exit code 2"* ]]
}

@test "silent no-op: detects exit_code=0 with success phrase and no recent commit" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/git" <<'MOCK'
#!/bin/bash
# mock git: returns empty output for all subcommands
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    echo "実装が完了しました。commit and push も完了しています。" > "$LOG_FILE"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" --log "$LOG_FILE" --exit-code 0 --issue 365 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" == *"silent-no-op"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
}

@test "silent no-op: detects exit_code=0 with English success phrase 'successfully committed'" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/git" <<'MOCK'
#!/bin/bash
# mock git: returns empty output for all subcommands
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    echo "Successfully committed all changes." > "$LOG_FILE"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" --log "$LOG_FILE" --exit-code 0 --issue 403 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" == *"silent-no-op"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
}

@test "silent no-op: no detection when exit_code=0 but no success phrase" {
    echo "Execution finished normally." > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 0 --issue 365 --phase code
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "dirty working tree: detects VERIFY_FAILED with uncommitted changes" {
    printf "VERIFY_FAILED\nCannot run verify because there are uncommitted changes in the working tree.\n" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 393 --phase verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"dirty-working-tree"* ]]
    [[ "$output" == *"#393"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
    [[ "$output" == *"### Improvement Proposals"* ]]
}

@test "dirty working tree: no detection when only VERIFY_FAILED present" {
    echo "VERIFY_FAILED" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 393 --phase verify
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "dirty working tree: no detection when only uncommitted present" {
    echo "Cannot run verify because there are uncommitted changes." > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 393 --phase verify
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
