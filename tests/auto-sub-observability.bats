#!/usr/bin/env bats

# Tests for run-auto-sub.sh observability: LOG_PREFIX and JSONL event log.
# Mocks sibling scripts via WHOLEWORK_SCRIPT_DIR, and gh/flock via PATH.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/run-auto-sub.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    # Isolate JSONL event log to per-test tmpdir
    export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/.tmp/auto-events.jsonl"

    # Mock flock: no-op to avoid macOS incompatibility
    cat > "$MOCK_DIR/flock" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/flock"

    # Mock emit-event.sh (sourced by run-auto-sub.sh) — writes a minimal JSONL line
    # so that event-format-check and append-no-clobber assertions can validate output.
    cat > "$MOCK_DIR/emit-event.sh" <<'MOCK'
emit_event() {
    local event_name="$1"
    mkdir -p "$(dirname "${AUTO_EVENTS_LOG}")"
    printf '{"ts":"%s","issue":%s,"event":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${EMIT_ISSUE_NUMBER:-0}" "${event_name}" >> "${AUTO_EVENTS_LOG}"
}
MOCK

    # Mock phase-banner.sh (sourced by run-auto-sub.sh)
    cat > "$MOCK_DIR/phase-banner.sh" <<'MOCK'
print_start_banner() { echo "Starting /$3 for issue #$2"; }
print_end_banner() { echo "Finished /$3 for issue #$2"; }
MOCK

    # Mock get-issue-size.sh: default Size XS (simplest path for observability checks)
    cat > "$MOCK_DIR/get-issue-size.sh" <<'MOCK'
#!/bin/bash
echo "XS"
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-issue-size.sh"

    # Mock run-code.sh: exit 0
    cat > "$MOCK_DIR/run-code.sh" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/run-code.sh"

    # Mock recovery helpers: not needed for happy path (exit 1 = no recovery)
    cat > "$MOCK_DIR/reconcile-phase-state.sh" <<'MOCK'
#!/bin/bash
echo '{"matches_expected":false}'
exit 0
MOCK
    chmod +x "$MOCK_DIR/reconcile-phase-state.sh"

    cat > "$MOCK_DIR/apply-fallback.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/apply-fallback.sh"

    cat > "$MOCK_DIR/spawn-recovery-subagent.sh" <<'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$MOCK_DIR/spawn-recovery-subagent.sh"

    # Mock gh: phase/ready present, so spec phase is skipped
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json labels"* ]]; then
    echo "phase/ready"
    echo "triaged"
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

@test "prefix-check: stdout contains [#42] prefix" {
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"[#42]"* ]]
}

@test "event-format-check: AUTO_EVENTS_LOG contains JSON line with event field" {
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ -f "$AUTO_EVENTS_LOG" ]
    grep -q '"event":' "$AUTO_EVENTS_LOG"
}

@test "append-no-clobber: two runs produce at least two log entries" {
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    local count
    count=$(wc -l < "$AUTO_EVENTS_LOG")
    [ "$count" -ge 2 ]
}

@test "backfill-emit: exits 0 with phase_start only emits phase_complete with backfilled" {
    # Override emit-event.sh to suppress completion events, leaving phase_start as last event
    cat > "$MOCK_DIR/emit-event.sh" <<'MOCK'
emit_event() {
    local event_name="$1"
    case "$event_name" in
        phase_complete|sub_complete|wrapper_exit) return 0 ;;
    esac
    mkdir -p "$(dirname "${AUTO_EVENTS_LOG}")"
    printf '{"ts":"%s","issue":%s,"event":"%s","session_id":"%s","phase":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${EMIT_ISSUE_NUMBER:-0}" "${event_name}" \
        "${AUTO_SESSION_ID:-}" "${EMIT_PHASE_NAME:-}" >> "${AUTO_EVENTS_LOG}"
}
MOCK
    export AUTO_SESSION_ID="test-session-backfill"
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q '"backfilled":true' "$AUTO_EVENTS_LOG"
}
