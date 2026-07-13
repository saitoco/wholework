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

## Entry Format

```markdown
## YYYY-MM-DD HH:MM UTC: <symptom-short>

### Context
- Issue #N, phase: <code-pr|code-patch|review|merge|verify>
- Source: <fallback-catalog|recovery-sub-agent|wrapper-anomaly-detector>
- Wrapper: <run-*.sh name>, exit code: <N>
- Log tail: "<last relevant log line>"

### Diagnosis
- <observed state inspection result and root cause hypothesis>

### Recovery Applied
- <catalog anchor (e.g., orchestration-fallbacks.md#anchor) or sub-agent plan excerpt or manual steps>

### Outcome
- <success|partial|failed>

### Improvement Candidate
- <未起票|起票済み #NNN|N/A (resolved by known catalog)>
```

## Field Definitions

| Field | Description |
|-------|-------------|
| `symptom-short` | Short identifier for the symptom pattern (kebab-case, used for frequency grouping) |
| `Source` | Which mechanism detected and handled this recovery event |
| `Outcome` | `success` = phase completed; `partial` = partial recovery; `failed` = stopped |
| `Improvement Candidate` | `未起票` = not yet filed; `起票済み #NNN` = filed as Issue #NNN; `N/A` = no action needed |

## Sources

| Source | Description | Dependency |
|--------|-------------|------------|
| `fallback-catalog` | Known pattern in `orchestration-fallbacks.md` was matched and applied | Available (#315 shipped) |
| `wrapper-anomaly-detector` | `detect-wrapper-anomaly.sh` detected a known failure pattern | Available (#313 shipped) |
| `recovery-sub-agent` | `orchestration-recovery` sub-agent diagnosed unknown failure | Available (#617 shipped) |

---

<!-- Log entries appear below, newest first. -->
## 2026-07-13 16:58 UTC: manual-recovery-respawn

### Context
- Issue #1006, phase: spec
- Source: parent-session-manual-recovery
- Wrapper: run-auto-sub.sh, exit code: unknown

### Diagnosis
- Parent session recovered the phase outside the Tier 1/2/3 machinery (recovery type: respawn)

### Recovery Applied
- modules/orchestration-fallbacks.md#manual-recovery-spec-write

### Outcome
- success

### Improvement Candidate
- 未起票


## 2026-07-12 06:18 UTC: code-pr-tier3-recovery

### Context
- Issue #995, phase: code-pr
- Source: recovery-sub-agent
- Wrapper: run-code-pr.sh, exit code: 1
- Log tail: "Finished at: 2026-07-12 15:17:09"

### Diagnosis
- reconcile_snapshot と2サイクル分のログはPRが存在しないことのみ示すが、worktree-code+issue-995 の作業ツリーには実装完了済みの未コミット差分（14ファイル変更＋新規 tests/operate-route.bats）が残存しており、ブランチHEADはmainと同一（コミット未実施）。bats実行待ちのwatchdog killが繰り返され、コミット・push・PR作成の直前で毎回中断されたパターンと判断し、実装を確定させてPRを作成する。

### Recovery Applied
- action=recover
- steps: 3 step(s)

### Outcome
- success

### Improvement Candidate
- 未起票

---

## 2026-07-10 18:09 UTC: review-tier3-recovery

### Context
- Issue #983, phase: review
- Source: recovery-sub-agent
- Wrapper: run-review.sh, exit code: 1
- Log tail: "Finished at: 2026-07-11 02:47:05"

### Diagnosis
- Claude exited 0 but produced a silent no-op: reconcile shows matches_expected:false with diagnosis 'Review Response Summary not found in PR #983 comments'. No persistent/unrecoverable error in the log — CI checks completed and the review command simply never posted a response before the watchdog-adjacent timeout. Re-running the review phase should complete it.

### Recovery Applied
- action=retry
- steps: none

### Outcome
- success

### Improvement Candidate
- 未起票

---

## 2026-07-05 08:37 UTC: nested-verify-committed-to-review-worktree

### Context
- Issue #902, phase: review
- Source: recovery-sub-agent
- Wrapper: run-review.sh, exit code: 0 (review phase itself succeeded)
- Log tail: "`/verify 794` の中で誤って PR #928 のレビュー worktree にコミット、一時ブランチ経由 cherry-pick で origin/main に push"

### Diagnosis
- `/review 928 --full` 完了直前の Opportunistic Verification Step で `observation-trigger.sh --event pr-review-full` が Issue #794 にマッチ、`Skill(wholework:verify, args="794")` を dispatch。sub-session が Verify Retrospective 追記を review worktree (`worktree-code+issue-902` branch) に誤コミットし、リカバリのため一時ブランチ + cherry-pick + push を実施。この push (`ab6af076`) が権限分類器で正規フロー外検出され後続 op が block された

### Recovery Applied
- Sub-agent が一時ブランチ経由で `origin/main` へ docs-only 差分 (26 行の Verify Retrospective 追記のみ) を push、誤コミットは worktree ごと破棄。Issue #902 の実装 PR (#928) には影響なし。人間確認後 (2026-07-05 会話中で) 続行判断

### Outcome
- partial

### Improvement Candidate
- 未起票 (nested `/verify` が親 PR の worktree に commit してしまう構造的問題。`Skill()` 経由の `/verify` が呼び出し元の CWD をそのまま継承する挙動を分離する仕組みが必要)

## 2026-07-05 07:35 UTC: code-pr-silent-no-op

### Context
- Issue #902, phase: code-pr
- Source: manual-parent-recovery
- Wrapper: run-code.sh, exit code: 1
- Log tail: "Warning: claude exited 0 but code-pr phase did not complete (silent no-op) ... auto-retry: max iterations reached (3/3)"

### Diagnosis
- code-pr フェーズが worktree branch `worktree-code+issue-902` に実装コミット `ae0d6165` (4 files, +98) を作成したが、push / PR 作成に至らず終了。run-code.sh の auto-retry が 3/3 まで回ったが各回とも no-op (コミット済みを検知せず push+PR に進めなかった)。#906/#907 で対応中の `code-patch-silent-no-op` の pr-route 変種。standalone `run-code.sh --pr` は run-auto-sub.sh の `code_phase_milestone` (post-commit → push-and-pr) resume を持たないため取りこぼした。

### Recovery Applied
- parent session が worktree branch の commit を確認 (`git log origin/main..worktree-code+issue-902` で `ae0d6165` を検出) し、手動で `git push -u origin worktree-code+issue-902` + `gh pr create` (PR #909) を実行。以降 review → merge → verify は正常完走。

### Outcome
- success

### Improvement Candidate
- 起票済み #910 (code フェーズ follow-up の重複防止は別件だが同 retro で起票)。pr-route silent-no-op resume 欠如は #906/#907 の関連領域として要確認 (standalone run-code.sh --pr への milestone resume 適用)

## 2026-07-04 15:25 UTC: code-pr-tier3-recovery

### Context
- Issue #893, phase: code-pr
- Source: recovery-sub-agent
- Wrapper: run-code-pr.sh, exit code: 1
- Log tail: "Error: parent main has uncommitted changes. Resolve before proceeding."

### Diagnosis
- The uncommitted diff blocking check-verify-dirty is the /code phase's own L0 comment-consumption log entry written to docs/spec/issue-893-l3-findings-disposition-tags.md before the watchdog killed the process. It is a legitimate bookkeeping addition for issue #893, not unrelated stray work, so committing it on main clears the persistent dirty-tree block and allows the code-pr phase retry to proceed.

### Recovery Applied
- action=recover
- steps: 1 step(s)

### Outcome
- success

### Improvement Candidate
- 未起票

---

## 2026-07-03 06:23 UTC: worktree-path-misuse-parent-dirty

### Context
- Issue #882, phase: code-pr
- Source: parent session manual recovery (batch orchestration)
- Wrapper: run-code.sh, exit code: 0 (silent no-op — check-verify-dirty gate blocked auto-retry after parent-main contamination)
- Log tail: "[check-verify-dirty] classify=parent-main path=scripts/run-spec.sh / Error: parent main has uncommitted changes. Resolve before proceeding."

### Diagnosis
- During code-pr auto-retries, edits intended for the `code+issue-882` worktree landed as uncommitted changes directly in the parent main repo (2 tracked files: `docs/spec/issue-882-review-agent-not-registered.md`, `scripts/run-spec.sh`) instead of the worktree. The worktree itself was found completely clean (no diff, no extra commits), confirming the edits bypassed the worktree entirely. This is the same worktree-path-misuse failure mode already tracked in Issue #888 (`hook-worktree-path-guard.sh` suspected non-firing in `claude -p` subprocess sessions) — this occurrence recurred 2 more times during the same Issue's later phases (spec, code) but self-corrected each time; only this one instance left parent-repo contamination that blocked automated retry.
- Root cause (identified independently by #882's own spec phase): `run-*.sh` wrappers invoke `claude -p` without `--plugin-dir`, so the wholework plugin (and its `hooks/hooks.json` PreToolUse registrations) is not loaded in headless subprocess sessions.

### Recovery Applied
- `git stash push -u` on the 2 dirty parent-main files (safety net, not discarded), verified clean state, then manually re-ran `scripts/run-code.sh 882 --pr` once. The retry succeeded cleanly (PR #889 created) with one more self-corrected worktree-path incident recorded in the PR's Code Retrospective.
- A resulting merge conflict (PR branch and the manual-recovery-record commit on main both appended to the same Spec file region) was resolved manually via a temporary worktree, then pushed.

### Outcome
- success

### Improvement Candidate
- 起票済み #888 (root-cause investigation; #882's `--plugin-dir` fix, merged as part of PR #889, is expected to resolve this recurrence going forward — pending confirmation)

## 2026-07-02 06:45 UTC: code-pr-external-timeout-kill

### Context
- Issue #875, phase: code-pr
- Source: recovery-sub-agent
- Wrapper: run-code.sh, exit code: killed (no explicit exit code — external Bash-tool timeout, not a script-internal failure)
- Log tail: "watchdog: still waiting (json mode), silent for 660s (pid=39967)"

### Diagnosis
- `run-code.sh 875 --pr` was invoked by the `/auto` parent session via `Bash(timeout: 600000, run_in_background: true)`, following `skills/auto/SKILL.md`'s literal pr-route Step 4 instruction. The process was killed externally at ~660–720s while still mid-flight. By kill time, all 7 implementation commits were already made locally and DCO-signed, matching the Spec (`git status` clean, `git log main..HEAD` showed the full expected commit set) — only push + `gh pr create` remained. Tier 1 (`reconcile-phase-state.sh code-pr --check-completion`) correctly reported `matches_expected: false` (no PR). Tier 2 (`detect-wrapper-anomaly.sh`) found no known pattern (log shows only watchdog heartbeat lines, no error signature). This is a distinct variant from the 5 prior `code-pr-tier3-recovery` entries below and the 2026-06-05 "watchdog kill before PR creation" entry (Issue #522) — those were killed by `run-auto-sub.sh`'s own *internal* watchdog before commit; this one was killed by the *external* Bash-tool timeout parameter after commit, in a non-batch single-issue `/auto` run calling `run-code.sh` directly.

### Recovery Applied
- Tier 3 `orchestration-recovery` sub-agent correctly diagnosed the "commits done, push/PR pending" state and proposed a 3-step `recover` plan: `git push origin worktree-code+issue-875` → `gh pr create` → `scripts/gh-label-transition.sh 875 review`. Validated by `validate-recovery-plan.sh` (exit 0) and applied successfully. Second Tier 1 check confirmed `matches_expected: true` (PR #879 OPEN).

### Outcome
- success

### Improvement Candidate
- 起票済み #880 (root cause: `skills/auto/SKILL.md`'s hard-coded `timeout: 600000` for `run-code.sh`/`run-review.sh`/`run-merge.sh` calls conflicts with `run-*.sh`'s own watchdog design, which is built to tolerate long silent windows; confirmed by this same session's review (~20min) and merge phases both completing naturally when invoked with `run_in_background: true` and no explicit timeout)

## 2026-06-27 18:15 UTC: code-pr-tier3-recovery

### Context
- Issue #775, phase: code-pr
- Source: recovery-sub-agent
- Wrapper: run-code-pr.sh, exit code: 143
- Log tail: "Finished at: 2026-06-28 03:06:16"

### Diagnosis
- Watchdog killed the process (SIGTERM, exit 143) after 1800s of silence in JSON mode with no persistent artifacts — the reconcile snapshot confirms no open PR and no commits for branch worktree-code+issue-775. Since the phase left no partial state requiring manual cleanup, a clean retry is the appropriate and safest recovery action.

### Recovery Applied
- action=retry
- steps: none

### Outcome
- success

### Improvement Candidate
- 起票済み #799

---

## 2026-06-27 16:54 UTC: code-pr-tier3-recovery

### Context
- Issue #769, phase: code-pr
- Source: recovery-sub-agent
- Wrapper: run-code-pr.sh, exit code: 143
- Log tail: "Finished at: 2026-06-28 01:52:57"

### Diagnosis
- Watchdog killed run-code.sh after 1800s of silence. The implementation is complete (5 commits in the worktree branch worktree-code+issue-769) but uncommitted test additions remain in 5 .bats files (15 lines), the branch has not been pushed, and no PR was created. Recovering by committing the remaining test changes, pushing the feature branch, creating the PR, and advancing the phase label to review.

### Recovery Applied
- action=recover
- steps: 4 step(s)

### Outcome
- success

### Improvement Candidate
- 起票済み #799

---

## 2026-06-27 15:39 UTC: code-pr-tier3-recovery

### Context
- Issue #770, phase: code-pr
- Source: recovery-sub-agent
- Wrapper: run-code-pr.sh, exit code: 143
- Log tail: "Finished at: 2026-06-28 00:38:19"

### Diagnosis
- Watchdog killed the /code session after 1800s of silence (exit 143) before PR creation. Reconcile confirms no open PR exists for the worktree-code+issue-770 branch. The 30-minute silent run in JSON mode indicates Claude Code was actively working but was killed before committing, pushing, or creating the PR. Recovery commits any uncommitted implementation work in the worktree, pushes the feature branch, and creates the PR.

### Recovery Applied
- action=recover
- steps: 3 step(s)

### Outcome
- success

### Improvement Candidate
- 起票済み #799

---

## 2026-06-20 20:45 UTC: code-pr-tier3-recovery

### Context
- Issue #729, phase: code-pr
- Source: recovery-sub-agent
- Wrapper: run-code-pr.sh, exit code: 143
- Log tail: "Finished at: 2026-06-21 05:43:56"

### Diagnosis
- Watchdog killed the /code process (exit 143, SIGTERM) after 1800 seconds of uninterrupted silence in json mode — the 30-minute runtime strongly suggests Claude Code was actively implementing but was terminated before commit, push, or PR creation. Reconcile confirms no open PR exists for the worktree-code+issue-729 branch. Recovering by locating the worktree, committing any pending changes, pushing the feature branch, and creating the PR.

### Recovery Applied
- action=recover
- steps: 3 step(s)

### Outcome
- success

### Improvement Candidate
- 起票済み #799

---

## 2026-06-15 18:20 UTC: code-pr-tier3-recovery

### Context
- Issue #675, phase: code-pr
- Source: recovery-sub-agent
- Wrapper: run-code-pr.sh, exit code: 143
- Log tail: "Finished at: 2026-06-16 03:05:26"

### Diagnosis
- Watchdog killed the process (exit 143) after 1800 seconds of silence before any implementation work was committed. The branch worktree-code+issue-675 exists but sits at the same commit as main — no code was written, no PR was created. This is a clean-slate transient hang (likely an API stall during initial /code startup), so a straight retry is safe and sufficient.

### Recovery Applied
- action=retry
- steps: none

### Outcome
- success

### Improvement Candidate
- 起票済み #799

---

## 2026-06-15 09:58 UTC: code-patch-tier3-recovery

### Context
- Issue #658, phase: code-patch
- Source: recovery-sub-agent
- Wrapper: run-code-patch.sh, exit code: 1
- Log tail: "Finished at: 2026-06-15 18:45:57"

### Diagnosis
- Claude exited 0 (no crash, no watchdog kill) but produced no commit on origin/main — a silent no-op. The 360-second silence followed by a 'test running' message suggests Claude was executing tests but failed to complete the commit step before exiting. This is a transient execution gap rather than a structural conflict; a single retry is low-risk and the appropriate first response.

### Recovery Applied
- action=retry
- steps: none

### Outcome
- success

### Improvement Candidate
- 起票済み #727

---

## 2026-06-14 18:02 UTC: code-patch-tier3-recovery

### Context
- Issue #486, phase: code-patch
- Source: recovery-sub-agent
- Wrapper: run-code-patch.sh, exit code: 143
- Log tail: "Finished at: 2026-06-15 02:41:13"

### Diagnosis
- Exit code 143 is SIGTERM (watchdog kill after the 30-minute timeout). The reconcile snapshot confirms no commit with 'closes #486' exists on origin/main, so the phase produced zero persistent state — the worktree is either clean or contains uncommitted work that was not yet ready to land. Because the patch route commits directly to main, a partial commit would be unsafe; a clean retry is the lowest-risk path that allows the implementation to run to completion.

### Recovery Applied
- action=retry
- steps: none

### Outcome
- success

### Improvement Candidate
- 起票済み #727

---

## 2026-06-14 16:01 UTC: code-patch-tier3-recovery

### Context
- Issue #489, phase: code-patch
- Source: recovery-sub-agent
- Wrapper: run-code-patch.sh, exit code: 1
- Log tail: "Finished at: 2026-06-15 00:47:59"

### Diagnosis
- Claude exited 0 but produced no commit (silent no-op). The working tree is unmodified and origin/main has no 'closes #489' commit, so state is clean with no partial artifacts to clean up. A single retry is the minimal safe recovery — the /code skill may have silently skipped on the first run.

### Recovery Applied
- action=retry
- steps: none

### Outcome
- success

### Improvement Candidate
- 起票済み #727

---

## 2026-06-15 00:25 UTC: Silent no-op when prior Issue's merge already satisfied AC (#490)

### Context
- Issue #490, phase: code-patch
- Source: recovery-sub-agent
- Wrapper: run-code.sh (via run-auto-sub.sh), exit code: 1
- Log tail: "Warning: claude exited 0 but code-patch phase did not complete (silent no-op). reconcile: {..., \"diagnosis\":\"no commit with closes #490 found on origin/main\"}"

### Diagnosis
- Issue #491 (predecessor in batch sequence) had just merged commit 70e45fd which added `modules/verify-patterns.md` §13 with `cron` + `workflow_dispatch` content
- #490's three Pre-merge ACs (`grep cron`, `section_contains §13 cron`, `section_contains §13 workflow_dispatch`) were already satisfied by #491's commit
- code phase Claude correctly identified ACs as already met and produced no commit
- Auto-Resolved Ambiguity Points in Issue body already noted: "#491 が本 Issue の受け入れ条件を実質カバー"

### Recovery Applied
- Tier 1 (reconcile) flagged commits_found=false → mismatch
- Tier 2 (wrapper-anomaly-detector) did not match a known pattern
- Tier 3 (recovery-sub-agent) returned `action=abort` with rationale "Human review needed to determine why Claude declined to implement"
- Manual recovery: parent session verified all 3 Pre-merge ACs pass via direct grep/section_contains; ran /verify Skill; posted comment with #491-coverage context; transitioned label to phase/verify

### Outcome
- partial (manual intervention required to convert silent no-op to verify-pass + record Spec retrospective)

### Improvement Candidate
- 未起票 — possible patterns: (a) Issue body Auto-Resolved Ambiguity Points propagation into code phase context; (b) reconciler awareness of "already-satisfied via predecessor commit" via grepping closes #N for related Issue numbers mentioned in body. Both have over-fit risk; leave manual handling for now.

## 2026-06-14 09:54 UTC: Tier 3 retry against deterministic route mismatch (#507, retry failed)

### Context
- Issue #507, phase: code-patch (route was patch after Step 3a re-detect; wrapper still used code-pr for reconcile)
- Source: recovery-sub-agent
- Wrapper: run-code.sh (via run-auto-sub.sh), exit code: 1 (after retry)
- Log tail: "Warning: claude exited 0 but code-pr phase did not complete (silent no-op). reconcile: {..., \"diagnosis\":\"no open PR found for worktree-code+issue-507 branch (stage2 recovery delegated to #316)\"}"

### Diagnosis
- Spec phase re-judged Size M → S (patch route per Step 3a)
- `run-auto-sub.sh` ran `run-code.sh 507 --patch`, which correctly committed to main and auto-closed Issue via `closes #507`. Commits 69a99d7, 1329f61, 5a66708 landed on main; Issue moved to CLOSED + `phase/verify`
- However, the wrapper's end-of-run reconcile call was hard-coded to `reconcile-phase-state.sh code-pr 507 --check-completion`, which looks for an open PR for `worktree-code+issue-507`. No PR exists in patch route → `matches_expected: false` → wrapper exits 1
- Tier 3 sub-agent received the false-failure signal, produced `action=retry`, and re-invoked `run-code.sh`. The retry re-attempted patch-route commit (cleaning stale worktree first), succeeded structurally — but the reconcile call again checked `code-pr`, hit the same mismatch, and returned exit 1 again
- Root cause: phase identifier passed to reconcile-phase-state is determined before route re-detection, not after. `action=retry` cannot resolve a deterministic logic mismatch by re-running the same wrapper with the same arguments

### Recovery Applied
- Tier 3 sub-agent retry: failed (wrapper exit 1 reproduced)
- Parent-session manual recovery: observed real state via `gh issue view 507` (CLOSED + `phase/verify` + 3 implementation commits with `closes #507`). Concluded that code phase had actually completed. Ran `Skill(wholework:verify, args="507")` manually, which PASSed all 3 pre-merge ACs and SKIPPED 3 post-merge manual ACs (require saito/trading)

### Outcome
- partial — code phase actually succeeded; reconcile incorrectly reported failure; parent session manually advanced to verify

### Improvement Candidate
- 起票済み #637 (reconcile-phase-state: size 再判定後の patch 経路で code-pr phase 判定が残るための route mismatch を解消)

## 2026-06-14 09:09 UTC: merge phase wrote Phase Handoff to parent main repo without committing (#508)

### Context
- Issue #508, phase: merge (PR #635 squash-merged successfully)
- Source: parent-session manual recovery (not auto-logged by wrapper; appended retroactively via `/audit recoveries` backfill)
- Wrapper: run-merge.sh (via run-auto-sub.sh), exit code: 0
- Log tail: (merge wrapper completed cleanly per `run-auto-sub.sh` Completed banner at 2026-06-14T18:07:22 JST)

### Diagnosis
- PR #635 was squash-merged to main correctly. Implementation commits landed; Issue auto-closed via `closes #508`
- However, the merge wrapper's Phase Handoff append (the `## Phase Handoff <!-- phase: merge -->` section added to `docs/spec/issue-508-post-merge-manual-verify-cli.md`) was written to the **parent session's main repo working tree**, not to the merge phase's own worktree. The change was uncommitted in the parent's index
- Verified by `git log` showing the upstream `main` already had the same content (`Patch contents already upstream` on rebase) — so the merge wrapper DID push the Phase Handoff from its worktree at some earlier step. The leak was specifically into the parent's working-tree state
- When the parent session subsequently ran `/verify 508`, Step 1's `check-verify-dirty.sh 508` detected the dirty spec file and exited 1, blocking verify until cleanup

### Recovery Applied
- Parent-session manual recovery: ran `git add docs/spec/issue-508-post-merge-manual-verify-cli.md && git commit -s && git push origin main`. Push was rejected (non-fast-forward) because remote was ahead. `git pull --rebase origin main` then dropped the local commit (`Patch contents already upstream`). Parent's working tree returned to clean state; `/verify 508` proceeded normally
- No Tier 1/2/3 wrapper-level recovery was attempted (wrapper had already exited 0)

### Outcome
- partial — the on-disk change reached main correctly via the merge wrapper, but the parent's working tree was left dirty, blocking the next phase until manual cleanup

### Improvement Candidate
- 起票済み #636 (merge: phase が main repo 直接編集する Phase Handoff を worktree 経由でコミットするよう運用変更)

## 2026-06-13 14:30 UTC: silent-no-op recovered via wrapper-anomaly Tier 2 retry (#576, 2nd in session)

### Context
- Issue #576, phase: code (patch route, run-auto-sub.sh)
- Source: wrapper-anomaly-detector + fallback-catalog (Tier 2)
- Wrapper: run-code.sh, exit code: 0 (first attempt)
- Log tail: "[anomaly] silent no-op detected in code: LLM reported success in phase `code` (exit code 0) but no commit for #576 found in recent git log"

### Diagnosis
- 初回 run-code.sh は wrapper exit 0 を返したが、`closes #576` を含むコミットが git log に見つからなかった（#365 silent no-op パターン）
- 本セッション 2 件目の発生（#580 → #576 連続）

### Recovery Applied
- run-auto-sub.sh が anomaly detector の提案を読みリトライ実行
- 2 回目の run-code.sh で正常にコミット c6a6170 を生成（skills/issue/spec-test-guidelines.md に PoC/measurement AC ガイダンスを追加）

### Outcome
- success — 親セッションへの手動介入不要。Tier 2 fallback が連続成功

### Improvement Candidate
- 未起票 (silent-no-op の発生頻度が上昇傾向。3 件目以降が発生した場合、予防策の起票を検討)

---

## 2026-06-13 14:00 UTC: silent-no-op recovered via wrapper-anomaly Tier 2 retry

### Context
- Issue #580, phase: code (patch route, run-auto-sub.sh)
- Source: wrapper-anomaly-detector + fallback-catalog (Tier 2)
- Wrapper: run-code.sh, exit code: 0 (first attempt)
- Log tail: "[anomaly] silent no-op detected in code: LLM reported success in phase `code` (exit code 0) but no commit for #580 found in recent git log"

### Diagnosis
- 初回 run-code.sh は wrapper exit 0 を返したが、`closes #580` を含むコミットが git log に見つからなかった（#365 silent no-op パターン）
- detect-wrapper-anomaly.sh が検出し、改善提案として "Re-run run-code.sh 580" を出力

### Recovery Applied
- run-auto-sub.sh が anomaly detector の提案を読みリトライ実行
- 2 回目の run-code.sh で正常にコミット c81aa61 を生成（skills/review/skill-dev-recheck.md に transcription divergence チェック観点を追加）

### Outcome
- success — 親セッションへの手動介入不要。fallback-catalog + wrapper-anomaly-detector の自動連携で完結

### Improvement Candidate
- N/A (resolved by known catalog: silent-no-op pattern with auto-retry)

---

## 2026-06-05 02:39 UTC: false-positive silent-no-op on patch route (#523, #526)

### Context
- Issue #523 and #526, phase: code (patch route, `/auto --batch`)
- Source: wrapper-anomaly-detector
- Wrapper: run-code.sh (via run-auto-sub.sh), exit code: 0
- Log tail: "[silent-no-op] LLM reported success in phase code (exit 0) but no commit for #N found in recent git log"

### Diagnosis
- `detect-wrapper-anomaly.sh` checked the local git log for a `closes #N` commit immediately after `run-code.sh`, but patch-route `/code` pushes the commit to origin/main via `worktree-merge-push.sh`. The local main branch was not yet synced, so the detector saw no commit and false-flagged a silent no-op. The authoritative check (`reconcile-phase-state.sh code-patch --check-completion`, which queries origin/main) returned `matches_expected:true` — commits `df3c7a7` (#523) and `fb487cc` (#526) were merged.

### Recovery Applied
- No code recovery needed (benign false positive). Parent session reconciled the true state via `git pull` + `reconcile-phase-state.sh --check-completion` and continued; `update_batch` marked both complete.

### Outcome
- success (benign false positive; no work lost)

### Improvement Candidate
- 未起票 (retro-proposals via #523/#526 verify retrospective で起票予定): `detect-wrapper-anomaly.sh` should `git fetch` / consult origin/<base> (or defer to `reconcile-phase-state.sh --check-completion`) before concluding a patch-route silent no-op.

## 2026-06-05 01:40 UTC: watchdog kill before PR creation; recovery sub-agent op unsupported (#522)

### Context
- Issue #522, phase: code (pr route, `/auto --batch`)
- Source: recovery-sub-agent
- Wrapper: run-code.sh (via run-auto-sub.sh), exit code: 1
- Log tail: "[spawn-recovery] action=recover ... ERROR: unsupported op 'push_branch' in step 1"

### Diagnosis
- `run-code.sh --pr` was watchdog-killed after implementing the change in worktree `code+issue-522` (+107 lines across 4 files) but before commit/PR creation (#385 pattern). Tier 1 reconcile (no PR) and Tier 2 fallback did not resolve; Tier 3 `spawn-recovery-subagent` produced a plan with `op=push_branch`, which the recovery executor does not support → exit 1.

### Recovery Applied
- Parent session manually recovered: committed the worktree changes with sign-off, pushed `worktree-code+issue-522`, created PR #532, then ran `run-review.sh --light` (MUST 0, CI green) and `run-merge.sh` (squash, closes #522).

### Outcome
- success (manual)

### Improvement Candidate
- 未起票 (retro-proposals via #522 verify retrospective で起票予定): add a supported `push_branch` recovery op (commit→push→PR create) to the recovery executor / `validate-recovery-plan.sh`, or constrain the recovery sub-agent to emit only supported ops. Would have automated the #385 watchdog-kill-before-PR recovery.

## 2026-06-03 16:15 UTC: verify worktree FF merge failed (concurrent push advanced base)

### Context
- Issue #505, phase: verify (Step 13 worktree exit, merge-to-main)
- Source: fallback-catalog
- Wrapper: worktree-merge-push.sh, exit code: 128
- Log tail: "fatal: Not possible to fast-forward, aborting."

### Diagnosis
- A concurrent /auto run pushed #517's verify retrospective (`f305822`) to origin/main while the #505 verify worktree (branched from `0a33f9e`) was active. Local/remote main advanced one commit ahead of the worktree branch, so the worktree branch was no longer an ancestor of base. The `ff-only-merge-fallback` (`git pull --rebase origin main`) only syncs the local base to remote — it does not rebase the worktree branch onto an advanced base — so it could not resolve the divergence (`git merge-base --is-ancestor main <branch>` → NO).

### Recovery Applied
- Consulted `modules/orchestration-fallbacks.md#ff-only-merge-fallback`; its steps did not cover the worktree-branch-behind-base case. Changed files were on a different Spec (#505 vs #517) and non-conflicting, so the parent session cherry-picked the single retrospective commit onto base: `git cherry-pick b0aa50a` → `git push origin main` (`f305822..d84705f`). Verified `Signed-off-by` preserved. Worktree + branch cleaned up.

### Outcome
- success

### Improvement Candidate
- 起票済み #522（worktree-merge-push: 長時間フェーズ中の base 前進による ff-only 失敗の rebase フォールバックを追加）。本 #505 verify での再発は #522 の優先度を補強する。提案内容: `worktree-merge-push.sh` の FF fallback を worktree-branch-behind-base ケースに拡張し、worktree ブランチを更新後の base へ rebase/cherry-pick してから ff-merge を再試行する。
