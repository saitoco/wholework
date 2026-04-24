# Issue #375: github_check Display Name Fallback

## Overview

`github_check "gh pr checks" "check-forbidden-expressions"` のような verify command で、`gh pr checks` の出力が CI job の **表示名**（"Forbidden Expressions check"）を返す一方、expected_value には **job ID**（"check-forbidden-expressions"）が指定されている場合に literal 不一致が発生する。

`modules/verify-executor.md` の `github_check` 処理に、literal match 失敗後に `.github/workflows/*.yml` の job key → `name` フィールドのマッピングを探索して display name で再照合する fallback ロジックを追加する。

## Changed Files

- `modules/verify-executor.md`: `github_check` 処理の説明を拡張 — literal match 失敗時に `.github/workflows/*.yml` から job key → display name を解決して再照合する fallback 手順を記述する

## Implementation Steps

1. `modules/verify-executor.md` の `github_check` テーブル行（"confirm output contains `expected_value`" の部分）を拡張する:
   - 現行: `expected_value` が出力に含まれていれば PASS
   - 拡張: literal match 失敗後の fallback として、`.github/workflows/*.yml` 内の全 job を走査し、`expected_value` に一致する job key を探す。見つかった場合、その job の `name` フィールドの値（display name）を取得し、`gh_command` 出力に display name が含まれるか再照合する。display name でも一致すれば PASS（detail に "Matched via display name: '{display name}' resolved from job key '{expected_value}'"を記録）。両方で一致しなければ FAIL。`.github/workflows/` が存在しないか、対応する job key が見つからない場合は fallback をスキップして literal match 結果（FAIL）を採用する（→ AC1、AC3）

## Verification

### Pre-merge
- <!-- verify: rubric "modules/verify-executor.md の github_check 処理に、expected_value が literal match しない場合に .github/workflows/ YAML の job key → name フィールドから display name を解決して再照合する fallback ロジックが説明されている" --> `verify-executor.md` に github_check で job ID と display name の両方を照合する仕組みが記述されている
- <!-- verify: grep "display name" "modules/verify-executor.md" --> `verify-executor.md` に display name の概念が記述されている（機械的確認）
- <!-- verify: rubric "modules/verify-executor.md が check-forbidden-expressions → Forbidden Expressions check のような具体的な job ID → display name 解決シナリオをカバーしており、literal match 失敗後に YAML fallback で PASS となる手順が明確である" --> job ID 形式の expected string を display name に解決して PASS を返す具体的な手順が記述されている

### Post-merge
- `/verify` を実行したとき、`github_check "gh pr checks" "check-forbidden-expressions"` が display name マッピングを経て PASS を返すことを確認する <!-- verify-type: opportunistic -->

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
