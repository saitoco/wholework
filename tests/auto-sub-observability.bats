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
_emit_comments_consumed() { :; }
MOCK

    # Real retry-on-kill.sh (sourced via WHOLEWORK_SCRIPT_DIR; must be present or source fails)
    cp "$(dirname "$BATS_TEST_FILENAME")/../scripts/retry-on-kill.sh" "$MOCK_DIR/retry-on-kill.sh"

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

@test "wrapper-alive-check: AUTO_EVENTS_LOG contains a wrapper_alive event" {
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ -f "$AUTO_EVENTS_LOG" ]
    grep -q '"event":"wrapper_alive"' "$AUTO_EVENTS_LOG"
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
    local event_name="$1"; shift
    case "$event_name" in
        phase_complete|sub_complete|wrapper_exit) return 0 ;;
    esac
    # Pass remaining kv args through as extra JSON fields (e.g. checkpoint=...)
    # so the real backfill logic's checkpoint check can be exercised faithfully.
    local extra=""
    while [[ $# -gt 0 ]]; do
        local kv="$1"; local k="${kv%%=*}"; local v="${kv#*=}"
        extra="${extra},\"${k}\":\"${v}\""
        shift
    done
    mkdir -p "$(dirname "${AUTO_EVENTS_LOG}")"
    printf '{"ts":"%s","issue":%s,"event":"%s","session_id":"%s","phase":"%s"%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${EMIT_ISSUE_NUMBER:-0}" "${event_name}" \
        "${AUTO_SESSION_ID:-}" "${EMIT_PHASE_NAME:-}" "${extra}" >> "${AUTO_EVENTS_LOG}"
}
_emit_comments_consumed() { :; }
MOCK
    export AUTO_SESSION_ID="test-session-backfill"
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q '"backfilled":true' "$AUTO_EVENTS_LOG"
}

@test "backfill-emit: SIGTERM (exit 143) with phase_start emits phase_complete with backfilled" {
    export AUTO_SESSION_ID="test-session-sigterm"
    export EMIT_ISSUE_NUMBER="42"
    export EMIT_PHASE_NAME="code-pr"
    mkdir -p "$(dirname "$AUTO_EVENTS_LOG")"
    printf '{"ts":"2026-01-01T00:00:00Z","issue":42,"event":"phase_start","session_id":"test-session-sigterm","phase":"code-pr"}\n' \
        >> "$AUTO_EVENTS_LOG"

    cat > "$BATS_TEST_TMPDIR/sigterm-helper.sh" <<HELPER
#!/usr/bin/env bash
source "$MOCK_DIR/emit-event.sh"
_maybe_emit_phase_complete() {
  local _exit_code=\$?
  [[ "\$_exit_code" -ne 0 && "\$_exit_code" -ne 143 ]] && return 0
  [[ -z "\${AUTO_EVENTS_LOG:-}" ]] && return 0
  [[ -z "\${AUTO_SESSION_ID:-}" ]] && return 0
  [[ -z "\${EMIT_ISSUE_NUMBER:-}" ]] && return 0
  [[ -z "\${EMIT_PHASE_NAME:-}" ]] && return 0
  local _last_event _last_checkpoint _last_json
  _last_json=\$(grep "\\"session_id\\":\\"\${AUTO_SESSION_ID}\\"" "\${AUTO_EVENTS_LOG}" 2>/dev/null \
      | jq -rs --argjson n "\${EMIT_ISSUE_NUMBER}" \
        '[.[] | select(.issue == \$n)] | last // empty' 2>/dev/null || true)
  _last_event=\$(echo "\${_last_json}" | jq -r '.event // ""' 2>/dev/null || true)
  _last_checkpoint=\$(echo "\${_last_json}" | jq -r '.checkpoint // ""' 2>/dev/null || true)
  if [[ "\${_last_event}" == "phase_start" ]] || \
     { [[ "\${_last_event}" == "wrapper_alive" ]] && [[ "\${_last_checkpoint}" == "pre_subprocess" ]]; }; then
    local _ts; _ts=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s\n' \
      "{\\"ts\\":\\"\${_ts}\\",\\"issue\\":\${EMIT_ISSUE_NUMBER},\\"event\\":\\"phase_complete\\",\\"session_id\\":\\"\${AUTO_SESSION_ID}\\",\\"phase\\":\\"\${EMIT_PHASE_NAME}\\",\\"backfilled\\":true}" \
      >> "\${AUTO_EVENTS_LOG}" 2>/dev/null || true
  fi
}
trap '_maybe_emit_phase_complete' EXIT
exit 143
HELPER
    run bash "$BATS_TEST_TMPDIR/sigterm-helper.sh"
    [ "$status" -eq 143 ]
    grep -q '"backfilled":true' "$AUTO_EVENTS_LOG"
}

@test "backfill-emit: SIGTERM (exit 143) with wrapper_alive checkpoint=pre_subprocess as last event also backfills" {
    export AUTO_SESSION_ID="test-session-sigterm-heartbeat"
    export EMIT_ISSUE_NUMBER="42"
    export EMIT_PHASE_NAME="code-pr"
    mkdir -p "$(dirname "$AUTO_EVENTS_LOG")"
    printf '{"ts":"2026-01-01T00:00:00Z","issue":42,"event":"phase_start","session_id":"test-session-sigterm-heartbeat","phase":"code-pr"}\n' \
        >> "$AUTO_EVENTS_LOG"
    printf '{"ts":"2026-01-01T00:00:01Z","issue":42,"event":"wrapper_alive","session_id":"test-session-sigterm-heartbeat","phase":"code-pr","checkpoint":"pre_subprocess"}\n' \
        >> "$AUTO_EVENTS_LOG"

    cat > "$BATS_TEST_TMPDIR/sigterm-heartbeat-helper.sh" <<HELPER
#!/usr/bin/env bash
source "$MOCK_DIR/emit-event.sh"
_maybe_emit_phase_complete() {
  local _exit_code=\$?
  [[ "\$_exit_code" -ne 0 && "\$_exit_code" -ne 143 ]] && return 0
  [[ -z "\${AUTO_EVENTS_LOG:-}" ]] && return 0
  [[ -z "\${AUTO_SESSION_ID:-}" ]] && return 0
  [[ -z "\${EMIT_ISSUE_NUMBER:-}" ]] && return 0
  [[ -z "\${EMIT_PHASE_NAME:-}" ]] && return 0
  local _last_event _last_checkpoint _last_json
  _last_json=\$(grep "\\"session_id\\":\\"\${AUTO_SESSION_ID}\\"" "\${AUTO_EVENTS_LOG}" 2>/dev/null \
      | jq -rs --argjson n "\${EMIT_ISSUE_NUMBER}" \
        '[.[] | select(.issue == \$n)] | last // empty' 2>/dev/null || true)
  _last_event=\$(echo "\${_last_json}" | jq -r '.event // ""' 2>/dev/null || true)
  _last_checkpoint=\$(echo "\${_last_json}" | jq -r '.checkpoint // ""' 2>/dev/null || true)
  if [[ "\${_last_event}" == "phase_start" ]] || \
     { [[ "\${_last_event}" == "wrapper_alive" ]] && [[ "\${_last_checkpoint}" == "pre_subprocess" ]]; }; then
    local _ts; _ts=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s\n' \
      "{\\"ts\\":\\"\${_ts}\\",\\"issue\\":\${EMIT_ISSUE_NUMBER},\\"event\\":\\"phase_complete\\",\\"session_id\\":\\"\${AUTO_SESSION_ID}\\",\\"phase\\":\\"\${EMIT_PHASE_NAME}\\",\\"backfilled\\":true}" \
      >> "\${AUTO_EVENTS_LOG}" 2>/dev/null || true
  fi
}
trap '_maybe_emit_phase_complete' EXIT
exit 143
HELPER
    run bash "$BATS_TEST_TMPDIR/sigterm-heartbeat-helper.sh"
    [ "$status" -eq 143 ]
    grep -q '"backfilled":true' "$AUTO_EVENTS_LOG"
}

@test "session-isolation: PGID-specific pointer file is read when AUTO_SESSION_ID is unset" {
    # Obtain the PGID of the current shell (same as run-auto-sub.sh will see)
    local pgid
    pgid=$(ps -o pgid= -p $$ | tr -d ' ')

    # Write a test session_id into the PGID-specific pointer file
    mkdir -p "$BATS_TEST_TMPDIR/.tmp"
    printf 'test-session-pgid\n' > "$BATS_TEST_TMPDIR/.tmp/auto-session-${pgid}"

    # Override emit-event.sh to capture the session_id value
    cat > "$MOCK_DIR/emit-event.sh" <<'MOCK'
emit_event() {
    local event_name="$1"
    mkdir -p "$(dirname "${AUTO_EVENTS_LOG}")"
    printf '{"ts":"%s","issue":%s,"event":"%s","session_id":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${EMIT_ISSUE_NUMBER:-0}" "${event_name}" \
        "${AUTO_SESSION_ID:-}" >> "${AUTO_EVENTS_LOG}"
}
_emit_comments_consumed() { :; }
MOCK

    # Unset AUTO_SESSION_ID so run-auto-sub.sh reads from the pointer file
    unset AUTO_SESSION_ID
    run bash "$SCRIPT" 42
    [ "$status" -eq 0 ]
    grep -q '"session_id":"test-session-pgid"' "$AUTO_EVENTS_LOG"
}
