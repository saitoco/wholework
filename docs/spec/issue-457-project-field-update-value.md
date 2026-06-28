# Issue #457: project-field-update: Label Naming Conventions 表に Value 行を追加

## Overview

`modules/project-field-update.md` の「Label Naming Conventions」表に Value フィールドの行が存在しない。Priority / Size / Type の 3 行のみ定義されており、Value フィールドのラベルフォールバック時の prefix・options・除去対象ラベルが未定義。`value/*` ラベルは `scripts/setup-labels.sh` に定義済みであり、表への追記のみが残存スコープ。根本バグ (triage Step 7 が Value 非対応モジュールを経由していた) は #435 で解消済み。

## Reproduction Steps

1. `modules/project-field-update.md` の「### Label Naming Conventions」表を参照する
2. Value フィールドの行が存在しないことを確認する (Priority / Size / Type の 3 行のみ)

## Root Cause

Label Naming Conventions 表が Priority / Size / Type の 3 フィールドしかカバーしていなかった。`scripts/setup-labels.sh` に `value/*` (value/1〜value/5) の fallback ラベルが定義されているにもかかわらず、対応するドキュメント行が追加されていなかった。

## Changed Files

- `modules/project-field-update.md`: 「### Label Naming Conventions」表の末尾 (Type 行の直後) に Value 行を追加 — bash 3.2+ 非該当 (Markdown テキスト変更のみ)

## Implementation Steps

1. `modules/project-field-update.md` の「### Label Naming Conventions」表の Type 行直後に Value 行を追加 (→ AC 1, AC 2)
   - Field: `Value`
   - Prefix: `value/`
   - Options (exhaustive): `1`, `2`, `3`, `4`, `5`
   - Labels to Remove: `--remove-label "value/1" --remove-label "value/2" --remove-label "value/3" --remove-label "value/4" --remove-label "value/5"`

## Verification

### Pre-merge

- <!-- verify: section_contains "modules/project-field-update.md" "### Label Naming Conventions" "value/" --> `modules/project-field-update.md` の「Label Naming Conventions」表に `value/` prefix 行が追加されている
- <!-- verify: grep "value/1" "modules/project-field-update.md" --> Value の除去対象ラベル (`value/1`〜`value/5`) が表に記載されている

### Post-merge

なし

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective with Auto-Resolve Log: 修正スコープを Label Naming Conventions 表への Value 行追加のみに限定、根本バグは #435 で解消済みと確認 / https://github.com/saitoco/wholework/issues/457#issuecomment-4825388438

## Notes

- 修正スコープはドキュメント補完のみ。行動バグ (Value フィールドが毎回 `value/N` ラベルにフォールバックしていた) は #435 の `update-issue-fields-batch` 導入で解消済みのため、本 PR はテーブル行追加だけで完了する。
- `modules/project-field-update.md` の冒頭見出し ("Priority / Size" とのみ記載) の更新は本 Issue のスコープ外 (Issue body の残存スコープに明示されていない)。
- `docs/structure.md` や `docs/ja/structure.md` はファイル名を参照するのみであり、内容変更は不要。

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- None — Spec was precise and the change was a single-line table row addition with no ambiguity.

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added Value row directly after the Type row in the Label Naming Conventions table, matching the column format of existing rows (Field / Prefix / Options / Labels to Remove).
- Scope limited strictly to the table addition; module header ("Priority / Size") not updated as it was explicitly out of scope per Spec Notes.

### Deferred Items
- Module header update ("Priority / Size" only mentions two fields) is deferred — out of scope per Issue body.

### Notes for Next Phase
- The change is a single Markdown table row addition; /verify pre-merge checks should PASS cleanly with section_contains and grep verify commands.
