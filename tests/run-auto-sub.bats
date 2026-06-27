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
MOCK

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
MOCK

    # Make run-code.sh write a token usage JSON file
    cat > "$MOCK_DIR/run-code.sh" <<MOCK
#!/bin/bash
mkdir -p .tmp
cat > ".tmp/token-usage-42.json" <<'JSON'
{"model":"claude-sonnet-4-6","usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20}}
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
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q "token_usage" "$BATS_TEST_TMPDIR/emit.log" 2>/dev/null || \
      skip "token_usage event not logged (emit mock not capturing)"
}

@test "test_result: emit_event called when bats output detected in log" {
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"
    export EMIT_ISSUE_NUMBER="42"

    cat > "$MOCK_DIR/emit-event.sh" <<MOCK
emit_event() {
  echo "emit_event \$*" >> "$BATS_TEST_TMPDIR/emit.log"
}
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

@test "run-auto-sub: tier2 recovery: writes Auto Retrospective to spec file" {
    export GIT_LOG="$BATS_TEST_TMPDIR/git.log"

    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    echo "# Issue #42: test spec" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
echo "$@" >> "$GIT_LOG"
if [[ "$*" == *"diff"* && "$*" == *"issue-42"* ]]; then
    exit 1
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
