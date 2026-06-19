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

@test "reconciler header mismatch: detects matches_expected false with Review Summary" {
    printf '"matches_expected":false\nreview: Review Summary not found in PR comment\n' > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 143 --issue 386 --phase review
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciler-header-mismatch"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
    [[ "$output" == *"### Improvement Proposals"* ]]
    [[ "$output" == *"#394"* ]]
}

@test "reconciler header mismatch: no detection when only matches_expected false present" {
    printf '"matches_expected":false\nno relevant context here\n' > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 143 --issue 386 --phase review
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "reconciler header mismatch: no detection when only Review Summary present" {
    echo "review: Review Summary found successfully" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 143 --issue 386 --phase review
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "code completed no PR: detects matches_expected false with phase code-pr" {
    printf '"matches_expected":false\n"phase":"code-pr"\n' > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 143 --issue 385 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" == *"code-completed-no-pr"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
    [[ "$output" == *"### Improvement Proposals"* ]]
    [[ "$output" == *"#415"* ]]
}

@test "code completed no PR: no detection when only matches_expected false present" {
    printf '"matches_expected":false\nno relevant context here\n' > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 143 --issue 385 --phase code
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "code completed no PR: no detection when only phase code-pr present" {
    printf '"phase":"code-pr"\nsome other content\n' > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 143 --issue 385 --phase code
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "API connection error: detects APIConnectionError pattern" {
    echo "anthropic.APIConnectionError: Connection error." > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 500 --phase spec
    [ "$status" -eq 0 ]
    [[ "$output" == *"mid-run-api-error"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
    [[ "$output" == *"### Improvement Proposals"* ]]
}

@test "API connection error: detects Request timed out pattern" {
    echo "Error: Request timed out after 60 seconds" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 500 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" == *"mid-run-api-error"* ]]
}

@test "API connection error: no detection when log has no API error pattern" {
    echo "Some unrelated error occurred." > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 500 --phase spec
    [ "$status" -eq 0 ]
    [[ "$output" != *"mid-run-api-error"* ]]
}

@test "silent no-op: no false positive for code-patch when commit found on origin/main" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/git" <<'MOCK'
#!/bin/bash
case "$*" in
  "log origin/main --oneline -20")
    echo "abc1234 chore: implement fix closes #523"
    ;;
esac
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    echo "実装が完了しました。commit and push も完了しています。" > "$LOG_FILE"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" --log "$LOG_FILE" --exit-code 0 --issue 523 --phase code-patch
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "silent no-op: suppressed when reconcile confirms matches_expected true and commits_found true" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/git" <<'MOCK'
#!/bin/bash
# mock git: returns empty output for all subcommands
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    printf 'reconcile-phase-state result: {"phase":"code-patch","matches_expected":true,"actual":{"commits_found":true}}\ncommit and push complete.\n' > "$LOG_FILE"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" --log "$LOG_FILE" --exit-code 0 --issue 576 --phase code
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "silent no-op: code-patch triggers detection when commit absent on both local and origin/main" {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/git" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    echo "実装が完了しました。commit and push も完了しています。" > "$LOG_FILE"
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash "$SCRIPT" --log "$LOG_FILE" --exit-code 0 --issue 526 --phase code-patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"silent-no-op"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
}

@test "json mode silent hang: detects exit 143 with still waiting (json mode) in log" {
    echo "watchdog: still waiting (json mode), silent for 1800s (pid=99)" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 143 --issue 684 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" == *"json-mode-silent-hang"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
    [[ "$output" == *"### Improvement Proposals"* ]]
}

@test "json mode silent hang: no detection when exit code is not 143" {
    echo "watchdog: still waiting (json mode), silent for 1800s (pid=99)" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 684 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" != *"json-mode-silent-hang"* ]]
}

@test "json mode silent hang: no detection when log does not contain json mode message" {
    echo "watchdog: still waiting, silent for 1800s (pid=99)" > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 143 --issue 684 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" != *"json-mode-silent-hang"* ]]
}

@test "review-completion-false-negative: detects matches_expected false with phase review" {
    printf '"matches_expected":false\n"phase":"review"\n' > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 547 --phase review
    [ "$status" -eq 0 ]
    [[ "$output" == *"review-completion-false-negative"* ]]
    [[ "$output" == *"### Orchestration Anomalies"* ]]
}

@test "review-completion-false-negative: reconciler-header-mismatch takes priority when Review Summary present" {
    printf '"matches_expected":false\n"phase":"review"\nreconcile-phase-state result: Review Summary found\n' > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 547 --phase review
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciler-header-mismatch"* ]]
    [[ "$output" != *"review-completion-false-negative"* ]]
}

@test "review-completion-false-negative: no detection for unrelated log" {
    echo "Some unrelated error occurred in the code phase." > "$LOG_FILE"
    run bash "$SCRIPT" --log "$LOG_FILE" --exit-code 1 --issue 547 --phase code
    [ "$status" -eq 0 ]
    [[ "$output" != *"review-completion-false-negative"* ]]
}
