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

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Issue Retrospective (/issue #342)

### 自動解決した曖昧点

| 曖昧点 | 採用した選択肢 | 根拠 |
|-------|-------------|------|
| 実装対象ファイル | `skills/code/forbidden-expressions-check.md`（新規 Domain file）+ `skills/code/SKILL.md` Step 9 に明示的参照 | #293 (Core/Domain 分離 Phase 2) が CLOSED 済みであることを確認。既存の `skill-dev-validation.md` と `stale-test-check.md` が同パターンで Domain file として実装されており、一貫性のある実装方針を採用 |
| ブロッカー関係 | "Blocked by #293" の記述を削除し「完了により実装可能」と更新 | `gh issue view 293` で CLOSED を確認。Issue body と Related Issues セクションの記述を最新状態に同期 |
| verify command 追加 | `file_exists "skills/code/forbidden-expressions-check.md"` を追加 | Domain file を新規作成する方針に変更したため、ファイル存在確認が適切。`skill-dev-validation.md` パターンとの整合性 |

### 受入条件変更の理由

元の受入条件は `skills/code/SKILL.md` に直接ステップを追加する前提だったが、#293 完了後の Domain file 方針に整合させるため、以下の変更を行った：

1. `file_exists "skills/code/forbidden-expressions-check.md"` を追加（Domain file 新規作成の確認）
2. `grep "check-forbidden-expressions" "skills/code/forbidden-expressions-check.md"` を追加（Domain file 内のコマンド確認）
3. `grep "check-forbidden-expressions" "skills/code/SKILL.md"` は継続して有効（SKILL.md が Domain file への参照を含むため）

### 特記事項

- `scripts/check-forbidden-expressions.sh` の存在を確認（ファイル実在済み）
- 実装パターンは `skill-dev-validation.md`（`validate-skill-syntax.py` 実行 Domain file）に倣う想定
