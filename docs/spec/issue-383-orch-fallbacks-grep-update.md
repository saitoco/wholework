# Issue #383: Update orchestration-fallbacks conflict marker doc to git grep

## Overview

`modules/orchestration-fallbacks.md` の `conflict-marker-residual` エントリ（行 176, 184）で、
競合マーカー検出コマンドとして `grep -rn '^<<<<<<' .` が記載されている。
`scripts/worktree-merge-push.sh` はすでに `git grep -l '^<<<<<<'` へ移行済みだが、
ドキュメント例が旧パターンのままになっており、手動復旧手順のコピー実装で
非推奨パターンが再導入されるリスクがある。本 Issue ではドキュメント例を
`git grep` 推奨に揃え、リポジトリ境界を越えたスキャンを誘発しないパターンに統一する。

## Changed Files

- `modules/orchestration-fallbacks.md`: `conflict-marker-residual` エントリの Symptom（行 176）と Fallback Steps Step 1（行 184）の `grep -rn '^<<<<<<' .` を `git grep -l '^<<<<<<'` に変更
- `modules/filesystem-scope.md`: Implementation Reference の `orchestration-fallbacks.md` 参照テキスト（行 75–76）を更新 — "historical reference" 文言を除去し、`git grep` を使用する旨に揃える（受入条件外・整合性改善）

## Implementation Steps

1. `modules/orchestration-fallbacks.md` の `### Symptom` セクション（行 176）を編集:
   - 変更前: `- \`grep -rn '^<<<<<<' .\` finds conflict marker lines (\`<<<<<<<\`, \`=======\`, \`>>>>>>>\`) in tracked files`
   - 変更後: `- \`git grep -l '^<<<<<<'\` finds tracked files containing conflict marker lines (\`<<<<<<<\`, \`=======\`, \`>>>>>>>\`)`
   (→ AC1, AC2)

2. `modules/orchestration-fallbacks.md` の `### Fallback Steps` セクション Step 1（行 184）を編集:
   - 変更前: `1. Run \`grep -rn '^<<<<<<' . 2>/dev/null\` to identify files containing conflict markers`
   - 変更後: `1. Run \`git grep -l '^<<<<<<' 2>/dev/null\` to identify files containing conflict markers`
   (→ AC1, AC2)

3. `modules/filesystem-scope.md` の `## Implementation Reference` セクション（行 75–76）を編集:
   - 変更前:
     ```
     - `modules/orchestration-fallbacks.md` — documents the `grep -rn '^<<<<<<' .` pattern
       (historical reference; `worktree-merge-push.sh` uses `git grep` instead)
     ```
   - 変更後:
     ```
     - `modules/orchestration-fallbacks.md` — documents conflict marker detection using `git grep -l '^<<<<<<'` (consistent with `worktree-merge-push.sh`)
     ```
   (→ 整合性改善)

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/orchestration-fallbacks.md" "git grep" --> `modules/orchestration-fallbacks.md` に `git grep` を推奨する記述が含まれている
- <!-- verify: file_not_contains "modules/orchestration-fallbacks.md" "grep -rn '^<<<<<<'" --> 旧 `grep -rn '^<<<<<<' .` パターンがドキュメント例から削除されている

### Post-merge

- 本 Issue で追加されたガイダンスが `scripts/worktree-merge-push.sh` の実装と一致していることを確認

## Notes

- `tests/orchestration-fallbacks.bats` はスキーマ検証テスト（構造・必須セクション・Issue 参照の有無）のみ。コマンド例の変更によるテスト更新は不要
- `docs/reports/repo-scope-audit.md`（行 88）には旧パターンを「historical reference」と記録しているが、`docs/reports/` は sync 対象外のスナップショットのため更新不要
- `filesystem-scope.md` 行 75–76 の更新は AC 外だが、変更後に記述が不正確になるため一括修正する
