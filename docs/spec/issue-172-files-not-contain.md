# Issue #172: verify: verify-executor に複数ファイル一括検査 verify command type を追加

## Overview

`/verify` の受入条件で `file_not_contains` を複数ファイルに対して繰り返す pattern が冗長（Issue #165 では 14 件並列）。`files_not_contain "glob_pattern" "text"` 一括検査 verify command type を `modules/verify-executor.md` の translation table に追加し、複数ファイルへの否定検査を 1 行で表現できるようにする。既存の `file_not_contains` は後方互換として維持する。

## Changed Files

- `modules/verify-executor.md`: translation table（Step 4）の `file_not_contains` 行の直後に `files_not_contain "glob_pattern" "text"` 行を追加
- `scripts/validate-skill-syntax.py`: `KNOWN_VERIFY_COMMAND_TYPES` dict に `'files_not_contain': (2, 2)` を `'file_not_contains': (2, 2)` の直後に追加
- `tests/validate-skill-syntax.bats`: valid verify commands テストケース（"success: valid verify commands pass validation"）に `files_not_contain` の使用例を追加

## Implementation Steps

1. `modules/verify-executor.md` の translation table（Step 4）で `| \`file_not_contains "path" "text"\` |` 行の直後に以下の行を追加（→ 受入条件 1, 2）:
   ```
   | `files_not_contain "glob_pattern" "text"` | Expand glob_pattern with Glob tool; search each matched file for "text" using Grep; PASS if no files contain it, FAIL listing files that match. If no files match the glob, PASS. Safe-mode compatible. |
   ```

2. `scripts/validate-skill-syntax.py` の `KNOWN_VERIFY_COMMAND_TYPES` dict（`'file_not_contains': (2, 2)` 行の直後）に追加（→ 受入条件 3）:
   ```python
   'files_not_contain': (2, 2),
   ```
   合わせて `tests/validate-skill-syntax.bats` の "success: valid verify commands pass validation" テストの SKILL.md ヒア文書に `files_not_contain` 使用例を追記。

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/verify-executor.md" "files_not_contain" --> `verify-executor.md` の translation table に `files_not_contain` コマンドが追加されている
- <!-- verify: grep "glob_pattern" "modules/verify-executor.md" --> glob pattern を引数とする構文が定義されている
- <!-- verify: file_contains "scripts/validate-skill-syntax.py" "files_not_contain" --> `KNOWN_VERIFY_COMMAND_TYPES` に `files_not_contain` が追加されている
- 既存の `file_not_contains` コマンドは後方互換として維持されている（手動確認）

### Post-merge

- `files_not_contain "glob/**/*.md" "deprecated-text"` 形式の verify command が `/verify` で正常に解釈・実行されることを確認

## Notes

- `files_not_contain` は `file_not_contains` の複数ファイル版。引数形式は `(2, 2)` で同じ（glob_pattern, text）
- glob に一致するファイルが 0 件の場合は PASS（検査対象なし = 含むファイルなし）
- Issue #165 の spec retrospective から提案された改善。14 件の `file_not_contains` を数件の `files_not_contain` に集約可能

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
