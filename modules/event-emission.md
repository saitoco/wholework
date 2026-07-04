# event-emission

<!-- ssot_for: phase event emission contract for run-*.sh wrappers -->

SSoT for phase event emission via `scripts/emit-event.sh` in all `run-*.sh` wrappers.
For per-skill data-layer reference, see `docs/reports/` and `modules/observation-trigger.md`.

## Purpose

Define the authoritative contract for how each `run-*.sh` wrapper emits phase lifecycle events
to `.tmp/auto-events.jsonl`. This log is the primary data source for `/audit auto-session`
Per-Issue Durations and session coverage metrics.

## Events

### phase_start

Emitted at the beginning of a phase, before invoking `claude -p`.

```json
{
  "ts": "2026-06-28T00:00:00Z",
  "issue": 123,
  "event": "phase_start",
  "session_id": "abc123",
  "phase": "code-pr"
}
```

### phase_complete

Emitted after a phase completes successfully (`EXIT_CODE=0` and `_EMIT_PHASE_OWNED=1`).

```json
{
  "ts": "2026-06-28T00:01:00Z",
  "issue": 123,
  "event": "phase_complete",
  "session_id": "abc123",
  "phase": "code-pr"
}
```

### phase_complete (backfilled)

When the EXIT trap fires and the last event for the issue is `phase_start`, a backfill entry
is written with `"backfilled": true`. This covers exit code 0 (clean exit) and exit code 143 (SIGTERM / watchdog timeout).

```json
{
  "ts": "2026-06-28T00:01:00Z",
  "issue": 123,
  "event": "phase_complete",
  "session_id": "abc123",
  "phase": "code-pr",
  "backfilled": true
}
```

### wrapper_exit

Emitted by `claude-watchdog.sh` on abnormal wrapper exit. Field: `exit_code`.

### token_usage

Emitted after a successful `--output-format json` run. Fields: `input_tokens`, `output_tokens`,
`cache_read_tokens`, `cache_write_tokens`, `phase`.

## Usage

### Required environment variables

| Variable | Set by | Description |
|----------|--------|-------------|
| `AUTO_EVENTS_LOG` | wrapper | Path to JSONL log (default: `.tmp/auto-events.jsonl`) |
| `AUTO_SESSION_ID` | wrapper (from `.tmp/auto-session-{PGID}`) | Identifies the `/auto` session |
| `EMIT_ISSUE_NUMBER` | wrapper | Issue number for the current phase |
| `EMIT_PHASE_NAME` | wrapper | Phase name (see Wrapper Coverage Table below) |

### _EMIT_PHASE_OWNED pattern

Each wrapper uses `_EMIT_PHASE_OWNED` to avoid double-emit when called from `run-auto-sub.sh`
(which sets `EMIT_PHASE_NAME` before invoking sub-wrappers):

```bash
AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
export AUTO_EVENTS_LOG
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" 2>/dev/null || echo '')}"
export AUTO_SESSION_ID
source "$SCRIPT_DIR/emit-event.sh"

_maybe_emit_phase_complete() { ... }  # EXIT trap — backfill if last event was phase_start
trap '_maybe_emit_phase_complete' EXIT

_EMIT_PHASE_OWNED=""
if [[ -z "${EMIT_PHASE_NAME:-}" ]]; then
  _EMIT_PHASE_OWNED=1
  export EMIT_ISSUE_NUMBER="$ISSUE_NUMBER"
  export EMIT_PHASE_NAME="<phase>"
  emit_event "phase_start" "phase=${EMIT_PHASE_NAME}"
fi

# ... run claude ...

if [[ $EXIT_CODE -eq 0 && -n "${_EMIT_PHASE_OWNED:-}" ]]; then
  emit_event "phase_complete" "phase=${EMIT_PHASE_NAME}"
fi
```

When `EMIT_PHASE_NAME` is already set (wrapper called from `run-auto-sub.sh`), `_EMIT_PHASE_OWNED`
stays empty and `phase_start` / `phase_complete` are not emitted — preventing double-emit.

## Wrapper Coverage Table

| Wrapper | Phase value(s) emitted | Notes |
|---------|------------------------|-------|
| `run-issue.sh` | `issue` | Added in #769 |
| `run-spec.sh` | `spec` | Added in #769 |
| `run-code.sh` | `code-pr` \| `code-patch` \| `code` | Selects based on route flag |
| `run-review.sh` | `review` | |
| `run-merge.sh` | `merge` | |
| `run-auto-sub.sh` | Sets `EMIT_PHASE_NAME` before delegating | Orchestrator; delegates to above |

## Non-Wrapper Emitters

`skills/verify/SKILL.md` emits `phase_start`/`phase_complete` (phase=`verify`) inline — directly from the skill body, gated only on `AUTO_EVENTS_LOG` being set — rather than through a `run-*.sh` wrapper. This is intentional: `/verify` has no `run-verify.sh` wrapper (removed in #485 when `/verify` moved to in-session execution), so the `_EMIT_PHASE_OWNED` pattern above, which lives in wrapper scripts, does not apply. `phase_complete` fires at every terminal branch of Step 11 (PASS/SKIPPED, FAIL retry, FAIL max-iterations, PENDING, UNCERTAIN) — not only on full PASS — because reaching an AC verdict, not the verdict itself, is the phase's completion signal. The skill also emits `verify_user_confirm` (phase-specific event, not a lifecycle event) at Step 8b whenever the interactive-mode manual-AC `AskUserQuestion` receives a response.

## Backfill

`_maybe_emit_phase_complete()` is registered as an EXIT trap in each wrapper. On exit, it checks
whether the last event for the current issue (in the session) was `phase_start`. If so, it writes
a `phase_complete` entry with `"backfilled": true`. This covers cases where `phase_start` was
emitted but `phase_complete` was not, on exit code 0 (clean exit) or exit code 143 (SIGTERM / watchdog timeout).

Guard conditions (all must be set and non-empty for backfill to fire):
- `AUTO_SESSION_ID`
- `EMIT_ISSUE_NUMBER`
- `EMIT_PHASE_NAME`
- `AUTO_EVENTS_LOG`
- Exit code must be 0 or 143 (SIGTERM): other non-zero exits are not backfilled (non-SIGTERM failures tracked by `wrapper_exit` events from `run-auto-sub.sh`)

## How to Reference

When a new wrapper needs phase event emission, copy the `_EMIT_PHASE_OWNED` pattern above,
set the appropriate `EMIT_PHASE_NAME`, and add a row to the Wrapper Coverage Table.
