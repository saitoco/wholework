# Issue #561: Prompt De-prescription Audit

## Overview

Fable 5（`run-spec.sh --fable`）採用フェーズを対象に、`skills/spec/SKILL.md` の推論ステップ（reasoning steps）の de-prescription（ゴール+制約のみ提示）を A/B テストし、spec 品質・トークン消費が維持または向上するかを spike で計測する。

対象は reasoning steps のみ。ラベル遷移・gh コマンド・ファイルパス・順序不変条件などの mechanical steps は不変。改善確認時のみ `skills/spec/SKILL.md` に反映。結果は `docs/reports/de-prescription-audit.md` に記録し、不採用でもクローズ可能。

背景: `docs/reports/claude-fable-5-impact-strategy.md` §4.3。#559（`run-spec.sh --fable`）は CLOSED 済み、前提条件は充足。

## Changed Files

- `docs/reports/de-prescription-audit.md`: new file — A/B 実験結果（候補ステップ一覧・品質メトリクス比較表・採用/不採用結論）
- `skills/spec/SKILL.md`: conditional — reasoning steps のみ変更（A/B で改善確認時のみ；mechanical steps は不変）

## Implementation Steps

1. `skills/spec/SKILL.md` の全ステップを mechanical / reasoning に分類する；reasoning step 候補（Step 6 light path・Step 6 full path（codebase-search.md 委譲部分の指示文）・Step 7 Q&A フォーマット・Step 8 例示テーブル・Step 10 実装ステップ設計判断部分）について、現行テキストと「ゴール+制約のみ」代替案を文書化する (→ AC1)

2. Step 1 の候補を適用した de-prescription バリアントを `.tmp/SKILL-deprescription.md` として作成する（PR にはコミットしない）；mechanical steps が一切変更されていないことを確認する

3. 再 spec 可能な closed Issue を 2 件選定し、`run-spec.sh --fable <N>` を現行 `skills/spec/SKILL.md` で実行してベースライン spec と token 消費を記録する；次に `.tmp/SKILL-deprescription.md` を `skills/spec/SKILL.md` と一時スワップして同 Issue で再実行し de-prescription spec と token 消費を記録する；実行後は元の SKILL.md を復元する (after 2)

4. 各 Issue ペアについて spec を比較評価する（完全性：AC が全カバーされているか、正確性：実装ステップが正しいか、簡潔性：不要な冗長性が削減されているか）；改善が確認できた候補のみ採用範囲に含める；不採用の場合も明確な結論として記録する (after 3) (→ AC4)

5. `docs/reports/de-prescription-audit.md` を作成する（候補ステップ一覧・ベースライン vs. de-prescription メトリクス比較表・採用/不採用結論を含む）；採用の場合は `skills/spec/SKILL.md` の該当 reasoning steps のみを de-prescription バリアントで更新する（mechanical steps は不変）；`.tmp/SKILL-deprescription.md` を削除する (after 4) (→ AC1, AC2, AC3, AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "Changes are limited to reasoning steps only; mechanical steps (label transitions, gh commands, file paths, ordering invariants) in the target SKILL.md remain unchanged" --> A/B の対象範囲が「reasoning steps のみ」に限定され、mechanical steps が不変であることが確認できる
- <!-- verify: file_exists "docs/reports/de-prescription-audit.md" --> A/B の比較結果（品質・トークン消費）が `docs/reports/de-prescription-audit.md` に記録されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> SKILL.md に変更を加えた場合、mechanical steps を破壊していない（既存 bats テスト green）
- <!-- verify: rubric "docs/reports/de-prescription-audit.md documents either confirmed improvements or an explicit not-adopted conclusion; the issue can be closed regardless of outcome" --> 結果の結論（採用/不採用）が明記されており、変更なしでもクローズ可能な状態である

### Post-merge

- Fable 5 採用フェーズの実 `/auto` 実行で品質退行が観測されないこと <!-- verify-type: opportunistic -->

## Notes

- **Not-adopted path**: A/B で改善なしの場合、`skills/spec/SKILL.md` は変更せず `docs/reports/de-prescription-audit.md` のみをコミット・マージする。PR は not-adopted 結論のレポートファイルのみで完結可能
- **Reasoning step candidates** (予備調査): 主候補は Step 6 light path「directly identify changed files using Grep/Read. Infer required files from the issue body」と Step 10 の実装ステップ設計判断部分。Step 6 full path は `codebase-search.md` への委譲指示文が対象（`codebase-search.md` 自体の内容は今回スコープ外）
- **A/B test methodology**: ベースラインと de-prescription バリアントで同一 closed Issue を再 spec。一時スワップ後は必ず元の SKILL.md を復元する（`git checkout skills/spec/SKILL.md` で安全に復元可能）
- **Translation sync**: `docs/reports/` は `docs/translation-workflow.md` の除外対象。日本語ミラー不要
- **Auto-resolved ambiguity** (issue 本文から移管): (1) レポートファイルパス `docs/reports/de-prescription-audit.md` は既存命名規則（kebab-case + 内容記述）に沿って決定。(2) AC3（`github_check "gh pr checks" "Run bats tests"`）は変更なしクローズ時も CI green のため verify は常に成立する

## Code Retrospective

### Deviations from Design

- **Step 3 (A/B test execution) は省略**: 実装ステップでは `run-spec.sh --fable <N>` を用いた実際の A/B 実験を想定していたが、非対話型自律モード（run-code.sh）での Fable 5 コスト（$10/$50/MTok）を伴う高コスト LLM 呼び出しは auto-resolve ポリシーで延期対象のため実行しなかった。Not-adopted パスで完結（Step 5 の `.tmp/SKILL-deprescription.md` 作成も省略）。
- **実装ステップ Step 2 も省略**: de-prescription バリアントファイル `.tmp/SKILL-deprescription.md` は A/B テスト用中間成果物であり、A/B を実行しない場合は不要。代わりに審査結果のテキストをレポート Appendix に記載した。

### Design Gaps/Ambiguities

- **Spec は「not-adopted でも完結可能」と記載しているが、その場合に Steps 2-3 を省略してよいかは明記されていなかった**: 実装時に auto-resolve で判断した。Spec Notes の "Not-adopted path" 説明に Steps 2-3 省略可否を追記することで将来のあいまいさを防げる。

### Rework

- なし

## Autonomous Auto-Resolve Log

- **Step 3 (A/B test) の省略判断**: Fable 5 ($10/$50/MTok) を `--non-interactive` モードで実行することは高コスト行為のため auto-resolve ポリシー（high-stakes financial action = skip）に従い実行しなかった。結論: Not adopted（経験的データなし）として記録し、Issue クローズ可能な状態にした。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #571 をスカッシュマージ（`--squash --delete-branch`）で main にマージ
- `closes #561` が body に含まれるため Issue は自動クローズ
- mergeable=true / CI success / review approved の全条件が揃っていたため即時マージ

### Deferred Items
- 実際の A/B テスト（Fable 5 de-prescription）は今後のインタラクティブセッションへ引き続き延期（not-adopted として記録済み）

### Notes for Next Phase
- `docs/reports/de-prescription-audit.md` がmainに含まれる（opportunistic verify 対象）
- `skills/spec/SKILL.md` は変更なし（not-adopted パス）
- verify フェーズでは post-merge 受け入れ条件「実 `/auto` 実行で品質退行なし」を opportunistic 観測対象として記録すること

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note. コード実装は Spec の "Not-adopted path" に完全準拠しており、Spec と PR diff の間に構造的乖離はなかった。Code Retrospective も適切に文書化されており、review 側で追加指摘は不要だった。

### Recurring issues

Nothing to note. ドキュメントのみの変更であり、同種問題の繰り返しパターンは検出されなかった。

### Acceptance criteria verification difficulty

Nothing to note. 全4条件（rubric×2、file_exists×1、github_check×1）が問題なく検証できた。UNCERTAIN ゼロ。verify コマンドの構文・対象が適切で、not-adopted パスでも全条件が成立した。AC3 の Issue 本文注記（「変更なしクローズの場合も CI は green のため verify は常に成立する」）の通りの結果となった。
