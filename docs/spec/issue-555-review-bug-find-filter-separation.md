# Issue #555: review-bug の find/filter 分離（literal filter-following 対策）

## Overview

`agents/review-bug.md` の Purpose セクションには「HIGH SIGNAL のみ報告 / 誤検知最小化 / 確証のあるもののみ」という自己フィルタ方針が記述されている。しかし `/review` Step 10.3 の downstream 検証 sub-agent がすでに false-positive フィルタを担当しているため、finder 段での自己フィルタは二重フィルタとなり、literal filter-following な新世代モデル（Opus 4.8/Fable 5）では計測上のリコール退行を引き起こす。

本 Issue では find（発見）と filter（取捨）を明確に分離する。`review-bug` には全所見を confidence + severity タグ付きで報告させ、フィルタは downstream 検証段が担うことを明記する。

## Changed Files

- `agents/review-bug.md`: frontmatter `description` 更新、`## Purpose` セクションを coverage-first + confidence/severity タグ方針に書き換え、`### What to Flag (HIGH SIGNAL)` を `### What to Report` にリネーム、Output Format に confidence フィールド追加
- `agents/review-light.md`: `## Purpose` セクションに review-bug とのフィルタ温度感整合の注記を追加
- `docs/structure.md`: Agents テーブルの review-bug 説明を "(HIGH SIGNAL)" から "(coverage-first)" に更新（bash compat 非対象）

## Implementation Steps

1. `agents/review-bug.md` を編集する (→ AC1, AC2, AC3, AC4)
   - frontmatter `description:` を `Review: Bug/Logic Error Detection (coverage-first) — report all findings with confidence and severity tags; downstream verification sub-agents filter false positives` に変更
   - `## Purpose` セクション本文を以下に置き換え:
     「Role here is **coverage, not filtering**. Report all findings — including uncertain or low-severity ones — tagging each with **confidence** (high/medium/low) and **severity** (MUST/SHOULD/CONSIDER). Downstream verification sub-agents handle false-positive filtering; self-filtering at the finder stage reduces recall with literal filter-following models.」
   - `### What to Flag (HIGH SIGNAL)` → `### What to Report` にリネーム（セクション見出しのみ変更。内容は維持）
   - Output Format の各 finding エントリに `- confidence: high / medium / low` フィールドを追加（`- line:` フィールドの直後）

2. `agents/review-light.md` を編集する (→ AC5)
   - `## Purpose` セクション末尾（1段落目の後）に以下の注記を追加:
     「Note: Like `review-bug`, avoid excessive self-suppression. Report findings with confidence and severity tags rather than pre-filtering; downstream verification handles false positives.」

3. `docs/structure.md` を編集する（SHOULD）
   - Agents テーブルの review-bug 行: `Bug/Logic Error Detection (HIGH SIGNAL)` → `Bug/Logic Error Detection (coverage-first, confidence+severity tagged)`

## Verification

### Pre-merge

- <!-- verify: file_contains "agents/review-bug.md" "confidence" --> `agents/review-bug.md` が各所見に confidence を付して報告するよう指示している
- <!-- verify: file_contains "agents/review-bug.md" "severity" --> `agents/review-bug.md` が各所見に severity を付して報告するよう指示している
- <!-- verify: grep "downstream" "agents/review-bug.md" --> finder の役割が「カバレッジ（フィルタは後段）」であることが明記されている
- <!-- verify: section_not_contains "agents/review-bug.md" "## Purpose" "Minimize false positives" --> 自己フィルタ方針（Minimize false positives）が Purpose セクションから削除されている
- <!-- verify: file_contains "agents/review-light.md" "review-bug" --> `agents/review-light.md` に `review-bug` とのフィルタ温度感整合の注記がある
- <!-- verify: file_contains "skills/review/SKILL.md" "Step 10.3" --> 既存の `/review` 検証段（false-positive フィルタ, Step 10.3）が温存されている

### Post-merge

- 実 PR の `/review --full` で、変更前と比べ review-bug の報告所見が抑制されすぎていない（検証段で適切に絞り込まれている）ことを 1 件以上で目視確認 <!-- verify-type: manual -->

## Spec Retrospective

N/A

## Code Retrospective

### Deviations from Design

- None

### Design Gaps/Ambiguities

- None

### Rework

- None

## Notes

- `/review` Step 10.x の検証段（Step 10.3 の false-positive フィルタ）は現状維持。`skills/review/SKILL.md` の変更は不要
- Pre-merge AC が 6 件あり SPEC_DEPTH=light の 5 件上限を超過しているが、Issue body 既定の verify command を verbatim コピーしているため調整不可
- `section_not_contains` で Purpose セクションのみをスコープとするのは、"Minimize false positives" という語句がレトロスペクティブや "Do NOT Flag" セクションに残留した場合の false-negative を防ぐため（verify-patterns §1 参照）
- `confidence` (小文字) は現在 `agents/review-bug.md` に存在しない → Step 1 の Purpose 書き換えで追加
- `severity` (小文字) は現在 `agents/review-bug.md` に存在しない（現行は大文字 "Severity"）→ Step 1 で Output Format に `- confidence: high / medium / low` フィールドと、Purpose 本文に小文字 "severity" を追加することで充足
- `downstream` は現在 `agents/review-bug.md` に存在しない → Step 1 の Purpose 書き換えで追加
- `file_contains "skills/review/SKILL.md" "Step 10.3"` は現行ファイル line 401 に "Pass integrated results to Step 10.3" として確認済み（変更不要）

## review retrospective

### Spec vs. Implementation Divergence Patterns

`review-light.md` への注記追加で、注記内容とOutput Formatの不整合が発生した。注記が "confidence and severity tags" を指示したが、Output Formatに confidence フィールドの定義がなかった。注記と出力形式を同一コミットで整合させる（または `review-output-format.md` の共通形式を先に更新してから参照させる）ことで防げる。

### Recurring Issues

`review-bug.md` と `review-light.md` は Output Format が類似構造だが独立定義されている。`review-bug.md` の format 変更（confidence 追加）が `review-light.md` に波及しなかった。複数エージェントに共通する format 変更は `review-output-format.md` の共通テンプレートを更新することで一括適用できる。

### Acceptance Criteria Verification Difficulty

全6件とも verify command で即時自動判定可能（UNCERTAIN なし）。verify command の精度は良好。Post-merge 条件（実 PR での review-bug 所見数の目視確認）は手動確認として適切に分類されている。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #566 は mergeable=true（CI PASS、review APPROVED）でありコンフリクトなし、スカッシュマージを即実行
- BASE_BRANCH=main のため `closes #555` による Issue 自動クローズが有効
- フェーズハンドオフは review→merge でローテーション（review handoff を本内容で置き換え）

### Deferred Items
- post-merge 確認（実 PR で review-bug の所見が抑制されすぎないこと）は verify フェーズで目視確認
- "downstream verification handles false positives" の表現改善は次の機会での対応候補

### Notes for Next Phase
- 変更ファイル: `agents/review-bug.md`, `agents/review-light.md`（confidence field 追加）, `docs/structure.md`, `docs/ja/structure.md`
- 全 6 件の pre-merge verify commands は PASS（review フェーズで確認済み）
- post-merge verify: 実 PR の `/review --full` で review-bug 所見が適切に報告されること（抑制過多でないこと）を 1 件以上で目視確認すること
