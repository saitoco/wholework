# Issue #774: auto: Fix-cycle Fast-path Detection

## Overview

`/auto N` を verify FAIL 後の fix-cycle 状態で実行した場合、現状では issue/spec phase が不要に再実行され、既存 Spec の上書きや FAIL marker comment の見落としが発生する。本 Issue では以下の 2 点を実装する:

1. `/auto` Step 2.5 として fix-cycle 検出ステップを追加し、3 条件 (verify-fail marker 存在 + phase/* ラベル不在 + Spec ファイル存在) を満たす場合は run-issue.sh / run-spec.sh を skip して run-code.sh を Size-aware で直接起動する fast-path を実装する
2. `modules/l0-surfaces.md` の Comment Consumption Procedure に FAIL marker 例外を追加し、`<!-- wholework-event: type=verify-fail` を含む comment は cutoff の前後にかかわらず常に consume 対象とする (defense in depth)

## Changed Files

- `skills/auto/SKILL.md`: Step 2.5 (Fix-cycle Detection) を Step 2 と Step 3 の間に挿入 — bash 3.2+ compatible
- `modules/l0-surfaces.md`: Comment Consumption Procedure Step 2 に verify-fail marker 例外ロジックを追加
- `tests/auto.bats`: fix-cycle 検出ステップの構造テストを追加

## Implementation Steps

1. `modules/l0-surfaces.md` Step 2 (Fetch comments) を更新: cutoff フィルタ済みコメント取得の後、cutoff より前のコメントも `<!-- wholework-event: type=verify-fail` を含む場合は consume 対象に追加するロジックを記述する (→ AC3, AC4)

2. `skills/auto/SKILL.md` Step 2 と Step 3 の間に `### Step 2a: Fix-cycle Detection` を挿入: (1) `gh issue view $NUMBER --json comments` で `<!-- wholework-event: type=verify-fail` を含む最新コメントを検索、(2) `gh issue view $NUMBER --json labels` で `phase/*` ラベルが存在しないことを確認、(3) `Glob("$SPEC_PATH/issue-$NUMBER-*.md")` で Spec ファイルの存在を確認 — 3 条件すべて true の場合を fix-cycle state と判定し、Size-aware で run-code.sh を直接起動 (`XS/S → --patch`, `M/L → --pr`, `XL → 手動介入`) して Step 4 の verify ループに進む; 条件未満は Step 3 へ通常フロー (→ AC1, AC2)

3. `tests/auto.bats` に fix-cycle 検出ステップの @test を追加: Step 2a セクションが SKILL.md に存在すること、"fix-cycle" キーワードが含まれることを検証 (→ AC5, AC6)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.md に fix-cycle detection ステップ (Step 2.5 または同等) が追加されており、(1) verify-fail marker comment 存在、(2) phase/* ラベル不在、(3) Spec ファイル存在 の 3 条件で run-issue.sh / run-spec.sh を skip して run-code.sh を Size-aware で直接起動する仕様が記述されている" --> fix-cycle 検出ステップが SKILL.md に追加されている
- <!-- verify: grep "fix-cycle|fix_cycle" "skills/auto/SKILL.md" --> SKILL.md に "fix-cycle" キーワードが追加されている
- <!-- verify: rubric "modules/l0-surfaces.md の Comment Consumption Procedure に、wholework-event: type=verify-fail を含む comment は cutoff の前後にかかわらず常に consume 対象に含める特別扱いが追加されている" --> FAIL marker の cutoff 特別扱いが l0-surfaces.md に追加されている
- <!-- verify: file_contains "modules/l0-surfaces.md" "verify-fail" --> l0-surfaces.md に verify-fail 関連の記述が追加されている
- <!-- verify: grep "fix.cycle" "tests/auto.bats" --> tests/auto.bats に fix-cycle 関連のテストケースが追加されている
- <!-- verify: command "bats tests/auto.bats" --> auto skill の bats テストが green (fix-cycle detection のケース追加)

### Post-merge

- 次回 verify FAIL → reopen された Issue で `/auto N` を実行した際、run-issue.sh / run-spec.sh が skip され直接 code phase に進むことを観察
- 同実行で `/code` の Consumed Comments セクションに verify-fail marker comment が記録されることを観察

## Notes

- **AC2 BRE 修正**: 元の Issue body AC2 に BRE メタキャラクタ `\|` が含まれていた (`grep "fix-cycle\|fix_cycle"`)。ripgrep は ERE をデフォルト使用するため `\|` はリテラル `|` として解釈されてしまう。ERE 形式 `grep "fix-cycle|fix_cycle"` に修正して Issue body を更新する。
- **AC4 の pre-existing 文字列について**: `modules/l0-surfaces.md` には既に `verify-fail` が example ブロック (line 78) に含まれているため、`file_contains` は実装前後ともに PASS する。AC4 は rubric (AC3) の mechanical safety net であり、実装後に新たなコンテキストで "verify-fail" が追加されることを前提としている。
- **COMMENT_SCOPE**: Issue 提案の "code phase の COMMENT_SCOPE は `issue+pr`" は l0-surfaces.md の cutoff 例外 (Step 1) で実現される。`run-code.sh` への追加フラグは不要。
- **`--fix-cycle` フラグ**: Issue スコープ外。Step 2.5 の自動検出で主要ユースケースをカバーするため、フラグ追加は follow-up Issue として別途検討。
- **XL route の fix-cycle fast-path**: XL は sub-issue 依存グラフ構造のため Step 2.5 の fast-path 対象外とし、手動介入が必要と明示する。

## Consumed Comments

- saito (MEMBER / first-class): Issue Retrospective — BRE metacharacter fix in AC2, additional verify ACs (AC4, AC5), auto-resolved ambiguity points confirmation
  URL: https://github.com/saitoco/wholework/issues/774#issuecomment-4817665323

## Code Retrospective

### Deviations from Design

- Spec says "Step 2.5" but `validate-skill-syntax.py` forbids decimal step format (N.M). Renamed to "Step 2a: Fix-cycle Detection" (first available letter suffix). The bats tests were updated to match the renamed step heading. The AC verify commands check for the "fix-cycle" keyword (not the step number), so all ACs still pass.

### Design Gaps/Ambiguities

- The Spec Notes mentioned "COMMENT_SCOPE は issue+pr の変更は run-code.sh への追加フラグは不要" but did not address that the Step 2.5 → Step 2a rename would affect bats awk patterns. Bats patterns updated accordingly with no functional impact.

### Rework

- N/A (no rework required beyond the Step 2.5 → Step 2a rename forced by the validator)

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- CI failing (reason=ci_failing) auto-resolved in non-interactive mode; CI failures are pre-existing on main (tests 11–15 in append-loop-state-heartbeat.bats), confirmed by review phase
- Squash merge executed with `--delete-branch`; `closes #774` in PR body triggers auto-close of Issue #774 on main merge

### Deferred Items
- Post-merge observation ACs (run-issue.sh/run-spec.sh skip in a real verify FAIL → reopen cycle) remain unverifiable until a live cycle occurs

### Notes for Next Phase
- Label transition to `verify` has been applied
- Pre-merge ACs all PASS; post-merge ACs require a real fix-cycle run to observe behavior
- No conflicts were present; rebase step was skipped

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

- Step 2.5 → Step 2a rename is a validator-forced deviation, documented in Code Retrospective. The Spec Overview still says "Step 2.5" (historical artifact), but verify commands reference the "fix-cycle" keyword rather than the step number, so all ACs are resilient to renaming. No structural divergence.
- The PR also adds docs/workflow.md and docs/ja/workflow.md updates (not in Spec Changed Files), consistent with translation-workflow.md requirements. No gap.

### Recurring Issues

- Nothing to note.

### Acceptance Criteria Verification Difficulty

- AC6 (command "bats tests/auto.bats") was UNCERTAIN in safe mode; resolved to PASS via CI log inspection. The pre-existing failures (tests 11–15) required CI log analysis to distinguish from PR-introduced failures — this investigation was straightforward once the main branch CI state was checked. Consider documenting the baseline failure state in CLAUDE.md or a pinned issue for faster triage.

## Verify Retrospective

### Phase-by-Phase Review

#### verify

- AC8 (observation: Consumed Comments セクションへの verify-fail marker 記録) は18回以上の `auto-run` イベント発火を経ても未確認のまま残っていた。2026-06-27 の調査で構造的 gap と判明し #811 に分離済みだったが、#811 解決後の再確認が行われていなかった。
- 本セッション (2026-07-09, `/auto #955` 経由の observation cascade) で #811 (bash/post-processor 駆動移行) のマージ状態と、#811 マージ後の実際の fix-cycle 事例 (#860, `/auto` M route, 2026-07-03) を確認し、`docs/spec/issue-860-worktree-edit-path-conventions.md` の `## Consumed Comments` セクションに verify-fail marker への言及が実際に記録されていることを実証。AC8 を PASS 判定し、Issue #774 を `phase/done` にクローズした。

### Improvement Proposals
- N/A
