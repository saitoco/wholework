#!/usr/bin/env bats

# Tests for run-code.sh mergeability check (pr route conflict detection)
# Mocks: claude, claude-watchdog.sh, phase-banner.sh, gh, git, reconcile-phase-state.sh,
#        gh-pr-merge-status.sh (via MOCK_DIR + WHOLEWORK_SCRIPT_DIR)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-code.sh"

setup() {
    echo "permission-mode: bypass" > "$BATS_TEST_TMPDIR/.wholework.yml"
    cd "$BATS_TEST_TMPDIR"
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    CLAUDE_CALL_LOG="$BATS_TEST_TMPDIR/claude_calls.log"
    export CLAUDE_CALL_LOG

    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    permission-mode) echo "bypass" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    cat > "$MOCK_DIR/claude" <<'MOCK'
#!/bin/bash
echo "FLAG_P=1" >> "$CLAUDE_CALL_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"

    cat > "$MOCK_DIR/claude-watchdog.sh" <<'MOCK'
#!/bin/bash
exec "$@"
MOCK
    chmod +x "$MOCK_DIR/claude-watchdog.sh"

    cat > "$MOCK_DIR/handle-permission-mode-failure.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/handle-permission-mode-failure.sh"

    cat > "$MOCK_DIR/phase-banner.sh" <<'MOCK'
print_start_banner() { echo "Starting /$3 for issue #$2"; }
print_end_banner() { echo "Finished /$3 for issue #$2"; }
MOCK

    cat > "$MOCK_DIR/watchdog-defaults.sh" <<'MOCK'
WATCHDOG_TIMEOUT_DEFAULT=1800
load_watchdog_timeout() { WATCHDOG_TIMEOUT=1800; }
MOCK

    cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/guard-prefix.sh" "$MOCK_DIR/guard-prefix.sh"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    # reconcile-phase-state.sh mock returns pr_number=123 for completion check
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":true,"phase":"code-pr","actual":{"pr_state":"OPEN","pr_number":123},"schema_version":"v1","diagnosis":"test"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    mkdir -p "$BATS_TEST_TMPDIR/skills/code"
    cat > "$BATS_TEST_TMPDIR/skills/code/SKILL.md" <<'SKILL'
---
type: skill
---
# Code Skill Body
This is the skill body content used for testing.
SKILL
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "mergeability: pr route with conflicts warns on stderr" {
    cat > "$MOCK_DIR/gh-pr-merge-status.sh" <<'MOCK'
#!/bin/bash
echo '{"mergeable": false, "reason": "conflicts", "ci_status": "unknown", "review_status": "unknown"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh-pr-merge-status.sh"

    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    [[ "$output" == *"conflicts with base"* ]]
}

@test "mergeability: pr route without conflicts outputs no warn" {
    cat > "$MOCK_DIR/gh-pr-merge-status.sh" <<'MOCK'
#!/bin/bash
echo '{"mergeable": true, "reason": "clean", "ci_status": "success", "review_status": "approved"}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh-pr-merge-status.sh"

    run bash "$SCRIPT" 123 --pr
    [ "$status" -eq 0 ]
    [[ "$output" != *"conflicts with base"* ]]
}
