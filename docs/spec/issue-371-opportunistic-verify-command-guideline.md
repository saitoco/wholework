# Issue #371: issue: opportunistic 条件への verify command 付与ガイドラインを追加

## Issue Retrospective

### Auto-Resolved Ambiguity Points

| # | Ambiguity | Decision | Rationale |
|---|-----------|----------|-----------|
| 1 | 編集対象ファイル (`verify-patterns.md` or `skills/issue/SKILL.md`) | `modules/verify-patterns.md` 単独 | 既存の同種 verify command ガイドライン (§1, §7, §8) が全て `verify-patterns.md` に集約。`skills/issue/SKILL.md` Step 4 から既に Read される位置で、編集を一元化できる |
| 2 | `modules/verify-classifier.md` の分類基準への波及 | 分類基準テーブルは変更しない | 「mechanically verifiable な opportunistic 寄り条件は verify command 併記により `auto` に分類されることを優先する」と新ガイドライン側で述べる方針で完結可能。分類ロジックの再設計は follow-up に分離 |
| 3 | AC の verify command (`grep "opportunistic.*verify command\\|verify command.*opportunistic"`) の品質 | `grep "^###.*[Oo]pportunistic"` + `rubric` + `section_contains "## Processing Steps" "opportunistic"` の三段に置換 | GNU BRE alternation 依存で brittle、かつ §1 既存行が "opportunistic" を含むため誤マッチ余地あり。verify-patterns.md §5 (新コマンド追加) と §9 (rubric + supplementary) の推奨パターンに合致する組合せを採用 |

### Key Policy Decisions

- **対象範囲を verify-patterns.md 1 ファイルに絞り込み**: classifier テーブル本体には触れず、運用ガイドラインのみ追加。Size XS を維持し、follow-up が必要なら別 Issue で扱う方針を Scope セクションに明記
- **AC 構造の強化**: 機械検証 (`grep` + `section_contains`) と意味検証 (`rubric`) を分離し、§9 の rubric + supplementary check ガイドに準拠

### Acceptance Criteria Changes

- 元の単一 pre-merge 条件 (脆弱な regex alternation grep) を 3 条件に分割: (a) セクション見出し追加検出、(b) rubric による意味的妥当性、(c) Processing Steps 配下への配置確認
- post-merge 条件は `verify-type: opportunistic` を維持し、文言を「`/issue` skill による運用」と「`/verify` での `auto` 自動消化事例の確認」に明確化
- Scope セクションを追加し対象外を明示

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 対象ファイルの特定・AC 構造の設計を含む Issue Retrospective が残っており、質の高い AC が設計された。rubric + supplementary check パターン (§9 準拠) を採用したことで verify の精度が向上した

#### design
- Scope を明確に絞り (1ファイル、Size XS)、`verify-classifier.md` を変更しない判断は適切。実装との乖離なし

#### code
- commit は `14221c1` の 1 件のみ。fixup や amend パターンなし。実装は diff 32行の最小変更で完結

#### review
- PR #374 にレビューコメントなし。CI チェックなし (patch ルートではなく PR ルート)。レビューが実施されていないため、見落としリスクの事後評価は不可

#### merge
- PR #374 が 2026-04-23 にマージ。コンフリクトなし

#### verify
- pre-merge 3条件すべて PASS。post-merge 1条件 (`verify-type: opportunistic`) は verify command なし のため auto-verify 対象外。Issue は `phase/verify` で CLOSED を維持
- post-merge 条件自体が本 Issue の改善対象 (「opportunistic 条件に verify command を付けるべき」) の例として、verify command なしの opportunistic 条件のままになっており、本ガイドラインの適用が自身には及んでいない点はやや皮肉だが、「実際の運用事例確認」という性質上、事前に verify command を付けることが困難なため許容範囲

### Improvement Proposals
- N/A
