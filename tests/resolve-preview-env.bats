#!/usr/bin/env bats

# Tests for scripts/resolve-preview-env.sh (Issue #1428)
# Mocks: get-config-value.sh, timeout (via PATH prepend + WHOLEWORK_SCRIPT_DIR)

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/resolve-preview-env.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"
}

mock_config_value() {
    # $1 = preview-url-command value to return (empty string = key not declared).
    # Written to a side file (not embedded in the heredoc below) so values
    # containing double quotes (e.g. a python3 -c '...' one-liner) round-trip
    # byte-for-byte instead of colliding with the heredoc's own quoting.
    printf '%s' "$1" > "$MOCK_DIR/preview-url-command-value"
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    preview-url-command) cat "$(dirname "$0")/preview-url-command-value" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"
}

@test "error: wrong number of arguments" {
    run --separate-stderr "$SCRIPT" url
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Usage:"* ]] || false
}

@test "error: unknown mode" {
    run --separate-stderr "$SCRIPT" basic-auth 123
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"unknown mode"* ]] || false
}

@test "error: PR number non-numeric" {
    mock_config_value "echo https://preview.example.com"
    run --separate-stderr "$SCRIPT" url abc
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"PR number must be a positive integer"* ]] || false
}

@test "no-op: preview-url-command not declared (empty stdout, exit 0)" {
    mock_config_value ""
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "success: resolves URL on stdout" {
    mock_config_value "echo https://preview-123.example.com"
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "https://preview-123.example.com" ]
}

@test "success: resolved message goes to stderr, not stdout" {
    mock_config_value "echo https://preview-123.example.com"
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "https://preview-123.example.com" ]
    [[ "$stderr" == *"Resolved PREVIEW_URL via preview-url-command for PR #123"* ]] || false
}

@test "success: {pr} placeholder is substituted with the PR number" {
    mock_config_value "echo https://pr-{pr}.example-preview.com"
    run --separate-stderr "$SCRIPT" url 456
    [ "$status" -eq 0 ]
    [ "$output" = "https://pr-456.example-preview.com" ]
}

@test "fallback: command times out (simulated via timeout binary exit 124)" {
    # Real 30s timeouts would make this test too slow; mock the `timeout`
    # binary itself to return 124 (the real coreutils timeout's own exit
    # code on expiry) without actually running the wrapped command. The
    # script treats any non-zero _resolved_status uniformly, so this
    # exercises the same code path a real timeout would hit.
    cat > "$MOCK_DIR/timeout" <<'MOCK'
#!/bin/bash
exit 124
MOCK
    chmod +x "$MOCK_DIR/timeout"
    mock_config_value "sleep 999"
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [[ "$stderr" == *"exited non-zero (status=124)"* ]] || false
}

@test "fallback: command exits non-zero" {
    mock_config_value "exit 1"
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [[ "$stderr" == *"exited non-zero"* ]] || false
}

@test "fallback: empty output" {
    mock_config_value "true"
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [[ "$stderr" == *"produced empty output"* ]] || false
}

@test "fallback: output exceeds 2048 chars" {
    mock_config_value "python3 -c \"print('https://' + 'a' * 2100 + '.example.com')\""
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [[ "$stderr" == *"exceeds 2048 chars"* ]] || false
}

@test "fallback: non-URL output" {
    mock_config_value "echo not-a-url"
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
    [[ "$stderr" == *"not an http(s) URL"* ]] || false
}

@test "MAIN_REPO_ROOT resolution: falls back gracefully outside a git worktree" {
    # BATS_TEST_TMPDIR is not a git repository, so `git worktree list` fails;
    # the script must not error out and must still resolve via WHOLEWORK_SCRIPT_DIR.
    mock_config_value "echo https://preview-123.example.com"
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "https://preview-123.example.com" ]
}

@test "MAIN_REPO_ROOT resolution: cds to main repo root reported by git worktree list" {
    # Simulate being called from a linked worktree: `git worktree list --porcelain`
    # points back to a main repo root; the script should cd there and still
    # resolve successfully via WHOLEWORK_SCRIPT_DIR-provided get-config-value.sh.
    mkdir -p "$BATS_TEST_TMPDIR/main-repo"
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ "\$1" == "worktree" && "\$2" == "list" ]]; then
    echo "worktree $BATS_TEST_TMPDIR/main-repo"
    exit 0
fi
exit 1
MOCK
    chmod +x "$MOCK_DIR/git"
    mock_config_value "echo https://preview-123.example.com"
    run --separate-stderr "$SCRIPT" url 123
    [ "$status" -eq 0 ]
    [ "$output" = "https://preview-123.example.com" ]
}
