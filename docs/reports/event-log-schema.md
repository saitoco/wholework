# Auto Event Log Schema

This document defines the schema for `.tmp/auto-events.jsonl`, the structured event log emitted during `/auto` sessions.

## Backward-Compatibility Guarantee

- Fields are **added only** — no existing field names are removed or have their types changed.
- Consumers must tolerate unknown fields (forward-compatible reading).
- The `ts`, `issue`, and `event` fields are always present in every event.

## Existing Events (introduced in #600)

| Event type | Description |
|---|---|
| `sub_start` | Sub-issue processing begins |
| `phase_start` | A phase (spec/code/review/merge) begins |
| `wrapper_exit` | A phase runner script exits (with exit_code) |
| `recovery` | A recovery tier was invoked |
| `phase_complete` | A phase completed successfully |
| `sub_complete` | Sub-issue processing completed |
| `anomaly` | An anomaly was detected in phase output |
| `size_refresh` | Issue size was re-evaluated after spec phase |

## New Events (introduced in #630)

### 1. `token_usage`

Emitted by `run-auto-sub.sh` after each phase completes, parsed from `TOKEN_USAGE_FILE` written by `run-code.sh` / `run-review.sh` / `run-merge.sh` when `AUTO_EVENTS_LOG` is set.

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "token_usage",
  "phase": "code",
  "model": "claude-sonnet-4-6",
  "input_tokens": "45000",
  "output_tokens": "12000",
  "cache_read_tokens": "18000"
}
```

| Field | Required | Description |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC timestamp |
| `issue` | Yes | Issue number |
| `event` | Yes | `"token_usage"` |
| `phase` | Yes | Phase name (`code`, `review`, `merge`) |
| `model` | Yes | Model identifier (e.g. `claude-sonnet-4-6`) |
| `input_tokens` | Yes | Input token count (string) |
| `output_tokens` | Yes | Output token count (string) |
| `cache_read_tokens` | Yes | Cache read token count (string, `0` if none) |

**Emission point**: `run-auto-sub.sh` `run_phase_with_recovery()`, immediately after `wrapper_exit` event, when `.tmp/token-usage-{issue}.json` exists.

**Scope**: `code`, `review`, `merge` phases only (those invoked via `run_phase_with_recovery`). `spec` phase is excluded as it is called directly.

---

### 2. `watchdog_kill`

Emitted by `claude-watchdog.sh` immediately before killing a hung process.

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "watchdog_kill",
  "phase": "code",
  "pid": "42296",
  "silent_window_sec": "600",
  "timeout_setting": "1800"
}
```

| Field | Required | Description |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC timestamp |
| `issue` | Yes | Issue number (from `EMIT_ISSUE_NUMBER`) |
| `event` | Yes | `"watchdog_kill"` |
| `phase` | Yes | Phase name (from `EMIT_PHASE_NAME`, `unknown` if unset) |
| `pid` | Yes | PID of the killed process |
| `silent_window_sec` | Yes | Seconds of silence that triggered the kill |
| `timeout_setting` | Yes | `WATCHDOG_TIMEOUT` value in effect |

**Emission point**: `claude-watchdog.sh` `_auto_emit_watchdog_kill()`, called immediately before `kill "$cmd_pid"` in both normal and `OUTPUT_FORMAT_JSON=1` modes.

---

### 3. `max_silent_window`

Emitted by `claude-watchdog.sh` after the monitored process exits (naturally or via kill), reporting the maximum consecutive-silence window observed during the run.

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "max_silent_window",
  "phase": "code",
  "max_sec": "480"
}
```

| Field | Required | Description |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC timestamp |
| `issue` | Yes | Issue number (from `EMIT_ISSUE_NUMBER`) |
| `event` | Yes | `"max_silent_window"` |
| `phase` | Yes | Phase name (from `EMIT_PHASE_NAME`, `unknown` if unset) |
| `max_sec` | Yes | Maximum consecutive-silence seconds observed |

**Emission point**: `claude-watchdog.sh` `_auto_emit_max_silent()`, called after `wait "$cmd_pid"` returns (regardless of kill or natural exit).

---

### 4. `concurrent_commit_detected`

Emitted by `run-auto-sub.sh` at the end of each phase when commits on `origin/main` are detected since the phase started.

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "concurrent_commit_detected",
  "phase": "code",
  "commit_sha": "abc1234",
  "author": "saito",
  "since_phase_start_sec": "150"
}
```

| Field | Required | Description |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC timestamp |
| `issue` | Yes | Issue number |
| `event` | Yes | `"concurrent_commit_detected"` |
| `phase` | Yes | Phase name |
| `commit_sha` | Yes | Full SHA of the concurrent commit |
| `author` | Yes | Commit author name |
| `since_phase_start_sec` | Yes | Elapsed seconds since phase start |

**Emission point**: `run-auto-sub.sh` `run_phase_with_recovery()`, after `wrapper_exit`. One event per concurrent commit found. No periodic polling — checked once at phase end to minimize overhead.

---

### 5. `ci_wait`

Emitted by `wait-ci-checks.sh` after CI polling completes.

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "ci_wait",
  "phase": "review",
  "wait_sec": "420",
  "checks_passed": "5",
  "checks_failed": "0"
}
```

| Field | Required | Description |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC timestamp |
| `issue` | Yes | Issue number (from `EMIT_ISSUE_NUMBER`) |
| `event` | Yes | `"ci_wait"` |
| `phase` | Yes | Phase name (from `EMIT_PHASE_NAME`, `review` if unset) |
| `wait_sec` | Yes | Total seconds spent waiting for CI |
| `checks_passed` | Yes | Approximate count of passed checks (grep-based) |
| `checks_failed` | Yes | Approximate count of failed checks (grep-based) |

**Emission point**: `wait-ci-checks.sh`, immediately before the final completion log line.

**Note**: `checks_passed` and `checks_failed` are approximate values derived from `grep -c` on `gh pr checks` stdout and may differ from the true GitHub check counts.

---

### 6. `test_result`

Emitted by `run-auto-sub.sh` during the `code` phase when bats test output is detected in the phase log file.

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "test_result",
  "phase": "code",
  "framework": "bats",
  "passed": "17",
  "failed": "0",
  "pattern": "unit"
}
```

| Field | Required | Description |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC timestamp |
| `issue` | Yes | Issue number |
| `event` | Yes | `"test_result"` |
| `phase` | Yes | Always `"code"` (only emitted from code phase) |
| `framework` | Yes | Test framework (`bats`) |
| `passed` | Yes | Number of passing tests |
| `failed` | Yes | Number of failing tests |
| `pattern` | Yes | Test pattern label (`unit`) |

**Emission point**: `run-auto-sub.sh` `run_phase_with_recovery()`, after `wrapper_exit`, when bats output pattern (`N tests, N failures`) is found in the code phase log file.

## New Events (introduced in #654)

### 7. `auto-session-report-published`

**Deprecated** — this event was tied to the `--narrative-draft` flag, which was removed in #776. No code path currently emits this event.

```json
{
  "ts": "2026-06-15T12:00:00Z",
  "issue": 0,
  "event": "auto-session-report-published",
  "session_id": "abc-999",
  "report_path": "docs/reports/auto-session-abc-999-2026-06-15.md"
}
```

| Field | Required | Description |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC timestamp |
| `issue` | Yes | Always `0` (session-level event, not tied to a specific issue) |
| `event` | Yes | `"auto-session-report-published"` |
| `session_id` | Yes | Session ID the report was generated for |
| `report_path` | Yes | Path to the generated report file |

**Emission point**: Previously `scripts/get-auto-session-report.sh` after `--narrative-draft` processing. The `--narrative-draft` feature was removed in #776; this event is no longer emitted.

**Scope**: Deprecated — was only emitted when `--narrative-draft` flag was used.
