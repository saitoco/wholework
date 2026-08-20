---
type: report
description: Cross-Issue orchestration recovery log. Append-only. Newest entries first.
---

# Orchestration Recovery Log

This file records cross-Issue recovery events, fallback applications, and diagnostics from `/auto` orchestration.

## Purpose and Role Division

**This file (orchestration-recoveries.md):**
- Scope: cross-Issue, persistent
- Role: Append-only log of symptom → recovery → outcome for recurrence detection
- Consumed by: `/audit recoveries` for frequency-based candidate detection

**Spec retrospective (per-Issue `docs/spec/issue-N-*.md`):**
- Scope: per-Issue, disposable (Spec-first principle)
- Role: Implementation-phase record of anomalies and improvement proposals
- These files are not long-term storage for cross-Issue knowledge

## Rotation / Archival Policy

- **Trigger**: when this live file exceeds 1500 lines (check with `wc -l docs/reports/orchestration-recoveries.md`). As with `orchestration-fallbacks-archive.md`, there is no automated hook — rotation depends on manual review (or incidental detection by `/audit fragility`).
- **Split boundary**: entries are ordered newest first, so rotation moves a contiguous block from the tail of the file (the oldest entries) into the archive, until the live file's line count returns to roughly 800 lines.
- **Archive destination**: `docs/reports/orchestration-recoveries-archive.md` (a single append-only archive, not date-split, matching `orchestration-fallbacks-archive.md`). The archive also preserves newest-first ordering, so each rotation's moved block is inserted directly under the archive's `## Archived Entries` heading (at the top).
- **Content preservation**: entries are moved verbatim, keeping the full `### Context` / `### Diagnosis` / `### Recovery Applied` / `### Outcome` / `### Improvement Candidate` structure (no summarization).
- **Effect on consumers**: `scripts/collect-recovery-candidates.sh` (and therefore `/verify` Step 15 and `/audit stats --retention` Section 10) only reads the live file, so archived entries drop out of frequency-grouping counts going forward. This is an accepted trade-off: the script's cutoff logic already excludes entries predating a resolved (CLOSED) Issue's `closedAt`, so the most recent entry for any still-open group-key always remains in the live file — what rotation actually discards is either already-excluded-from-counting entries, or entries old enough that they no longer inform recent-recurrence judgments.

## Entry Format

```markdown
## YYYY-MM-DD HH:MM UTC: <symptom-short>

### Context
- Issue #N, phase: <code-pr|code-patch|review|merge|verify>
- Source: <fallback-catalog|recovery-sub-agent|wrapper-anomaly-detector>
- Wrapper: <run-*.sh name>, exit code: <N> (or `iteration: <N>/<M>` — see `Outcome` below)
- Log tail: "<last relevant log line>"

### Diagnosis
- cause: <slug> (optional; short kebab-case root-cause label, e.g. `dirty-guard`. When
  present, `/audit recoveries` groups this entry under `<symptom-short>/<cause-slug>`
  instead of the bare `<symptom-short>`, separating occurrences by known root cause)
- notification: <class> (optional; one of `harness-stop`/`external-signal`/`indeterminate`/
  `unobserved` — classification of the task notification the parent session observed for the
  killed background task, written only by the manual recovery path
  (`run-auto-sub.sh --write-manual-recovery --notification`). Absent means the flag was not
  passed, distinct from `unobserved` which means the wording could not be confirmed. Does not
  participate in frequency grouping)
- <observed state inspection result and root cause hypothesis>

### Recovery Applied
- <catalog anchor (e.g., orchestration-fallbacks.md#anchor) or sub-agent plan excerpt or manual steps>

### Outcome
- <success|partial|failed|retry fired (iteration <N>/<M>)>

### Improvement Candidate
- <未起票|起票済み #NNN|N/A (resolved by known catalog)>
```

## Field Definitions

| Field | Description |
|-------|-------------|
| `symptom-short` | Short identifier for the symptom pattern (kebab-case). Frequency grouping key is `symptom-short`, or `symptom-short/cause-slug` when a `cause` line is present in `### Diagnosis` |
| `cause` | Kebab-case root-cause slug in `### Diagnosis` (e.g. `dirty-guard`). Optional at read time — pre-#1281 entries lack it. Separates occurrences of the same symptom by known root cause during frequency grouping. Always written by Tier 2 (`apply-fallback.sh`, value is the matched symptom anchor) and Tier 3 (`spawn-recovery-subagent.sh`, value is the recovery plan's `cause` field, `unclassified` when missing/invalid); optional for manual recovery (`run-auto-sub.sh --write-manual-recovery --cause`) |
| `notification` | Classification of the observed task notification wording in `### Diagnosis` (Issue #1153): `harness-stop`/`external-signal`/`indeterminate`/`unobserved`. Written only by the manual recovery path (`run-auto-sub.sh --write-manual-recovery --notification`), never by Tier 2/3. Line is absent when the flag was not passed (see `notification_class=unspecified` on the corresponding `manual_intervention` event). Does not participate in `/audit recoveries` frequency grouping — `cause` is the only grouping key |
| `Source` | Which mechanism detected and handled this recovery event |
| `Outcome` | `success` = phase completed; `partial` = partial recovery; `failed` = stopped; `retry fired (iteration <N>/<M>)` = the retry was fired but its result is not yet known at write time (Issue #1320: `code-retry-fire` entries are written immediately before an `exec`-based self-restart, which replaces the process before the retry's own outcome can be observed — see `modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire`) |
| `Improvement Candidate` | `未起票` = not yet filed; `起票済み #NNN` = filed as Issue #NNN; `N/A` = no action needed |

## Sources

| Source | Description | Dependency |
|--------|-------------|------------|
| `fallback-catalog` | Known pattern in `orchestration-fallbacks.md` was matched and applied | Available (#315 shipped) |
| `wrapper-anomaly-detector` | `detect-wrapper-anomaly.sh` detected a known failure pattern | Available (#313 shipped) |
| `recovery-sub-agent` | `orchestration-recovery` sub-agent diagnosed unknown failure | Available (#617 shipped) |

---

<!-- Log entries appear below, newest first. -->
## 2026-08-19 10:53 UTC: manual-recovery-verified-already-complete

### Context
- Issue #1410, phase: merge
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- notification: indeterminate
- External-kill detected mid-run; reconcile-phase-state.sh confirmed PR #1411 was already MERGED before the kill, so no respawn was needed

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-19 09:52 UTC: manual-recovery-respawn

### Context
- Issue #1410, phase: review
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- notification: indeterminate
- Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: respawn)

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-19 08:59 UTC: manual-recovery-respawn

### Context
- Issue #1410, phase: code-pr
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- notification: indeterminate
- Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: respawn)

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-17 07:02 UTC: review-tier3-recovery

### Context
- Issue #1387, phase: review
- Source: recovery-sub-agent
- Wrapper: run-review.sh (via run-auto-sub.sh), exit code: unknown
- Log tail: "[#1387] --- review phase (full): PR #1393 ---"

### Diagnosis
- cause: harness-task-stop
- `run-auto-sub.sh`'s background task was reported `killed`/`was stopped` by the harness immediately after the review phase started (no watchdog/timeout keyword, no numeric exit code, no persistent error). `scripts/detect-external-kill.sh` returned `no-match` and the Tier 2 anomaly detector matched no known pattern. The Tier 3 sub-agent found PR #1393 had zero comments/reviews and both worktree checkouts clean with nothing uncommitted — no partial state to recover, consistent with a harness-level stop rather than a genuine external signal or unrecoverable failure. A manual `bash scripts/run-review.sh 1393 --full` retry then hit a second, unrelated snag: a stale `review+pr-1393` worktree left locked by the killed attempt caused the retried `/review` to self-abort (exit 1, silent no-op) on a false-positive concurrent-session detection (it misread its own killed predecessor's leftover lock + a `ListAgents` entry for this very parent session as evidence of a live peer session). Unlocking and removing the stale worktree, then retrying `run-review.sh` a third time, succeeded cleanly.

### Recovery Applied
- action=retry (Tier 3 plan) + manual stale-worktree cleanup (`git worktree unlock` / `git worktree remove --force` / `git branch -D`) before the retry that actually succeeded
- steps: 0 (Tier 3 plan itself had no explicit steps; the worktree cleanup was performed by the parent session after the plan's first retry attempt hit the unrelated stale-worktree self-abort)

### Outcome
- success

### Improvement Candidate
- 未起票

---

## 2026-08-17 00:29 UTC: manual-recovery-conflict-resolve

### Context
- Issue #1273, phase: merge
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 143

### Diagnosis
- cause: concurrent-batch-merge-conflict
- watchdog killed merge phase after 600s silent window; PR #1383 was CONFLICTING with main due to concurrent batch issues (#1096/#1229/#1243/#1302) landing overlapping edits in the same files; parent session manually merged origin/main, resolved 3 conflicting files by combining both independent features, ran full bats suite (1826 tests green), pushed, and squash-merged

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-17 00:29 UTC: manual-recovery-respawn

### Context
- Issue #1273, phase: review
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- notification: indeterminate
- Background command was stopped (no numeric exit code observed)

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-16 08:22 UTC: manual-recovery-respawn

### Context
- Issue #1365, phase: code
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- cause: background-task-killed-mid-code-phase
- notification: indeterminate
- background wrapper stopped (status: killed) shortly after code phase started; no numeric exit code observed

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-16 07:43 UTC: manual-recovery-respawn

### Context
- Issue #1381, phase: code-patch
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- cause: harness-task-stop
- detect-external-kill.sh returned external-kill (no Exit code trailer, no wrapper_exit event, process group gone at ~22min elapsed) but the parent-observed task notification read status=killed / was stopped, which per upstream #82586 is the harness own kill path rather than an external signal; parent session had run 6d2h and this was its 3rd phase (issue 11m OK, spec 16m OK, code killed), matching upstream #76942 long-session pattern; respawn completed cleanly

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-14 21:57 UTC: code-retry-fire

### Context
- Issue #1355, phase: code-pr
- Source: run-code.sh auto-retry-on-fail
- Wrapper: run-code.sh, iteration: 1/3

### Diagnosis
- cause: silent-no-op
- reconcile-phase-state.sh --check-completion reported matches_expected:false (silent no-op) prior to this retry

### Recovery Applied
- modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire

### Outcome
- retry fired (iteration 1/3)

### Improvement Candidate
- 未起票

## 2026-08-10 03:51 UTC: manual-recovery-respawn

### Context
- Issue #1316, phase: code-pr
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- cause: external-kill
- code phase wrapper process group was SIGKILLed externally at ~5min elapsed, before its own EXIT trap could print a completion marker; respawned run-code.sh 1316 --pr resumed cleanly

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-10 03:34 UTC: manual-recovery-spec-rerun

### Context
- Issue #1130, phase: spec
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: background-notification-wait
- /spec declared a wait for a background bats suite completion notification; claude -p has no subsequent turn, so the process exited 0 without writing the Spec and run-spec.sh converted it to exit 1. Recovered by re-running run-auto-sub.sh from phase/spec.

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-08 22:08 UTC: wrapper-retry-on-kill

### Context
- Issue #1275, phase: merge
- Source: retry-on-kill.sh
- Wrapper: run-merge.sh, exit code: 0

### Diagnosis
- wrapper (run-merge.sh) が early-kill window (WHOLEWORK_RETRY_ON_KILL_MAX_SEC) 内に exit code 0 で終了し、retry-on-kill.sh が自動再試行した

### Recovery Applied
- modules/orchestration-fallbacks.md#wrapper-retry-on-kill

### Outcome
- success

### Improvement Candidate
- 未起票


## 2026-08-07 15:11 UTC: merge-tier3-recovery

### Context
- Issue #1227, phase: merge
- Source: recovery-sub-agent
- Wrapper: run-merge.sh, exit code: 143
- Log tail: "Finished at: 2026-08-08 00:07:19"

### Diagnosis
- run-merge.sh completed CI checks and the forbidden-expressions check successfully, then hung silently for 600s during the merge wait step until the watchdog killed it (exit 143). No error or conflicting state is indicated in the log, and reconcile_snapshot is empty so partial-completion state cannot be confirmed; a stalled but otherwise clean merge wait is best resolved by re-running the phase.

### Recovery Applied
- action=retry
- steps: none

### Outcome
- success

### Improvement Candidate
- 未起票

---

## 2026-08-07 14:06 UTC: manual-recovery-respawn

### Context
- Issue #939, phase: merge
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- cause: external-kill-during-merge
- merge phase killed ~3min after last output (watchdog threshold 600s not reached); detect-external-kill.sh matched signature; uptime 70h under concurrency; task notification wording: status=killed 'was stopped'

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票


## 2026-08-07 07:41 UTC: code-pr-tier3-recovery

### Context
- Issue #1224, phase: code-pr
- Source: recovery-sub-agent
- Wrapper: run-code-pr.sh, exit code: 1
- Log tail: "Finished at: 2026-08-07 16:40:59"

### Diagnosis
- Reconcile and repeated retries agree the phase never completed, but the worktree branch worktree-code+issue-1224 already has 3 unpushed commits ahead of main implementing the fix (last: c9a4de2d) and no PR exists yet. Five silent no-op retries wasted ~90 minutes re-running /code instead of pushing the existing work, so recovery pushes the branch and creates the PR directly instead of retrying again.

### Recovery Applied
- action=recover
- steps: 2 step(s)

### Outcome
- success

### Improvement Candidate
- 未起票

---

## 2026-08-07 07:22 UTC: manual-recovery-manual-recovery-commit-push-pr

### Context
- Issue #1234, phase: code-pr
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: background-notification-wait
- run-code.sh --pr silent no-op x4, exhausting auto-retry (3/3). Same failure mode as #1102/#1212/#1213 but recurring AFTER #1213 landed. The third attempt's log is decisive: 'bats tests/ フルスイートを実行中です。10分のタイムアウトを超えたためバックグラウンドに移行しました。完了通知を待って Step 9 以降を継続します。' #1213 mandates foreground execution with an explicit timeout of 600000ms, but 600000ms IS the Bash tool ceiling - once a full suite exceeds it the tool auto-moves the command to the background, and the agent then waits on a notification that never arrives in a claude -p surface. So an explicit timeout does not guarantee foreground execution; it only defers the same failure. Implementation was complete (6 files matching the Spec Changed Files) but uncommitted in worktree code+issue-1234 when the retry budget ran out. Parent session recovered manually: inspected the diff, ran the suite in PARALLEL (bats --jobs 18) which completed well inside the window with 1516 passed / 0 failed, committed with sign-off as 21429b96, pushed, and created PR #1246. Parallelisation is the candidate fix - the serial suite exceeds 10 minutes on this machine while CI runs it in 2-3 minutes.

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-07 06:34 UTC: manual-recovery-reconcile-override

### Context
- Issue #1166, phase: code-pr
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: operate-route-pr-dispatch-mismatch
- run-auto-sub.sh dispatched code-pr from Size M without honoring the Spec-derived operate route; operate produces no PR so the code-pr completion check failed, while code-patch --check-completion reports matches_expected:true via the operate execution-log marker.

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票


## 2026-08-07 05:51 UTC: code-pr-tier2-recovery

### Context
- Issue #1167, phase: code-pr
- Source: fallback-catalog
- Wrapper: run-code-pr.sh
- Log tail: "Finished at: 2026-08-07 14:51:28"

### Diagnosis
- Symptom anchor `json-mode-silent-hang` matched in wrapper log (modules/orchestration-fallbacks.md#json-mode-silent-hang)

### Recovery Applied
- action=run-code.sh-pr-retry

### Outcome
- success

### Improvement Candidate
- N/A (resolved by known catalog)

---

## 2026-08-07 04:11 UTC: manual-recovery-push-only

### Context
- Issue #1223, phase: code-patch
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: background-notification-wait
- 3rd consecutive occurrence of the same failure mode, and the first since #1213's guard-hoist fix (38663cb3) landed. All 3 auto-retry attempts of run-code.sh ended their turn with a background-wait sentence ('bats tests/ のバックグラウンド完了を待ちます (ポーリングはせず、通知を待機)') instead of reaching the commit/push step; claude -p has no re-invocation guarantee, so the notification never arrived and reconcile-phase-state reported silent no-op each time. Retry 3 did produce the implementation and committed it to worktree-code+issue-1223 as 75bbb950 (worktree_commits_found=true), but never pushed to main. Tier 2 fallback anchor matched but its handler failed; the Tier 3 sub-agent's plan was rejected by validate-recovery-plan.sh because patch-route recovery legitimately requires 'git push origin main', which is on the forbidden-ops list — a structural blind spot for patch route. Parent session recovered manually: reviewed the 1-file diff against both pre-merge AC rubrics, cherry-picked 75bbb950 onto main as ab816d29, ran the 6 related bats files (127 pass / 0 fail), pushed, and force-removed the worktree left locked by the dead pid 55183.

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-07 03:55 UTC: manual-recovery-manual-recovery-review-uncommitted-work

### Context
- Issue #1213, phase: review
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 0

### Diagnosis
- cause: background-notification-wait
- Second consecutive occurrence of the same failure mode, this time on the very Issue that fixes it. /review (PR #1225) ended its turn with 'バックグラウンドタスクの完了通知を待ちます。' before reaching Step 12.2 (commit/push); run-review.sh uses claude -p --non-interactive with no re-invocation guarantee, so the notification never arrived. 4 files of review fixes were left uncommitted in worktree review+pr-1225. post-fallback-review-summary.sh recovered the completion signal but not the work; run-merge.sh blocked on review_incomplete_fallback=true and the Tier 3 sub-agent returned action=abort. Parent session recovered manually: inspected the diff, ran the full suite (1507 pass / 0 fail), committed with sign-off and pushed as 3a382d81, posted a decision=override fallback=true gate marker, and re-ran run-merge.sh. Notably the review findings identified a deeper cause than the Issue's own scope: modules/test-runner.md Step 2 hardcoded a 120s timeout while a full bats suite measures ~407s, so the #994 foreground-execution guard was unenforceable on its own - that pressure is what pushed agents to run_in_background. The spec phase of this same Issue was also watchdog-killed at 1800s after posting Design Complete, with no work lost.

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-07 02:13 UTC: manual-recovery-review-rerun

### Context
- Issue #1206, phase: review
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: ci-infra-outage-during-ci-wait
- GitHub Actions repo-wide outage: Validate skill syntax failed at Set up job with 'Failed to resolve action download info. Error: Service Unavailable' and macOS shell compatibility stalled QUEUED; run-review.sh returned exit 2 (PENDING) and Tier 3 sub-agent chose action=retry but the retry also failed (result=failed) since the outage persisted. Parent session diagnosed via gh run view --log-failed, re-ran the failed CI jobs (9/9 green after rerun), then re-ran run-review.sh which completed exit 0 in 35m45s. No code change was required.

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-07 01:54 UTC: manual-recovery-manual-recovery-review-uncommitted-work

### Context
- Issue #1212, phase: review
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 0

### Diagnosis
- cause: background-notification-wait
- /review (PR #1222) ended its turn stating it was waiting for a backgrounded 'bats tests/' completion notification before proceeding to Step 12.2 (commit/push). run-review.sh runs claude -p --non-interactive, which has no re-invocation guarantee, so the notification never arrived and the phase became a silent no-op with 4 files of MUST/SHOULD fixes left uncommitted in worktree review+pr-1222. post-fallback-review-summary.sh posted a substitute Response Summary, which recovered the completion signal but not the work; reconcile-phase-state.sh flagged review_incomplete_fallback=true and run-merge.sh correctly blocked the merge (Tier 3 sub-agent returned action=abort, judging it a human decision rather than a mechanical retry). Parent session recovered manually: inspected the diff, ran the full suite (1495 pass / 0 fail), committed with sign-off and pushed as e878a321, posted a decision=override fallback=true gate marker, and re-ran run-merge.sh. Same failure mode as #1102 but in the review phase, where no built-in auto-retry exists; the #994 guard in skills/code/SKILL.md has no counterpart in skills/review/SKILL.md.

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-07 00:19 UTC: manual-recovery-review-rerun

### Context
- Issue #1214, phase: review
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 143

### Diagnosis
- cause: ci-infra-outage-during-ci-wait
- GitHub Actions repo-wide outage stalled CI; /review went silent in ci_wait and was watchdog-killed at 5400s. Recovered by re-running CI on the same SHA (9/9 green) then retrying run-review.sh, which completed in 1200s.

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-06 08:26 UTC: manual-recovery-worktree-rebase

### Context
- Issue #1174, phase: verify
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: ff-only-merge-base-advanced
- Worktree Exit hit the true-side (main checked out) path of worktree-merge-push.sh; git merge --ff-only failed because a concurrent session advanced local main from 17cf13e3 to 67205df7 while the verify worktree was alive. No rebase fallback existed on that path (#1076), so the script exited 1. Recovered by rebasing worktree-verify+issue-1174 onto main and retrying.

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-06 07:30 UTC: manual-recovery-worktree-rebase

### Context
- Issue #1152, phase: spec
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: ff-only-merge-base-advanced
- spec phase の Worktree Exit で worktree-merge-push.sh が exit 1。ref-fetch が main の checkout により拒否され step 2 の in-place git merge --ff-only に落ちたが、並行セッションが main を進めていたため FF 不可で abort。catalog の documented escalation どおり step 5 相当の git -C .claude/worktrees/spec+issue-1152 rebase origin/main を手動実行し再実行して解消。conflict なし。#1076 が扱う経路の 3 件目

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 起票済み #1076 (closed 2026-08-06T07:37:58Z — worktree-merge-push.sh に base=current branch 経路の rebase fallback を追加)

## 2026-08-06 06:16 UTC: manual-recovery-worktree-rebase

### Context
- Issue #1179, phase: verify
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- cause: base-advanced-during-verify
- Concurrent /verify 1180 in another session pushed to main while the 1179 verify worktree was active, leaving the worktree branch behind base; git rebase main onto the worktree branch resolved it and ff-merge succeeded on retry

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 起票済み #1076 (closed 2026-08-06T07:37:58Z — worktree-merge-push.sh に base=current branch 経路の rebase fallback を追加)

## 2026-08-06 06:15 UTC: manual-recovery-worktree-rebase

### Context
- Issue #1180, phase: verify
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: ff-only-merge-base-advanced
- verify phase の Worktree Exit で worktree-merge-push.sh が exit 1。ref-fetch が main の checkout により拒否され step 2 の in-place git merge --ff-only に落ちたが、並行セッション (#1185 verify) が main を 2 コミット進めていたため FF 不可で abort。catalog の documented escalation どおり、親セッションが step 5 相当の git -C .claude/worktrees/verify+issue-1180 rebase origin/main を手動実行し、worktree-merge-push.sh を再実行して解消。conflict なし

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 起票済み #1076 (closed 2026-08-06T07:37:58Z — worktree-merge-push.sh に base=current branch 経路の rebase fallback を追加)


## 2026-08-06 04:45 UTC: review-tier3-recovery

### Context
- Issue #1174, phase: review
- Source: recovery-sub-agent
- Wrapper: run-review.sh, exit code: 143
- Log tail: "Finished at: 2026-08-06 13:33:33"

### Diagnosis
- run-review.sh completed CI wait successfully but then hung with no output for 2600s until the watchdog killed it (pid=31881); reconcile-phase-state confirms matches_expected=false because no Review Response Summary was posted to PR #1192. No partial artifact (comment, label transition) exists to salvage, so a clean re-run of the review phase is the safe recovery.

### Recovery Applied
- action=retry
- steps: none

### Outcome
- success

### Improvement Candidate
- 起票済み #1105 (Tier 2 に review 完了失敗パターンがなく Tier 3 が毎回 action=retry を出す構造)

---

## 2026-08-05 17:30 UTC: manual-recovery-merge-rerun

### Context
- Issue #1180, phase: merge
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: pre-merge-ac-command-unverifiable
- pre-merge AC #9 の verify command が command 型のため /review の safe mode で実行されず未チェックのまま残り、/merge の pre-merge AC gate が非対話モードでブロック。#1181 と同一原因の 2 件目。親セッションが PR ブランチ上で en/ja のコミット時刻一致を直接確認して AC をチェックし run-merge.sh を再実行

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-08-05 15:53 UTC: manual-recovery-merge-rerun

### Context
- Issue #1181, phase: merge
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: pre-merge-ac-command-unverifiable
- pre-merge AC #9 の verify command が command 型のため /review の safe mode で実行されず未チェックのまま残り、/merge の pre-merge AC gate が非対話モードでブロック。親セッションが PR ブランチ上で en/ja のコミット時刻一致を直接確認して AC をチェックし、run-merge.sh を再実行

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票


## 2026-08-05 15:44 UTC: review-tier3-recovery

### Context
- Issue #1181, phase: review
- Source: recovery-sub-agent
- Wrapper: run-review.sh, exit code: 1
- Log tail: "Finished at: 2026-08-06 00:03:38"

### Diagnosis
- CI checks completed successfully, but the review agent was killed by a transient 'API Error: 529 Overloaded' after ~21 minutes of watchdog silence, before producing any review output. PR #1183 has no reviews or comments, confirming no partial review state to recover — a clean re-run of the review phase is safe.

### Recovery Applied
- action=retry
- steps: none

### Outcome
- success

### Improvement Candidate
- 起票済み #1105 (Tier 2 に review 完了失敗パターンがなく Tier 3 が毎回 action=retry を出す構造)

---

## 2026-08-05 05:25 UTC: manual-recovery-review-rerun

### Context
- Issue #1168, phase: review
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- cause: background-test-wait
- run-review.sh exited as silent no-op twice while waiting on a backgrounded bats run; parent session applied the MUST/SHOULD fixes left uncommitted in the review worktree, then committed, pushed, and posted the Response Summary manually

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 起票済み #1175 (発生原因側: バックグラウンドテスト完了待ちによる silent no-op), #1174 (完了シグナル側: fallback Response Summary が未対応 MUST の merge 通過を許す)

## 2026-08-04 10:24 UTC: manual-recovery-merge-rerun

### Context
- Issue #1123, phase: merge
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: merge-rerun)

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

## 2026-07-31 19:12 UTC: manual-recovery-commit-push

### Context
- Issue #1135, phase: code-patch
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: 1

### Diagnosis
- Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: commit-push)

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票

