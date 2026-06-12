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

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- coverage-first 方針への切り替え: Purpose セクション本文を丸ごと置き換え、downstream 検証段へのフィルタ委譲を明示した
- `confidence` フィールドを Output Format の `- line:` 直後に追加（Spec 指定通り）
- `review-light.md` への注記は Purpose 1段落目の直後に挿入（自然な読み順）
- `docs/structure.md` + `docs/ja/structure.md` の両方を更新（translation-workflow.md に従う）

### Deferred Items
- post-merge 確認（実 PR で review-bug の所見が抑制されすぎないこと）は `/review` 後の目視確認として残置

### Notes for Next Phase
- 変更ファイル: `agents/review-bug.md`, `agents/review-light.md`, `docs/structure.md`, `docs/ja/structure.md`
- 全 6 件の pre-merge verify commands は PASS 済み（Issue チェックボックス更新済み）
- `skills/review/SKILL.md` は変更なし（Step 10.3 は現状維持）
