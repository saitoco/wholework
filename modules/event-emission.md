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

### pr field (review/merge phase events)

For review/merge phase events dispatched via `run-auto-sub.sh`'s `run_phase_with_recovery()`,
the `issue` field always holds the real Issue number (not the PR number the phase was invoked
with) — resolved from `_EXTRA_SELF_ISSUE` (see `run-auto-sub.sh` row in Wrapper Coverage Table below). The PR number
is recorded separately in a `pr` field so both remain traceable without the PR being double-counted
as an independent Issue by `get-auto-session-report.sh` (#987):

```json
{
  "ts": "2026-07-11T00:00:00Z",
  "issue": 987,
  "event": "phase_start",
  "session_id": "abc123",
  "pr": 1001,
  "phase": "review"
}
```

The `pr` field is added only when `EMIT_PR_NUMBER` is set (code phase events, which are called
with the real Issue number directly, never carry a `pr` field).

### wrapper_exit

Emitted by `run-auto-sub.sh`'s `run_phase_with_recovery()` for `code-patch` / `code-pr` / `review` /
`merge`, and by `run-spec.sh` / `run-issue.sh` for their own `spec` / `issue` phase (gated by
`_EMIT_PHASE_OWNED`, same guard as `phase_start`/`phase_complete` — see "`_EMIT_PHASE_OWNED`
pattern" below). In both cases, emitted unconditionally on every `claude -p` subprocess exit
(regardless of the exit code, after any reconcile-based correction). Field: `phase`, `exit_code`.
An external kill that takes down the wrapper itself before this point still leaves `wrapper_exit`
absent for the affected phase — this is the signature `detect-external-kill.sh` relies on, and it
now holds for `spec` / `issue` the same way it already did for `code-patch` / `code-pr` / `review` /
`merge`.

### token_usage

Emitted immediately after `wrapper_exit`, when the `.tmp/token-usage-<issue>.json` file produced
by a `--output-format json` run exists. Written by `run-code.sh` / `run-review.sh` / `run-merge.sh`
(via `run-auto-sub.sh`'s `run_phase_with_recovery()`) and by `run-spec.sh` / `run-issue.sh` directly
for their own phase. Skipped when the file does not exist (e.g. `AUTO_EVENTS_LOG` was unset, so no
`--output-format json` capture ran) or when `usage.input_tokens` is absent from it. Fields: `phase`,
`model` (the `modelUsage` key with the largest `inputTokens + outputTokens`, or `unknown`),
`input_tokens`, `output_tokens`, `cache_read_tokens`.

## Usage

### Required environment variables

| Variable | Set by | Description |
|----------|--------|-------------|
| `AUTO_EVENTS_LOG` | wrapper | Path to JSONL log (default: `.tmp/auto-events.jsonl`) |
| `AUTO_SESSION_ID` | wrapper (from `.tmp/auto-session-{PGID}`) | Identifies the `/auto` session |
| `EMIT_ISSUE_NUMBER` | wrapper | Issue number for the current phase |
| `EMIT_PHASE_NAME` | wrapper | Phase name (see Wrapper Coverage Table below) |

### Optional environment variables

| Variable | Set by | Description |
|----------|--------|-------------|
| `EMIT_PR_NUMBER` | `run-auto-sub.sh` (review/merge phase calls only) | PR number, recorded in a separate `pr` field alongside the real Issue number in `EMIT_ISSUE_NUMBER` (see "pr field" above) |

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
| `run-issue.sh` | `issue` | Added in #769. Also emits `wrapper_exit`/`token_usage` for `phase=issue` (#1228) |
| `run-spec.sh` | `spec` | Added in #769. Also emits `wrapper_exit`/`token_usage` for `phase=spec` (#1228) |
| `run-code.sh` | `code-pr` \| `code-patch` \| `code` | Selects based on route flag |
| `run-review.sh` | `review` | |
| `run-merge.sh` | `merge` | |
| `run-auto-sub.sh` | Sets `EMIT_PHASE_NAME` before delegating | Orchestrator; delegates to above. For review/merge phase calls, resolves `EMIT_ISSUE_NUMBER`/`EMIT_PR_NUMBER` from `_EXTRA_SELF_ISSUE` so the real Issue number (not the PR number) lands in the `issue` field (#987) |

## Non-Wrapper Emitters

`skills/verify/SKILL.md` emits `phase_start`/`phase_complete` (phase=`verify`) inline — directly from the skill body, gated only on `AUTO_EVENTS_LOG` being set — rather than through a `run-*.sh` wrapper. This is intentional: `/verify` has no `run-verify.sh` wrapper (removed in #485 when `/verify` moved to in-session execution), so the `_EMIT_PHASE_OWNED` pattern above, which lives in wrapper scripts, does not apply. `phase_complete` fires at every terminal branch of Step 11 (PASS/SKIPPED, FAIL retry, FAIL max-iterations, PENDING, UNCERTAIN) — not only on full PASS — because reaching an AC verdict, not the verdict itself, is the phase's completion signal. The skill also emits `verify_user_confirm` (phase-specific event, not a lifecycle event) at Step 8b whenever the interactive-mode manual-AC `AskUserQuestion` receives a response.

**`restore_auto_session_pointer()` (Issue #902 Fix Cycle, resolution order revised in #1075)**: `scripts/emit-event.sh` defines this helper to cover a gap specific to non-wrapper emitters. Wrapper scripts (`run-code.sh`, `run-review.sh`, `run-merge.sh`) export `AUTO_EVENTS_LOG`/`AUTO_SESSION_ID` before spawning the nested `claude -p` process, so every Bash tool call inside that nested session inherits them as OS environment variables. `/verify` has no wrapper — when invoked via an in-session `Skill()` call (e.g. `/auto --batch` List mode), it runs as a series of independent Bash tool calls in the parent session, each a new process group that does not inherit env vars set by a sibling call.

Every `AUTO_EVENTS_LOG`-gated emit site in `skills/verify/SKILL.md` calls `source emit-event.sh` + `restore_auto_session_pointer $NUMBER` immediately before the guard, which resolves `AUTO_SESSION_ID`/`AUTO_EVENTS_LOG` in this order (exhaustive):

1. `AUTO_EVENTS_LOG` already set — no-op, return immediately (existing behavior preserved)
2. `AUTO_SESSION_ID` already set — adopt it directly. This is the in-band hand-off path (see `persist_auto_session_pointer()` / `--session-id` below) and also fixes a prior bug where a pre-set `AUTO_SESSION_ID` with no matching pointer file left `AUTO_EVENTS_LOG` unset and silently skipped the emit
3. the optional issue-number argument is given and `.tmp/auto-session-issue-<N>` exists — adopt it
4. `.tmp/auto-session-<PGID>` exists — adopt it
5. `.tmp/auto-session-current` exists — adopt it (final fallback; under concurrent `/auto` sessions this file is a single PGID-independent global that any session may have last overwritten, so it does not guarantee attribution accuracy — see the Concurrent-session attribution problem below)
6. none of the above — no-op, preserving the existing policy that standalone `/verify` runs (outside any `/auto` session) stay uninstrumented

issue-scoped (step 3) is checked before PGID (step 4) because in-session `/verify` never has a matching PGID pointer (each Bash tool call gets a fresh process group), and OS PGID reuse could otherwise pick up a stale pointer left by an unrelated session.

**`persist_auto_session_pointer()` and `--session-id` in-band hand-off (Issue #1075)**: `scripts/emit-event.sh` also defines `persist_auto_session_pointer(session_id, issue_number)`, which writes `session_id` to the issue-scoped pointer file `.tmp/auto-session-issue-<issue_number>` (or deletes it when `session_id` is empty — a standalone `/verify`'s self-healing path for a stale pointer left by a prior `/auto` session that never reached verify). `/auto` passes its own `SESSION_ID` (recorded in Step 1) as `--session-id=<literal SESSION_ID>` in every `Skill(skill="wholework:verify", ...)` dispatch's `args`; `/verify` Step 1 parses that flag and calls `persist_auto_session_pointer` with it immediately after the phase banner, before the `phase_start` emit. This in-band hand-off is the authoritative path (resolution order step 2 above adopts it directly once set), and the issue-scoped pointer it writes is what carries that same value to all 11 `restore_auto_session_pointer $NUMBER` emit sites in `/verify` within the same run (each a separate Bash tool call / PGID, including the Step 1 `phase_start` emit that immediately follows the `persist_auto_session_pointer` call). Both together solve the concurrent-session attribution problem described next: the caller's own id travels with the call instead of being inferred from a shared file.

**Concurrent-session attribution problem (Issue #1075, motivating the above)**: before this resolution order existed, in-session `/verify` always fell through to `.tmp/auto-session-current` (step 5) — the issue-scoped pointer, `AUTO_SESSION_ID`-already-set path, and `persist_auto_session_pointer()` itself did not exist — because PGID (step 4) never matches for `/verify`'s own Bash tool calls. Since `.tmp/auto-session-current` is a single PGID-independent global file that every `/auto` session's Step 1 unconditionally overwrites, two or more concurrent `/auto` sessions produced timing-dependent misattribution: whichever session wrote the file last "won" it for every other session's in-session `/verify` emits, observed in production for `phase_start`/`phase_complete` (2026-07-29), `retro_proposal_classified` (bidirectional, 2026-08-06), and `run-auto-sub.sh --write-manual-recovery`'s `manual_intervention` event (2026-08-05 — a second gap, since that subcommand's single Bash tool call also never regenerates the PGID pointer; see `skills/auto/SKILL.md` Step 6's pointer-regeneration instructions for the fix). `.tmp/auto-session-current` itself was not removed (see Notes below) — it remains step 5's last-resort fallback for callers that cannot supply an issue-scoped or in-band id.

**Worktree-CWD independence (Issue #1006)**: `/verify` Step 3 (Worktree Entry) switches CWD into its own `verify/issue-N` worktree before Step 11's FAIL-branch emits run, so a purely CWD-relative pointer lookup (`.tmp/auto-session-current`) silently fails there — `.tmp/` is gitignored and does not exist in a fresh worktree. `restore_auto_session_pointer()` resolves the main repository root via `git worktree list --porcelain` (the same idiom used by `scripts/detect-foreign-worktree.sh` and `scripts/run-code.sh`) and prefixes both the pointer file search (including the issue-scoped pointer added in #1075) and the resulting `AUTO_EVENTS_LOG` with that root, so the FAIL-branch events (`verify_reopen_cycle`, `verify_fail_marker_posted`, `verify_retry_fire`, and the branch's `phase_complete`) resolve correctly regardless of which worktree the caller's CWD is in. Outside a git repository (e.g. bats tmpdir fixtures), `git worktree list` fails and the prefix stays empty, preserving the prior CWD-relative fallback.

**`retro_proposal_classified` (Issue #1159, issue-scoped resolution added in #1075)**: emitted by `modules/retro-proposals.md` — not a `run-*.sh` wrapper — right after Tier classification is finalized for each improvement proposal, from all three of its callers: `/verify` Step 16, `/auto` Step 4a step 6, and `/auto` Step 5 L3 auto-retrospective step 6. Like the other non-wrapper emitters above, it calls `source emit-event.sh` + `restore_auto_session_pointer` immediately before the `AUTO_EVENTS_LOG` guard, and skips the emit entirely when `AUTO_EVENTS_LOG` stays unset (no `/auto` session pointer to restore from). When `NUMBER` is a bare integer, it is passed to `restore_auto_session_pointer` so the issue-scoped pointer resolves ahead of PGID/current; because `retro-proposals.md` can also run with a non-numeric `NUMBER` (the `/auto` L3 route's `BRIDGE_NUMBER="batch-<session-id>"`), in that case it passes `EMIT_ISSUE_NUMBER=0` and calls `restore_auto_session_pointer` with no argument, to avoid corrupting the unquoted `"issue":${_issue}` field `emit_event()` writes. For that non-numeric-`NUMBER` case, the `/auto` parent-session callers (Step 4a step 6 / Step 5 L3 step 6) instead set `AUTO_SESSION_ID="<literal SESSION_ID>"` explicitly before calling `restore_auto_session_pointer` — resolution order step 2 above adopts it directly, which is the only reliable path when the issue-scoped pointer (step 3) is unavailable.

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
