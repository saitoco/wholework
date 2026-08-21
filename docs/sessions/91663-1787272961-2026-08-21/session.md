# L3 Session Retrospective: 91663-1787272961

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-08-21T00:43:26Z
**Session end**: 2026-08-21T12:44:15Z
**Wall-clock**: 12:00:49
**Route mix**: patch: 7, pr: 3, xl: 0, unknown: 6

### Summary

| Metric | Value |
|---|---|
| Issues processed | 16 |
| Fully closed (phase/done) | N/A (--no-github) |
| phase/verify remaining | N/A (--no-github) |
| Throughput | 1.3 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Recovery success rate (tier) | T1: 0 recovered / 0 failed, T2: 0 recovered / 0 failed, T3: 0 recovered / 0 failed |
| Watchdog kills | 0 |
| Max silent window (any phase) | 1680s |
| Phase silent windows > threshold | 1 (issue:1) |
| Total token usage | input 5308 / output 1498715 |
| Concurrent commits detected | 2 |
| Parent session manual interventions | 4 |
| verify FAIL → reopen fix cycles | 0 |
| Backfilled phase_complete events | 0 |
| Retro proposal tiers (1/2/3) | 0 / 0 / 0 |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
| code-patch | 14 |
| code-pr | 7 |
| issue | 20 |
| merge | 6 |
| review | 9 |
| spec | 20 |
| verify | 31 |

### Sub-Issue Completion Timeline

| Issue | Size/Route | Duration | Phase breakdown | PR | Recovery | Notes |
|---|---|---|---|---|---|---|
| #758 | ?/? | 2026-08-21T12:19:28Z – 2026-08-21T12:21:33Z | verify 2m | — | T1:0/T2:0/T3:0 | — |
| #760 | ?/? | 2026-08-21T12:27:15Z – 2026-08-21T12:29:06Z | verify 1m | — | T1:0/T2:0/T3:0 | — |
| #765 | ?/? | 2026-08-21T12:33:44Z – 2026-08-21T12:35:38Z | verify 1m | — | T1:0/T2:0/T3:0 | — |
| #778 | ?/? | 2026-08-21T12:38:51Z – 2026-08-21T12:40:08Z | verify 1m | — | T1:0/T2:0/T3:0 | — |
| #804 | ?/? | 2026-08-21T12:43:03Z – 2026-08-21T12:44:15Z | verify 1m | — | T1:0/T2:0/T3:0 | — |
| #1057 | S/patch | 2026-08-21T05:40:22Z – 2026-08-21T06:29:38Z | code-patch 21m → issue 9m → spec 15m → verify 1m | — | T1:0/T2:0/T3:0 | Silent 1300s |
| #1071 | S/pr | 2026-08-21T06:32:06Z – 2026-08-21T08:50:10Z | code-pr 34m → issue 7m → merge 3m → review 63m → spec 25m → verify 2m | PR#1426 | T1:0/T2:0/T3:0 | Size S→L; Silent 1520s; 2 manual-recovery-respawn (code-pr, review) |
| #1100 | S/patch | 2026-08-21T10:41:45Z – 2026-08-21T11:16:49Z | code-patch 9m → issue 7m → spec 16m → verify 0m | — | T1:0/T2:0/T3:0 | Silent 970s |
| #1112 | S/patch | 2026-08-21T11:19:19Z – 2026-08-21T12:11:26Z | code-patch 23m → issue 9m → spec 16m → verify 1m | — | T1:0/T2:0/T3:0 | Size S→XS; Silent 1410s |
| #1154 | S/patch | 2026-08-21T08:53:05Z – 2026-08-21T09:38:45Z | code-patch 21m → issue 9m → spec 12m → verify 0m | — | T1:0/T2:0/T3:0 | Silent 1270s |
| #1245 | S/patch | 2026-08-21T04:29:11Z – 2026-08-21T05:36:31Z | code-patch 25m → issue 13m → spec 25m → verify 1m | — | T1:0/T2:0/T3:0 | Silent 810s phase=issue; 2 concurrent commits (false-positive — see Findings) |
| #1327 | S/patch | 2026-08-21T09:41:14Z – 2026-08-21T10:39:17Z | code-patch 28m → issue 8m → spec 18m → verify 0m | — | T1:0/T2:0/T3:0 | Silent 1680s |
| #1365 | ?/? | 2026-08-21T04:14:21Z – ? | — | PR#1425 | T1:0/T2:0/T3:0 | — |
| #1407 | M/pr | 2026-08-21T03:09:34Z – 2026-08-21T04:24:12Z | code-pr 18m → issue 6m → merge 2m → review 29m → spec 15m → verify 1m | PR#1425 | T1:0/T2:0/T3:0 | Silent 1110s; 1 manual-recovery-respawn (review) |
| #1412 | M/pr | 2026-08-21T01:38:16Z – 2026-08-21T03:06:12Z | code-pr 24m → issue 7m → merge 2m → review 30m → spec 18m → verify 2m | PR#1424 | T1:0/T2:0/T3:0 | Silent 1470s; 1 manual-recovery-respawn (review) |
| #1421 | S/patch | 2026-08-21T00:43:26Z – 2026-08-21T01:33:45Z | code-patch 24m → issue 7m → spec 14m → verify 2m | — | T1:0/T2:0/T3:0 | Size S→XS; Silent 1490s |

### Token Usage Aggregate

| Issue | Input tokens | Output tokens | Total |
|---|---|---|---|
| #1057 | 540 | 146594 | 147134 |
| #1071 | 400 | 139286 | 139686 |
| #1100 | 442 | 129837 | 130279 |
| #1112 | 528 | 151043 | 151571 |
| #1154 | 482 | 118851 | 119333 |
| #1245 | 498 | 168122 | 168620 |
| #1327 | 534 | 160067 | 160601 |
| #1407 | 586 | 151987 | 152573 |
| #1412 | 796 | 212047 | 212843 |
| #1421 | 502 | 120881 | 121383 |

### Recovery Events

(no Tier 1/2/3 recovery events — the 4 orchestration recoveries this session were all `manual-recovery-respawn` from the External kill pre-check, recorded in `docs/reports/orchestration-recoveries.md`, not the Tier 1/2/3 machinery)

### Verify Phase Residuals

(--no-github mode: cannot detect phase/verify residuals via live label lookup.)

### Concurrent Sessions Detected

- [2026-08-21T05:34:42Z] phase=code-patch sha=3d54461a author=Toshihiro Saito
- [2026-08-21T05:34:42Z] phase=code-patch sha=1b272de5 author=Toshihiro Saito

(Both are false positives — see Findings below. Both commits are #1245's own intermediate code-patch commits, misclassified as concurrent because their subject lines do not contain `#1245`.)

### Improvement Candidates Surfaced

(none — no Tier 3 recoveries or Tier 2 approaching recoveries-auto-fire threshold)

### Retro Proposal Tier Breakdown

(none)

## What worked

- **External kill pre-check + respawn resume worked cleanly 4/4 times.** All 4 `manual-recovery-respawn` events (issue #1071 code-pr, #1071 review, #1407 review, #1412 review) were diagnosed correctly via `detect-external-kill.sh`, respawned with the same `run-*.sh` arguments, and resumed via the `code_phase_milestone` checkpoint mechanism without redoing completed work. Each was recorded in `docs/reports/orchestration-recoveries.md` per the documented procedure.
- **Zero FAIL/UNCERTAIN across all verify passes.** Every one of the 16 Issues processed (10 batch + 5 observation-dispatch + reconciliation) resolved to PASS/SKIPPED on auto-verification targets; no reopen-fix cycles were triggered.
- **Real, concrete verification was performed for every Claude-executable post-merge condition**, rather than assumption-based judgment:
  - #1412: live `gh run view`/job-log investigation of a CI bash-version failure
  - #1407: live typo-config test of `check-config-schema.sh` against a synthetic `.wholework.yml`
  - #1071: live extraction and standalone test of the fence-aware awk logic in `gh-issue-edit.sh`
  - #760: live execution of `get-auto-session-report.sh` against a historical Tier-2-recovery session to confirm Improvement Candidates Surfaced actually works
  - #765: source-level confirmation that all 3 `check-forbidden-expressions.sh` false-positive patterns are fixed, plus a live exit-0 check against the current repo
  - #778 / #804: cross-referenced a later real migration Issue (#1214) to confirm the symmetric `file_not_contains` / symbol-grep guidance is actually being applied in newly generated Specs
- **`recoveries-auto-fire.enabled: false` opt-out was respected correctly.** Despite the `manual-recovery-respawn` symptom count crossing the configured threshold (reaching 7 by session end), no auto-filed Issue was created — only the `Recommend: gh issue create ...` advisory line was printed each time, consistent with the repo's own prior deliberate decision (Issue #1179).
- **Run-fact AC reconciliation ran cleanly as a genuine judgment exercise**: of 13 pending post-merge candidates surfaced by `scan-pending-ac.sh`, 5 were confidently judged `not_satisfied` (route/Size mismatches directly readable from facts JSON) and 8 correctly deferred to `ambiguous`/advisory rather than being forced to a premature `satisfied`.

## Findings

- **`concurrent_commit_detected` false-positive recurrence (Issue #1245)**: `scripts/run-auto-sub.sh`'s self-commit exclusion filter (`_self_issue_pattern="#${issue}([^0-9]|$)"`, introduced by Issue #895's fix) only recognizes a self-commit as "not concurrent" when its subject line literally contains `#<issue-number>`. During #1245's own code-patch phase, two intermediate WIP commits (`3d54461a` "Fix bare bracket assertion in new precondition test", `1b272de5` "Add code-pr precondition test: Spec missing but Size XS") were created without the issue number in their subject — only the final commit carried it. Both were misclassified as `concurrent_commit_detected` events even though no other session was running. This is the same failure class #895 originally fixed (self-commits misread as concurrent activity), recurring because the fix's detection surface (commit subject text) doesn't cover every commit a single phase's own work can produce, only the one that happens to reference the Issue number. Confirmed via direct `git log` inspection of both SHAs — not a guess. [Filed: #1427]
- **Manual-recovery-respawn symptom count (7) has been above the `recoveries-auto-fire.threshold` (3) for multiple sessions** but `recoveries-auto-fire.enabled: false` in this repo means no Issue is ever auto-filed — only advisory `Recommend:` lines accumulate across runs with no forcing function to actually act on them. This is a known, deliberate repo-level trade-off (Issue #1179) rather than a new finding, so no action is proposed here beyond noting the advisory has now fired in 3+ consecutive `/verify` passes this session alone. [No action: deliberate opt-out per Issue #1179, already tracked]

## Skill Self-Update Propagation Note

Session 中に以下の skill が origin 上で更新されました (比較対象: origin/main)。ローカル main が追従できていない場合、本 session 内の以降の実行や次回セッションが更新前の版を使う可能性があります:
- skills/auto/SKILL.md: b54329559be3e6baee0aeb12732202b6006bd1fc → 6d806b95916b6cf65b0f3279c6444bba2aad8f79
- skills/code/SKILL.md: 64bc478d38c2455f7e33b724bf6254c0b7674093 → a7ecd3589cd56054e07121175276e0133cc3e700
- skills/spec/SKILL.md: 9e5f3f6edf89e3f833299fc3798f7642b3f3771e → 5e01a1b3764d8b84665881113f1791e24ea5a8e7
- skills/verify/SKILL.md: 9e5f3f6edf89e3f833299fc3798f7642b3f3771e → 6d806b95916b6cf65b0f3279c6444bba2aad8f79
- skills/review/SKILL.md: 9e5f3f6edf89e3f833299fc3798f7642b3f3771e → 6d806b95916b6cf65b0f3279c6444bba2aad8f79
- skills/merge/SKILL.md: 795e6d33db55d395673112fbc060ef46bd39fc33 → b5745101ca0208fd2731a6cce8f0b45104f63723
- skills/issue/SKILL.md: (no change)
- skills/audit/SKILL.md: f3feeb28721dbaf434cfdb39271aa4cfbef3932f → 6d806b95916b6cf65b0f3279c6444bba2aad8f79

これらの更新は本 session 自身の Issue 処理 (#1071/#1407/#1412/#1421 等の code/review/merge phase 実装) によるもので、外部起因ではない。

## Filed Issues

- #1427

## Auto Retrospective
### Improvement Proposals
- **`concurrent_commit_detected` false-positive recurrence (Issue #1245)**: `scripts/run-auto-sub.sh`'s self-commit exclusion filter (`_self_issue_pattern="#${issue}([^0-9]|$)"`, introduced by Issue #895's fix) only recognizes a self-commit as "not concurrent" when its subject line literally contains `#<issue-number>`. During #1245's own code-patch phase, two intermediate WIP commits (`3d54461a` "Fix bare bracket assertion in new precondition test", `1b272de5` "Add code-pr precondition test: Spec missing but Size XS") were created without the issue number in their subject — only the final commit carried it. Both were misclassified as `concurrent_commit_detected` events even though no other session was running. This is the same failure class #895 originally fixed (self-commits misread as concurrent activity), recurring because the fix's detection surface (commit subject text) doesn't cover every commit a single phase's own work can produce, only the one that happens to reference the Issue number. Confirmed via direct `git log` inspection of both SHAs — not a guess.
