# Issue #493: spec/issue: rubric AC を file_contains hint で数値定数照合を補強するガイドライン追加

## Issue Retrospective

### Triage 結果
- Type: Task（既存ガイドラインの拡充・skill 側参照追加が主体）
- Size: XS（`modules/verify-patterns.md` §9 と `skills/issue/SKILL.md` / `skills/spec/SKILL.md` の数十行レベルの追記、CI 依存変更なし）
- Value: 3（Impact: shared component `modules/verify-patterns.md` 改修 +2 / Alignment: Vision との関連やや高、Non-Goals 抵触なし）
- Priority: 未指定（skip）

### Refinement で行った主な判断
- **AC1 の機械検証 hint を `rubric` ベースに変更**: 当初案の `section_contains "modules/verify-patterns.md" "## 9." "数値定数"` は §9 の実際の見出し階層 (`### 9.` level 3) および本文言語（英語）と不一致で検出失敗の恐れがあったため、(a) `rubric` で意味的判断、(b) 補完として `section_contains "### 9." "numeric"` の 2 段構成に変更（§9 が推奨する rubric + supplementary パターン自体に従う形）。
- **追加先**: §9 内の既存「Combining `rubric` with supplementary `file_contains` / `section_contains`」サブセクションを拡張する方針を採用。skill 側 (`skills/issue/SKILL.md`, `skills/spec/SKILL.md`) は新規セクションを切らず、verify-patterns.md §9 への参照を介する既存パターンに揃える。
- **「数値閾値が含まれる場合」の判定**: skill 内での自動検出ロジック実装は本 Issue のスコープ外。rubric の grader description テキストに数値定数・閾値が現れる場合にモデル判断で `file_contains` 補完を促す、というガイドライン記述に留める方針で auto-resolve。

### Scope 再評価 (post-refinement)

「下流からの retro/verify として実装価値あるか?」のレビューを行い、以下の理由で **scope を skill 側のみに縮小** した:

- `modules/verify-patterns.md` §9 の「Combining `rubric` with supplementary `file_contains` / `section_contains`」は既に汎用的に記述されており、「数値定数」は `target keyword` の一適用例にすぎない。§9 への追記は重複ガイドになり運用効果が薄い。
- 真の症状は §9 の不足ではなく、`/issue` / `/spec` が rubric AC 生成時に §9 補完パターンを積極適用していない運用面。修正対象は **skill 側のプロンプト/ガイド**。

### 変更点
- 削除した AC: 「§9 に補完パターン例追加」「§9 に `numeric` キーワード含有」
- 残した AC: skill 側 (issue + spec) の rubric AC 生成箇所への注記追加（rubric)
- 残した Post-merge AC: 実 Issue での目視確認 (opportunistic)
