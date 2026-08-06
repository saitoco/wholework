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

## 2026-07-15 Update (H-a isolation experiment, session 32651-1784096613)

The user explicitly restarted the terminal and Claude Code session (previous sessions had run continuously across 5 batches and multiple context compactions) and switched the parent model from Fable 5 to Sonnet 5, specifically to test whether the kill rate changes in a fresh, young session — a direct test of H-a (harness background-task reaper triggered by long session lifetime). `/auto --batch 1017 1010 1009 994 993` was run as the comparison batch.

**Result: kills continued at an undiminished rate in the fresh session.** 5 external-kill occurrences were recorded across 4 of the 5 issues processed (`manual_intervention` count: 5, confirmed via `docs/reports/orchestration-recoveries.md` and `.tmp/auto-events.jsonl`): #1017 code-pr, #1010 spec, #1009 spec, #1009 review, #994 issue (this last one occurred after the phase's actual work had already completed — no respawn needed, recorded via `--write-manual-recovery` only). The batch's 5th issue (#993) completed with zero kills, so the rate was not uniform even within this one fresh session — but 5 occurrences in a single ~1-hour batch is not a reduced rate relative to the prior investigation windows.

**Read on H-a**: this is negative evidence against the "long-lived session task reaper" hypothesis in its simple form — the session was newly started (session_start 06:23:36Z) and the first kill (#1017 code-pr) had already occurred by the time that phase's respawn completed at 07:22Z, under an hour in. It does not rule out a more general per-background-task reaper unrelated to session age (still a form of H-a), nor does it implicate or clear the Fable→Sonnet parent model switch either way, since no kills were observed to correlate with which model issued the `claude -p` call specifically (all killed phases run via `run-*.sh` wrappers regardless of parent model). H-b and H-c remain equally uninformed by this data point.

**Phase-correlated signal-type split — additional confirming sample.** Of the 5 occurrences this session, the `phase_complete` backfill (EXIT-trap-fired, SIGTERM-consistent) pattern held again: #1010 spec and #1009 spec both backfilled; #994 issue phase also backfilled (a first data point for the `issue` phase specifically — previously only spec/code-patch/review/code-pr had been sampled). #1017 code-pr and #1009 review both showed no backfill at all (SIGKILL-consistent), consistent with F1/F2 and the #1014 finding. This session alone: 3 backfilled (issue×1, spec×2) vs. 2 non-backfilled (code-pr×1, review×1) — directionally consistent with the #1014 sample (spec/issue-phase kills tending to backfill, code-pr/review-phase kills tending not to), though the combined sample across all three investigation windows remains small enough that this should still be read as a trend, not a settled conclusion.

**`wrapper_exit_code` still unobtainable.** All 5 new `manual_intervention` events again recorded `"wrapper_exit_code":"unknown"` (5/5), consistent with the prior finding that this data path is structurally unable to produce the exit code.

## 2026-08-01 Update (Issue #1135: wrapper_alive correlation + isolation experiment / 実行サーフェス切り分け実験)

This update resumes the investigation using the two leads that accumulated since 2026-07-15: the `wrapper_alive` checkpoint events introduced by #1045 (PR #1048, merged 2026-07-23), and a controlled execution-surface isolation experiment (切り分け実験). Data sources are the committed session logs `docs/sessions/25766-1785288928-2026-07-29/events.jsonl` and `docs/sessions/46196-1785292524-2026-07-31/events.jsonl` — the live `.tmp/auto-events.jsonl` is session-local and gitignored, so it retains no historical data.

**wrapper_alive × kill correlation: all 3 checkpoint-bracketed kills happened mid-subprocess.** Correlating `wrapper_alive` checkpoints with `manual_intervention` (kill) records in the 7/29–7/31 window yields 3 kills bracketed by checkpoints:

| Kill | Last checkpoint before silence | `wrapper_exit`? | Classification |
|---|---|---|---|
| #1061 kill 1 (code-pr) | `pre_subprocess` 05:35:08Z, then `code_retry_fire` (retry-1 dispatch) 05:50:53Z | absent | mid-subprocess |
| #1061 kill 2 (review) | `pre_subprocess` 06:14:43Z | absent | mid-subprocess |
| #1066 kill (code-pr) | `pre_subprocess` 06:04:08Z (leaf had already committed when killed — recovered via `push-and-pr`) | absent | mid-subprocess |

Combined with the 7/23 #1042 occurrence (killed one second after a clean `wrapper_exit code=0`, i.e., in wrapper control flow between phases — recorded in #1045's writeup), the sample now contains kills both **mid-subprocess and mid-control-flow**. The kill does not correlate with what the wrapper is doing at the moment — consistent with an indiscriminate process-group-level SIGKILL, which supports (but does not by itself confirm) the generalized form of H-a: a harness per-background-task lifecycle action unrelated to session age.

**Execution-surface isolation experiment (実行サーフェス切り分け実験): 0/3 vs 0/3 — no reproduction.** Design: 6 identical read-only workloads (docs-corpus analysis via `claude -p --model sonnet`, each wrapped in a bash wrapper mimicking the `run-*.sh` structure — bash → `claude -p` child in the same process group, with a `WRAPPER_EXIT` log trailer as the kill detector, matching the F1/F2 signature) were launched in the same time window (2026-07-31T19:01:34–19:01:48Z) from the same interactive parent session:

- **Arm A (harness-managed)**: 3 wrappers via the Bash tool with `run_in_background: true` — the same surface where all 30+ production kills occurred. Result: **0/3 kills** (runtimes 3m19s / 3m59s / 6m58s; all `WRAPPER_EXIT code=0`).
- **Arm B (harness-detached)**: 3 wrappers via python3 `subprocess.Popen(..., start_new_session=True)` — the setsid(2) equivalent. Selection rationale: the kill signature is process-group-scoped (F1/F2), so detaching the process group is the most direct test of H-a; macOS ships no setsid(1) binary, hence the python3 substitute. Detachment verified: each wrapper's pgid equals its own pid. Result: **0/3 kills** (runtimes 3m45s / 3m56s / 4m42s).

**Limitations (why this is not a null result for H-a):** (1) actual runtimes were 3–7 minutes — shorter than the intended 10–15 minutes and well below the 15–30 minute pr-route wrappers that showed a 4/4 (100%) kill rate on 7/23; (2) the parent was a single-shot interactive session, not a long-lived `/auto --batch` session — and all 30+ production kills are batch-session-exclusive; (3) n=3 per arm has no statistical power against a kill rate that is bursty even on bad days (7/21 had two fully clean sessions). What the experiment does establish: under single-shot-session conditions with short wrappers, neither surface kills — consistent with the standing observation that single-shot invocations have never produced this symptom.

**Verdicts (判定):**

- **H-a generalized (harness per-background-task lifecycle): 未決 (undetermined).** The wrapper_alive correlation is consistent with it (indiscriminate process-group kill regardless of wrapper activity), but the experiment could not reach the reproduction conditions, so neither confirmation nor refutation. The batch-session-exclusivity of all 30+ occurrences remains the strongest structural hint in this direction.
- **H-b (terminal/shell-side process-group kill): 未決 (undetermined).** Undetectable while the kill does not reproduce. Weak counter-evidence: kills have never occurred in single-shot sessions running in the same terminal.
- **H-c (other): 未決 (undetermined)** — default verdict per the Issue's Auto-Resolve Log.

**Operational workaround:** no new workaround was validated by this experiment (the setsid detachment could not be tested against a reproducing kill). 回避策なし — 既存の respawn 補償層による観測を継続する。The already-observed operational avoidance stands: prefer single-shot `/auto` invocations (never killed to date) over long `--batch` sessions where feasible.

**Next actions / next iteration (designed, not yet run):** reproduce first, then isolate. Run a real `/auto --batch` workload (2–3 real issues, pr-route, 15+ minute wrappers) twice: once with wrappers on the harness-managed surface (control — expected to reproduce at recent rates) and once with the same batch's wrappers detached via `start_new_session` (treatment). If the control reproduces and the treatment does not, H-a is confirmed and the detachment doubles as the fix (feeding the #598 in-session migration re-evaluation and the Anthropic report preparation with 30+ occurrences of reproduction data); if both reproduce, H-a is refuted in favor of H-b/H-c. This requires a detachment flag in `run-auto-sub.sh`'s spawn path and is deliberately sequenced after #1136 (event-log decontamination) lands, so kill-rate metrics are computed from clean data. The #598 icebox re-evaluation trigger ("watchdog kill rate worsens beyond 5.7%") is separately noted as already quantitatively fired (7/23 pr-route 4/4) — posted to #598 as part of this Issue's next-action hand-off.

## 2026-08-01 Addendum (host-uptime / PID-reuse variant of H-b)

Prompted by an operational observation: the host Mac has not been rebooted for an extended period, and the terminal emulator (Ghostty) and tmux sessions have been running equally long. This addendum records whether host/terminal uptime could contribute to the kill, and folds a cheap discriminating step into the next iteration.

**What existing data already says (uptime as a *primary* cause is disfavored):**

1. Single-shot invocations run kill-free on the same long-uptime host/terminal/tmux (0 occurrences to date, including #1135's own verify run) — a pure environment-age cause would not discriminate batch from single-shot.
2. The 2026-07-15 experiment (session 32651) restarted the terminal and Claude Code session and kills continued undiminished — terminal-process uptime alone is already refuted in that direction. Host (kernel/OS) uptime, however, was **not** reset in that experiment and remains unfalsified.
3. No jetsam/OOM evidence (F4) and no SIGKILL trace in the unified log; resource exhaustion from long uptime would typically surface there, or as spawn failures rather than the disappearance of running process groups. tmux/Ghostty have no ordinary code path that SIGKILLs a process group (session teardown sends SIGHUP, which does not match the F1/F2 signature).

**The one uptime-correlated mechanism that fits the batch-exclusivity: PID/PGID reuse.** On a long-uptime host, macOS PID numbers wrap (max 99999), and a `/auto --batch` session spawns processes at a rate far exceeding single-shot use — raising the probability that a PID/PGID recorded earlier by some managing layer (e.g., the harness's background-task tracking) is later reused by an unrelated process group. A stale-PGID kill issued after reuse would look exactly like the observed signature: an indiscriminate process-group SIGKILL uncorrelated with what the wrapper is doing. This variant is consistent with (a) batch-exclusivity via spawn volume, (b) the terminal-restart experiment's null result (PID space is kernel state, not reset by terminal restart), and (c) the absence of jetsam/log traces. It is recorded here as an unverified hypothesis — no direct evidence yet.

**Discriminating step added to the next iteration (order matters — do not reboot ad hoc):**

1. After #1136 lands, reproduce first on the **current, long-uptime environment** (control arm of the next iteration above).
2. If reproduction succeeds, **reboot the host Mac** (resetting PID space and all accumulated kernel/launchd state) and re-run the identical control workload once. Kill rate collapses after reboot → the uptime/PID-reuse variant (H-b') becomes the leading hypothesis; kill rate unchanged → H-a (harness lifecycle, uptime-independent) is further strengthened.
3. Only then proceed to the `start_new_session` detachment (treatment) arm comparison.

Rebooting before step 1 would destroy the reproduction baseline and muddy the isolation — the reboot is itself one of the experiment's arms, not maintenance.

## 2026-08-03 Update (Issue #1142 Arm 1: control reproduction attempt — 再現条件に未到達 / no reproduction)

The 3-arm experiment's Arm 1 (control: current long-uptime host, harness-managed spawn, `WHOLEWORK_SPAWN_DETACH` unset) ran as a real `/auto --batch`-equivalent workload — 3 real backlog issues (#1129 M pr-route, #1104 M→patch after post-spec demotion, #1101 M pr-route) processed serially from an interactive parent session with no concurrent sessions (session 64199-1785717064, 2026-08-03 00:33–03:37 UTC).

**Result: 0 kills across 6 background wrappers / 13 phase subprocesses (~3 hours wall-clock).** All wrappers emitted their `wrapper_exit` trailers with exit 0. The workload included the exact conditions that showed a 4/4 (100%) kill rate on 7/23: continuous wrapper lifetimes of 41 / 43 / 63 minutes and four 15-minute-plus phase subprocesses (review 17m, code-patch 25m, code-pr 25m, review 16m).

| Wrapper | Lifetime | Phases (subprocess durations) | Kills |
|---|---|---|---|
| #1129 run-issue | 6m | issue | 0 |
| #1129 run-auto-sub | 41m | spec 12m / code-pr 9.5m / review 17m / merge 2m | 0 |
| #1104 run-issue | 5m | issue | 0 |
| #1104 run-auto-sub | 43m | spec 18m / code-patch 25m | 0 |
| #1101 run-issue | 5m | issue | 0 |
| #1101 run-auto-sub | 63m | spec 18m / code-pr 25m / review 16m / merge 4m | 0 |

**Interpretation (facts vs. readings):** The non-reproduction is consistent with at least three readings, none of which this single window can separate: (a) **burstiness** — 7/21 already showed two consecutive fully-clean sessions in the middle of the kill wave, so one clean 3-hour window is weak evidence of absence; (b) **environmental change** — the kill wave's onset correlated with the 6/30–7/1 model/harness deployments, and a subsequent harness update (late July / early August) may equally have removed the trigger; (c) **condition mismatch** — this parent session started as a single-shot `/auto` and grew into batch orchestration, whereas the July kill sessions were `/auto --batch` from the start; if the trigger keys on something established at batch-session start, this window may not have armed it. Per the experiment design, Arms 2 (host reboot) and 3 (detached spawn) were **not run** — with zero kills in the control arm there is nothing to isolate against, and running them would produce uninterpretable "0 vs 0" comparisons.

**Verdicts: unchanged.** H-a generalized / H-b' (PID-reuse) / H-b all remain 未決 (undetermined). No new evidence for or against any of them.

**Redesign plan (再設計方針):**
1. **Repeat Arm 1 opportunistically** — treat every future real `/auto --batch` run (starting the session as `--batch` from the outset, matching the July condition) as an Arm 1 window, recording kill rate per wrapper in this report. No dedicated workload is spent on this; normal backlog consumption doubles as the experiment.
2. **Arm 2/3 are armed and standing by** — the `WHOLEWORK_SPAWN_DETACH` flag is implemented and tested (PR #1143); the moment any future window reproduces a kill, run the reboot arm and the detach arm against the then-current conditions per the 2026-08-01 Addendum sequence.
3. **Expiry criterion** — if no external kill is observed across 2 weeks of normal batch operation (through ~2026-08-17), conclude "trigger removed by environment change (likely harness update), root cause unidentified but moot," close the H-a/H-b'/H-b line of investigation as overtaken by events, and file the respawn-compensation-layer slimming decision (#1070/#1081/#1093/#1119 scope reduction) plus the #598 re-evaluation with that conclusion as input. **(Revised 2026-08-05 — see the criterion revision below; the conclusion clause of this item no longer stands.)**

## 2026-08-05 Update (upstream issue cross-reference — anthropics/claude-code)

Every section above reasons exclusively from local data. A search of the `anthropics/claude-code` issue tracker on 2026-08-05 found the same symptom reported independently by other users on the same tool surface (Bash tool with `run_in_background: true`), including one report filed **2026-08-04 against 2.1.221 — the exact version this host runs**. This is the first external corroboration this investigation has had, and it moves two things: the evidentiary basis for H-a, and the validity of the expiry criterion above.

### Three near-identical upstream reports (all OPEN, none with an Anthropic response)

| Issue | Filed / CC version | Platform | Reported signature |
|---|---|---|---|
| [#76974](https://github.com/anthropics/claude-code/issues/76974) | 2026-07-12 / 2.1.207 | Linux (Debian 13, tmux) | Process-group SIGKILL of background Bash tasks by "the CLI's task supervision"; 1.45% of 965 sandboxed background dispatches, 0.84% of 477 unsandboxed, measured over 30 days / 304 sessions / ~28.5k dispatches |
| [#76942](https://github.com/anthropics/claude-code/issues/76942) | 2026-07-12 / 2.1.207 | macOS (Terminal.app) | External SIGTERM mid-run, "only after a session runs long"; first tasks in a session complete, later ones die at progressively different points |
| [#83814](https://github.com/anthropics/claude-code/issues/83814) | 2026-08-04 / **2.1.221** | macOS | Exit 143 on 10–60 min background tasks (headless `claude -p` / `codex exec` subprocesses) in long-lived interactive sessions |

**#76974 independently reproduces F1/F2/F4/F5 with kernel-level evidence this investigation could not obtain on macOS.** Its author correlated killed tasks against Linux process accounting (`acct`) and the kernel journal:

| This report's finding | #76974's independent observation |
|---|---|
| F1 — the wrapper's whole process group dies, not just the leaf | Every process in the task tree (`bash` + `git` + grandchildren) carries the acct "killed by signal" flag at the same death instant — a process-group signal |
| F2 — no EXIT-trap backfill, pointing to SIGKILL | "Trap handlers never fire (EXIT traps produce no output), consistent with SIGKILL specifically" |
| F4 — no jetsam/OOM evidence | Zero kernel OOM lines across the observation window; session cgroup had no memory limit |
| F5 — time-to-kill is not fixed (2–22 min) | Kills at 28–136 s, one at 317 s, one at 3600.4 s, while other tasks ran 2 h+ untouched |
| 2026-08-03 Arm 1: 0 kills across a 3-hour window | "Kills are **BURSTY** — several within a few minutes, then days of silence — suggesting an episodic supervision state rather than per-job decisions" |
| Batch-session exclusivity (30+ occurrences, never single-shot) | Foreground Bash calls effectively immune (2 lost of 27,032 ≈ 0.007%) vs. 1.45% for background; user-typed `!` commands never enter the task-supervision tree at all |

The last row is the sharpest external match: both datasets say the discriminator is **which supervision tree the process lands in**, not what the process does. #76942's corroborating comment (2026-07-20, 2.1.214, macOS, ~11 occurrences) adds that an immediate identical relaunch succeeds ~11/11 — the same "respawn always works" property our compensation layer relies on.

### Lead 1 — a single mechanism that explains the phase-correlated SIGTERM/SIGKILL split

[#82586](https://github.com/anthropics/claude-code/issues/82586) (2026-07-30, 2.1.220) reports, from third-party inspection of the CLI bundle, that the harness's own task-kill path is **SIGTERM to the task shell, followed by a delayed SIGKILL to its process group**. If that is accurate, the "phase-correlated signal-type split" recorded in the #1014 and 2026-07-15 sections is not phase-dependent at all: it is a race against that grace window. Whether a killed wrapper leaves a backfilled `phase_complete` depends only on whether its EXIT trap finished before the follow-up SIGKILL landed — and short phases (`spec`, `issue`) plausibly have less trap work in flight than long ones (`code-pr`, `review`). This subsumes the two-vs-four and three-vs-two splits under one mechanism and removes the need to explain a phase dependency that may never have existed.

This is a third-party reverse-engineering claim, not an official statement, and we have not verified it. Recorded as the leading explanation of the split, superseding nothing in the observational record.

### Lead 2 — an observable discriminator the parent session already receives

The same report states that the two kill origins are distinguishable from the **task notification text alone**: the harness's own stop path renders `status: killed` / "Background command … was stopped", whereas a genuinely external signal renders "failed with exit code N" (verified there against a `pkill` control case that surfaced as exit 144). #82586 also observed one killed task's child in a *different* process group surviving orphaned and completing 10 minutes later — consistent with a group-scoped harness kill, inconsistent with a pattern-matching external killer.

This matters because the `wrapper_exit_code` channel the 2026-07-15 section found structurally unobtainable is not the only signal available: the parent `/auto` session receives the task notification directly, and its wording is a free harness-vs-external discriminator that we have never recorded. Tracked as **#1153**.

### Lead 3 — the expiry criterion's conclusion clause is contradicted

The 2026-08-03 Redesign plan's item 3 would conclude, on 2 quiet weeks, that the trigger was "removed by environment change (likely harness update)". That clause is now directly contradicted: #83814 is an active report of this exact symptom on 2.1.221, filed 2026-08-04, and CHANGELOG entries for 2.1.217 through 2.1.221 contain no fix for this class. Combined with #76974's burstiness finding (days of silence between bursts is the normal shape) and its ~1.45%-per-dispatch base rate, a quiet local window is much weaker evidence of upstream repair than the criterion assumed.

**Revised criterion**: a quiet window through ~2026-08-17 supports only "not reproducing locally under current conditions" — it does not license the "trigger removed upstream" conclusion, and therefore does not by itself justify retiring the respawn compensation layer. The Arm 2/3 standby and the compensation layer both remain warranted while the upstream issues are open and unanswered. The #598 / #596 re-evaluation inputs are unchanged in kind but should now carry the upstream reports as evidence rather than a local-only inference.

### Precedent: this bug class is real in the harness

[#72660](https://github.com/anthropics/claude-code/issues/72660) (closed 2026-07-04 as a duplicate of #72233) captured, via `strace`, a Claude Code background-agent daemon issuing `kill(0, SIGKILL)` — a self-directed process-group SIGKILL — on a ~50-second idle timer, taking down every background task sharing that group (699 daemon starts vs. 53 graceful shutdowns in one log). That is not our symptom (different component, different cadence, and it was fixed), but it establishes that harness code paths issuing indiscriminate process-group SIGKILLs exist and have shipped before. Separately, [#59691](https://github.com/anthropics/claude-code/issues/59691) asked whether the documented ~1 h supervisor reaping kills in-flight `run_in_background` children and was closed as stale without an answer — the lifecycle contract H-a depends on is still undocumented upstream.

### Verdicts (判定)

- **H-a generalized (harness per-background-task lifecycle): 未決 (undetermined), but materially strengthened.** Three independent reporters on two platforms describe the same process-group-scoped, activity-uncorrelated, bursty kill of `run_in_background` tasks, with kernel-level evidence (#76974) matching F1/F2/F4/F5. The foreground-vs-background rate gap (0.007% vs 1.45%) localizes the mechanism to the background task-supervision path specifically. This is corroboration, not confirmation: no reporter has identified the sending code path, and Anthropic has not responded to any of the three issues.
- **H-b (terminal/shell-side process-group kill): 未決, weakened.** #76974 reproduces on Linux/tmux and #76942/#83814 on macOS/Terminal.app and zsh — the symptom crosses terminal emulators and shells, which a terminal-side cause would not.
- **H-b' (host-uptime / PID-reuse): 未決, weakened.** Same reasoning: the symptom appears across independent hosts with unrelated uptimes, and #76974's per-dispatch rate is stable enough over 30 days to be hard to reconcile with PID-space wraparound.

### Next actions

1. **#1153** — record the parent-observed task-notification wording on the external-kill recovery path (Lead 2), so the harness-stop vs. external-signal discriminator accumulates across occurrences.
2. **#1146** — apply the revised expiry criterion above at the ~2026-08-17 decision point; a quiet window no longer concludes "trigger removed upstream".
3. **Upstream corroboration (optional, not yet filed)** — our 30+ occurrences with `wrapper_alive` checkpoint correlation and the 0/3-vs-0/3 detachment experiment would add macOS-side depth to #76974, whose kernel evidence is Linux-only. Deferred pending the #1153 notification-class data, which would make the report materially stronger.

## 2026-08-05 Addendum (Arm 1 opportunistic window + concurrent-session hypothesis)

This addendum records a second Arm 1 window run under #1146's opportunistic re-observation policy, and a hypothesis shift that reframes the experiment design.

### Arm 1 window: 0 kills across 3 wrappers (~4.5 hours)

Session `6722-1785907145`, `/auto --batch 1170 1171 1172` — started as `--batch` from session start (matching the July condition), main synced, no leftover wrapper processes at start.

| Wrapper | Lifetime | Route / Size | Result |
|---|---|---|---|
| #1170 run-auto-sub | ~64 min | pr / M | exit 0, `Exit code:` trailer present |
| #1171 run-auto-sub | ~112 min | pr / L | exit 0, trailer present |
| #1172 run-auto-sub | ~96 min | pr / L | exit 0, trailer present |

**0 kills.** All three exceed the 15–30 minute band that showed a 4/4 kill rate on 7/23. Combined with the 2026-08-03 Arm 1 (0 kills / 6 wrappers / ~3 hours), two consecutive Arm 1 windows have now failed to reproduce.

One non-kill anomaly: #1170's spec phase hit a `ff-only-merge-fallback` twice when main advanced under it (a concurrent session's `/verify` commits). Recovered as designed — not an external kill.

### Hypothesis shift: concurrent sessions

Both 0-kill windows share a condition that was imposed for a different reason: **#1142's Spec requires "no concurrent sessions / no concurrent `/auto`" during the experiment (交絡排除)**, and Arm 1 inherits it. If concurrency is the trigger, **Arm 1 cannot reproduce by construction** — the control imposed to remove confounds removes the causal variable.

Supporting observations (user-reported, 2026-08-05):

- The kill-dense window (7/13–7/31) coincides with the period when the real projects **pds / tofas were active**. Both are separate repositories, so their sessions never appear in this repository's `docs/sessions/`.
- The recent clean windows (8/4 session `73536`, 8/5 session `6722`) were run under **deliberate suppression of concurrent sessions** — fully confounded with the "a harness update removed the trigger" reading in the 2026-08-03 Update.
- **Before 7/13, concurrent `/auto --batch` ran reliably.** This argues against concurrency alone and for a combination: *a harness-side change around 7/13 × concurrent execution*.

### Session-overlap analysis (not decisive)

Correlating `docs/sessions/*/events.jsonl` time spans with `manual_intervention` counts:

| Kill-bearing session | Date | Kills | Overlapping session (this repo) |
|---|---|---|---|
| 33265 | 07-13 | 5 | none |
| 12825 | 07-14 | 4 | none |
| 32651 | 07-15 | 5 | none |
| 89630 | 07-20 | 1 | none |
| 5059 | 07-22〜23 | 2 | none |
| 30985 | 07-23 | 3 | none |
| 46196 | 07-29〜31 | 11 | 25766 |

6 of 7 kill-bearing sessions had no overlapping session *in this repository*, and the 13 sessions that did overlap were all kill-free. **This does not refute the concurrency hypothesis** — the analysis cannot measure three things:

1. **Sessions in other repositories (pds / tofas) are entirely invisible** — the largest blind spot, and precisely where the reported concurrency lived
2. **Single-shot `/auto` leaves no session directory** — the L3 retrospective commits `docs/sessions/` only for batch/XL routes, so "no overlap" means "no overlapping *batch* session"
3. **`manual_intervention` events only exist from #1005/#1014 onward (~7/13–15)** — earlier kills register as 0

### Consequences

- **Arm 4 (concurrent-session arm) added to #1146**: run two sessions with `/auto --batch` simultaneously (cross-repo is acceptable and closer to real operation) and compare the kill rate against the single-session arm; if it reproduces, re-run with `WHOLEWORK_SPAWN_DETACH=1` as Arm 4b, which doubles as the workaround validation. The host-reboot arm (Arm 2) moves behind Arm 4, since the concurrent condition looks more likely to reproduce.
- **Expiry criterion revised again**: the 2026-08-03 Redesign plan's "2 quiet weeks → trigger removed" cannot hold while concurrency is deliberately suppressed. #1146 now requires Arm 4a to have run before an expiry conclusion is permitted.
- **Operational impact is now explicit**: being unable to run `/auto` concurrently is a measurable productivity regression relative to pre-7/13 operation. #1146 was re-prioritized (`Priority: high`, Size M) and its scope now includes establishing a usable workaround, not only tracking the investigation.

### Deferred instrumentation (not filed)

A **`concurrency_snapshot` event** — sampling the number of live wholework wrappers via `ps` at session start and at each wrapper spawn — would make concurrency measurable **across repositories**, using only an added event in the existing `auto-events.jsonl` and giving the concurrency level at the moment of each kill directly (rather than by after-the-fact time-span correlation, which carries the three blind spots above). The existing `concurrent_commit_detected` event covers git-level contention, not session-level concurrency; this axis is unfilled. Deliberately not filed as an Issue (2026-08-05) to avoid backlog sprawl; recorded here and in project memory. Worth adding before Arm 4a so that arm's data carries concurrency levels from the start.

Committing a session directory for single-shot `/auto` runs was considered and **rejected**: it would not close blind spot 1 (other repositories), while multiplying directory count and commit frequency for the most common invocation shape — which in turn worsens the `ff-only-merge-fallback` contention observed twice in this very session.

## 2026-08-05 Update (Arm 4a executed — concurrent sessions, 0 kills, confounded by an unplanned host reboot)

Arm 4a (the concurrent-session arm added to #1146 earlier the same day) was executed. It reproduced nothing — but the host was rebooted the previous night, which changes what the null result means.

### Execution

Session `65022-1785935372`, `/auto --batch 1169 1140`, run **deliberately concurrent** with a second session's `/auto --batch 1179 1181 1180` in the same repository. Concurrency was sampled with `ps` (the `concurrency_snapshot` instrumentation is still unimplemented) and recorded in the session metadata as `arm4a_concurrency_baseline`:

- **At session start**: 3 concurrent wholework wrapper processes (other session's `run-auto-sub.sh 1179` + `run-spec.sh 1179`)
- **Throughout**: the other session progressed #1179 → #1181, remaining active for the entire window
- **At session end**: 7 concurrent processes (other session's `run-review.sh 1183` plus its bats subprocess tree)

| Wrapper | Lifetime | Result |
|---|---|---|
| `run-auto-sub.sh 1169` | ~46 min | exit 0, `Exit code:` trailer present |
| `run-issue.sh 1140` | ~5 min | exit 0, trailer present |
| `run-auto-sub.sh 1140` | ~40 min | exit 0, trailer present |

**0 external kills.** Kill determination used the wrapper-log trailer as primary evidence, not `manual_intervention` events — the prior session had shown those events can be misattributed across concurrent sessions (#1075).

### The reboot confound

The host was rebooted on **2026-08-04 23:51 JST** (`kern.boottime`), after more than a month of continuous uptime, forced by an unrelated application problem. Both of 2026-08-05's sessions therefore ran at ~24 hours of uptime.

This means the reboot arm from the 2026-08-01 Addendum (Arm 2, testing the H-b' PID/PGID-reuse variant) was **executed unplanned, and before any reproduction baseline was established** — exactly the sequencing the Addendum warned against ("the reboot is itself one of the experiment's arms, not maintenance").

### The 2×2 as it now stands

|  | Long uptime | Freshly rebooted |
|---|---|---|
| **No concurrency** | 2026-08-03 Arm 1: 0 kills | 2026-08-05 session `6722`: 0 kills |
| **Concurrent** | **2026-07-13〜31: kills (30+)** | 2026-08-05 session `65022` (Arm 4a): **0 kills** |

Kills appear in exactly one cell — the one with **both** long uptime and concurrency. The remaining three cells are all 0. The data is therefore consistent with concurrency alone, uptime alone, or their conjunction; Arm 4a's null result rules out **concurrency alone being sufficient at low uptime**, which promotes the uptime axis (H-b') from "weakened" back to a live co-factor.

### Consequences

- **H-b' (host uptime / PID reuse) is no longer disfavored.** The 2026-08-05 Addendum weakened it on the grounds that the symptom crossed independent hosts; that reasoning stands for *hosts*, but says nothing about the uptime *within* this host, which is what Arm 4a now bears on.
- **The July condition cannot currently be reproduced.** "Long uptime × concurrent" requires uptime to accumulate again. This is a passive wait, not a forcible experiment — the only lever is to avoid rebooting.
- **If the reboot is what stopped it, that is an acceptable outcome.** A periodic reboot is a zero-code, zero-verification-cost workaround that preserves concurrent `/auto` entirely — strictly better than `WHOLEWORK_SPAWN_DETACH`, the foreground migration (#598), or suppressing concurrency. #1146's workaround ordering is revised accordingly.

### Concurrency has a confirmed cost regardless of kills

Even with 0 kills, the concurrent arm produced **1 `ff-only-merge-fallback`** (main advanced 2 commits under a verify worktree; recovered by rebasing the worktree branch) and **3 `concurrent_commit_detected`** events. The single-session arm earlier the same day produced 2 fallbacks under lighter concurrency. Git contention on `main` is a deterministic cost of parallel operation in this repository, independent of the kill question, and it scales with commit frequency — which is why committing session directories for single-shot runs was rejected above.

---

## 2026-08-06 Update (Arm 4a extended — 8h at 2–4 concurrent wrappers, 0 kills, uptime 34→40h)

Session `63129-1785977471` ran `/auto --batch 1175 1174 1076 1188` for **8h21m** (00:51–09:12 UTC) with 2–4 concurrent `claude -p` processes throughout. This is the longest sustained concurrent window measured to date and roughly triples Arm 4a's sample.

### Result: 0 external kills

12 `wrapper_exit` events (4 Issues × code-pr / review / merge). Exactly one was non-zero:

| Issue | Phase | Exit | Classification |
|---|---|---|---|
| #1174 | review | **143** | **watchdog kill, not external** — `Exit code:` trailer present, `wrapper_exit` event present, explicit watchdog diagnosis (2600s silent after CI wait, pid=31881). Tier 3 sub-agent recovered via `action=retry` |

All 11 others exited 0. The detection signature (143/unknown **+** missing trailer **+** missing `wrapper_exit`) was never satisfied.

### Concurrency measured, not assumed

| Time (JST) | Concurrent `claude -p` | Composition | load avg | uptime |
|---|---|---|---|---|
| 10:00 | 0 | other session between wrapper spawns | — | 1d 10h |
| 10:10 | 4 | self 1 + foreign 1 | 2.69 | 1d 10h |
| 11:35 | 4 | **three full bats suites simultaneously** | **5.19** | 1d 11h |
| 11:56 | 3 | self 1 + foreign 2 | 3.13 | 1d 12h |
| 15:56 | 4 | **self 2** + foreign 1 | 3.32 | 1d 16h |

**New axis: intra-session parallelism.** At 15:56 two wrappers ran from the *same* `/auto` session (PGID 25686 — `run-auto-sub.sh 1076` and `run-issue.sh 1188`). Every prior Arm 4a sample was one-wrapper-per-session. No kills resulted.

### The 2×2, updated

|  | Long uptime | Freshly rebooted (≤ ~40h) |
|---|---|---|
| **No concurrency** | 2026-08-03 Arm 1: 0 kills | 2026-08-05 session `6722`: 0 kills |
| **Concurrent** | **2026-07-13〜31: kills (30+)** | 2026-08-05 `65022`: 0 · **2026-08-06 `63129`: 0 (8h, 2–4 concurrent)** |

The "freshly rebooted × concurrent" cell is now substantially reinforced. **Concurrency alone remains insufficient to reproduce the symptom at low uptime**, across ~10 hours of cumulative concurrent operation over two days.

This does not confirm H-b'; it continues to be consistent with uptime being a necessary co-factor, and equally consistent with an upstream harness change between July and August. The distinguishing experiment is still a passive wait for uptime to accumulate — see #1146's watch item.

### Concurrency cost, restated with a larger sample

| Cost | Count |
|---|---|
| `concurrent_commit_detected` | **40** |
| `ff-only-merge-fallback` (inline, self-recovered) | 1 |
| **Parent-session manual recovery** (inline fallback hit the unimplemented true-side path) | **1** (#1174 verify) |

The manual recovery is the one that matters: it required human-in-the-loop intervention mid-batch. Its root cause — `worktree-merge-push.sh`'s true-side (`current_branch == BASE_BRANCH`) branch lacking a rebase fallback — was **fixed within this same batch as #1076**. Two further same-day occurrences from other sessions (#1179, #1180 verify) are recorded in `docs/reports/orchestration-recoveries.md` as `manual-recovery-worktree-rebase`.

Note the vocabulary distinction, which the earlier entries above blur: `ff-only-merge-fallback` is **inline logic inside `worktree-merge-push.sh`**, not a Tier 2 catalog handler (`scripts/apply-fallback.sh:75` marks it `not yet implemented`). When that inline logic succeeds, nothing is recorded. When it fails, recovery falls to whoever called it — a `run-*.sh` wrapper (→ Tier 1/2/3) or, for in-session `/verify` which has no wrapper, **the parent session** (→ `manual_intervention`). All four of today's `manual-recovery-worktree-rebase` entries are of the latter kind; three of them occurred in the `verify` phase.

### Measurement caveat carried forward

One `manual_intervention` event from this session (the #1174 recovery) was **misattributed to session `41961-1785999585`**: the `--write-manual-recovery` call did not regenerate its PGID pointer file first, so `restore_auto_session_pointer` read `.tmp/auto-session-current`, which a concurrent session had overwritten. This is #1075's known failure mode, and it means **`manual_intervention` counts remain unreliable for per-session attribution under concurrency** — the same caveat that applies to the July data. Counts of the *recoveries log* (`docs/reports/orchestration-recoveries.md`), which carries an explicit `- Issue #N, phase: P` Context line, are not affected.
