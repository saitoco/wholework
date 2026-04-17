# Issue #218: Update docs/tech.md model-effort-matrix for Opus 4.7 / xhigh

## Overview

Update the "Phase-specific model and effort matrix" section in `docs/tech.md` to reflect Opus 4.7 behavior: document `xhigh` as the recommended default for most coding and agentic use cases, add strict effort calibration notes for `low`/`medium`, add diminishing returns warning for `max`, and note that `model: opus` alias auto-resolves to Opus 4.7. This is a docs-only update; run-*.sh implementation values are unchanged (handled in #217 and #229).

## Changed Files

- `docs/tech.md`: add "Opus 4.7 effort calibration" paragraph to the "Phase-specific model and effort matrix" section

## Implementation Steps

1. In `docs/tech.md`, insert the following paragraph between the matrix table (after the `triage (skill)` row) and the existing SSoT note (line 88), as a blank-line-separated paragraph:

   ```
   **Opus 4.7 effort calibration**: Opus 4.7 enforces strict effort calibration — `low` and `medium` aggressively scope to literal task requirements. `max` carries a diminishing returns risk (overthinking) with Opus 4.7; reserve it for intelligence-demanding experimental tasks only. `xhigh` is the Opus 4.7 recommended default for most coding and agentic use cases. Sub-agent `model: opus` / `model: sonnet` alias values in agent frontmatter auto-resolve to Opus 4.7.
   ```

   Exact insertion point: after the last row of the matrix table (currently `| verify (skill) | ...`) and before the `SSoT note:` line. Note: when this Spec was written, `triage (skill)` was the last row; #231 later added `merge (skill)` and `verify (skill)` rows.

## Verification

### Pre-merge

- <!-- verify: section_contains "docs/tech.md" "Phase-specific model and effort matrix" "Opus 4.7" --> matrix セクションに Opus 4.7 への言及がある
- <!-- verify: section_contains "docs/tech.md" "Phase-specific model and effort matrix" "xhigh" --> matrix セクションに xhigh effort の使用基準が記載されている
- <!-- verify: section_contains "docs/tech.md" "Phase-specific model and effort matrix" "default" --> xhigh が Opus 4.7 のデフォルトであることが明記されている
- <!-- verify: file_contains "docs/tech.md" "strict effort" --> Opus 4.7 の strict effort calibration 挙動が記載されている
- <!-- verify: file_contains "docs/tech.md" "diminishing returns" --> `max` のオーバーシンクリスクが記載されている
- <!-- verify: file_contains "docs/tech.md" "ssot_for:" --> frontmatter の `ssot_for: model-effort-matrix` が維持されている
- <!-- verify: section_contains "docs/tech.md" "Phase-specific model and effort matrix" "alias" --> サブエージェント (`model: opus` / `model: sonnet` alias) が 4.7 へ自動解決される旨が記載されている

### Post-merge

- `/audit drift` 実行時に matrix と run-*.sh 実装の整合が取れている
- `docs/ja/tech.md` 翻訳版が `/doc translate ja` で更新済み

## Notes

- docs-only 更新。`run-*.sh` の実際の effort/model 変更は #217 (run-spec.sh xhigh) および #229 (run-*.sh 全体の effort 再評価) で別途対応
- 既存の matrix テーブルは変更しない（行の追加・変更なし）。テーブル直後に calibration 段落を追記するのみ
- 段落に含まれる文字列が検証条件を満たすことを確認済み: "strict effort" ✓、"diminishing returns" ✓、"Opus 4.7" ✓、"alias" ✓

## Code Retrospective

### Deviations from Design
- Spec の挿入ポイントは「`triage (skill)` 行の後」と記載されていたが、#231 で `merge (skill)` / `verify (skill)` 行が追加されており、実際には `verify (skill)` 行（テーブル最終行）の後、`SSoT note:` 行の前に挿入した。意図は同じ（テーブル末尾＋SSoT note 前）であり、結果は正しい

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
