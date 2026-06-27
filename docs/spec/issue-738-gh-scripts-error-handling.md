# Issue #738: scripts/gh-*.sh: unify explicit error handling for API failures

## Overview

`scripts/gh-*.sh` 8 個のうち 4 個 (`gh-check-blocking.sh`, `gh-issue-edit.sh`, `gh-issue-comment.sh`, `gh-extract-issue-from-pr.sh`) は既に明示的 error handling (exit code チェック + stderr メッセージ + non-zero exit) を持つ。残る 4 個 (`gh-graphql.sh`, `gh-label-transition.sh`, `gh-pr-merge-status.sh`, `gh-pr-review.sh`) は `set -euo pipefail` のみで、GitHub API 失敗時に stderr へ識別可能なメッセージを出力しない。本 Issue はこれら 4 個に明示的 error handling を追加し、API failure を発見可能にする。

## Changed Files

- `scripts/gh-pr-merge-status.sh`: `gh pr view` 呼び出し (line 45) に `|| { echo "Error: ..." >&2; exit 1; }` を追加 — bash 3.2+ compatible
- `scripts/gh-label-transition.sh`: `gh issue edit` 3 呼び出し (lines 68, 90, 92) を `if ! ...; then echo "Error..." >&2; exit 1; fi` パターンに変更 — bash 3.2+ compatible
- `scripts/gh-graphql.sh`: `gh api graphql` 2 呼び出し (cache path line 274, no-cache path line 291) に `|| { echo "Error: ..." >&2; exit 1; }` を追加 — bash 3.2+ compatible
- `scripts/gh-pr-review.sh`: 2 箇所のパイプライン heredoc ブロック (lines 91-93, 120-130) を python3 出力を変数キャプチャ → `echo | gh api` へ分離リファクタ; `gh api` 呼び出しに `|| { echo "Error: ..." >&2; exit 1; }` を追加 — bash 3.2+ compatible
- `tests/gh-pr-merge-status.bats`: "error: gh pr view failure" テスト追加
- `tests/gh-label-transition.bats`: "error: gh issue edit failure" テスト追加
- `tests/gh-graphql.bats`: "error: gh api graphql failure" テスト追加
- `tests/gh-pr-review.bats`: "error: gh api POST failure" テスト追加

## Implementation Steps

1. `scripts/gh-pr-merge-status.sh` — `gh pr view` に error handling 追加 (→ AC1)
   - line 45: `JSON=$(gh pr view "$PR" --json mergeable,mergeStateStatus)` を
     `JSON=$(gh pr view "$PR" --json mergeable,mergeStateStatus) || { echo "Error: failed to fetch PR #$PR" >&2; exit 1; }` に変更

2. `scripts/gh-label-transition.sh` — `gh issue edit` 3 箇所に error handling 追加 (→ AC1)
   - line 68: `gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"` を `if ! gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"; then echo "Error: failed to update labels for issue #$ISSUE_NUMBER" >&2; exit 1; fi` に変更
   - line 90: `gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}" --add-label "phase/$TARGET_PHASE"` を同パターンに変更
   - line 92: `gh issue edit "$ISSUE_NUMBER" "${REMOVE_ARGS[@]}"` を同パターンに変更

3. `scripts/gh-graphql.sh` — `gh api graphql` 2 箇所に error handling 追加 (→ AC1)
   - cache path (line 274): `RAW_RESPONSE=$(gh api graphql "${GH_ARGS[@]}")` を `RAW_RESPONSE=$(gh api graphql "${GH_ARGS[@]}") || { echo "Error: gh api graphql failed" >&2; exit 1; }` に変更
   - no-cache path (line 291): `gh api graphql "${GH_ARGS[@]}"` を `gh api graphql "${GH_ARGS[@]}" || { echo "Error: gh api graphql failed" >&2; exit 1; }` に変更

4. `scripts/gh-pr-review.sh` — heredoc パイプライン 2 箇所をリファクタ + error handling 追加 (→ AC1, AC3)
   - `--with-line-comments` path (lines 91-93): python3 ... <<'PYEOF' | gh api ... を変数キャプチャ方式に変更:
     ```
     REVIEW_PAYLOAD=$(python3 - "$REVIEW_BODY_FILE" "$LINE_COMMENTS_FILE" "$EVENT" <<'PYEOF'
     ...python content (unchanged)...
     PYEOF
     )
     echo "$REVIEW_PAYLOAD" | gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --method POST --input - || {
         echo "Error: failed to post review for PR #$PR_NUMBER" >&2
         exit 1
     }
     ```
   - `--no-line-comments` path (lines 120-130): 同パターンで変更

5. `tests/gh-*.bats` 4 ファイルにそれぞれ "error: API failure" テスト追加 (→ AC4)
   - `gh-pr-merge-status.bats`: `gh` mock が exit 1 の場合に script が exit 1 かつ "Error" を含む出力をすること
   - `gh-label-transition.bats`: `gh issue edit` が失敗した場合に exit 1 かつ "Error" メッセージが出力されること (setup の gh mock を exit 1 に上書き)
   - `gh-graphql.bats`: `gh api graphql` が失敗した場合に exit 1 かつ "Error" メッセージが出力されること
   - `gh-pr-review.bats`: `gh api repos/.../reviews` POST が失敗した場合に exit 1 かつ "Error" メッセージが出力されること

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/gh-*.sh のうち少なくとも 7 個が gh CLI 呼び出し直後に明示的 error handling (exit code チェック + stderr メッセージ + non-zero exit) を持つ" --> 7 個以上の gh-*.sh が API failure を観察可能にする error handling を持つ
- <!-- verify: grep "Error.*>&2" "scripts/gh-check-blocking.sh" --> gh-check-blocking.sh が API failure 時に明示的な stderr エラーメッセージを持つ (代表スクリプト確認)
- <!-- verify: command "bash -n scripts/gh-issue-edit.sh && bash -n scripts/gh-issue-comment.sh && bash -n scripts/gh-graphql.sh && bash -n scripts/gh-label-transition.sh && bash -n scripts/gh-extract-issue-from-pr.sh && bash -n scripts/gh-pr-merge-status.sh && bash -n scripts/gh-check-blocking.sh && bash -n scripts/gh-pr-review.sh" --> 主要 gh-*.sh の syntax check 通過 (修正後の sanity check)
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI bats 全件 green (回帰検出)

### Post-merge

- 次回 GitHub API rate limit / permission error が発生した際、silent pass through せず stderr で発見可能になっていることを観察

## Consumed Comments

- saitoco (MEMBER, first-class): Issue Retrospective + Auto-Resolve Log — 3 点の曖昧ポイントの解決記録を確認、AC が更新済であることを確認 [https://github.com/saitoco/wholework/issues/738#issuecomment-4815837827]

## Notes

- `gh-pr-review.sh` のリファクタは heredoc パイプライン (`python3 <<'PYEOF' | gh api`) を変数キャプチャ方式に変更するが、動作は等価。既存テストはモック `gh` が `echo "$REVIEW_PAYLOAD" | gh api ...` で同じく呼ばれるため影響なし
- `gh-graphql.sh` の error メッセージは QUERY_NAME が空の場合もあるため "gh api graphql failed" というシンプルな形にする (QUERY_NAME を含めると空文字が混入する可能性)
- `gh-label-transition.sh` line 68 は `ENTERED_WORKTREE` の "already set" パスの `gh issue edit` 呼び出し — 3 箇所すべて同じパターンで統一
- `gh-check-blocking.sh` は audit report で「唯一 error handling があった」と記録されているが、現在は 3 個 (`gh-issue-edit.sh`, `gh-issue-comment.sh`, `gh-extract-issue-from-pr.sh`) も既に完全対応済み (Issue 記述時点から実装が進んだ)
