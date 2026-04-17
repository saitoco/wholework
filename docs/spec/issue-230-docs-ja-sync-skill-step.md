# Issue #230: Add docs/ja/ Sync Check to Skill Steps

## Overview

When English top-level `docs/*.md` files (steering/project documents) are updated, the
corresponding `docs/ja/` mirror files may be missed. This was detected in Issue #227's
review as a Copilot finding but was not structurally prevented by skill steps.

Add explicit `docs/ja/` sync checks to:
- `/code` SKILL.md Step 9 "Documentation consistency check" subsection
- `/review` SKILL.md `## Review Aspects` documentation consistency check list

Target scope: top-level `docs/*.md` files only (excluding `docs/spec/`, `docs/reports/`
subdirectories). `doc-checker.md` already excludes `docs/ja/` from its target list, so
this is a complementary check, not a replacement.

## Changed Files

- `skills/code/SKILL.md`: add `docs/ja/` sync check paragraph after the doc-checker
  section in "Documentation consistency check" subsection of Step 9
- `skills/review/SKILL.md`: add `docs/ja/` sync check bullet to the documentation
  consistency check list in `## Review Aspects`

## Implementation Steps

1. Edit `skills/code/SKILL.md` — append `docs/ja/` sync check paragraph after "If sync
   is required, update the target documents..." in Step 9's "Documentation consistency
   check" subsection (→ acceptance criteria A)

2. Edit `skills/review/SKILL.md` — add `docs/ja/` sync bullet to the documentation
   consistency check list in `## Review Aspects` (→ acceptance criteria B)

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/code/SKILL.md" "### Step 9: Run Tests" "docs/ja" --> `/code` SKILL.md の Step 9 に `docs/ja/` 同期チェックが追記されている
- <!-- verify: section_contains "skills/review/SKILL.md" "## Review Aspects" "docs/ja" --> `/review` SKILL.md の Review Aspects セクションに `docs/ja/` 同期チェックが追記されている

### Post-merge

- `/code` 実行時に英語 `docs/*.md` 変更が含まれる場合、Step 9 で `docs/ja/` の確認が促される
- `/review` 実行時に英語 `docs/*.md` 変更が含まれる場合、Review Aspects の観点として `docs/ja/` 同期漏れが検出される

## Notes

- `doc-checker.md` の Processing Steps 2 で `docs/{lang}/` は明示的に除外されているため、本 Issue の追記は doc-checker を補完する独立したチェックとして位置付ける
- Issue body の Auto-Resolved Ambiguity Points で実装箇所が確定済み（モジュール新設なし、SKILL.md 直接追記）
- 対象ドキュメント範囲: `docs/*.md` トップレベルのみ（`docs/spec/`・`docs/reports/` 配下を除く）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
