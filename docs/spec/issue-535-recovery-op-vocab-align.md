# Issue #535: recovery-executor: recover op 語彙を agent↔executor 間で整合し watchdog-kill-before-PR 自動復旧を有効化

## Overview

recovery sub-agent（`agents/orchestration-recovery.md`）が広告する recover step の op 語彙と、executor（`scripts/spawn-recovery-subagent.sh`）が実装する op が不一致で、watchdog-kill-before-PR（#385）パターンの自動復旧が `ERROR: unsupported op` で失敗する。agent を executor の実能力（`run_command` / `git_commit_amend_signoff`）に整合させ、復旧（commit→push feature branch→`gh pr create`）を `run_command` step で表現することで自動復旧を成立させる。executor 側のコード変更は不要（`run_command` は既存・`validate-recovery-plan.sh` のガード内で push/PR 可能）。

## Reproduction Steps

1. `/auto --batch <issue>` の code phase（pr route）で `run-code.sh --pr` が実装完了後・commit/PR 作成前に watchdog kill される（worktree に未コミット実装が残存）。
2. `run-auto-sub.sh` が Tier 3 で `spawn-recovery-subagent.sh` を spawn。
3. sub-agent が recover plan に `op=push_branch` を生成。
4. executor が `push_branch` を未実装 → `ERROR: unsupported op 'push_branch'` で exit 1。手動復旧（commit→push→PR）が必要になる（`docs/reports/orchestration-recoveries.md` 2026-06-05 01:40 UTC、#522）。

## Root Cause

agent と executor の recover step 規約が三重に不一致:

| 観点 | agent (`agents/orchestration-recovery.md`) | executor (`scripts/spawn-recovery-subagent.sh`) |
|---|---|---|
| op 語彙 | `push_branch` / `create_pr` / `transition_label` / `extract_pr_number` / `wait_ci` / `noop`（line 79-88） | `run_command` / `git_commit_amend_signoff` のみ（line 225-237） |
| step フィールド名 | JSON 例で `detail`（line 68） | `step.get("cmd")` を読む（line 222, 226） |
| 復旧の表現可能性 | 名前付き op は cmd を持たず run_command を広告しない | run_command が cmd 必須 |

`scripts/validate-recovery-plan.sh` は run_command の cmd に対し force-push / main(master) への push / `reset --hard` / `gh issue close` / `gh pr merge` のみ禁止（line 54-60）。feature branch への `git push` / `gh pr create` は許可されるため、復旧は run_command で安全に表現可能。

**修正方針**: executor を SSoT とし、agent の op 語彙・JSON schema を executor の実装（`run_command` / `git_commit_amend_signoff`、フィールド `cmd`）に整合させる。executor のコードは変更しない。

## Changed Files

- `agents/orchestration-recovery.md`: change — (1) `### 4. Produce Recovery Plan` の JSON schema 例の step フィールドを `detail` → `cmd` に修正し `run_command` を明示、(2) `**Step op vocabulary (allowed):**` の表を executor 実装に一致させ `run_command` / `git_commit_amend_signoff` の2種に置換（`push_branch` 等の架空 op を削除）、(3) watchdog-kill-before-PR 復旧を run_command で表現する例（commit→push feature branch→`gh pr create`、必要なら `gh-label-transition.sh`）を追記。既存 Constraints（force-push / main 直 push / merge / close / 破壊的 fs 書き込み禁止）は維持。
- `tests/spawn-recovery-subagent.bats`: change — watchdog-kill-before-PR 相当の recover plan（run_command で commit→push→PR、git/gh は MOCK_DIR でモック）が `unsupported op` エラーなく全 step を実行し exit 0 となる bats テストを追加（bash 3.2+ / bats 互換）。

## Implementation Steps

1. `agents/orchestration-recovery.md` を修正（→ AC1, AC1-supp2/3）:
   - `### 4. Produce Recovery Plan` の JSON 例（`{ "op": "...", "detail": "..." }`）を `{ "op": "run_command", "cmd": "..." }` 形へ修正（executor が読む `cmd` に統一）。
   - `**Step op vocabulary (allowed):**` の表を `run_command`（任意の安全シェル。push/PR/label 遷移を表現）と `git_commit_amend_signoff`（DCO sign-off 付き amend）の2種に置換し、架空 op（`push_branch` / `create_pr` / `transition_label` / `extract_pr_number` / `wait_ci` / `noop`）を削除。`skip`/`abort` 時は `steps: []`。
   - watchdog-kill-before-PR 復旧の run_command 例（`git add -A && git commit -s -m ...` → `git push origin <worktree-branch>` → `gh pr create --base main --head <worktree-branch> ...`）を追記。Constraints は維持（force-push / main 直 push / `gh pr merge` / `gh issue close` / 破壊的 fs 禁止）。
2. `tests/spawn-recovery-subagent.bats` に watchdog-kill-before-PR 復旧テストを追加（after 1）（→ AC2, AC3）:
   - setup の MOCK_DIR に `git` / `gh` の最小モック（引数を RUNNER_LOG に記録し exit 0）を追加。
   - `make_claude_mock` で `action=recover` かつ steps が run_command（commit→push→`gh pr create`）の plan を返し、`$SCRIPT code 42 --log` が exit 0、出力に `unsupported op` を含まず、各 step が実行されたことを assert。テスト名に `watchdog-kill-before-PR` を含める。

## Verification

### Pre-merge

- <!-- verify: rubric "agents/orchestration-recovery.md の recover step op 語彙と JSON schema が scripts/spawn-recovery-subagent.sh の executor 実装（op=run_command / git_commit_amend_signoff、フィールド cmd）に整合している。watchdog-kill-before-PR ケース（commit→push feature branch→gh pr create）が run_command で表現でき unsupported-op エラーなく実行できる。force-push / main への直 push / gh pr merge / gh issue close は validate-recovery-plan.sh の forbidden として引き続き拒否される" --> agent↔executor の op 語彙/schema が整合し watchdog-kill-before-PR が自動復旧可能、危険操作は禁止維持
- <!-- verify: file_not_contains "agents/orchestration-recovery.md" "push_branch" --> executor 未実装の架空 op `push_branch` が agent から削除されている
- <!-- verify: file_contains "agents/orchestration-recovery.md" "run_command" --> executor 実装 op `run_command` が agent に advertise されている
- <!-- verify: rubric "tests/spawn-recovery-subagent.bats に、watchdog-kill-before-PR 相当の recover plan（run_command による commit→push→PR、git/gh はモック）が unsupported-op エラーなく全 step を実行し exit 0 となることを検証する bats テストが追加されている" --> 復旧シナリオの bats テストが追加されている
- <!-- verify: github_check "gh pr checks --json name,state --jq '[.[] | select(.name | test(\"bats\"; \"i\")) | .state] | unique | join(\",\")'" "SUCCESS" --> CI の bats テストが green

### Post-merge

- watchdog-kill-before-PR（実装完了・commit/PR 作成前に kill）を再現し、`run-auto-sub.sh` の Tier 3 が `unsupported op` エラーなく commit→push→PR create で自動復旧することを実運用で確認する <!-- verify-type: manual -->

## Notes

- **executor コード変更なし**: `spawn-recovery-subagent.sh` の recover 分岐は既に `run_command` / `git_commit_amend_signoff` をサポート（line 225-237）。本 Issue は agent 側の語彙・schema を executor に合わせる SSoT 整合であり、executor の op 実装は追加しない（代替案: executor に名前付き op を実装する方向は surface 拡大のため不採用。#535 retrospective 参照）。
- **セキュリティ境界（/review で要確認）**: 本 fix により recovery sub-agent が run_command で feature branch への push + PR 作成を自動実行可能になる。ただし (1) `run_command` は既存機能で新規能力追加ではない、(2) `validate-recovery-plan.sh` の forbidden（force-push / main 直 push / `gh pr merge` / `gh issue close`）と agent Constraints（破壊的 fs 禁止）でガード、(3) PR は通常の review/merge ゲートを通る。/review は agent の run_command ガイダンスが forbidden 境界を逸脱しないか確認すること。
- **bats モック**: 復旧テストは git/gh を MOCK_DIR でモックし実 push/PR を発生させない。既存テストの mock パターン（`make_claude_mock`、`WHOLEWORK_SCRIPT_DIR`）を踏襲。

## Code Retrospective

### Deviations from Design
- なし。Specの実装ステップ（1→2の順序）を忠実に実施した。

### Design Gaps/Ambiguities
- Specでは「setup の MOCK_DIR に git/gh の最小モック」と記述されていたが、既存setupは他テストの副作用を避けるためtest関数内に局所的に配置した。これはbatsの慣用パターンに沿った選択であり機能的問題はない。
- Specのbats例示「`$SCRIPT code 42 --log`」は`--log`引数で終端しており実ファイルパスが必要だが、既存テストの`$LOG_FILE`変数パターンを踏襲して自然に解決した。

### Rework
- なし。初回実装でテスト（ok 10）がPASSし修正不要だった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #542 を squash merge（`--squash --delete-branch`）で main にマージ完了
- BASE_BRANCH=main のため `closes #535` により Issue #535 は自動クローズされる
- merge phase での conflict 解決は不要（mergeable=true, reason=clean, CI green, review approved）

### Deferred Items
- 負ケーステスト（run_command mid-step failure）: フォローアップ Issue で対応（review phase から引き継ぎ）
- post-merge manual verify: Tier 3 が unsupported op エラーなく watchdog-kill-before-PR シナリオで自動復旧することを実運用で確認する

### Notes for Next Phase
- Spec の Post-merge Verification に manual verify command あり（Tier 3 実運用確認）
- verify phase では post-merge verify command（manual）に対して `/verify 535` で対応予定
- セキュリティ境界確認済み（review phase）：run_command ガイダンスは forbidden 境界を逸脱しない

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

Spec の実装ステップと PR diff に構造的な乖離はなし。"write to filesystem" constraint の削除は `run_command` パラダイムへの必然的変更で Spec の意図（破壊的 fs 禁止）とも整合しているが、この削除が intentional かどうかを Spec に明示しておくと将来の読者に親切。

### Recurring Issues

特になし。今回は単一ファイル修正（agent）+ テスト追加の小規模 PR で、類似パターンの問題は出なかった。

### Acceptance Criteria Verification Difficulty

全 5 条件が verify command 付きで定義されており、rubric/file_not_contains/file_contains/github_check が適切に使い分けられている。UNCERTAIN なし。Security 境界確認の rubric は Spec の Notes セクション（"/review は agent の run_command ガイダンスが forbidden 境界を逸脱しないか確認すること"）に明示されており、引き継ぎが機能した。
