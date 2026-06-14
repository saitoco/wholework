# Issue #496: spec: Data Output Value (Code Value / Label) Accuracy Guideline

## Overview

When writing data output values (column names, enum values, code values) in Spec descriptions, there is a risk of surface mismatch with the actual implementation — particularly when Japanese labels and English code values coexist. For example, a Spec may write "新高値" (Japanese label) while the implementation outputs `rs_new_high` (English code value).

This mismatch degrades `rubric` grading reliability: the grader may resolve a Japanese label to the wrong English string, causing inconsistent PASS/FAIL.

This Issue adds a guideline to `skills/spec/SKILL.md` Step 10 (Create Spec) requiring that data output values in Spec descriptions be verified against actual implementation code.

## Changed Files
- `skills/spec/SKILL.md`: add **Data output value accuracy check** guideline to Step 10, after the rubric `file_contains` supplement paragraph (around line 358) and before the **String-matching verify command existence check** section

## Implementation Steps
1. In `skills/spec/SKILL.md` Step 10, immediately after the paragraph beginning "In particular, when the rubric's grader description contains a numeric literal, constant name, or threshold value..." (after the `file_contains` supplement guidance), insert the new **Data output value accuracy check** block (→ AC1, AC2):

```
**Data output value accuracy check:**

When Spec descriptions include data output values — column names, enum values, code values (コード値) — verify the exact value against the actual implementation code before writing:

1. Run `grep -rn '<value>' <impl-file>` to confirm the exact string the implementation outputs
2. When Japanese labels and English code values coexist, write both explicitly — e.g., `{rs_new_high (新高値) / rs_leading (Leader)}`
3. For `rubric` ACs that reference output values, cite the actual code value (not the display label) to prevent grader misinterpretation

**Background**: if a Spec writes a Japanese label where the implementation outputs an English code value, a `rubric` grader may fail to infer the correct mapping and produce inconsistent PASS/FAIL results.
```

## Verification
### Pre-merge
- <!-- verify: rubric "skills/spec/SKILL.md に『データ出力値は実実装コードを参照して正確に記述する』ガイドラインと多言語（日本語ラベルと英語コード値）併用時の明記例が追加されている" --> Spec 記述ガイドにデータ出力値一致ルールが追加されている
- <!-- verify: file_contains "skills/spec/SKILL.md" "コード値" --> SKILL.md にコード値一致ルールの説明（日本語用語を含む例）が含まれる

### Post-merge
- enum 値・コード値を含む実 Issue で `/spec` 実行 → 生成される Spec で実コード値が引用され、日本語ラベルと併記される場合は両方明示されることを目視確認する <!-- verify-type: opportunistic -->

## Notes
- SKILL.md はプロジェクト規約上英語だが、多言語例として "コード値" を含む記述は許容される（`docs/ja/` translation sync は `docs/*.md` のみが対象であり、`skills/spec/SKILL.md` は対象外）
- Auto-Resolved: Issue 本文の AC1 rubric が `skills/spec/SKILL.md または modules/skill-dev-checks.md` と両ファイルを対象にしていたが、`skills/spec/SKILL.md` のみを主対象とする — AC2 の `file_contains "skills/spec/SKILL.md"` が SKILL.md を必須チェックするため "または" は矛盾する。Step 10 がガイドラインの適切な追加先であり、`skill-dev-checks.md` はスキル開発チェック専用で汎用 Spec 記述ガイドには不適
- 変更は `skills/spec/SKILL.md` のみ。doc-checker の Change Type "Skill addition, change, or deletion" に当たるが、外部インターフェース変更なし（コマンドシグネチャ・ワークフローフェーズ不変）のため README.md / docs/workflow.md / CLAUDE.md の更新は不要

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- The Spec specified `chore:` prefix for Task type, but initial commit used `feat:` prefix — caught and corrected before push via `git commit --amend`

### Rework
- Commit prefix amended from `feat:` to `chore:` to match Issue Type=Task mapping; no functional change

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Inserted **Data output value accuracy check** block in `skills/spec/SKILL.md` Step 10 after the `file_contains` supplement paragraph and before the **String-matching verify command existence check** section, matching the Spec insertion point exactly
- Used `chore:` commit prefix (Issue Type=Task mapping)
- No documentation sync required: change is internal to `skills/spec/SKILL.md`, no external interface change

### Deferred Items
- Post-merge: observe that `/spec` runs on Issues with enum/code values and verify the generated Spec cites actual code values with Japanese/English dual notation (AC marked `verify-type: opportunistic`)

### Notes for Next Phase
- Both pre-merge ACs PASS: rubric and file_contains verified locally
- Change is a single-file guideline addition — no structural or interface changes; review scope is narrow
- Watch for any half-width `!` in the added block (none present; confirmed by validate-skill-syntax.py PASS)
