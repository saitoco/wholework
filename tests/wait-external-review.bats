#!/usr/bin/env bats

# Tests for wait-external-review.sh
# Mocks external commands (gh, sleep) by placing them at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/wait-external-review.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Default: sleep is always a no-op
    cat > "$MOCK_DIR/sleep" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/sleep"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# Helper: create gh mock that returns a reviewer's review
create_gh_mock_with_review() {
    local reviewer_short="${1:-copilot-pull-request-reviewer}"
    local reviewer_full="${2:-copilot-pull-request-reviewer[bot]}"
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
if [[ "\$1" == "pr" && "\$2" == "view" && "\$*" == *"--json latestReviews"* ]]; then
    echo '{"author":{"login":"${reviewer_short}"},"state":"COMMENTED"}'
    exit 0
fi
if [[ "\$1" == "api" && "\$*" == *"reviews"* && "\$*" != *"comments"* ]]; then
    echo '{"id":111,"body":"Looks good","user":{"login":"${reviewer_full}"}}'
    exit 0
fi
if [[ "\$1" == "api" && "\$*" == *"comments"* ]]; then
    echo '[]'
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

# Helper: create gh mock that returns no review (for timeout tests)
create_gh_mock_no_review() {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "view" && "$*" == *"--json latestReviews"* ]]; then
    echo ""
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "view" && "$*" == *"--json number"* ]]; then
    echo "42"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

# === Copilot (default reviewer) tests ===

@test "copilot: review found with explicit PR number" {
    create_gh_mock_with_review
    run bash "$SCRIPT" 88
    [ "$status" -eq 0 ]
    [[ "$output" == *"Copilot Review Complete"* ]]
}

@test "copilot: review found with explicit reviewer type" {
    create_gh_mock_with_review
    run bash "$SCRIPT" 88 copilot
    [ "$status" -eq 0 ]
    [[ "$output" == *"Copilot Review Complete"* ]]
}

@test "copilot: PR number auto-detected from current branch" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "view" && "$*" == *"--json number"* ]]; then
    echo "42"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "view" && "$*" == *"--json latestReviews"* ]]; then
    echo '{"author":{"login":"copilot-pull-request-reviewer"},"state":"COMMENTED"}'
    exit 0
fi
if [[ "$1" == "api" && "$*" == *"reviews"* && "$*" != *"comments"* ]]; then
    echo '{"id":111,"body":"LGTM"}'
    exit 0
fi
if [[ "$1" == "api" && "$*" == *"comments"* ]]; then
    echo '[]'
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Copilot Review Complete"* ]]
}

# === Claude Code Review tests ===

@test "claude-code-review: review found with explicit PR number" {
    create_gh_mock_with_review "claude-code-review" "claude-code-review[bot]"
    run bash "$SCRIPT" 88 claude-code-review
    [ "$status" -eq 0 ]
    [[ "$output" == *"Claude Code Review Complete"* ]]
}

@test "claude-code-review: timeout when no review arrives" {
    create_gh_mock_no_review
    export EXTERNAL_REVIEW_TIMEOUT=1
    export EXTERNAL_REVIEW_INTERVAL=1

    run bash "$SCRIPT" 88 claude-code-review
    [ "$status" -eq 1 ]
    [[ "$output" == *"Claude Code"* ]]
    [[ "$output" == *"Timeout"* ]]
}

# === CodeRabbit tests ===

@test "coderabbit: review found with explicit PR number" {
    create_gh_mock_with_review "coderabbitai" "coderabbitai[bot]"
    run bash "$SCRIPT" 88 coderabbit
    [ "$status" -eq 0 ]
    [[ "$output" == *"CodeRabbit Review Complete"* ]]
}

@test "coderabbit: timeout when no review arrives" {
    create_gh_mock_no_review
    export EXTERNAL_REVIEW_TIMEOUT=1
    export EXTERNAL_REVIEW_INTERVAL=1

    run bash "$SCRIPT" 88 coderabbit
    [ "$status" -eq 1 ]
    [[ "$output" == *"CodeRabbit"* ]]
    [[ "$output" == *"Timeout"* ]]
}

# === Error handling tests ===

@test "error: invalid PR number (non-numeric)" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"PR number must be a positive integer"* ]]
}

@test "error: PR number cannot be determined" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo ""
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not determine PR number"* ]]
}

@test "error: timeout when no Copilot review arrives" {
    create_gh_mock_no_review
    export EXTERNAL_REVIEW_TIMEOUT=1
    export EXTERNAL_REVIEW_INTERVAL=1

    run bash "$SCRIPT" 88
    [ "$status" -eq 1 ]
    [[ "$output" == *"Timeout"* ]]
}

@test "error: unknown reviewer type" {
    run bash "$SCRIPT" 88 unknown-reviewer
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown reviewer type"* ]]
}

# === Hook behavior tests ===

@test "hook: exits early when CLAUDE_PROJECT_DIR set and command is not gh pr create" {
    # read -t 0.1 requires bash 4+ (macOS ships bash 3.2)
    local bash_major
    bash_major=$(bash -c 'echo ${BASH_VERSINFO[0]}')
    if [ "$bash_major" -lt 4 ]; then
        skip "bash ${bash_major}.x does not support fractional read timeout"
    fi

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "should not be called for review"
exit 1
MOCK
    chmod +x "$MOCK_DIR/gh"

    local input_file="$BATS_TEST_TMPDIR/hook_input.json"
    echo '{"tool_input":{"command":"git status"}}' > "$input_file"

    export CLAUDE_PROJECT_DIR="/tmp/test-project"
    run bash "$SCRIPT" < "$input_file"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Review Complete"* ]]
}
