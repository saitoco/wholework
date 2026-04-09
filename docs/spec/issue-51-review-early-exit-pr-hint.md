# Issue #51: fix: PR 経路を意図的に選択した Size=S の PR で /review が早期スキップされる

## Overview

`/review` skill は Size=XS/S の場合、`REVIEW_DEPTH=skip` として早期終了する設計になっている。
しかし、main ブランチ保護等の理由でユーザーが意図的に PR 経路を選択した場合でも、同じ早期終了メッセージが表示され、`--light` で再実行できることが伝わらない。

早期終了メッセージに `--light` での明示的再実行案内を追加することで、ユーザーがレビューを取りこぼさないようにする。

## Reproduction Steps

1. Size=S の Issue を作成
2. ユーザー判断により patch route ではなく PR route を選択
3. PR 作成後に `/review {PR番号}` を実行
4. → "Patch route — review is not needed." で早期終了し、`--light` での再実行案内が表示されない

## Root Cause

`skills/review/SKILL.md` Step 3（line 109）の早期終了メッセージが単一行のみで、明示的レビューが必要なケース（main ブランチ保護等）での再実行方法を案内していない。

## Changed Files

- `skills/review/SKILL.md`: Step 3 早期終了メッセージに `--light` 再実行案内行を追加

## Implementation Steps

1. `skills/review/SKILL.md` の Step 3 早期終了メッセージ（line 109）を以下のように変更する（→ 受け入れ条件 1, 2, 3）:

   変更前:
   ```
   Patch route — review is not needed. Proceed with `/merge $PR_NUMBER`.
   ```

   変更後:
   ```
   Patch route — review is not needed. Proceed with `/merge $PR_NUMBER`.
   If you need to run a review explicitly (e.g., main branch protection required PR route), run `/review $PR_NUMBER --light`.
   ```

## Verification

### Pre-merge

- <!-- verify: grep "need to run a review explicitly" "skills/review/SKILL.md" --> `skills/review/SKILL.md` の早期終了メッセージに `--light` での再実行案内が追加されている
- <!-- verify: grep "main branch protection" "skills/review/SKILL.md" --> 早期終了メッセージに main 保護のユースケース言及がある
- <!-- verify: file_contains "skills/review/SKILL.md" "/review $PR_NUMBER --light" --> 早期終了メッセージに具体的な再実行コマンドが含まれている

### Post-merge

- Size=S の Issue で PR を作成し `/review {PR番号}` を実行 → 新しい早期終了メッセージが表示されることを確認 (verify-type: opportunistic)
- 続けて `/review {PR番号} --light` を実行 → light review が走ることを確認 (verify-type: opportunistic)

## Notes

- XS も同じ早期終了パスを通るため、メッセージ変更で同時にカバーされる
- 既存の Size=S → skip 動作（patch route 想定）は変更しない（後方互換性維持）
- 本提案は Issue #49 の `/verify` レトロスペクティブで検出
