# Issue #381: skill-dev-constraints: Add Non-Interactive Fallback Rule for macOS System-Level Debugging

## Overview

Add one SHOULD constraint row to `skills/spec/skill-dev-constraints.md` that instructs Spec designers to explicitly state a static analysis fallback when implementation steps include macOS system-level debugging procedures (e.g., `fs_usage`, Console.app privacy logs) that cannot run in `--non-interactive` mode.

Background: Issue #378 `/code` run in non-interactive mode had to auto-resolve because the Spec's Step 1 (live trace via `fs_usage` / Console.app) was impossible in that context. Adding this constraint at design time reduces auto-resolve risk for future similar implementations.

## Changed Files

- `skills/spec/skill-dev-constraints.md`: add one row to the SHOULD constraint table — macOS system-level debug fallback

## Implementation Steps

1. In `skills/spec/skill-dev-constraints.md`, append the following row to the SHOULD constraint table (after the last existing row):

   ```
   | macOS system-level debug fallback | When implementation steps include macOS system-level debugging procedures (e.g., `fs_usage`, Console.app privacy logs) requiring interactive execution, explicitly state that `--non-interactive` mode uses static analysis + hypothesis evaluation as an alternative | #378 |
   ```

   (→ acceptance criteria 1, 2, 3)

## Verification

### Pre-merge

- <!-- verify: grep "non-interactive" "skills/spec/skill-dev-constraints.md" --> `skills/spec/skill-dev-constraints.md` に `non-interactive` の記述が追加されている
- <!-- verify: grep "fs_usage\|実機トレース\|system-level" "skills/spec/skill-dev-constraints.md" --> macOS システムレベルデバッグ手順（`fs_usage` または `system-level`）への言及がある
- <!-- verify: file_contains "skills/spec/skill-dev-constraints.md" "static analysis" --> 静的解析代替の旨（`static analysis`）が記述されている

### Post-merge

- 次回 macOS システムレベルデバッグを含む Spec を `/spec --full` で設計した際、この SHOULD 制約が design-time チェックリストとして表示されることを確認

## Notes

- ISSUE_TYPE=Task のため Uncertainty および UI Design セクションは省略
- 追加するテキストは 1 行（テーブル行）のみ。`skill-dev-constraints.md` は docs/ 配下でなく `skills/spec/` 配下のため翻訳同期不要

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
