# Issue #941: docs: model-effort-matrix の Rationale 列を effort 再校正の発見と整合 (run-issue/run-review 行の到達不能パス記述を修正)

## Consumed Comments

No new comments since last phase.

## Overview

#921 (C2) と #923 (C4) による Sonnet 5 effort 再校正の過程で、`docs/tech.md` § Phase-specific model and effort matrix の Rationale 列に不正確な記述が2件見つかった。各 Issue は Auto-Resolved Ambiguity Points によりテーブルセル自体の書き換えをスコープ外とし、正しい根拠は表下の prose note にのみ記録した。結果として SSoT であるテーブルの Rationale 列と note の内容に乖離が生じている。本 Issue はテーブルの Rationale 列を note が示す正しい根拠に更新し、この乖離を解消する。Effort 列 (Sonnet: high 等) の値は変更しない。

- **run-issue.sh 行**: 現行 Rationale「L/XL scope analysis and sub-issue splitting require thorough orchestration」は、`run-issue.sh` が常に非対話モードで実行され Step 12 の L/XL sub-agent fan-out が Issue サイズによらず常にスキップされるため、実際には到達しないコードパスを記述している (#923 で発見)。正しい根拠は、Existing Issue Refinement がパイプライン最上流の成果物を生成し blast radius が最長である点。
- **run-review.sh 行**: 現行 Rationale「Review orchestration; sub-agents handle deep analysis」は、orchestrator 自身が外部レビューフィードバックを解釈して fix コミットを作成する実質的推論作業 (Step 7.2/7.4/7.6) を行っている点を捉えておらず、「mechanical」という位置づけと矛盾する (#921 で発見)。

## Changed Files

- `docs/tech.md`: § Phase-specific model and effort matrix の run-issue.sh 行 (89行目) と run-review.sh 行 (92行目) の Rationale セルを、#923/#921 の recalibration note (123行目・121行目) が示す正しい根拠に更新。Model/Effort 列 (Sonnet / high) は変更しない
- `docs/ja/tech.md`: 上記と対応する run-issue.sh 行 (89行目) / run-review.sh 行 (92行目) の Rationale セルを同期更新 (`docs/translation-workflow.md` の Sync Procedure に準拠)

## Implementation Steps

1. `docs/tech.md` の run-issue.sh 行の Rationale セル (89行目、現行:「L/XL scope analysis and sub-issue splitting require thorough orchestration」) を、#923 note (123行目) の正しい根拠に沿って書き換える。推奨文言例:「Existing Issue Refinement performs substantive judgment work (ambiguity resolution, AC/verify-command authoring) to produce the pipeline's most upstream artifact; errors propagate through every downstream phase — the longest blast radius in the C-series」。Model/Effort 列 (Sonnet / high) は変更しない (→ 受け入れ基準1・2)
2. `docs/tech.md` の run-review.sh 行の Rationale セル (92行目、現行:「Review orchestration; sub-agents handle deep analysis」) を、#921 note (121行目) の正しい根拠に沿って書き換える。推奨文言例:「Orchestrator performs substantive reasoning beyond dispatch — Steps 7.2/7.4/7.6 interpret external review feedback and author fix commits, work comparable to run-code.sh's own implementation reasoning」。Model/Effort 列は変更しない (after 1) (→ 受け入れ基準1・2)
3. `docs/translation-workflow.md` の Sync Procedure に従い、`docs/ja/tech.md` の対応する2行 (run-issue.sh: 89行目, run-review.sh: 92行目) の Rationale セルを Step 1・2 の内容の日本語訳で同期更新する。既存の隣接 prose note (119行目・121行目) の用語 (「最上流の成果物」「blast radius」「実質的な判断作業」等) と表現を揃える。推奨文言例 — run-issue.sh:「Existing Issue Refinement は曖昧性解決・受入条件と verify command の作成などの実質的な判断作業を行い、パイプライン最上流の成果物を生成する。その誤りは下流の全フェーズに伝播し、C-series の中で最も波及範囲が広い」、run-review.sh:「orchestrator は dispatch 以外にも実質的な推論作業を行う — Step 7.2/7.4/7.6 は外部レビューのフィードバックを解釈して fix コミットを作成しており、run-code.sh 自身の実装推論と同種の作業である」 (after 2) (→ 受け入れ基準3)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/tech.md の model-effort-matrix の run-issue.sh 行と run-review.sh 行の Rationale 列が、到達不能パスや mechanical という不正確な記述ではなく、#923/#921 の recalibration note が示す正しい根拠 (最上流成果物生成・blast radius・orchestrator 自身の推論作業) に更新されている" --> run-issue.sh / run-review.sh 行の Rationale が正しい根拠に更新されている
- <!-- verify: rubric "Rationale 列の更新のみで Effort 列 (Sonnet: high 等) の値および run-*.sh の実効 effort 値は変更されておらず、SSoT 一致が維持されている" --> Effort 列は変更されず SSoT 一致が維持されている
- <!-- verify: rubric "docs/ja/tech.md の対応する Rationale 記述も docs/tech.md と同期して更新されている (docs/translation-workflow.md の同期対象)" --> docs/ja/tech.md も同期更新されている

### Post-merge

なし

## Notes

- **CI-sensitive**: `docs/tech.md` の model-effort-matrix (SSoT) に触れるため `[[feedback_ci_sensitive_size_m]]` に従い PR route (Size M) が安全。`get-issue-size.sh` で Size=M を確認済み。
- Effort 列・run-*.sh の実効 effort 値は変更しない。据え置き判定は #921/#923 で確定済みで、本 Issue はスコープ外 (Rationale 列の記述精度のみが対象)。
- **除外ファイル (履歴記録)**: 以下は現行 (修正前) の Rationale 文言をそれ自体の分析対象として引用している履歴記録であり、本 Issue の変更対象から除外する: `docs/spec/issue-923-run-issue-effort-recalib.md` / `docs/spec/issue-108-effort-matrix.md` (disposable Spec)、`docs/reports/sonnet-5-effort-recalibration-issue.md` (report)。`docs/tech.md`/`docs/ja/tech.md` 以外を変更しないという方針は、tech.md 自身の "Spec-first (disposable)" architecture decision と整合する。
- `tests/*.bats` に Rationale 列の文言を検証するテストは存在しないことを grep で確認済み (変更不要)。
- Issue body の Background 記述 (#923/#921 発見内容) を `docs/tech.md` の実ファイル内容 (89, 92, 121, 123行目) と突き合わせ、齟齬がないことを確認済み (conflict検出なし)。

## Code Retrospective

### Deviations from Design
- N/A — Spec の Implementation Steps 1-3 の推奨文言をそのまま採用し、計画通りに実装した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps 1-3 で提示された推奨文言 (英語・日本語とも) をそのまま採用した。Rationale 列の記述精度のみが本 Issue のスコープであり、文言自体の独自解釈による変更はリスクを増やすだけで利益がないため。
- `docs/tech.md`/`docs/ja/tech.md` の2行のみを変更し、Effort 列・run-*.sh 実効値・disposable Spec/report 等の除外ファイルには一切触れなかった (Spec Notes の除外方針に準拠)。

### Deferred Items
- None — 本 Issue は Rationale 列の記述精度修正のみを対象としており、後続フェーズへの繰越事項はない。

### Notes for Next Phase
- 全 1107 bats テスト PASS、`validate-skill-syntax.py`・`check-forbidden-expressions.sh` とも問題なし。docs-only の軽微な変更であるため、review/merge フェーズでの追加確認は Rationale 文言の意味的正確性 (rubric 判定) に絞ってよい。
