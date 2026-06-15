# Issue #663: review summary 投稿チャネルを issue comment に強制し reconcile に PR Review scan を追加

## Overview

`/review` フェーズで、summary 投稿に `gh pr comment` (issue comment channel) を使うべきところを実行 LLM が PR Review channel (`gh api .../reviews`) に投稿した場合に silent no-op が発生していた。本 Issue では 2 層の対策を実施する:

- **案 A (一次予防)**: `skills/review/SKILL.md` Step 14 に `gh pr comment` 使用の明示的禁則 (MUST) と `<!-- review-summary -->` marker を body 先頭行に置く指示を追加
- **案 B (二次防衛)**: `scripts/reconcile-phase-state.sh` の `_completion_review` 関数に PR Review body (GitHub API `pulls/{N}/reviews`) のスキャンを追加し、deviation しても reconcile が marker を検出できるようにする

## Changed Files

- `skills/review/SKILL.md`: Step 14 "Post Response Summary" に MUST 禁則ノートを追加 — `gh pr comment` 使用必須、`gh api .../reviews`/`gh pr review` 使用禁止、marker は body 先頭行
- `scripts/reconcile-phase-state.sh`: `_completion_review` 関数 (lines 268-285) に PR Review body scan を追加 — `gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews" -q '.[].body'` 取得後 comments と結合してマーカー検索 — bash 3.2+ 互換
- `tests/reconcile-phase-state.bats`: 新規テスト追加 — "review completion: marker only in PR Review body -> matches_expected true" (mock `gh` が `pr view` に対し空、`api` に対し `<!-- review-summary -->` を返す)

## Implementation Steps

1. `skills/review/SKILL.md` Step 14 のテンプレートと marker ノートを更新: (→ AC2)
   - テンプレートの `<!-- review-summary -->` を body 先頭行に移動 (`## Review Response Summary` の前)
   - 既存 marker note (line 718) に先頭行配置の要件を追記
   - `### 14.2. Post PR Comment` の直前に MUST 禁則ブロックを追加:「MUST: `gh pr comment` を使用。`gh api repos/.../pulls/.../reviews` や `gh pr review` は使用しないこと — PR Review channel は `reconcile-phase-state.sh` がスキャンしないため silent no-op になる」

2. `scripts/reconcile-phase-state.sh` `_completion_review` 関数を拡張: (→ AC3)
   - `comments` 取得の直後に reviews 取得を追加:
     ```bash
     local reviews
     reviews=$(gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews" -q '.[].body' 2>/dev/null) || true
     local combined="${comments}${reviews}"
     ```
   - `echo "$comments"` を `echo "$combined"` に変更し、PR Review body も grep 対象に含める

3. `tests/reconcile-phase-state.bats` に PR Review body 検出テストを追加: (→ AC4)
   - `# --- review completion ---` セクション末尾に新規 `@test` を追加
   - mock `gh`: `case "$1" in pr) echo "" ;; api) echo "<!-- review-summary -->" ;; esac`
   - 期待: `status -eq 0` かつ `'"matches_expected":true'` を含む

## Verification

### Pre-merge

- <!-- verify: grep "gh pr comment" "skills/review/SKILL.md" --> `skills/review/SKILL.md` に `gh pr comment` 使用の明示的指示が残っている（regression guard: 既存指示の削除防止）
- <!-- verify: rubric "skills/review/SKILL.md の summary 投稿セクション (Step 11 Post Review Results 周辺) に、(1) MUST: gh pr comment を使用し gh api .../reviews や gh pr review を使用しないこと、(2) <!-- review-summary --> marker は body の先頭行に置くこと、の 2 点が明示的な禁則・指示として追加されている" --> SKILL.md に PR Review channel 使用禁止 (MUST) と review-summary marker 配置 (body 先頭行) の指示が追加されている
- <!-- verify: grep "pulls/.+/reviews" "scripts/reconcile-phase-state.sh" --> `reconcile-phase-state.sh` に `pulls/.../reviews` API 呼び出し経路の PR Review body scan が追加されている
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> 既存 bats テストが green (regression 無し)

### Post-merge

- 次回 `/auto` 完走時に review phase の silent no-op が再発しないことを確認

## Notes

- `gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews"` の `{owner}/{repo}` は `gh` CLI が自動解決する
- PR Review body が空または API が失敗した場合は `|| true` で無視し、issue comments のみで判定する
- 既存テストの mock `gh` は args に関係なく固定値を返す実装のため、新規テストでは `case "$1"` で `pr` / `api` を分岐させる
- Step 1 で marker を body 先頭行に移動するのはテンプレートのみ。既存の `_completion_review` grep パターンはヘッダー行検索も含むため、marker の位置変更はスクリプト側の変更不要
