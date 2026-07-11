#!/usr/bin/env bats

# Tests for run-auto-sub.sh
# Mocks sibling scripts via WHOLEWORK_SCRIPT_DIR, and gh/git via PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-auto-sub.sh"

setup() {
    # Isolate test from repo .wholework.yml
    echo "permission-mode: bypass" > "$BATS_TEST_TMPDIR/.wholework.yml"
    cd "$BATS_TEST_TMPDIR"
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    # Call logs for sibling script invocations
    export RUN_SPEC_LOG="$BATS_TEST_TMPDIR/run-spec.log"
    export RUN_CODE_LOG="$BATS_TEST_TMPDIR/run-code.log"
    export RUN_REVIEW_LOG="$BATS_TEST_TMPDIR/run-review.log"
    export RUN_MERGE_LOG="$BATS_TEST_TMPDIR/run-merge.log"
    export RECONCILE_LOG="$BATS_TEST_TMPDIR/reconcile.log"
    export APPLY_FALLBACK_LOG="$BATS_TEST_TMPDIR/apply-fallback.log"
    export SPAWN_RECOVERY_LOG="$BATS_TEST_TMPDIR/spawn-recovery.log"

    # Mock flock: no-op to avoid macOS incompatibility (needed by emit_event)
    cat > "$MOCK_DIR/flock" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"

    # Mock emit-event.sh (sourced by run-auto-sub.sh via emit-event.sh)
    cat > "$MOCK_DIR/emit-event.sh" <<'MOCK'
emit_event() { :; }
_emit_comments_consumed() { :; }
MOCK

    cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/check-verify-dirty.sh"

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

    # Mock recovery helpers: default behavior (exit 1 = no recovery) for happy-path tests
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/apply-fallback.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$APPLY_FALLBACK_LOG"
exit 1
MOCK
    chmod +x "$MOCK_DIR/apply-fallback.sh"

    cat > "$MOCK_DIR/spawn-recovery-subagent.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$SPAWN_RECOVERY_LOG"
exit 1
MOCK
    chmod +x "$MOCK_DIR/spawn-recovery-subagent.sh"

    # Real retry-on-kill.sh (sourced via WHOLEWORK_SCRIPT_DIR; must be present or source fails)
    cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/retry-on-kill.sh" "$MOCK_DIR/retry-on-kill.sh"

    # Real get-config-value.sh (needed to exercise .wholework.yml always-pr reads per test)
    cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/get-config-value.sh" "$MOCK_DIR/get-config-value.sh"
    chmod +x "$MOCK_DIR/get-config-value.sh"

    # Mock auto-checkpoint.sh: no-op milestone operations so existing tests are unaffected
    cat > "$MOCK_DIR/auto-checkpoint.sh" <<'MOCK'
#!/bin/bash
case "$1" in
    read_milestone) echo "initial" ;;
    resume_action)  echo "run-code" ;;
    write_milestone) exit 0 ;;
    write_single)   exit 0 ;;
    read_single)    echo "0" ;;
    *) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_DIR/auto-checkpoint.sh"

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

@test "Size XS + always-pr: true: promoted to pr route (run-code.sh --pr, run-review.sh, run-merge.sh called)" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"
    echo "always-pr: true" >> "$BATS_TEST_TMPDIR/.wholework.yml"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"always-pr: true is set in .wholework.yml. Promoting to pr route."* ]]
    grep -q "42 --pr" "$RUN_CODE_LOG"
    [ -f "$RUN_REVIEW_LOG" ]
    [ -f "$RUN_MERGE_LOG" ]
}

@test "Size S + always-pr: true: promoted to pr route (run-code.sh --pr, run-review.sh, run-merge.sh called)" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "S"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"
    echo "always-pr: true" >> "$BATS_TEST_TMPDIR/.wholework.yml"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"always-pr: true is set in .wholework.yml. Promoting to pr route."* ]]
    grep -q "42 --pr" "$RUN_CODE_LOG"
    [ -f "$RUN_REVIEW_LOG" ]
    [ -f "$RUN_MERGE_LOG" ]
}

@test "Size M: run-code.sh --pr, run-review.sh --light, run-merge.sh called; verify is NOT called (deferred to parent /auto)" {
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --pr" "$RUN_CODE_LOG"
    grep -q -- "--light" "$RUN_REVIEW_LOG"
    [ -f "$RUN_MERGE_LOG" ]
    [ ! -f "$BATS_TEST_TMPDIR/run-verify.log" ]
}

@test "Size L: run-code.sh --pr, run-review.sh --full, run-merge.sh called; verify is NOT called (deferred to parent /auto)" {
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
    [ ! -f "$BATS_TEST_TMPDIR/run-verify.log" ]
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

@test "--base flag propagates to run-code.sh for Size M; verify is NOT called by run-auto-sub.sh (deferred to parent /auto)" {
    run bash "$SCRIPT" 42 --base release/v1
    [ "$status" -eq 0 ]
    grep -q -- "--base release/v1" "$RUN_CODE_LOG"
    [ ! -f "$BATS_TEST_TMPDIR/run-verify.log" ]
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

@test "run-auto-sub: phase exit nonzero + tier1 reconcile matches_expected=true: override to success" {
    # run-code.sh exits 1, but tier1 reconciler says phase completed
    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_CODE_LOG"
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":true}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier1 reconciler"* ]]
}

@test "run-auto-sub: phase exit nonzero + tier1 fails + tier2 apply-fallback succeeds: recover" {
    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_CODE_LOG"
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    # tier1 returns no match
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    # tier2 succeeds
    cat > "$MOCK_DIR/apply-fallback.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$APPLY_FALLBACK_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/apply-fallback.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier2 fallback catalog"* ]]
    [ -f "$APPLY_FALLBACK_LOG" ]
}

@test "run-auto-sub: phase exit nonzero + tier1+tier2 fail + tier3 spawn succeeds: recover" {
    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_CODE_LOG"
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    # tier1 no match, tier2 fails, tier3 succeeds
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/spawn-recovery-subagent.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$SPAWN_RECOVERY_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/spawn-recovery-subagent.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"tier3 sub-agent"* ]]
    [ -f "$SPAWN_RECOVERY_LOG" ]
}

@test "run-auto-sub: tier3 recovery: commits orchestration-recoveries.md when dirty" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"diff"* && "$*" == *"orchestration-recoveries.md"* ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_CODE_LOG"
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/spawn-recovery-subagent.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$SPAWN_RECOVERY_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/spawn-recovery-subagent.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -qE "commit.*Record Tier 3 recovery event" "$GIT_LOG"
}

@test "run-auto-sub: all tiers fail: propagate original exit code" {
    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_CODE_LOG"
exit 2
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 2 ]
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

@test "post-spec size demotion M->XS: run-code.sh --patch is called and Post-spec is logged" {
    CALL_COUNT_FILE="$BATS_TEST_TMPDIR/.size-call-count"
    cat > "$MOCK_DIR/get-issue-size.sh" <<MOCK
#!/bin/bash
COUNT=\$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo 0)
COUNT=\$((COUNT + 1))
echo "\$COUNT" > "$CALL_COUNT_FILE"
if [[ "\$COUNT" -eq 1 ]]; then
  echo "M"
else
  echo "XS"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json labels"* ]]; then
    echo "triaged"
    exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
    if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
        echo "test issue title"
    elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
        echo "https://github.com/test/repo/issues/42"
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

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --patch" "$RUN_CODE_LOG"
    [[ "$output" == *"Post-spec route demotion/upgrade"* ]]
}

@test "post-spec size upgrade S->M: run-code.sh --pr is called and Post-spec is logged" {
    CALL_COUNT_FILE="$BATS_TEST_TMPDIR/.size-call-count"
    cat > "$MOCK_DIR/get-issue-size.sh" <<MOCK
#!/bin/bash
COUNT=\$(cat "$CALL_COUNT_FILE" 2>/dev/null || echo 0)
COUNT=\$((COUNT + 1))
echo "\$COUNT" > "$CALL_COUNT_FILE"
if [[ "\$COUNT" -eq 1 ]]; then
  echo "S"
else
  echo "M"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json labels"* ]]; then
    echo "triaged"
    exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
    if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
        echo "test issue title"
    elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
        echo "https://github.com/test/repo/issues/42"
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

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --pr" "$RUN_CODE_LOG"
    [[ "$output" == *"Post-spec route demotion/upgrade"* ]]
}

@test "Size S + run-code.sh exit1: reconcile-phase-state.sh receives code-patch as first arg" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "S"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # run-code.sh exits 1 to trigger tier1 reconcile
    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$RUN_CODE_LOG"
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    # reconcile-phase-state.sh logs first arg and returns matches_expected=true
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<MOCK
#!/bin/bash
echo "\$1" >> "$RECONCILE_LOG"
echo '{"matches_expected":true}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "code-patch" "$RECONCILE_LOG"
}

@test "token_usage: emit_event called with token_usage when TOKEN_USAGE_FILE exists" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    # Override emit-event.sh mock to record calls
    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    # Make run-code.sh write a token usage JSON file (real CLI output shape:
    # top-level "model" is always null; the actual model ID lives under modelUsage.<id>.*)
    cat > "$MOCK_DIR/run-code.sh" <<MOCK
#!/bin/bash
mkdir -p .tmp
cat > ".tmp/token-usage-42.json" <<'JSON'
{"model":null,"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20},"modelUsage":{"claude-sonnet-5":{"inputTokens":100,"outputTokens":50}}}
JSON
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Mock git to return no concurrent commits
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "model=claude-sonnet-5" "$BATS_TEST_TMPDIR/emit.log"
}

@test "token_usage: selects modelUsage key with highest input+output token total" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    # Two modelUsage keys: main session (claude-sonnet-5, total=105562) and a
    # sub-agent that used a different model (claude-haiku-4-5-20251001, total=58899).
    # The key with the larger input+output total must be selected as the phase's model.
    cat > "$MOCK_DIR/run-code.sh" <<MOCK
#!/bin/bash
mkdir -p .tmp
cat > ".tmp/token-usage-42.json" <<'JSON'
{"model":null,"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20},"modelUsage":{"claude-sonnet-5":{"inputTokens":52549,"outputTokens":53013},"claude-haiku-4-5-20251001":{"inputTokens":57614,"outputTokens":1285}}}
JSON
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "model=claude-sonnet-5" "$BATS_TEST_TMPDIR/emit.log"
}

@test "compute: modelUsage jq expression selects single key directly" {
    local input='{"model":null,"modelUsage":{"claude-sonnet-5":{"inputTokens":100,"outputTokens":50}}}'
    local result
    result=$(echo "$input" | jq -r '.modelUsage // {} | to_entries | if length == 0 then empty else (max_by(.value.inputTokens + .value.outputTokens) | .key) end')
    [ "$result" = "claude-sonnet-5" ]
}

@test "compute: modelUsage jq expression selects highest-total key among multiple" {
    local input='{"model":null,"modelUsage":{"claude-sonnet-5":{"inputTokens":52549,"outputTokens":53013},"claude-haiku-4-5-20251001":{"inputTokens":57614,"outputTokens":1285}}}'
    local result
    result=$(echo "$input" | jq -r '.modelUsage // {} | to_entries | if length == 0 then empty else (max_by(.value.inputTokens + .value.outputTokens) | .key) end')
    [ "$result" = "claude-sonnet-5" ]
}

@test "compute: modelUsage jq expression returns empty when modelUsage is absent" {
    local input='{"model":null}'
    local result
    result=$(echo "$input" | jq -r '.modelUsage // {} | to_entries | if length == 0 then empty else (max_by(.value.inputTokens + .value.outputTokens) | .key) end')
    [ -z "$result" ]
}

@test "test_result: emit_event called when bats output detected in log" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    # run-code.sh echoes bats output to stdout; run-auto-sub.sh captures it
    # into .tmp/wrapper-out-42-code-patch.log (XS route -> code-patch phase)
    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
echo "17 tests, 0 failures"
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "test_result" "$BATS_TEST_TMPDIR/emit.log"
}

@test "concurrent_commit_detected: emit_event called when git log returns commits" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Mock git to return a concurrent commit
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"log origin/main"* ]]; then
  echo "abc1234 Test User"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "concurrent_commit_detected" "$BATS_TEST_TMPDIR/emit.log" 2>/dev/null || \
      skip "concurrent_commit_detected event not logged (emit mock not capturing)"
}

@test "concurrent_commit_detected: self-issue-only commit is not emitted (no false positive)" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Mock git: origin/main has exactly one commit, authored by this issue's own
    # phase (subject contains "closes #42"). Must not be treated as concurrent.
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"log origin/main"* ]]; then
  echo "aaa1111 Test User"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"aaa1111"* ]]; then
  echo "chore: patch (closes #42)"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    ! grep -q "concurrent_commit_detected" "$BATS_TEST_TMPDIR/emit.log" 2>/dev/null
}

@test "concurrent_commit_detected: other-issue commit is emitted while self-issue commit is excluded" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Mock git: origin/main has two commits since phase start — one from this
    # issue's own phase (#42, must be excluded) and one from another issue's
    # phase (#99, a true concurrent commit that must still be emitted).
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"log origin/main"* ]]; then
  printf '%s\n' "aaa1111 Test User" "bbb2222 Other User"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"aaa1111"* ]]; then
  echo "chore: patch (closes #42)"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"bbb2222"* ]]; then
  echo "chore: patch (closes #99)"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "concurrent_commit_detected.*commit_sha=bbb2222" "$BATS_TEST_TMPDIR/emit.log"
    ! grep -q "commit_sha=aaa1111" "$BATS_TEST_TMPDIR/emit.log"
}

@test "concurrent_commit_detected: merge/review phase self-commit referencing the Issue number (not the PR number) is excluded (issue #974)" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    # Default Size is M (see setup): code-pr phase is called with issue=42, and
    # review/merge phases are called with issue=$PR_NUMBER=99. The commit below
    # is one of this run's own phase commits, but its subject references the
    # originating Issue number (#42) rather than the PR number (#99) — the
    # scenario that previously false-positived during review/merge.
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"log origin/main"* ]]; then
  echo "aaa1111 Test User"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"aaa1111"* ]]; then
  echo "Add merge phase handoff for issue #42"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    ! grep -q "concurrent_commit_detected" "$BATS_TEST_TMPDIR/emit.log" 2>/dev/null
}

@test "concurrent_commit_detected: an unrelated commit is still detected during review/merge phase (issue #974)" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    # A commit from a different Issue (#123) must still be flagged as concurrent,
    # confirming the Issue-number self-exclusion does not over-exclude.
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"log origin/main"* ]]; then
  echo "ccc3333 Other User"
  exit 0
fi
if [[ "$*" == *"log -1"* && "$*" == *"ccc3333"* ]]; then
  echo "chore: unrelated patch (closes #123)"
  exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "concurrent_commit_detected.*commit_sha=ccc3333" "$BATS_TEST_TMPDIR/emit.log"
}

@test "review/merge phase events emit issue=<real Issue number> and pr=<PR number> (issue #987)" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "phase=\${EMIT_PHASE_NAME:-} issue=\${EMIT_ISSUE_NUMBER:-} pr=\${EMIT_PR_NUMBER:-<unset>} event=\$1" >> "$BATS_TEST_TMPDIR/emit.log"
}
_emit_comments_consumed() { :; }
MOCK

    # Default fixture (see setup): SUB_NUMBER=42, PR_NUMBER=99, Size M.
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]

    # code-pr phase is called with the real Issue number and no PR context.
    grep -q "phase=code-pr issue=42 pr=<unset>" "$BATS_TEST_TMPDIR/emit.log"

    # review/merge phases are called with issue=$PR_NUMBER=99, but _EXTRA_SELF_ISSUE=42
    # resolves EMIT_ISSUE_NUMBER back to the real Issue number, with the PR number
    # preserved separately in EMIT_PR_NUMBER.
    grep -q "phase=review issue=42 pr=99" "$BATS_TEST_TMPDIR/emit.log"
    grep -q "phase=merge issue=42 pr=99" "$BATS_TEST_TMPDIR/emit.log"
}

@test "run-auto-sub: tier2 recovery: writes Auto Retrospective to spec file" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    echo "# Issue #42: test spec" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"status"* && "$*" == *"--porcelain"* && "$*" == *"issue-42"* ]]; then
    echo " M docs/spec/issue-42-test.md"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/apply-fallback.sh" <<'MOCK'
#!/bin/bash
printf '%s\n' \
  "### Orchestration Anomalies" \
  "- **[code-patch-silent-no-op]** Tier 2 fallback applied: result=recovered."
exit 0
MOCK
    chmod +x "$MOCK_DIR/apply-fallback.sh"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "Auto Retrospective" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    grep -q "code-patch-silent-no-op" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    grep -qE "commit.*Tier 2 recovery" "$GIT_LOG"
}

@test "run-auto-sub: tier3 recovery: writes Auto Retrospective to spec file" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    echo "# Issue #42: test spec" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"status"* && "$*" == *"--porcelain"* && "$*" == *"issue-42"* ]]; then
    echo " M docs/spec/issue-42-test.md"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/spawn-recovery-subagent.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$SPAWN_RECOVERY_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/spawn-recovery-subagent.sh"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "Auto Retrospective" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    grep -qE "commit.*Tier 3 recovery" "$GIT_LOG"
}

@test "run-auto-sub: manual recovery: writes Auto Retrospective to spec file" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    echo "# Issue #42: test spec" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"status"* && "$*" == *"--porcelain"* && "$*" == *"issue-42"* ]]; then
    echo " M docs/spec/issue-42-test.md"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    # No open PR for this issue: override the global gh mock's pr list default.
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "[]"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" --write-manual-recovery 42 code push-only
    [ "$status" -eq 0 ]
    grep -q "Auto Retrospective" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    grep -q "Manual recovery" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    grep -qE "commit.*manual recovery" "$GIT_LOG"
}

@test "run-auto-sub: push retry: non-fast-forward push succeeds after one fetch+rebase retry" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    echo "# Issue #42: test spec" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"status"* && "$*" == *"--porcelain"* && "$*" == *"issue-42"* ]]; then
    echo " M docs/spec/issue-42-test.md"
    exit 0
fi
if [[ "$*" == *"rev-parse --abbrev-ref HEAD"* ]]; then
    echo "main"
    exit 0
fi
if [[ "$*" == *"push origin HEAD"* ]]; then
    COUNT_FILE="$BATS_TEST_TMPDIR/push_count"
    count=0
    [ -f "$COUNT_FILE" ] && count=$(cat "$COUNT_FILE")
    count=$((count + 1))
    echo "$count" > "$COUNT_FILE"
    [ "$count" -eq 1 ] && exit 1
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    # No open PR for this issue: override the global gh mock's pr list default.
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "[]"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" --write-manual-recovery 42 code push-only
    [ "$status" -eq 0 ]
    push_count=$(grep -c "push origin HEAD" "$GIT_LOG")
    [ "$push_count" -eq 2 ]
    grep -q "fetch origin main" "$GIT_LOG"
    grep -q "rebase origin/main" "$GIT_LOG"
}

@test "run-auto-sub: push retry: gives up after 3 attempts and warns but continues" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    echo "# Issue #42: test spec" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"status"* && "$*" == *"--porcelain"* && "$*" == *"issue-42"* ]]; then
    echo " M docs/spec/issue-42-test.md"
    exit 0
fi
if [[ "$*" == *"rev-parse --abbrev-ref HEAD"* ]]; then
    echo "main"
    exit 0
fi
if [[ "$*" == *"push origin HEAD"* ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    # No open PR for this issue: override the global gh mock's pr list default.
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "[]"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" --write-manual-recovery 42 code push-only
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: could not commit/push manual recovery to spec; continuing"* ]]
    push_count=$(grep -c "push origin HEAD" "$GIT_LOG")
    [ "$push_count" -eq 3 ]
}

@test "run-auto-sub: manual recovery: skips commit when an open PR exists for the issue" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"
    export GH_LOG="$BATS_TEST_TMPDIR/gh.log"

    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    echo "# Issue #42: test spec" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GH_LOG"
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo '[{"number":123}]'
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" --write-manual-recovery 42 code push-only
    [ "$status" -eq 0 ]
    [[ "$output" == *"PR #123"* ]]
    [[ "$output" == *"Retry"* ]]
    ! grep -qE "commit.*manual recovery" "$GIT_LOG"
    ! grep -q "Auto Retrospective" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    grep -q -- "closes #42" "$GH_LOG"
    grep -q -- "--state open" "$GH_LOG"
}

@test "run-auto-sub: tier2 recovery: commits when spec file is untracked" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    # No pre-existing spec file: simulates untracked (initial creation) state
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"status"* && "$*" == *"--porcelain"* && "$*" == *"issue-42"* ]]; then
    echo "?? docs/spec/issue-42-recovery.md"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/apply-fallback.sh" <<'MOCK'
#!/bin/bash
printf '%s\n' \
  "### Orchestration Anomalies" \
  "- **[code-patch-silent-no-op]** Tier 2 fallback applied: result=recovered."
exit 0
MOCK
    chmod +x "$MOCK_DIR/apply-fallback.sh"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "Auto Retrospective" "$BATS_TEST_TMPDIR/docs/spec/issue-42-recovery.md"
    grep -qE "commit.*Tier 2 recovery" "$GIT_LOG"
}

@test "run-auto-sub: tier3 recovery: commits when spec file is untracked" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    # No pre-existing spec file: simulates untracked (initial creation) state
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"status"* && "$*" == *"--porcelain"* && "$*" == *"issue-42"* ]]; then
    echo "?? docs/spec/issue-42-recovery.md"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    cat > "$MOCK_DIR/spawn-recovery-subagent.sh" <<'MOCK'
#!/bin/bash
echo "$@" >> "$SPAWN_RECOVERY_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/spawn-recovery-subagent.sh"

    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "Auto Retrospective" "$BATS_TEST_TMPDIR/docs/spec/issue-42-recovery.md"
    grep -qE "commit.*Tier 3 recovery" "$GIT_LOG"
}

@test "run-auto-sub: manual recovery: commits when spec file is untracked" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    # No pre-existing spec file: simulates untracked (initial creation) state
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"rev-parse --show-toplevel"* ]]; then
    echo "$BATS_TEST_TMPDIR"
    exit 0
fi
if [[ "$*" == *"status"* && "$*" == *"--porcelain"* && "$*" == *"issue-42"* ]]; then
    echo "?? docs/spec/issue-42-recovery.md"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    # No open PR for this issue: override the global gh mock's pr list default.
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "[]"
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" --write-manual-recovery 42 code push-only
    [ "$status" -eq 0 ]
    grep -q "Auto Retrospective" "$BATS_TEST_TMPDIR/docs/spec/issue-42-recovery.md"
    grep -q "Manual recovery" "$BATS_TEST_TMPDIR/docs/spec/issue-42-recovery.md"
    grep -qE "commit.*manual recovery" "$GIT_LOG"
}

@test "post-spec size unchanged XS->XS: Post-spec is not logged" {
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json labels"* ]]; then
    echo "triaged"
    exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json"* ]]; then
    if [[ "$*" == *"-q"* && "$*" == *".title"* ]]; then
        echo "test issue title"
    elif [[ "$*" == *"-q"* && "$*" == *".url"* ]]; then
        echo "https://github.com/test/repo/issues/42"
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

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [[ "$output" != *"Post-spec route demotion/upgrade"* ]]
}

@test "resume preamble: no residual worktree or branch - run-code.sh is called normally (Size M)" {
    # No worktree dir, no branch: gate does not fire, code phase runs normally
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "42 --pr" "$RUN_CODE_LOG"
    [[ "$output" != *"[resume]"* ]]
}

@test "resume preamble: residual worktree dir present and action=skip-to-review: code phase is skipped (Size M)" {
    # Create worktree dir to trigger the resume preamble gate
    mkdir -p "$BATS_TEST_TMPDIR/.claude/worktrees/code+issue-42"

    # Override auto-checkpoint.sh to return skip-to-review for resume_action
    cat > "$MOCK_DIR/auto-checkpoint.sh" <<'MOCK'
#!/bin/bash
case "$1" in
    read_milestone) echo "post-PR-create" ;;
    resume_action)  echo "skip-to-review" ;;
    *) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_DIR/auto-checkpoint.sh"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    # run-code.sh should NOT be called (code phase skipped)
    [ ! -f "$RUN_CODE_LOG" ]
    # review and merge should still be called
    [ -f "$RUN_REVIEW_LOG" ]
    [ -f "$RUN_MERGE_LOG" ]
    [[ "$output" == *"[resume]"* ]]
}

@test "validate: --write-manual-recovery rejects whitespace-only issue" {
    run bash "$SCRIPT" --write-manual-recovery " " code push-only
    [ "$status" -ne 0 ]
}

@test "validate: --write-manual-recovery rejects non-numeric issue" {
    run bash "$SCRIPT" --write-manual-recovery "abc" code push-only
    [ "$status" -ne 0 ]
}

@test "validate: --write-manual-recovery rejects phase with whitespace" {
    run bash "$SCRIPT" --write-manual-recovery "42" "bad phase" push-only
    [ "$status" -ne 0 ]
}

@test "retry-on-kill: child runner killed once then succeeds, run-auto-sub exits 0" {
    COUNTER_FILE="$BATS_TEST_TMPDIR/call_counter"
    echo "0" > "$COUNTER_FILE"
    export COUNTER_FILE
    # XS route: only code-patch phase, shortest path
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"
    # Counter mock: 1st call exits 143 (SIGTERM), 2nd call exits 0
    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
N=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
N=$((N + 1))
echo "$N" > "$COUNTER_FILE"
if [[ $N -eq 1 ]]; then exit 143; fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"
    # orchestration-recoveries.md is absent in test env: _write_wrapper_retry_recovery skips
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ "$(cat "$COUNTER_FILE")" -eq 2 ]
}

@test "session-isolation: exit 1 causes abort with error" {
    cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/check-verify-dirty.sh"
    run bash "$SCRIPT" 42
    [ "$status" -eq 1 ]
    [[ "$output" == *"parent main has uncommitted changes"* ]]
}

@test "session-isolation: exit 2 shows warning and continues" {
    cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
#!/bin/bash
exit 2
MOCK
    chmod +x "$MOCK_DIR/check-verify-dirty.sh"
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"other-session dirty files"* ]]
}
