# Issue #436: issue/verify: retrospective を特筆事項あり時のみ生成して空 comment を抑制

## Overview

`/issue` (Step 10, Step 12) と `/verify` (Step 12) の retrospective ステップが、特筆事項のない場合でも無条件に comment を生成・post している。これにより Quick Start XS 経路で合計 40-80s のオーバーヘッドが発生し、Issue ノイズも増える。skip 条件を追加して、実質的な内容がある場合のみ生成・post するよう改善する。

## Changed Files

- `skills/issue/SKILL.md`: Step 10 と Step 12 の retrospective ステップに skip 条件を追加
- `skills/verify/SKILL.md`: Step 12 (Retrospective) に skip 条件を追加

## Implementation Steps

1. `skills/issue/SKILL.md` Step 10 を更新: "Always create the section (write 'Nothing to note' if no content)" を skip 条件付きに置き換える。Skip 条件: (1) ambiguity auto-resolution がゼロ、(2) AC 変更がゼロ、(3) surprising policy decision がない。Skip 時は `retrospective skipped: no notable content` をターミナルに出力し、comment は post しない。(→ AC1, AC2, AC6)

2. `skills/issue/SKILL.md` Step 12 を Step 1 と同様に更新する (Existing Issue Refinement 経路)。(→ AC1, AC3, AC6)

3. `skills/verify/SKILL.md` Step 12 に skip 条件を追加する。Skip 条件: 全 AC が PASS かつ改善提案がゼロかつ (Spec が存在しない または lifecycle review の全フェーズに観察事項がない)。Skip 時は `retrospective skipped: no notable content` をターミナルに出力し、Spec への追記とコミットもスキップする。(→ AC4, AC5, AC6)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md の retrospective ステップに skip 条件 (例: ambiguity 自動解決ゼロ・AC 変更ゼロ・surprising decision なし) が明記されている" --> `skills/issue/SKILL.md` に retrospective の skip 条件が明記されている
- <!-- verify: section_contains "skills/issue/SKILL.md" "### Step 10: Issue Retrospective" "skip" --> `skills/issue/SKILL.md` Step 10 の Retrospective セクションに skip の記述が含まれている
- <!-- verify: section_contains "skills/issue/SKILL.md" "### Step 12: Issue Retrospective" "skip" --> `skills/issue/SKILL.md` Step 12 の Retrospective セクションに skip の記述が含まれている
- <!-- verify: rubric "skills/verify/SKILL.md の retrospective ステップに skip 条件が明記されている" --> `skills/verify/SKILL.md` に retrospective の skip 条件が明記されている
- <!-- verify: section_contains "skills/verify/SKILL.md" "### Step 12: Retrospective (Full Workflow Review)" "skip" --> `skills/verify/SKILL.md` Step 12 の Retrospective セクションに skip の記述が含まれている
- <!-- verify: rubric "両 skill とも skip 時はターミナル出力にスキップ理由 (例: 'retrospective skipped: no notable content') を出すことが SKILL に明記されている" --> skip 時のターミナル出力フォーマットが定義されている
- <!-- verify: github_check "gh pr checks" "Validate skill syntax" --> SKILL.md 構文 lint が通る

### Post-merge

- サンプル XS Issue に対して `/issue <N>` `/verify <N>` を実行し、retrospective comment が post されないこと (もしくは notable content がある時だけ post されること) を実機で確認

## Notes

- SPEC_DEPTH=light で pre-merge verification が 7 件 (上限 5 件超) だが、Issue body の AC を verbatim でコピーするため全件含む
- `/verify` の skip 条件は Issue body の `## Auto-Resolved Ambiguity Points` で auto-resolve 済み: 「全AC PASS かつ改善提案ゼロかつ Spec 未存在（または lifecycle review に観察事項なし）」を採用
- `docs/workflow.md` の `/verify` 説明 ("Performs a cross-phase retrospective review") は変更後も意味的に正確 (skip はあくまで注記事項がない場合のみ) なので更新不要

## review retrospective

### Spec vs. implementation divergence patterns

特筆事項なし。diff がSpec の実装ステップ3件と完全に一致。verify/SKILL.md の旧ステップ3→新ステップ4へのリナンバリングも正確。

### Recurring issues

特筆事項なし。全4観点 (Spec divergence / Edge cases / Security / Documentation consistency) で MUST/SHOULD/CONSIDER 指摘ゼロ。SKILL.md テキスト変更のみのため構造的リスクが低く、高品質な実装。

### Acceptance criteria verification difficulty

特筆事項なし。全7件 PASS、UNCERTAIN ゼロ。`rubric` 条件はPRブランチ上のSKILL.mdを直接参照して判定可能。`section_contains` / `github_check` は機械的に確認。verify commandの設計が変更内容に対して適切で検証フリクションが低かった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #689 はすでにマージ済み状態で到達（review フェーズ後に手動または別セッションでマージ済み）
- `closes #436` を含む squash コミットにより Issue #436 が自動クローズされた
- BASE_BRANCH=main のため Issue 自動クローズの遅延なし

### Deferred Items
- Post-merge 実機検証: サンプル XS Issue で `/issue <N>` `/verify <N>` を実行し retrospective skipped が出力されることを確認 (AC #8)

### Notes for Next Phase
- verify フェーズでは Post-merge 実機検証 (AC #8) を優先的に実行すること
- SKILL.md 変更のみのため回帰リスクは低い

## Auto Retrospective

### Execution Summary
| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| issue | pr | SUCCESS | — |
| spec | pr | SUCCESS | — |
| code | pr | SUCCESS (manual recovery) | run-code.sh exit 1: 実装は完了して worktree に差分残るが commit/push/PR creation に失敗。parent session が手動 commit + push + `gh pr create` で復旧し PR #689 作成 |
| review | pr | SUCCESS | — |
| merge | pr | SUCCESS | 4 分強で完了、wait-ci-checks hang なし (#685 fix 効果) |
| verify | pr | SUCCESS | 全 pre-merge AC PASS、opportunistic post-merge は次回観測 |

### Orchestration Anomalies
- **code phase exit 1 with implementation present**: `run-code.sh 436 --pr` が exit 1 で終了したが、worktree branch `worktree-code+issue-436` には skills/issue/SKILL.md + skills/verify/SKILL.md の修正が uncommitted のまま残っていた。原因は run-code.sh 内の commit/test/push のいずれかが silent fail した可能性。parent session が `git add` → `git commit -s` → `git push` → `gh pr create` を手動実行して PR #689 作成。
- **`source=ci` test_result emit failure (継続)**: 新 TAP parser は正しいが、`run-merge.sh` が merge 直後に走る in-progress CI run を query し TAP plan line が log にまだ書かれていない状態で取得 → "TAP plan line (1..N) not found" warning。#679/#662/#630 連鎖 close は本セッションでも trigger されず。

### Improvement Proposals

1. **`run-merge.sh` の CI run query タイミング改善（高優先）**
   - 症状: merge 直後の `gh run list --workflow=test.yml --branch=main --limit=1` が **in-progress run** を返し、log に TAP plan line がまだ書かれていない時点で `gh run view --log` を実行 → 空マッチ。
   - 影響: 新 TAP parser (#687) があっても `source=ci` test_result event が emit されず、#679/#662/#630 の post-merge observation 連鎖が trigger されない。
   - 提案: (A) PR の latest successful workflow run を query する（merge 前に既に green になっている）、(B) `gh run watch` で CI 完了を待つ、(C) `gh run list --status completed` で in-progress を除外。Issue 起票候補。

2. **`run-code.sh` の silent exit-1 with implementation 残留対策（中優先）**
   - 症状: run-code.sh が exit 1 で終了したが、worktree に実装差分が残ったまま commit/push が実行されず、PR も作成されなかった。原因が log に明示されない。
   - 影響: parent session が手動で commit + PR 作成する recovery を毎回手動実施する必要がある。
   - 提案: run-code.sh の各ステップ (commit/test/push/PR create) に明示的な失敗ハンドリング + log 出力を追加。または run-code.sh exit 1 時に worktree の uncommitted 状態を検出して reconcile-phase-state.sh に hint を追加。Issue 起票候補。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC が 7 件と多めだが、`section_contains` + `rubric` + `github_check` の組合せで各 skill の各 step 追加内容を mechanical に検証できる設計。Auto-Resolved Ambiguity Points で `/verify` の skip 条件を事前に固めており spec フェーズが滞らなかった。

#### spec
- Implementation Steps が 3 ステップに整理（issue Step 10、issue Step 12、verify Step 12）。spec と実装で乖離なし。

#### code
- 実装自体は正しい (skills/issue/SKILL.md + skills/verify/SKILL.md 両方に skip 条件 + terminal output format 追加) だが、wrapper exit 1 のため manual recovery 必要。orchestration anomaly。

#### review
- light review で MUST 0 件。light review 自体は review phase 起動後に commit 済の PR を対象としていたため anomaly の影響なし。CI 全 SUCCESS。

#### merge
- merge phase は新 wait-ci-checks.sh polling loop で正常動作（hang なし、~4 分で完了）。ただし source=ci test_result emit は in-progress CI を query した結果 fail。

#### verify
- Pre-merge 7/7 PASS、Post-merge は opportunistic 1 件残留 → `phase/verify` 維持。
- Skip 条件のロジック自体は新版で実装済だが、本 verify session の SKILL.md スナップショットは旧版（session 開始時点）のため、本 verify では従来通り retrospective を記録（self-applied skip 不可、#673 snapshot 制約）。

### Improvement Proposals

- 上記 Auto Retrospective 既出 2 件（run-merge.sh CI run timing / run-code.sh silent exit-1）を引き継ぐ。重複 listing は省略。
