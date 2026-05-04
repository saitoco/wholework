# Issue #396: verify Step 13 の title-normalizer 二重読み込みを解消

## Overview

`skills/verify/SKILL.md` Step 13 の冒頭と `modules/retro-proposals.md` Step 1 の両方が `title-normalizer.md` を読み込んでいる。`modules/retro-proposals.md` は self-contained モジュールとして設計されており（`/auto` からも直接呼び出せるように）、内部で `title-normalizer.md` を読み込む。`skills/verify/SKILL.md` Step 13 冒頭の読み込み指示は冗長であるため削除する。

## Changed Files

- `skills/verify/SKILL.md`: Step 13 冒頭の `Read modules/title-normalizer.md` 文を削除

## Implementation Steps

1. `skills/verify/SKILL.md` の Step 13 冒頭にある以下の文を削除する（→ 受け入れ条件1・2）:
   ```
   Read `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` and follow the "Processing Steps" section to normalize titles (used for Issue title normalization when creating Issues).
   ```
   `Reuse \`HAS_SKILL_PROPOSALS\` already fetched...` の文は残す（`retro-proposals.md` に必要なコンテキスト）。

## Verification

### Pre-merge

- <!-- verify: file_not_contains "skills/verify/SKILL.md" "title-normalizer.md" --> `skills/verify/SKILL.md` Step 13 から `title-normalizer.md` 読み込み指示が削除されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "retro-proposals.md" --> `skills/verify/SKILL.md` Step 13 は引き続き `modules/retro-proposals.md` を読み込んでいる（リグレッション防止）
- <!-- verify: grep "title-normalizer" "modules/retro-proposals.md" --> `modules/retro-proposals.md` Step 1 の `title-normalizer.md` 読み込みが保たれている（リグレッション防止）

### Post-merge

- `/verify` Step 13 が `retro-proposals.md` 経由でのみ `title-normalizer.md` を使用することを確認する

## Notes

- `modules/retro-proposals.md` の self-contained 設計は維持する（`/auto` Step 4a からも直接呼び出されるため）
- 削除後も `HAS_SKILL_PROPOSALS` の reuse 文は Step 13 に残す（`retro-proposals.md` の Input として必要）
