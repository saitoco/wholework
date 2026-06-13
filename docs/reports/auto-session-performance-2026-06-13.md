# /auto Session Performance Report — 2026-06-13

Session-level performance record for a long-running `/auto` session driven by Claude Fable 5 (parent orchestrator) with Sonnet `claude -p` child phases. 14 issues were fully processed across two waves in a single session. All timestamps are JST (local), taken from `run-*.sh` Started/Finished banners; verify-phase boundaries (parent-session execution, no wrapper banner) are estimated from the next phase's start time.

Idle time waiting for user input is excluded from all per-issue durations.

## Summary

| Metric | Value |
|--------|-------|
| Issues fully processed (triage → verify) | 14 (#555–#563, #572–#574, #567, #569) |
| Fully closed (phase/done) | 7 (#558, #559, #560, #561, #572, #573, #574) |
| phase/verify remaining (observation-only conditions) | 7 (#555, #556, #557, #562, #563, #567, #569) |
| Wave 1 wall-clock (continuous, no idle) | ~7h 50m (#555–#563, 22:45–06:35 JST) |
| Wave 2 wall-clock (continuous, no idle) | ~3h 30m (/audit drift + #572–#574, #567, #569, 07:18–10:48 JST) |
| verify FAIL → reopen fix cycles | 1 (#557, resolved at iteration 2/3) |
| Manual recoveries by parent session | 1 (#557 test-mock fix) |
| Watchdog kills | 2 (out of 35+ wrapped phase executions) |
| Improvement issues filed and consumed in-session | 5 (#567, #569, #572, #573, #574) |
| Fable 5 opt-in spec runs (`run-spec.sh --fable`) | 1 (#560, success) |

## Per-Issue Durations (idle excluded)

Durations span from the issue's first phase start to verify completion (parent-session verify estimated from the next issue's triage start).

### Wave 1 — `/auto` batch #555–#563

| Issue | Size/Route | Duration | Phases | Notes |
|-------|-----------|----------|--------|-------|
| #555 | M / pr | ~60 min | issue 8m → spec 9m → code 12m → review 12m → merge 2m → verify ~15m | Clean run; filed #567 from retro |
| #556 | M / pr | ~65 min | issue ~7m → spec ~9m → code ~30m → review ~12m → merge ~2m → verify ~6m | code phase hit 1800s watchdog kill (old default); reconcile auto-recovered |
| #557 | S / patch | ~87 min | issue 7m → code 17m → verify(1) FAIL → fix-code 45m (killed) → manual fix ~10m → CI wait ~6m → verify(2) | Full fix cycle; reconcile false positive; filed #569 |
| #558 | S / patch | ~28 min | issue ~8m → code ~15m → verify ~5m | Cleanest patch run |
| #559 | M / pr | ~48 min | issue ~6m → spec ~8m → code ~12m → review ~10m → merge ~6m → verify ~6m | ZDR pseudo-env test built in verify |
| #560 | M→S / patch | ~45 min | issue ~7m → spec(Fable 5) 8m52s → code ~25m → verify ~5m | Size re-judged M→S after spec |
| #561 | M / pr | ~62 min | issue ~6m → spec ~12m → code ~18m → review ~14m → merge ~3m → verify ~9m | Not-adopted conclusion; all ACs PASS |
| #562 | S / patch | ~35 min | issue ~7m → spec ~8m → code ~13m → verify ~7m | |
| #563 | S / patch | ~40 min | issue ~5m → spec ~7m → code ~15m → verify ~13m | Batch tail incl. final report |

### Wave 2 — /audit drift + follow-ups

| Issue | Size/Route | Duration | Notes |
|-------|-----------|----------|-------|
| /audit drift | — | ~22 min | 2 drifts found → #572/#573 filed; consumed #558/#560 post-merge conditions |
| #572 | XS / patch | ~30 min | audit/drift follow-up; phase/done |
| #573 | XS / patch | ~35 min | Triage fixed an always-PASS verify command; phase/done; gap found in verify → #574 filed |
| #574 | XS / patch | ~27 min | retro→issue→fix→verify loop closed in one cycle; phase/done |
| #567 | S / patch | ~39 min | Triage strengthened already-true verify commands to section_not_contains |
| #569 | M / pr | ~55 min | reconcile fix-cycle freshness condition (reopen_ts + git log --after); 55/55 bats incl. 3 new fix-cycle cases |

### Duration observations

- **Patch route (XS/S)**: 27–40 min end-to-end. The dominant cost is the code phase (13–25 min); triage and verify are stable at 5–8 min each.
- **PR route (M)**: 45–65 min end-to-end on clean runs. review adds 10–14 min and merge 2–6 min over the patch route.
- **Fix cycle cost**: #557's single FAIL → reopen → fix → re-verify cycle added ~60 min over its clean-run baseline, of which 45 min was a watchdog-killed no-op wrapper run. Parent-session manual recovery (5-file test mock fix) took ~10 min including local test runs.
- **Issue triage is remarkably stable**: 5–8 min regardless of size, including 3 cases where triage materially repaired verify commands (#573 always-PASS command, #567 already-true commands, #555 grep argument order).

## Watchdog Observations (relevant to #556 post-merge AC)

2 kills across 35+ wrapped phase executions in this session:

| # | Phase | Timeout in effect | Outcome | Recovery |
|---|-------|------------------|---------|----------|
| 1 | #556 code (pr) | 1800s (old default) | PR #568 already created before kill | Tier 1 reconcile detected OPEN PR → auto success, no manual action |
| 2 | #557 fix-cycle code (patch) | 2700s (new default) | True mid-work kill, zero commits produced | Tier 1 reconcile **false-positived** on the pre-reopen `closes #557` commit; parent session detected via `git log` HEAD check and manually recovered. Root cause fixed in #569 |

Post-#556 (2700s default active from #558 onward): **0 kills in 25+ subsequent wrapped executions**, including the longest clean code phase (~25 min, #560). The 2700s raise eliminated the kill class observed at 1800s; the one 2700s kill (#557) was qualitatively different (a genuinely stalled run, which the watchdog is designed to kill). Both Layer 3 recovery behaviors are now exercised: post-completion kill (auto-recovered) and mid-work kill (now correctly detected after #569).

Longest observed silent windows on *surviving* runs: ~660s (review phases), ~480–540s (spec/code phases) — well within the 2700s budget.

## Quality-Loop Events

- **verify FAIL detection worked**: #557 iteration 1 correctly FAILed on a CI-red condition that the code phase had inaccurately self-reported as green. The reopen → fix → iteration-2 PASS loop completed without reaching the max-iterations cap (3).
- **Triage as a verify-command audit layer**: 3 issues had defective verify commands repaired at triage time before they could produce false PASSes (#573, #567) or false FAILs (#555).
- **Self-healing pipeline**: every improvement issue generated by this session's retrospectives (#567, #569, #572, #573, #574) was implemented, verified, and closed within the same session. The #557 incident → #569 structural fix loop closed in under 10 hours including the fix-cycle bats regression tests.
- **Fable 5 opt-in**: first production `run-spec.sh --fable` run (#560) succeeded — 3 warning lines emitted, spec generated in 8m52s at effort=high, Size correctly re-judged M→S. ZDR graceful degrade verified via pseudo-environment bats test (#559).

## Remaining Observation Conditions

The 7 phase/verify issues carry only future-event observation conditions: real-PR `/review --full` finding volume (#555), watchdog kill recurrence (#556), early-stop absence (#557), retrospective reading effects (#562), cyber-classifier fallback (#563), format-change propagation (#567), and real fix-cycle reconcile behavior (#569). Each closes via `/verify N` when its triggering event occurs in normal operation.
