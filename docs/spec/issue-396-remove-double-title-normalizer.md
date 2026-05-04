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

## Code Retrospective

### Deviations from Design

- N/A（Spec 通りに実装）

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件は `file_not_contains` / `file_contains` / `grep` の 3 パターンで明確に検証可能に設計されており、曖昧さがない。
- Issue body の「Auto-Resolved Ambiguity Points」に、修正前の状態確認クライテリア（修正後に意図的に FAIL になるため削除）を明示的に記載しており、意思決定の透明性が高い。

#### design
- Spec が「`skills/verify/SKILL.md` 1 ファイルのみ変更」と明示しており、実装範囲が明確だった。
- `modules/retro-proposals.md` の self-contained 設計維持について Notes に記載されており、設計判断の根拠が残っている。

#### code
- 1 行変更（1 insertion, 1 deletion）で完結。fixup/amend なし、リワークなし。Spec 通りに実装。

#### review
- パッチルート（PR なし）のため、コードレビューは未実施。変更が 1 行と小さく、自動検証で十分カバーできた。

#### merge
- main へのダイレクトコミット。コンフリクトなし、CI 問題なし。

#### verify
- 3 条件すべて PASS。verify コマンドが実装対象のファイル内容を直接検証する設計で、誤判定リスクがない。

### Improvement Proposals
- N/A
