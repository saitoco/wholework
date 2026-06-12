# Issue #557: 自律実行の GUARD_PREFIX に early-stop/boundary リマインダ追加

(No spec phase ran — Size S patch route went directly to phase/ready. This file was created during /auto Step 4a to record the orchestration retrospective.)

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|--------|--------|-------|
| issue | patch | SUCCESS | triage set phase/ready directly (spec skipped) |
| code (1st) | patch | SUCCESS with defect | guard-prefix.sh extraction landed (165bc08, 761fe20) but test mocks were not updated; "all 692 bats PASS" claim in the phase output was inaccurate — CI on 761fe20 failed (run-*.bats not ok 439–459) |
| verify (iter 1) | - | FAIL detected | AC5 (CI green) FAIL; root cause isolated (missing guard-prefix.sh in MOCK_DIR); Issue reopened |
| code (2nd, fix cycle) | patch | FAILED (watchdog kill, no commit) | run-code.sh killed at 2700s silence; produced NO fix commit; wrapper exit 0 + reconcile matches_expected:true was a FALSE POSITIVE (matched the pre-existing 165bc08 "closes #557" commit) |
| manual recovery | - | SUCCESS | parent session added `cp .../guard-prefix.sh "$MOCK_DIR/"` to 5 run-*.bats setups (be917de); local 95/95 green; CI success |
| verify (iter 2) | - | SUCCESS | pre-merge 5/5 PASS; post-merge 1 SKIPPED (observation) |

### Orchestration Anomalies
- **False-positive completion check in fix cycle**: after reopen, `reconcile-phase-state.sh code-patch --check-completion` judges success via "commit with closes #N found on origin/main". In a fix cycle the original (defective) commit already satisfies this heuristic, so a wrapper that dies before committing anything is still reported as `matches_expected: true`. The parent session only caught it by checking `git log` HEAD directly.
- **Watchdog kill at 2700s (new default)**: the 2nd run-code.sh was killed after 2700s of silence with no commits produced. Relevant observation for Issue #556's post-merge condition: the raised default did not prevent this kill; unlike the #556 code-phase incident, this time there was no completed work to salvage (true mid-work kill, not a post-completion one).
- **Inaccurate phase self-report**: the 1st code phase claimed "all 692 bats tests PASS" while CI on the pushed commit failed. Likely the test run happened before the final docs commit or against a stale checkout; the claim was not re-validated against CI before reporting.

### Improvement Proposals
- reconcile-phase-state.sh: in fix cycles (reopened issue with prior closes #N commit), the code-patch completion heuristic should require a commit newer than the reopen timestamp (or compare HEAD against the recorded pre-phase HEAD) instead of any "closes #N" match — otherwise wrapper failures after reopen are invisible to Tier 1 recovery.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- spec フェーズなし（S patch ルート）。Issue の AC は verify command 完備で、patch ルート用に `gh run list` 形式の CI チェックが正しく選択されていた（#554 の知見が反映済み）

#### code
- 実装本体（guard-prefix.sh 抽出・5 スクリプトの source 化）は正確だったが、テストモックの更新が漏れた。run-*.bats が `WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` で動く設計の把握不足
- fix cycle の run-code.sh は watchdog kill で空振り。最終修正は親セッションの手動リカバリ（be917de）

#### review
- patch ルートのため review フェーズなし。テストモック漏れは PR review があれば検出された可能性がある（S サイズでもテスト構造に波及する変更は pr ルート昇格を検討する余地）

#### merge
- patch ルートのため merge フェーズなし

#### verify
- iteration 1 が AC5 FAIL を正しく検出し reopen → 修正 → iteration 2 で PASS。verify-reopen ループが設計通り機能した
- `gh run list --limit=1` は「最新 run」を見るため、修正 push 前に実行すると古い failure を拾う。今回は CI 完了を待ってから再実行して正しく PASS

### Improvement Proposals
- （Auto Retrospective の reconcile fix-cycle 提案と同一のため重複起票しない）
