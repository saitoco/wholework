English | [日本語](../ja/reports/auto-session-49779-1781466317-2026-06-15.md)

# /auto Session Report — 49779-1781466317

**Session start**: 2026-06-14T19:53:45Z
**Session end**: 2026-06-15T02:13:05Z
**Wall-clock**: 06:19:20
**Route mix**: patch: 23, pr: 2, xl: 0

## Summary

| Metric | Value |
|---|---|
| Issues processed | 28 |
| Fully closed (phase/done) | 17 |
| phase/verify remaining | 8 |
| Throughput | 4.4 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 1490s |
| Total token usage | N/A |
| Concurrent commits detected | 67 |
| Parent session manual interventions | 0 |
| verify FAIL → reopen fix cycles | 0 |
| Merge conflicts | 0 |

## Per-Issue Durations

| Issue | Size/Route | Duration | Phase breakdown | PR | Notes |
|---|---|---|---|---|---|
| #460 | S/patch | 2026-06-15T01:17:08Z – 2026-06-15T01:37:02Z | code-patch 19m | — | Silent 1190s;3 concurrent commits |
| #461 | S/patch | 2026-06-15T00:47:39Z – 2026-06-15T00:58:33Z | code-patch 10m | — | Silent 800s;3 concurrent commits |
| #462 | XS/patch | 2026-06-15T00:10:57Z – 2026-06-15T00:20:31Z | code-patch 9m | — | 1 concurrent commits |
| #463 | S/patch | 2026-06-14T23:49:59Z – 2026-06-15T00:01:54Z | code-patch 11m | — | Size S→XS;Silent 710s;2 concurrent commits |
| #465 | S/patch | 2026-06-14T23:25:55Z – ? | — | — | 1 concurrent commits |
| #466 | XS/patch | 2026-06-14T22:57:56Z – 2026-06-14T23:09:41Z | code-patch 11m | — | Silent 700s;1 concurrent commits |
| #467 | XS/patch | 2026-06-14T22:36:42Z – 2026-06-14T22:47:47Z | code-patch 11m | — | Silent 660s;1 concurrent commits |
| #468 | XS/patch | 2026-06-14T22:16:56Z – 2026-06-14T22:28:00Z | code-patch 11m | — | Silent 660s;2 concurrent commits |
| #471 | XS/patch | 2026-06-14T22:00:49Z – 2026-06-14T22:10:03Z | code-patch 9m | — | 2 concurrent commits |
| #476 | S/patch | 2026-06-14T21:37:55Z – 2026-06-14T21:51:49Z | code-patch 13m | — | Silent 830s;5 concurrent commits |
| #477 | S/patch | 2026-06-14T21:04:11Z – 2026-06-14T21:29:06Z | code-patch 24m | — | Size S→XS;Silent 1490s;3 concurrent commits |
| #478 | S/patch | 2026-06-14T20:33:29Z – 2026-06-14T20:44:43Z | code-patch 11m | — | Silent 670s;5 concurrent commits |
| #479 | S/patch | 2026-06-14T20:02:50Z – 2026-06-14T20:15:24Z | code-patch 12m | — | Size S→XS;Silent 750s;2 concurrent commits |
| #639 | S/patch | 2026-06-15T01:41:19Z – 2026-06-15T01:56:04Z | code-pr 14m | #516 | Size S→M;Silent 880s |
| #641 | XS/patch | 2026-06-15T01:01:30Z – 2026-06-15T01:20:45Z | code-patch 19m | — | Silent 1150s;2 concurrent commits |
| #642 | XS/patch | 2026-06-15T00:40:46Z – 2026-06-15T00:51:00Z | code-patch 10m | — | Silent 610s;2 concurrent commits |
| #645 | XS/patch | 2026-06-15T00:15:11Z – ? | — | — | Silent 730s;1 concurrent commits |
| #646 | XS/patch | 2026-06-14T23:51:37Z – 2026-06-15T00:08:12Z | code-patch 16m | — | Silent 990s;4 concurrent commits |
| #647 | S/patch | 2026-06-14T23:25:48Z – 2026-06-14T23:41:32Z | code-patch 15m | — | Silent 940s;3 concurrent commits |
| #648 | XS/patch | 2026-06-14T23:02:59Z – 2026-06-14T23:14:23Z | code-patch 11m | — | Silent 680s;2 concurrent commits |
| #649 | M/pr | 2026-06-14T22:22:54Z – 2026-06-14T22:36:59Z | code-pr 14m | #657 | Silent 840s;1 concurrent commits |
| #650 | S/patch | 2026-06-14T21:51:20Z – 2026-06-14T22:03:04Z | code-patch 11m | — | Silent 700s;2 concurrent commits |
| #652 | XS/patch | 2026-06-14T21:18:52Z – 2026-06-14T21:39:46Z | code-patch 20m | — | Silent 1250s;5 concurrent commits |
| #653 | XS/patch | 2026-06-14T20:54:04Z – 2026-06-14T21:06:38Z | code-patch 12m | — | Silent 750s;2 concurrent commits |
| #654 | M/pr | 2026-06-14T20:05:12Z – 2026-06-14T20:25:08Z | code-pr 19m | #655 | Silent 1190s;3 concurrent commits |
| #655 | ?/? | 2026-06-14T20:25:08Z – 2026-06-14T20:40:29Z | merge 3m → review 11m | #655 | Silent 630s;3 concurrent commits |
| #657 | ?/? | 2026-06-14T22:36:59Z – 2026-06-14T22:51:40Z | merge 3m → review 11m | #657 | Silent 610s;3 concurrent commits |
| #659 | ?/? | 2026-06-15T01:56:04Z – 2026-06-15T02:13:05Z | merge 3m → review 13m | #659 | Silent 740s;3 concurrent commits |


## Recovery Events

(no recovery events)

## Verify Phase Residuals

(none)

## Concurrent Sessions Detected

- [2026-06-14T20:15:24Z] phase=code-patch sha=0525b3ca → #479 (author=Toshihiro Saito)
- [2026-06-14T20:15:24Z] phase=code-patch sha=ac377c7e → #479 (author=Toshihiro Saito)
- [2026-06-14T20:25:08Z] phase=code-pr sha=1fb717e3 → #479 (author=Toshihiro Saito)
- [2026-06-14T20:25:08Z] phase=code-pr sha=0525b3ca → #479 (author=Toshihiro Saito)
- [2026-06-14T20:25:08Z] phase=code-pr sha=ac377c7e → #479 (author=Toshihiro Saito)
- [2026-06-14T20:36:44Z] phase=review sha=05707a3d → #478 (author=Toshihiro Saito)
- [2026-06-14T20:40:29Z] phase=merge sha=069b31c3 → #654 (author=Toshihiro Saito)
- [2026-06-14T20:40:29Z] phase=merge sha=ad84fa1a → #654 (author=Toshihiro Saito)
- [2026-06-14T20:44:43Z] phase=code-patch sha=e05b1247 → #654 (author=Toshihiro Saito)
- [2026-06-14T20:44:43Z] phase=code-patch sha=615a41ac → #478 (author=Toshihiro Saito)
- [2026-06-14T20:44:43Z] phase=code-patch sha=359a4a1a → #478 (author=Toshihiro Saito)
- [2026-06-14T20:44:43Z] phase=code-patch sha=069b31c3 → #654 (author=Toshihiro Saito)
- [2026-06-14T20:44:43Z] phase=code-patch sha=ad84fa1a → #654 (author=Toshihiro Saito)
- [2026-06-14T21:06:38Z] phase=code-patch sha=b12b7b7b → #653 (author=Toshihiro Saito)
- [2026-06-14T21:06:38Z] phase=code-patch sha=0cf572d4 → #477 (author=Toshihiro Saito)
- [2026-06-14T21:29:06Z] phase=code-patch sha=6b204430 → #477 (author=Toshihiro Saito)
- [2026-06-14T21:29:06Z] phase=code-patch sha=14d39123 → #477 (author=Toshihiro Saito)
- [2026-06-14T21:29:06Z] phase=code-patch sha=b12b7b7b → #653 (author=Toshihiro Saito)
- [2026-06-14T21:39:46Z] phase=code-patch sha=1a08e9cc → #652 (author=Toshihiro Saito)
- [2026-06-14T21:39:46Z] phase=code-patch sha=c76d350f → #652 (author=Toshihiro Saito)
- [2026-06-14T21:39:46Z] phase=code-patch sha=6da1956f → #477 (author=Toshihiro Saito)
- [2026-06-14T21:39:46Z] phase=code-patch sha=6b204430 → #477 (author=Toshihiro Saito)
- [2026-06-14T21:39:46Z] phase=code-patch sha=14d39123 → #477 (author=Toshihiro Saito)
- [2026-06-14T21:51:49Z] phase=code-patch sha=ebaa49da → #476 (author=Toshihiro Saito)
- [2026-06-14T21:51:49Z] phase=code-patch sha=e4b1002c → #476 (author=Toshihiro Saito)
- [2026-06-14T21:51:49Z] phase=code-patch sha=a89cc1fe → #652 (author=Toshihiro Saito)
- [2026-06-14T21:51:49Z] phase=code-patch sha=1a08e9cc → #652 (author=Toshihiro Saito)
- [2026-06-14T21:51:49Z] phase=code-patch sha=c76d350f → #652 (author=Toshihiro Saito)
- [2026-06-14T22:03:04Z] phase=code-patch sha=cb106d77 → #650 (author=Toshihiro Saito)
- [2026-06-14T22:03:04Z] phase=code-patch sha=76057fcb → #476 (author=Toshihiro Saito)
- [2026-06-14T22:10:03Z] phase=code-patch sha=26bb74ee → #471 (author=Toshihiro Saito)
- [2026-06-14T22:10:03Z] phase=code-patch sha=cb106d77 → #650 (author=Toshihiro Saito)
- [2026-06-14T22:28:00Z] phase=code-patch sha=41bae8d5 → #468 (author=Toshihiro Saito)
- [2026-06-14T22:28:00Z] phase=code-patch sha=b819ef35 → #649 (author=Toshihiro Saito)
- [2026-06-14T22:36:59Z] phase=code-pr sha=41bae8d5 → #468 (author=Toshihiro Saito)
- [2026-06-14T22:47:47Z] phase=code-patch sha=9ea3f993 → #467 (author=Toshihiro Saito)
- [2026-06-14T22:48:14Z] phase=review sha=9ea3f993 → #467 (author=Toshihiro Saito)
- [2026-06-14T22:51:39Z] phase=merge sha=7a001607 → #649 (author=Toshihiro Saito)
- [2026-06-14T22:51:39Z] phase=merge sha=c4bcea18 → #649 (author=Toshihiro Saito)
- [2026-06-14T23:09:40Z] phase=code-patch sha=70db3bc7 → #466 (author=Toshihiro Saito)
- [2026-06-14T23:14:23Z] phase=code-patch sha=83423a7e → #648 (author=Toshihiro Saito)
- [2026-06-14T23:14:23Z] phase=code-patch sha=70db3bc7 → #466 (author=Toshihiro Saito)
- [2026-06-14T23:31:39Z] phase=code-patch sha=e25d506c → #465 (author=Toshihiro Saito)
- [2026-06-14T23:41:32Z] phase=code-patch sha=071bf975 → #647 (author=Toshihiro Saito)
- [2026-06-14T23:41:32Z] phase=code-patch sha=9890b589 → #465 (author=Toshihiro Saito)
- [2026-06-14T23:41:32Z] phase=code-patch sha=e25d506c → #465 (author=Toshihiro Saito)
- [2026-06-15T00:01:54Z] phase=code-patch sha=b487b2a0 → #463 (author=Toshihiro Saito)
- [2026-06-15T00:01:54Z] phase=code-patch sha=27c4b36a → #463 (author=Toshihiro Saito)
- [2026-06-15T00:08:12Z] phase=code-patch sha=2ec4e553 → #646 (author=Toshihiro Saito)
- [2026-06-15T00:08:12Z] phase=code-patch sha=aa748765 → #463 (author=Toshihiro Saito)
- [2026-06-15T00:08:12Z] phase=code-patch sha=b487b2a0 → #463 (author=Toshihiro Saito)
- [2026-06-15T00:08:12Z] phase=code-patch sha=27c4b36a → #463 (author=Toshihiro Saito)
- [2026-06-15T00:20:31Z] phase=code-patch sha=b73032e9 → #462 (author=Toshihiro Saito)
- [2026-06-15T00:27:25Z] phase=code-patch sha=b73032e9 → #462 (author=Toshihiro Saito)
- [2026-06-15T00:51:00Z] phase=code-patch sha=7755eeaa → #642 (author=Toshihiro Saito)
- [2026-06-15T00:51:00Z] phase=code-patch sha=4f061c4a → #461 (author=Toshihiro Saito)
- [2026-06-15T00:58:33Z] phase=code-patch sha=8b02499f → #461 (author=Toshihiro Saito)
- [2026-06-15T00:58:33Z] phase=code-patch sha=2a921075 → #461 (author=Toshihiro Saito)
- [2026-06-15T00:58:33Z] phase=code-patch sha=7755eeaa → #642 (author=Toshihiro Saito)
- [2026-06-15T01:20:45Z] phase=code-patch sha=9373cae7 → #641 (author=Toshihiro Saito)
- [2026-06-15T01:20:45Z] phase=code-patch sha=7a308b6a → #460 (author=Toshihiro Saito)
- [2026-06-15T01:37:02Z] phase=code-patch sha=c9656465 → #460 (author=Toshihiro Saito)
- [2026-06-15T01:37:02Z] phase=code-patch sha=f84c90bb → #460 (author=Toshihiro Saito)
- [2026-06-15T01:37:02Z] phase=code-patch sha=9373cae7 → #641 (author=Toshihiro Saito)
- [2026-06-15T02:13:05Z] phase=merge sha=18ac76f7 → #639 (author=Toshihiro Saito)
- [2026-06-15T02:13:05Z] phase=merge sha=9da07f71 → #631 (author=Toshihiro Saito)
- [2026-06-15T02:13:05Z] phase=merge sha=cfaaf001 → #639 (author=Toshihiro Saito)


## Improvement Candidates Surfaced

(none — no Tier 3 recoveries)

---

## Narrative Section (manual / --full LLM-assist)

### What worked
> [LLM draft — human review required]

1. **High-throughput batch run with zero recovery events**: 28 issues processed in 6h19m at 4.4 issues/hr with 0 Tier 1/2/3 recoveries, 0 watchdog kills, 0 verify reopen cycles, and 0 manual interventions. The fleet ran end-to-end on the auto pipeline alone — the strongest "happy path" signal of the series.
2. **Concurrent-session coexistence at scale**: 67 concurrent commits detected across phases without a single merge conflict reported, indicating that the patch-lock + ff-only-merge + worktree-branch-rebase fallback (#522) holds under heavy parallelism (multiple `/auto` sub-sessions and external commits interleaved).
3. **Dynamic Size re-judgment routed correctly**: 4 issues (#463, #477, #479 S→XS, #639 S→M) had their Size re-judged at Step 3a and the route adjusted accordingly. #639 promoted to pr route and completed in 14m code-pr + downstream review (PR #516); #463/#477/#479 demoted to patch and completed in 11–24m. The Size-driven route demotion logic kept all 4 within their target SLOs.
4. **pr-route review→merge phases stayed compact**: 3 pr-route issues (#655, #657, #659) each completed merge in 3m and review in 11–13m — the longest review was 13m on #659, suggesting review-light agent latency is steady at the 10-minute scale.
5. **#660 post-merge structural change took effect immediately**: The Summary table now reports `Parent session manual interventions | 0` and `verify FAIL → reopen fix cycles | 0` rows unconditionally, satisfying the #660 observation AC on the first follow-up `/audit auto-session` call.

### Limits and gaps
> [LLM draft — human review required]

1. **Two issues left without phase-end timestamps**: #465 and #645 show `? end` in Per-Issue Durations — their phases started but no completion event was emitted. #465 remains OPEN at `phase/verify` while #645 reached `phase/done` (closed externally?). The session-report data layer cannot distinguish "still running" from "completed but un-emitted" — a gap in event reliability that masks tail latency.
2. **Silent windows reached 25 minutes on patch-route issues**: Max silent window in the session was 1490s (#477) and 1190s (#460), both patch-route. The current uniform 2700s watchdog timeout absorbs these without firing, but the headroom (~1200s remaining at peak) suggests stalls of this magnitude routinely consume more wall-clock than necessary on small issues. Phase-tier watchdogs (now defined for code/spec/review/merge separately) would tighten this further.
3. **High concurrent-commit count without per-issue impact analysis**: 67 concurrent commits is roughly 2.4 per issue. The data layer surfaces the count but does not classify each event by "did this affect the issue's phase outcome?" — the only consequence visible from the report is that base-conflict warnings did not fire (otherwise they'd be in Notes). The signal is collected but its actionability is limited.
4. **8 of 28 issues remain at phase/verify (29%)**: Below the 50% rate seen in earlier batch sessions (e.g., 6/6 in 2026-06-14), but still a meaningful backlog. The mix is presumably `verify-type: observation` and `verify-type: opportunistic` ACs that wait for future events. The session-report data layer does not break down which verify-type subcategory drove each residual — that classification is needed to decide whether the backlog is healthy or accumulating.
5. **Total token usage is `N/A`**: The token_usage event type is documented but not yet emitted by wrappers (see #662 / #630 follow-up). Cost-accounting questions cannot be answered from this report despite the session running 6+ hours.

### Improvement candidates surfaced
> [LLM draft — human review required]

1. **Per-issue silent-window threshold violation tracking** — "Issue 起票候補": Add a Summary row `Phase silent windows > 1200s` (count) and a per-issue note `Silent {N}s phase={phase}` whenever a phase's silent window exceeded the phase-tier watchdog default minus 600s margin. Surfaces stalls that didn't fire watchdog but are within margin of doing so. Body skeleton: "Add a new derived metric `phase_silent_window_at_risk` to `get-auto-session-report.sh`. Threshold = phase-tier default − 600s. Append a Summary row + per-issue Notes annotation. Enables tightening watchdog defaults from evidence."
2. **Distinguish `phase/verify` residuals by verify-type subcategory** — "Issue 起票候補": Augment Verify Phase Residuals section to break down `phase/verify` issues by their unchecked AC type (observation event=X / opportunistic / manual). Body skeleton: "In `get-auto-session-report.sh` Verify Phase Residuals section, for each phase/verify issue scan its body for unchecked `verify-type: ...` markers and group counts by subcategory. Enables 'observation waiting' vs 'opportunistic backlog' discrimination at session retrospective time, paralleling `/audit stats` Section 7 metrics."
3. **Concurrent-commit impact classification** — "凍結推奨（trigger: > 100 commits/session observed without diff-side incident）": The 67 concurrent commits caused no visible impact this session. Until a session emerges where they correlate with issue outcomes (e.g., base-conflict warnings, retry counts), per-commit classification is over-engineering. Freeze until trigger condition.
4. **Phase-end event emit verification** — "既存 #465 に統合提案": #465 itself is the meta-issue for "run-code 正常終了時に reconcile-phase-state.sh --check-completion を呼ぶ" — extending that scope to also re-emit a `phase_complete` event if the wrapper terminated cleanly but the previous event was a `phase_start` covers the "? end" pattern observed here.
5. **token_usage event wiring** — "既存 #662 に統合提案": #662 already tracks `token_usage / ci_wait / test_result` non-emission. The Summary `Total token usage | N/A` row will start populating automatically once #662 is closed.

### Conclusion
> [LLM draft — human review required]

This session is the cleanest single `/auto` execution recorded so far in Wholework's history: 28 issues processed in 6h19m at 4.4 issues/hr with zero recovery events, zero watchdog kills, zero verify reopen cycles, and zero manual interventions. The structural changes accumulated over the prior 2 days — Step 3a route demotion (#629), patch-lock concurrency safety (#522), and the recent #660 metric expansion — all held under a workload that produced 67 concurrent commits across phases. The pipeline functioned end-to-end without parent intervention.

The most important structural finding is the **observability gap around silent windows and phase-end events**: two issues (#465, #645) ended with `? end` because their phase_complete events were never emitted, and the longest silent windows (1490s, 1190s) sat just inside the 2700s watchdog without surfacing in the Summary table. Both are tractable — re-emit on normal exit (closing #465 covers this) and add a "silent window at risk" derived metric — but until they are closed, the report's tail-latency signal is muted.

The session demonstrates that Wholework has crossed from "stable when nothing goes wrong" to "stable while many things happen at once" — the natural next moat is per-issue cost accounting (blocked on #662) and observation-AC subcategory analysis. The retrospective process itself now operates against a data layer rich enough to surface these next-tier questions without leaving the auto-session report.

---

## Follow-up Verification (2026-06-15, addendum)

This report was the primary trigger for filing #662 (token_usage / ci_wait / test_result non-emission). After this session, the following remediations landed and were partially verified:

### Resolved

- **#662** (PR #664, merged 2026-06-15T04:28Z): `2>&1` removed from `run-code.sh` / `run-review.sh` / `run-merge.sh` `--output-format json` invocations; phase glob `code*` adopted in `run-auto-sub.sh`; merge-phase bats test added for `wait-ci-checks.sh` AUTO_EVENTS_LOG propagation.
- **#670** (merged 2026-06-15T06:24Z): pr-route single-Issue orchestration gap fixed — `AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}" + export` added to the top of `run-code.sh` / `run-review.sh` / `run-merge.sh`. Discovered while verifying #663; pr-route parent sessions previously did not propagate AUTO_EVENTS_LOG to wrapper invocations, masking #662's fix on single-Issue runs.

### Verified in subsequent batch session 9171-1781503269 (2026-06-15T06:01–06:49Z, `--batch 670 388`)

| Event | Result | Notes |
|---|---|---|
| `token_usage` | ✅ 2 emitted | Both #670 and #388 code-patch phases recorded `input_tokens` / `output_tokens` / `cache_read_tokens` — confirms #662's `2>&1` fix |
| `ci_wait` | ⏳ 0 emitted | Both issues were patch-route; `wait-ci-checks.sh` invoked only by review/merge phases. Awaits next pr-route execution |
| `test_result` | ⏳ 0 emitted | Both code-patch phases did not run bats; `run-auto-sub.sh` test-output parser had no log to parse. Awaits a code phase whose log contains bats output |

### Impact on this report's original findings

- "**Total token usage `N/A`**" (Limits and gaps item 5) and the corresponding "**token_usage event wiring — 既存 #662 に統合提案**" (Improvement candidates item 5) — partially resolved. Future `/audit auto-session` reports against post-#662 sessions will populate `Total token usage` from emitted events.
- "**Per-issue cost accounting (blocked on #662)**" (Conclusion para 3) — unblocked structurally. The next session run after these fixes will be the first to carry cost data through the data layer.
- "**Phase-end event emit verification — 既存 #465 に統合提案**" (Improvement candidates item 4) — unchanged; #465 remains open and separately tracks the `phase_complete` event reliability issue.

### Remaining observation work

- #662's observation AC ("3 種記録") is at 1/3 (token_usage confirmed). Closure requires a session that exercises pr-route review/merge phases (emits `ci_wait`) and a code phase whose log captures bats output (emits `test_result`).
- #670's observation AC ("pr-route single-Issue events emit") still pending — today's batch was patch-route only.
