# Issue #342: code: forbidden-expressions チェックをローカル実行するステップを /code 完了前に追加

## Overview

`skills/code/forbidden-expressions-check.md` Domain file を新規作成し、`scripts/check-forbidden-expressions.sh` のローカル実行ステップを定義する。また `skills/code/SKILL.md` Step 9 に当該 Domain file への明示的な参照ステップを追加し、CI でのみ検知される forbidden expressions 違反を事前に防ぐ。

実装パターンは `skills/code/skill-dev-validation.md`（`validate-skill-syntax.py` を実行する Domain file）に倣う。

**起因**: Issue #316 の fix commit で forbidden expression 混入を PR レビュー後に検知。ローカル実行ステップで CI より先に検知可能にする。

## Changed Files

- `skills/code/forbidden-expressions-check.md`: new file — Domain file for local forbidden expressions check
- `skills/code/SKILL.md`: add reference to `forbidden-expressions-check.md` in Step 9 "Additional validation" section

## Implementation Steps

1. Create `skills/code/forbidden-expressions-check.md` following the `skill-dev-validation.md` pattern — bash 3.2+ compatible:
   - frontmatter: `type: domain`, `skill: code`, `load_when: file_exists_any: [scripts/check-forbidden-expressions.sh]`
   - Processing Steps: run `bash scripts/check-forbidden-expressions.sh` and handle failure same as test failures
   (→ acceptance criteria 1, 2)

2. In `skills/code/SKILL.md` Step 9, add after the existing `skill-dev-validation.md` reference line (line 227):
   ```
   If `scripts/check-forbidden-expressions.sh` exists, Read `${CLAUDE_PLUGIN_ROOT}/skills/code/forbidden-expressions-check.md` and follow the "Processing Steps" section.
   ```
   (→ acceptance criteria 3)

## Verification

### Pre-merge

- <!-- verify: file_exists "skills/code/forbidden-expressions-check.md" --> `skills/code/forbidden-expressions-check.md` が新規作成されている
- <!-- verify: grep "check-forbidden-expressions" "skills/code/forbidden-expressions-check.md" --> Domain file に `check-forbidden-expressions.sh` の実行ステップが含まれている
- <!-- verify: grep "check-forbidden-expressions" "skills/code/SKILL.md" --> `skills/code/SKILL.md` Step 9 に forbidden-expressions-check.md への参照が追加されている

### Post-merge

- `/code` 実行時に `scripts/check-forbidden-expressions.sh` が存在するリポジトリで Domain file がロードされ、ローカルチェックが実行されることを確認する

## Notes

- `load_when: file_exists_any: [scripts/check-forbidden-expressions.sh]` — `skill-dev-validation.md` の `file_exists_any: [scripts/validate-skill-syntax.py]` と同じ条件型を採用。wholework リポジトリ以外ではスクリプトが存在しないため、`load_when` で条件付きロードにする
- Domain file の追加によって `skills/code/SKILL.md` 自体の domain-loader 呼び出し箇所（Step 7）は変更不要。`load_when` 条件が `forbidden-expressions-check.md` 側で制御するため
