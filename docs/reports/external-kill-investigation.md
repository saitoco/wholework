# External Kill Investigation

**Report date**: 2026-07-13
**Issue**: #1005
**Scope**: root-cause investigation of the recurring external kill of background `run-auto-sub.sh` / `run-code.sh` wrappers during `/auto --batch` sessions

## Background

`/auto --batch` session 37830-1783901301 (2026-07-13, Issues #998 #1000 #1003) hit 4 external kills of background `claude -p` phases (via `run-auto-sub.sh` / `run-code.sh`) within a single batch. Combined with 3 prior occurrences in the preceding batch (session 11543 series, 2026-07-12), this is 7 occurrences total — a high enough recurrence rate to warrant investigation. None of the 7 were watchdog kills (the watchdog only ever logged "still waiting" heartbeats, never reached its kill threshold) or user-initiated kills.

Every occurrence recovered via parent-session-driven respawn (label-as-SSoT + `code_phase_milestone` resume, or spec-skip re-spawn), but that recovery path sits outside the Tier 1/2/3 recovery machinery and left no record anywhere — see #1005's Background for the full framing and the resulting Metrics gap this report's companion implementation (the `--write-manual-recovery` extension) addresses.

## Investigation Findings

**F1 — Killed phases have no `wrapper_exit` event.**
`docs/sessions/37830-1783901301-2026-07-13/events.jsonl` shows all three killed phases (#998 code-pr: 00:29:23Z `phase_start` → next event 00:41:09Z `sub_start`; #1000 code-pr: 02:46:32Z → 03:08:35Z; #1003 code-patch: 04:06:15Z → 04:08:13Z) end with no `wrapper_exit` event. `run_phase_with_recovery()` emits `wrapper_exit` unconditionally regardless of the child process's exit code, so its absence means **`run-auto-sub.sh` itself was killed** — not just the leaf `claude -p` process it launched.

**F2 — No backfilled `phase_complete` via the EXIT trap either.**
`_maybe_emit_phase_complete()` (the EXIT trap installed near the top of `run-auto-sub.sh`) fires on exit 0 or 143 (SIGTERM) and backfills a `phase_complete` event when the last observed event was `phase_start`. None of the 3 occurrences produced this backfill event. Combined with F1, this points to **SIGKILL** (which bypasses EXIT traps entirely) rather than SIGTERM, taking down the wrapper's entire process group at once.

**F3 — Wrapper logs cut off mid-heartbeat, no exit trailer.**
`.tmp/wrapper-out-998-code-pr.log` ends on a "silent for 480s" watchdog heartbeat line; `.tmp/wrapper-out-1000-code-pr.log` ends on "silent for 1260s". Neither has the `Exit code:` trailer line that normal wrapper completion (success or failure) always appends. The watchdog itself did not kill either phase: the code phase's configured timeout is 4680s, far beyond the largest observed silent window (1280s).

**F4 — No jetsam (macOS OOM kill) evidence.**
`/Library/Logs/DiagnosticReports/` (36 files) and `~/Library/Logs/DiagnosticReports/` (34 files) contain zero `JetsamEvent-*` reports. jetsam kills always leave a report of this form, so the memory-pressure OOM-kill hypothesis is not supported by the available evidence.

**F5 — Time-to-kill is not fixed.**
#1003 code-patch: ~2 minutes. #998 code-pr: ~12 minutes. #1000 code-pr: ~22 minutes. This rules out a fixed-duration timeout as the trigger.

**F6 (design implication) — `retry-on-kill` structurally cannot cover this class of kill.**
`run_with_retry_on_kill()` (Layer B, see `modules/orchestration-fallbacks.md#wrapper-retry-on-kill`) executes *inside* `run-auto-sub.sh`'s own process. When the wrapper's whole process group is SIGKILLed (F1/F2), Layer B is killed along with everything else and never gets a chance to observe or react. The parent `/auto` session — running in a separate process outside the killed group — is therefore the **only actor capable of observing and recovering from this class of kill**. This is the design basis for `modules/orchestration-fallbacks.md#external-kill-parent-respawn` and for extending `--write-manual-recovery` (rather than attempting in-wrapper self-detection) in this Issue.

## Additional Investigation (macOS unified log)

Per the Spec's uncertainty resolution plan, the following query was run against the unified log for the kill window of the first occurrence (kill time 2026-07-13 09:41 JST, i.e. 2026-07-13 00:41 UTC — the query below uses the local system's log timestamps, which matched JST at the time of the original investigation):

```bash
log show --start "2026-07-13 09:35:00" --end "2026-07-13 09:45:00" \
  --predicate 'eventMessage CONTAINS[c] "memorystatus" OR eventMessage CONTAINS[c] "jetsam" OR eventMessage CONTAINS[c] "SIGKILL"' \
  --style compact
```

**Result**: the query returned **zero matching entries**. The unified log was confirmed reachable and populated for this window (an unfiltered `log show` over the same 10-minute range returned 30,961 lines, and a spot-check at the window start returned normal application log traffic), ruling out "log retention already expired" as the explanation for the empty result. This is a genuine negative result: no `memorystatus`, `jetsam`, or `SIGKILL` string appears anywhere in the unified log for this window, which is consistent with F4 (no jetsam-class OOM kill) but does not by itself identify what *did* send the kill signal — `SIGKILL` delivery does not always produce a corresponding unified-log message from the sender, so a negative result here does not rule out any of the remaining hypotheses below.

## Remaining Hypotheses (unverified)

- **H-a**: Claude Code harness background-Bash-task lifecycle (context compaction, turn-boundary cleanup, or a task reaper) sends SIGKILL to the process group
- **H-b**: Terminal/shell-side process-group kill (e.g. a parent shell or terminal session ending and taking its process group with it)
- **H-c**: Something outside H-a/H-b (unidentified)

None of these could be confirmed or ruled out with the evidence gathered in this investigation. The unified-log negative result (above) is compatible with all three — a harness-internal kill (H-a) would not necessarily log through the unified logging system at all.

## Future Observation Plan

The recording mechanism added by this Issue (`--write-manual-recovery` extended to also write `docs/reports/orchestration-recoveries.md` and emit a `manual_intervention` event — see `modules/orchestration-fallbacks.md#external-kill-parent-respawn` and `#manual-recovery-spec-write`) means every future external-kill-and-respawn cycle now accumulates two new data points it previously did not:

1. A `## <date> UTC: manual-recovery-respawn` entry in `docs/reports/orchestration-recoveries.md`, giving `scripts/collect-recovery-candidates.sh` a frequency signal across Issues (and triggering `recoveries-auto-fire` once the configured threshold is reached)
2. A `manual_intervention` event in `.tmp/auto-events.jsonl` with `wrapper_exit_code` recorded — when the parent session can observe the wrapper's actual exit code (137 vs. 143 vs. `unknown`), this starts to distinguish SIGKILL-class terminations from SIGTERM-class ones across occurrences, which the 7 cases investigated here could not do individually (see F2: none of them left an exit code behind at all)

If the recurrence rate stays high after this mechanism ships, the accumulated `wrapper_exit_code` distribution and inter-occurrence timing (F5 showed no fixed duration) across a larger sample should narrow H-a/H-b/H-c further than this single-session investigation could.

## 2026-07-15 Update (Issue #1014)

The recording mechanism from the Future Observation Plan above shipped and accumulated 6 more `manual-recovery-respawn` occurrences (#1006 ×2, #1007 ×2, #1012, and this Issue's own `/spec` phase — see `docs/reports/orchestration-recoveries.md`), bringing the combined total across both investigations to 13. This section documents the additional findings from that accumulated sample and the mitigation decision this Issue made as a result.

**All 13 occurrences happened during an `/auto --batch` session.** The original 7 (Background above) were explicitly `/auto --batch` sessions 37830-1783901301 and the 11543 series. The 6 new occurrences trace to two more batch sessions: `33265-1783950923` (#1006, #1007 — confirmed via the `next_cycle_seeded` event's `batch_session_id` field) and `12825-1784042432` (#1012, and this Issue's own spec-phase kill — confirmed via `.tmp/auto-batch-state-81514-1784042456.json`'s `remaining`/`completed` lists). No single-shot `/auto`, `/spec`, or `/code` invocation has produced this symptom to date.

**A phase-correlated signal-type split, on a small sample.** Filtering `.tmp/auto-events.jsonl` for `"backfilled":true` `phase_complete` events narrowed to the relevant issues/sessions surfaces exactly 2 hits, both `"phase":"spec"` (#1006 and this Issue's own #1014 spec-phase kill) — meaning those two killed wrappers' EXIT trap *did* fire (consistent with SIGTERM). The other 4 recorded occurrences (#1012 code-patch, #1007 review, #1007 code-pr, #1006 code-pr) have no backfilled `phase_complete` at all (consistent with SIGKILL, matching F1/F2 above). The 2-vs-4 split is too small to be conclusive, but it is the first evidence that the external kill is not a single uniform signal across phases — recorded here as a trend for future samples to confirm or refute, not a settled conclusion.

**The `wrapper_exit_code` data source the Future Observation Plan was counting on is not producing data.** All 6 new `manual_intervention` events have `"wrapper_exit_code":"unknown"` (6/6). Inspecting `scripts/run-auto-sub.sh`'s `--write-manual-recovery` subcommand shows why: it takes the exit code as a caller-supplied argument (`_mr_exit_code="${4:-}"`) with no code path that captures the OS-level exit status of the killed wrapper itself — because, by definition of this symptom (F1/F2), the wrapper's own process group is gone before it can record anything about its own exit. The parent `/auto` session that performs the respawn also has no way to observe that exit code after the fact. This means the 137-vs-143 exit-code distribution the Future Observation Plan was designed to accumulate is not, in practice, obtainable through this path — every future occurrence recorded via `--write-manual-recovery` will also read `unknown` unless the recording path itself changes.

**Mitigation decision: automate the respawn detection, not the root-cause elimination.** Issue #1014's Purpose allows either resolving the underlying kill source or automating the respawn. Given the finding above — the primary planned data source for narrowing H-a/H-b/H-c is structurally non-functional — there is no new verifiable lead to chase for root-cause elimination beyond what this report already covers. This Issue instead implements `scripts/detect-external-kill.sh`, which mechanizes the detection signature previously described only in prose in `skills/auto/SKILL.md` Step 6 (exit code 137 alone, or 143/`unknown` combined with both the wrapper-log trailer and the `auto-events.jsonl` `wrapper_exit` event being absent) so the respawn decision no longer depends on an LLM re-deriving the condition from text each time. H-a/H-b/H-c remain open; further root-cause work is deferred until a new, independently verifiable signal emerges.
