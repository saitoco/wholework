#!/usr/bin/env bats

# Tests for run-auto-sub.sh
# Mocks sibling scripts via WHOLEWORK_SCRIPT_DIR, and gh/git via PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-auto-sub.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    # Call logs for sibling script invocations
    export RUN_SPEC_LOG="$BATS_TEST_TMPDIR/run-spec.log"
    export RUN_CODE_LOG="$BATS_TEST_TMPDIR/run-code.log"
    export RUN_REVIEW_LOG="$BATS_TEST_TMPDIR/run-review.log"
    export RUN_MERGE_LOG="$BATS_TEST_TMPDIR/run-merge.log"
    export RUN_VERIFY_LOG="$BATS_TEST_TMPDIR/run-verify.log"

    # Mock phase-banner.sh (sourced by run-auto-sub.sh)
    cat > "$MOCK_DIR/phase-banner.sh" <<'MOCK'
print_start_banner() { echo "Starting /$3 for issue #$2"; }
print_end_banner() { echo "Finished /$3 for issue #$2"; }
MOCK

    # Mock get-issue-size.sh: default Size M
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "M"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Mock sibling run-*.sh scripts: log args and exit 0
    cat > "$MOCK_DIR/run-spec.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_SPEC_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-spec.sh"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_CODE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/run-review.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_REVIEW_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-review.sh"

    cat > "$MOCK_DIR/run-merge.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_MERGE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-merge.sh"

    cat > "$MOCK_DIR/run-verify.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_VERIFY_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-verify.sh"

    # Mock git: used by run_verify_with_retry on verify failure (pull --ff-only)
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ "\$1" == "pull" ]]; then
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    # Mock gh: default phase/ready label present, pr list returns PR 99
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json labels"* ]]; then
    echo "phase/ready"
    echo "triaged"
    exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
    if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
        echo "test issue title"
    elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
        echo "https://github.com/test/repo/issues/99"
    fi
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo '[{"headRefName":"worktree-code+issue-42","number":99}]'
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage: run-auto-sub.sh <sub-issue-number>"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Issue number must be numeric: abc"* ]]
}

@test "error: --base without branch argument" {
    run bash "$SCRIPT" 99 --base
    [ "$status" -eq 1 ]
    [[ "$output" == *"--base requires a branch name"* ]]
}

@test "error: unknown option is rejected" {
    run bash "$SCRIPT" 99 --unknown
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: Invalid option: --unknown"* ]]
}

@test "Size XS: run-code.sh --patch is called, run-review.sh and run-merge.sh are not called" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --patch" "$RUN_CODE_LOG"
    [ ! -f "$RUN_REVIEW_LOG" ]
    [ ! -f "$RUN_MERGE_LOG" ]
}

@test "Size S: run-code.sh --patch is called, run-review.sh and run-merge.sh are not called" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "S"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --patch" "$RUN_CODE_LOG"
    [ ! -f "$RUN_REVIEW_LOG" ]
    [ ! -f "$RUN_MERGE_LOG" ]
}

@test "Size M: run-code.sh --pr, run-review.sh --light, run-merge.sh, run-verify.sh are called" {
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --pr" "$RUN_CODE_LOG"
    grep -q -- "--light" "$RUN_REVIEW_LOG"
    [ -f "$RUN_MERGE_LOG" ]
    [ -f "$RUN_VERIFY_LOG" ]
}

@test "Size L: run-code.sh --pr, run-review.sh --full, run-merge.sh, run-verify.sh are called" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "L"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --pr" "$RUN_CODE_LOG"
    grep -q -- "--full" "$RUN_REVIEW_LOG"
    [ -f "$RUN_MERGE_LOG" ]
    [ -f "$RUN_VERIFY_LOG" ]
}

@test "Size XL: exits with error about sub-issue splitting" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XL"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 1 ]
    [[ "$output" == *"Further sub-issue splitting is required"* ]]
}

@test "phase/ready present: run-spec.sh is not called" {
    # Default gh mock has phase/ready
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ ! -f "$RUN_SPEC_LOG" ]
}

@test "phase/ready absent: run-spec.sh is called" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json labels"* ]]; then
    echo "triaged"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo '[{"headRefName":"worktree-code+issue-42","number":99}]'
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ -f "$RUN_SPEC_LOG" ]
}

@test "--base flag propagates to run-code.sh and run-verify.sh for Size M" {
    run bash "$SCRIPT" 42 --base release/v1
    [ "$status" -eq 0 ]
    grep -q -- "--base release/v1" "$RUN_CODE_LOG"
    grep -q -- "--base release/v1" "$RUN_VERIFY_LOG"
}

@test "PR extraction: exact-match SSoT filter matches worktree-code+issue-N (#311 regression, #325 fix)" {
    # Override gh mock: return JSON array with SSoT branch name so jq filter drives extraction
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
if [[ "\$1" == "issue" && "\$2" == "view" && "\$*" == *"--json labels"* ]]; then
    echo "phase/ready"
    echo "triaged"
    exit 0
fi
if [[ "\$1" == "issue" && "\$2" == "view" ]]; then
    exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "list" ]]; then
    echo '[{"headRefName":"worktree-code+issue-42","number":99}]'
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]

    # PR 99 was successfully propagated to review and merge
    # (proves jq filter matched worktree-code+issue-42 and extracted the number)
    grep -q "99" "$RUN_REVIEW_LOG"
    grep -q "99" "$RUN_MERGE_LOG"
}

@test "Size XS: lock dir is NOT created by run-auto-sub wrapper" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_CODE_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ ! -d "$BATS_TEST_TMPDIR/test-repo/.tmp/claude-auto-patch-lock" ]
}
