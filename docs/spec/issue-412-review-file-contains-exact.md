# Issue #412: Add file_contains Exact Match Check to Review Checklist

## Overview

During `/review` Step 8 (acceptance criteria verification), `file_contains` verify commands perform exact fixed-string substring matches. When the pattern string in a verify command differs from the actual implementation code due to shell quoting (e.g., `get-config-value.sh permission-mode auto` vs `"$SCRIPT_DIR/get-config-value.sh" permission-mode auto`), the check returns FAIL even though the implementation is correct.

Add a note to `skills/review/SKILL.md` Step 8 instructing the reviewer to cross-check `file_contains` patterns against the actual PR diff for exact match validity, specifically flagging shell quoting discrepancies.

## Changed Files

- `skills/review/SKILL.md`: add `file_contains` exact match check note to Step 8, between the condition classification list and `### Checkbox Updates`

## Implementation Steps

1. In `skills/review/SKILL.md`, after line 248 (`- POST-MERGE — condition to verify after merge`) and before line 250 (`### Checkbox Updates`), insert the following note (→ acceptance criteria 1, 2, 3):

   ```markdown

   **`file_contains` exact match check:**

   For `file_contains` verify commands, verify that the pattern is an exact substring of the implementation code in the PR diff. Shell quoting causes false negatives: `get-config-value.sh permission-mode auto` will not match `"$SCRIPT_DIR/get-config-value.sh" permission-mode auto`. When a FAIL result stems from a quoting or path-prefix discrepancy rather than a genuine implementation gap, report it as a spec quality issue requiring a verify command update.
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md includes a checklist item or note to verify that file_contains verify command patterns exactly match the implementation code substring" --> `skills/review/SKILL.md` に `file_contains` verify command のパターンが実装コードの exact substring と一致しているかを確認する記述が追加されている
- <!-- verify: grep "file_contains.*exact" "skills/review/SKILL.md" --> `skills/review/SKILL.md` に `file_contains` と `exact` が同一行に存在する（補助確認）
- <!-- verify: grep "quoting" "skills/review/SKILL.md" --> `skills/review/SKILL.md` に shell quoting に関する記述が追加されている

### Post-merge

- `/review` を使用した際に Step 8 の verify command 実行後に `file_contains` exact match チェックのガイダンスが表示されることを確認する

## Notes

- 追加箇所は Step 8 の条件分類リスト（PASS/FAIL/UNCERTAIN/POST-MERGE）の直後、`### Checkbox Updates` の前（`skills/review/SKILL.md` L248〜L250 間）
- 挿入する注記はノート形式（箇条書きではなく `**bold heading:**` 形式）。Issue body の "スコープは `file_contains` に限定" の auto-resolve 決定に従い、`grep` や他のコマンドは対象外
- verify command 1（rubric）はセマンティック検証、verify command 2/3（grep）は機械的補助確認として組み合わせ使用

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue の受け入れ条件が明確かつ自動検証可能な形式で記述されていた。`rubric`（セマンティック）+ `grep`（機械的補助）の組み合わせはドキュメント追加系 Issue に適したパターン
- Auto-resolve ambiguity points がスコープ決定（`file_contains` 限定）と検索パターン変更（日本語→英語）の経緯を正確に記録しており、retrospective 上も追跡可能

#### design
- Spec の実装ステップが挿入位置（L248〜L250 間）まで具体的に指示しており、実装との乖離なし
- 単一ファイル・単一箇所の追記であり、設計判断の複雑さは低い

#### code
- コミット `f491677` 1件で完結、fixup/amend なし。Spec 通りの挿入位置・形式で実装
- patch route（PR なし、main 直コミット）で適切なサイズ判断

#### review
- patch route のため正式 review なし（PR 未作成）。Size S 相当の一行注記追加なので許容範囲

#### merge
- main への直接コミットで競合なし

#### verify
- 全 3 条件が初回で PASS。rubric + grep の組み合わせが機能した
- post-merge 条件（`/review` 実行時の動作確認）は verify command なしのため手動確認扱いとなっているが、実装が Spec 通りのため実質的リスクは低い

### Improvement Proposals
- N/A
