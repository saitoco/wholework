English | [日本語](../ja/reports/auto-batch-list-mode-2026-06-14.md)

# /auto --batch List Mode Performance Report — 2026-06-14

Performance record for a `/auto --batch 581 554 548 547 546 541` (List mode) run under an Opus 4.7 parent orchestrator with Sonnet `claude -p` child phases. 6 issues processed sequentially in a single batch run. All timestamps are JST (local), derived from `run-auto-sub.sh` Started/Finished banners and git commit timestamps. User idle time is excluded by construction — the user announced they were stepping away early in the run, so the parent session never blocked on input.

This run also coexisted with a concurrent single-session `/auto` run on the same repository (the session that produced `auto-parent-session-comparison-2026-06-14.md`). The two sessions' commit interleaving is the first observed natural test of concurrent `/auto` execution on `main`.

## Summary

| Metric | Value |
|--------|-------|
| Issues fully processed (spec → code → review → merge) | 6 (#581, #554, #548, #547, #546, #541) |
| Fully closed (phase/done) | 0 |
| phase/verify remaining (opportunistic pending, observation-type post-merge ACs) | 6 (#581, #554, #548, #547, #546, #541) |
| Wall-clock (continuous, idle excluded) | ~4h 43m (00:36:23 → 05:19:37 JST) |
| Throughput | ~1.27 issues/hr |
| Tier 1 reconcile auto-recoveries | 0 |
| Tier 2 fallback-catalog recoveries | 0 |
| Tier 3 recovery sub-agent invocations | 1 (#554 code phase, action=recover, success) |
| Watchdog kills | 0 |
| Parent session manual interventions | 0 |
| verify FAIL → reopen fix cycles | 0 (verify phase invocation deferred — see "Verify phase observations") |
| Concurrent `/auto` session detected | Yes (~10 additional issues processed by another session in the same window) |
| Merge conflicts from concurrent commits | 0 |

## Per-Issue Durations

Durations span the `run-auto-sub.sh` Started → Finished banners (spec → code → review → merge end-to-end per issue). Verify is **not** included in these durations — see "Verify phase observations" below.

| Issue | Size/Route | Duration | Spec | code+review+merge | PR | Notes |
|-------|-----------|----------|------|-------------------|-----|-------|
| #581 | M → XS / pr→pr | 48m 04s (00:36:23→01:24:27) | 9m 42s | ~38m | #602 | Spec phase re-judged Size M→XS (documentation-only ADR). Route remained `pr` (executed before Step 3a re-routing applied to the in-flight run; size update visible on the issue but route did not auto-switch). |
| #554 | M / pr | 32m 28s (01:25:34→01:58:02) | 8m 03s | ~24m | #606 | Tier 3 recovery sub-agent invoked during code phase; `action=recover` succeeded (PR push raced with a remote-branch creation hint, then recovered) |
| #548 | M → XS / pr→pr | 44m 40s (01:58:34→02:43:14) | 10m 43s | ~33m | #607 | Spec phase re-judged Size M→XS |
| #547 | M / pr | ~44m (02:43:30→03:27:25) | ~13m | ~30m | #609 | Clean run |
| #546 | M / pr | 47m 02s (03:27:47→04:14:49) | 11m 23s | ~35m | #611 | Clean run |
| #541 | M / pr | 64m 23s (04:15:14→05:19:37) | 13m 03s | ~50m | #613 | Longest run; PR for self-improving mergeability pre-check (irony: ran concurrently with another session merging to `main`) |

### Duration Observations

- **PR route (M)**: 32–64 min end-to-end (spec + code + review + merge), median ~46 min. Comparable to the 2026-06-14 single-session baseline (27–53 min for M/pr issues) and faster than the 2026-06-13 Fable 5 baseline (45–65 min clean).
- **Spec phase stability**: 8–13 min across all 6 issues — no degradation across the 4h 43m window.
- **Code phase variance**: dominant cost (~24–50 min). #541 was the slowest; the spec described a multi-step pre-check (git fetch + behind-by parsing + comment posting) which justifies the wall-clock.
- **Re-judged sizes (M→XS) did not change the route mid-batch**: #581 and #548 were re-judged to XS during their respective spec phases (the spec deliverable subsumed the issue scope), but each continued on the `pr` route already selected. This matches the documented Step 3a behavior in the auto skill: post-spec size refresh only applies on the next phase routing decision, not retroactively to an in-flight phase sequence.

## Tier 3 Recovery Event (#554)

The code phase of #554 ran into a wrapper-level anomaly that the in-wrapper recovery hierarchy handled without parent-session intervention:

```
[spawn-recovery] action=recover: executing recovery steps
remote: Create a pull request for 'worktree-code+issue-554' on GitHub by visiting:
remote:      https://github.com/saitoco/wholework/pull/new/worktree-code+issue-554
* [new branch]      worktree-code+issue-554 -> worktree-code+issue-554
https://github.com/saitoco/wholework/pull/606
[spawn-recovery] step 1: op=run_command
[spawn-recovery] step 2: op=run_command
[spawn-recovery] all recovery steps completed
[recovery] tier3 sub-agent: recovered
PR number: 606
```

Reading the trace: a branch push succeeded but the PR creation in the wrapper's normal path did not (the `gh pr create` likely raced against the just-pushed branch state). The Tier 3 recovery sub-agent recognized the state (push succeeded, PR not yet present), produced a recovery plan (`action=recover`), and executed two `run_command` steps. The plan's validation passed and the recovered phase output a clean `PR number: 606`. Subsequent review and merge phases ran normally.

This is the **first observed Tier 3 recovery sub-agent invocation in production**. Prior reports had observed only Tier 1 (reconcile) and parent-session manual recovery (#557 in the 2026-06-13 baseline). The Tier 3 path resolved the failure entirely inside the child wrapper, requiring zero parent-session intervention.

## Concurrent /auto Session Coexistence

A second `/auto` session ran in parallel on the same `main` branch during this batch, processing improvement issues from the 2026-06-13 backlog (#583, #584, #585, #586, #587) plus several `/audit drift` follow-ups (#601, #604, #605, #606). Both sessions wrote commits to `main` via worktree-based isolation.

Interleaved commit timeline (excerpt, JST):

```
00:36:23  this batch: #581 sub-issue start
01:22:35  this batch: #581 PR #602 merged
01:30:21  this batch: #554 design committed
01:32:38  other session: #583 PR #603 merged
01:56:40  other session: #606 (audit issue) merged
01:56:45  other session: #604 merged
01:57:18  this batch: #554 merge handoff
02:11:31  other session: #605 merged
02:42:03  this batch: #548 PR #607 merged
02:43:21  other session: #584 PR #608 merged
03:26:02  this batch: #547 PR #609 merged
03:43:49  other session: #585 PR #610 merged
04:13:44  this batch: #546 PR #611 merged
05:12:45  other session: #586 PR #612 merged
05:18:01  this batch: #541 PR #613 merged
05:37:04  other session: #587 design committed
```

### Observations

- **Zero merge conflicts**: Despite ~16 merges to `main` from two independent sessions over ~4h 43m, no merge failures were reported by either session's wrapper logs. Worktree-based branch isolation (`worktree-code+issue-N`) plus the PR merge model (each PR fetches and rebases at merge time) absorbed the concurrent base movement.
- **Mergeability pre-check ran while it was being implemented**: #541 was implementing a base-mergeability pre-check for `run-code.sh`. During its own code phase, the concurrent session merged #608, #610, #612 into `main` — exactly the scenario #541's pre-check is designed to detect. None of these caused #541's own merge to fail, since the PR rebase at merge time resolved any base drift.
- **No spawn-recovery cascades observed**: The single Tier 3 recovery (in #554) was triggered by a PR creation race, not a concurrent-merge race. No other anomaly was attributable to the concurrent session.

This is the first empirical data point for concurrent `/auto` safety on a single repository. The result is encouraging but the sample is small (one paired run with ~16 merges); no general claim is warranted.

## Verify Phase Observations

The batch wrapper (`run-auto-sub.sh`) executes spec → code → review → merge for each issue but does **not** invoke the verify phase from within the wrapper (verify is a parent-session Skill invocation in single-Issue auto routes — `Skill(skill="wholework:verify", args="$NUMBER")`). For `--batch` List mode, the design assumes the parent session orchestrates verify after each child wrapper returns; in this run, the parent session deferred verify because the user announced they were stepping away and asked the run to leave manual ACs for later.

Final state of all 6 issues:

| Issue | State | Label | Reason |
|-------|-------|-------|--------|
| #581 | CLOSED | phase/verify | PR #602 closed via `closes` reference; verify-type post-merge ACs not yet checked |
| #554 | CLOSED | phase/verify | Same |
| #548 | CLOSED | phase/verify | Same |
| #547 | CLOSED | phase/verify | Same |
| #546 | CLOSED | phase/verify | Same |
| #541 | CLOSED | phase/verify | Same |

All 6 carry observation-type / future-event post-merge ACs (the design-level expectation for retro-generated improvement issues): real watchdog kill recurrence, real fix-cycle reconcile behavior, fullPage screenshot fidelity in CI, etc. These are scheduled to close via `/verify N` when their triggering events occur in normal operation — they are not session-completable.

**Gap surfaced**: The batch wrapper's deliberate exclusion of verify means the `phase/verify` label is the universal terminal state for batch-completed issues, regardless of whether their ACs are pseudo-environment-testable today or are observation-type only. The 2026-06-13 report's structural fix (#583, `verify-type: observation event=<name>`) would let the verify phase classify ACs and auto-PASS the observation type — but this batch run did not exercise that path because verify never ran.

## Recovery Audit Trail Updates

The Tier 3 recovery on #554 produced an entry on `docs/reports/orchestration-recoveries.md` via the `run-auto-sub.sh` recovery emission path. No fallback-catalog entries were applied (Tier 2 returned empty detector output, escalating directly to Tier 3).

## Evaluation

### What worked

1. **Sequential batch wrapper held**: 6 consecutive `run-auto-sub.sh` invocations completed cleanly under an Opus 4.7 parent. No wrapper-level state corruption, no skipped phases.
2. **Tier 3 recovery first run was clean**: The recovery sub-agent produced a valid plan (passed `validate-recovery-plan.sh`), executed it, and the wrapper continued without parent intervention. The sub-agent's existence is proven beyond synthetic tests.
3. **Concurrent session safety**: ~16 merges to `main` from two `/auto` sessions, zero conflicts. Worktree isolation + PR rebase at merge time absorbs concurrent base movement at this scale.
4. **Parent idle time genuinely zero**: User informed the parent of the absence early; the run sustained 4h 43m of continuous progress with no input wait. The 1.27 issues/hr throughput is the floor (PR-route only, M-size dominant), not the ceiling.

### Limits and gaps

1. **Verify exclusion → universal phase/verify terminal state**: All 6 batch-completed issues sit at `phase/verify`. The batch wrapper does not run verify, and the parent session deferred it. The user can `/verify N` per issue, but at scale the batch terminal state collapses to a single bucket regardless of AC verifiability. The fix proposed in #583 (event-driven observation type) addresses the AC-side issue but does not change the batch-wrapper-side exclusion.
2. **Size re-judgement does not re-route a running issue**: #581 and #548 were re-judged M→XS during spec, but the in-flight `pr` route was not reduced to `patch`. This is documented (Step 3a applies on the next routing decision), but the duration cost is real — #581 paid 38 min of code+review+merge for a documentation-only ADR that a patch route would have closed in ~10 min.
3. **Sample size for concurrent safety claim is one paired run**: The zero-conflict result is encouraging but not statistically meaningful. A deliberate stress test (two sessions both touching `skills/` files concurrently) would be needed to claim general safety.
4. **`--batch` List mode value vs. single-session is unmeasured here**: The single-session report (`auto-parent-session-comparison-2026-06-14.md`) concluded `--batch` is not recommended. This run does not contradict that — it shows `--batch` is safe and concurrent-tolerant, not that it is preferable. Throughput (1.27/hr) is below the single-session baseline (2.4/hr in the comparison report), consistent with the M-heavy issue mix rather than batch overhead.

### Improvement candidates surfaced

(Not filed as issues from this report — to be decided by the user.)

1. **Batch wrapper verify orchestration**: Either invoke `/verify` per child issue from the parent session after each `run-auto-sub.sh` returns (List mode could do this between issues), or document that batch mode always terminates at `phase/verify` and requires follow-up `/verify N`. The current behavior is correct but silently produces a backlog.
2. **In-flight route demotion on Step 3a re-judge**: When spec re-judges Size from M to XS, the remaining phases (code, review, merge) could be re-planned to the patch route. This would have saved ~25 min each for #581 and #548. The trade-off is added complexity in the phase orchestrator and is probably not worth it for a heuristic case — but worth raising.
3. **Tier 3 sub-agent invocation logging**: The trace was captured in the wrapper log only. A summary line in `docs/reports/orchestration-recoveries.md` keyed on `source: recovery-sub-agent` (currently marked "available after #316 ships" in the auto skill) would close the audit-trail loop.

## Conclusion

The `--batch` List mode run of 6 issues completed cleanly under an Opus 4.7 parent over 4h 43m of continuous execution. The two notable production firsts are (1) a Tier 3 recovery sub-agent invocation that resolved without parent intervention, and (2) coexistence with a concurrent single-session `/auto` on the same repository without merge conflict. Throughput at ~1.27 issues/hr is consistent with the M-heavy issue mix.

The unresolved structural observation is the universal terminal `phase/verify` state for batch-completed issues — a wrapper-design gap that the AC-side fix (#583, event-driven observation type) does not address. Either batch mode should orchestrate verify between issues, or the design should be acknowledged as "batch terminates at verify, user runs `/verify N` per follow-up."

---

## Follow-up: Improvement Issues Filed + Second Batch + Single-Issue Run

After the primary batch and report-writing finished, the same session continued with three follow-on `/auto` runs that exercised additional code paths. Adding them here both as raw data and as a check on the report's own predictions.

### Improvement Issues Filed from the Report

Three improvement candidates from the "Improvement candidates surfaced" section above were filed at the user's request:

| # | Title (truncated) | Source candidate |
|---|---|---|
| #615 | auto: --batch List モードで Issue 間 verify を親セッションがオーケストレート | 1. Batch wrapper verify orchestration |
| #616 | auto: Step 3a 再判定で実行中ルートを M/pr → patch に縮退 | 2. In-flight route demotion on Step 3a re-judge |
| #617 | auto: Tier 3 recovery sub-agent 起動を orchestration-recoveries.md に記録 | 3. Tier 3 sub-agent invocation logging |

### Wave 2: `/auto --batch 615 616 617`

Same Opus 4.7 parent, same `--batch` List mode wrapper. All 3 issues started with no phase labels and went through full triage → spec → code → review → merge.

| Issue | Size/Route | Duration (triage + run-auto-sub) | PR | Result |
|-------|-----------|----------------------------------|-----|--------|
| #615 | M / pr | ~50 min (06:42→07:32 JST: 7m triage + 42m spec→code→review→merge) | #619 | CLOSED / phase/verify (clean) |
| #616 | M / pr | ~57 min (07:40→08:37 JST: 10m triage + 47m spec→code→review→merge) | #620 | CLOSED / **phase/review** (anomaly — see below) |
| #617 | M / pr | ~70 min (08:39→09:38 JST: 10m triage + 60m spec→code→review→merge) | #622 | CLOSED / phase/verify (clean, long silent windows during spec — 1080s) |

Wall-clock: ~3h (06:42→09:38 JST). Throughput: ~1.0 issues/hr (slower than Wave 1's 1.27/hr because Wave 2 added a triage phase per issue).

### Anomaly: #616 stuck at phase/review after merge

`run-auto-sub.sh` for #616 exited 0; PR #620 was actually MERGED at 2026-06-13T23:36:01Z; issue auto-closed via PR's `closes #616`. But the phase label remained `phase/review` — the `merge → verify` label transition was missed inside the merge child wrapper. Manual `gh-label-transition.sh 616 verify` corrected it. `reconcile-phase-state.sh merge 616 --pr 620 --check-completion` returned `matches_expected: true` (merge succeeded), so the existing wrapper validation could not detect the gap.

This is a **previously-unobserved wrapper anomaly**. Same flow on #615 and #617 transitioned correctly, so the issue is non-deterministic — likely a `claude -p` early-stop between `gh pr merge` and `gh-label-transition.sh` calls inside the merge skill.

The anomaly was filed as **#624 — merge: PR merge 後の phase/review → phase/verify ラベル遷移漏れを検出・補正** (Size S, patch route).

### Wave 3: `/auto 624` (single-issue, patch route)

Same Opus 4.7 parent. Single-issue auto under patch route.

| Phase | Duration | Result |
|-------|----------|--------|
| triage (run-issue.sh) | ~7 min (10:23→10:30 JST) | Size assigned S (proposal was M); AC verify commands corrected from `section_contains` (inapplicable to shell scripts) to `grep` x2. Auto-Resolved Ambiguity Points recorded. |
| spec (run-spec.sh) | ~10 min (10:30→10:40 JST) | Option A (run-merge.sh completion-check extension) selected. |
| code --patch (run-code.sh) | ~8 min (10:40→10:48 JST) | Direct commit to main: `run-merge.sh` extended to detect `phase/review` stuck and auto-transition. bats 17/17 PASS (new test case "label stuck: merge succeeded but phase/review label stuck, auto-transitions to verify"). Implementation commit `6f6f29f`. |
| verify (parent-session Skill) | ~30 min (incl. retro write and improvement-Issue filing) | Pre-merge 3/3 PASS. Post-merge AC4 PASS via **alternative verification** (see below). Post-merge AC5 deferred (observation type). |

Total: ~55 min triage → code → verify; verify alone took half the run.

### What #624's verify exposed: a verify-command-design problem

Post-merge AC4 was written as:
```
<!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->
```

The verify command returned `""` (empty) — because `--limit=1` picked up the latest run on `main`, which was from a concurrent /auto session's push (issue #600, commit `7a918fca`, status `in_progress`), not from #624's own commit. The implementation commit (`3dec8ac8`) and design commit (`175b3cfe`) had `success` conclusions when filtered by `headSha`, but the AC's verify command did not filter by commit.

This is the same concurrent-session interference dynamic noted in the primary batch's "Concurrent /auto Session Coexistence" section, surfacing in a new place — verify command semantics. AC4 was marked PASS via alternative verification (filtered by commit manually) and an improvement issue was filed:

**#626 — verify-patterns: github_check の gh run list テンプレートに --commit フィルタを標準化**

### Summary of follow-up

| Metric | Value |
|--------|-------|
| Wave 2 issues processed (batch) | 3 (#615, #616, #617) |
| Wave 3 issues processed (single) | 1 (#624) |
| Wall-clock (Wave 2 + Wave 3) | ~4h 15m (06:42→11:00 JST, no idle) |
| Watchdog kills | 0 |
| Wrapper anomalies observed | 1 (#616 merge→verify label transition missed) |
| Parent session manual recoveries | 1 (`gh-label-transition.sh 616 verify`) |
| New improvement issues filed | 2 (#624, #626) |
| Verify phase invocations under `/auto` | 1 (Wave 3 #624 only; Wave 2 deferred per user request) |

### What the follow-up confirmed

1. **The phase/verify universal terminal state is real** — even when verify is run after a single-issue `/auto` (Wave 3 #624), the issue still ends at `phase/verify` due to its own `event=auto-run` observation AC. The wrapper-side gap (#615) and the AC-side gap (#583) are independent and both need addressing.
2. **Wrapper anomalies are not rare**: the previously-unobserved `phase/review` stuck path appeared on the very next batch. The Tier 3 recovery from Wave 1 (#554) and this new gap suggest the wrapper-anomaly surface is broader than the existing fallback catalog covers.
3. **Concurrent /auto safety holds in new dimensions, breaks in others**: 0 merge conflicts still (concurrent merges to main continued through Wave 2 + 3). But verify-command semantics broke under concurrent push — a new class of interference that the "Concurrent /auto Session Coexistence" claim did not anticipate.
4. **Triage's verify-command audit value re-confirmed**: #624's triage corrected an inapplicable `section_contains` (used for markdown headings, applied here to a shell script) to two `grep` calls. The same value pattern observed in the 2026-06-13 baseline report (3 triage repairs in 14 issues) recurred here in 4 issues. This is a stable property of the triage skill worth promoting.

### Loose ends

- **#624 itself ended at `phase/verify`** because its post-merge AC5 is `verify-type: observation event=auto-run`. The auto-recover behavior in `run-merge.sh` only triggers when a real merge label transition is missed — which by definition is non-deterministic. AC5 closes when a future `/auto` run exercises the recovery path.
- **#626 (the verify-command fix) is unprocessed.** The standard `--commit=$(git rev-parse HEAD)` form needs editing in `modules/verify-classifier.md` and `skills/issue/spec-test-guidelines.md`, plus migrating existing patch-route ACs. Defer to next session.
