# Issue #497: Record Review-Based Fix Origin as PR Inline Comment

## Overview

`skills/review/SKILL.md` に「`/review` 後に行われるすべてのレビュー起因修正は、元レビュー指摘を PR インラインコメントとして残さなければならない」ルールを追加する。修正コミットメッセージには `Refs: <PR comment URL>` を含め、Code Retrospective からの追跡性を確保する。

## Changed Files

- `skills/review/SKILL.md`: Step 12.2 Fix Work にインラインコメント保存ルールを追加、Notes セクションにポリシー記載 — bash 3.2+ 互換

## Implementation Steps

1. Step 12.2 (Fix Work) の手順 3（`git add`）と 4（Commit）の間に新手順を挿入: 元レビュー指摘が PR インラインコメントとして未投稿の場合、`gh pr comment "$NUMBER" --body "Review: {summary}"` で投稿し、返却された URL を `PR_COMMENT_URL` として記録する（Step 11 経由で既に投稿済みの場合はスキップ）。手順 4 のコミットメッセージを `"Address review feedback: {fix summary}\n\nRefs: $PR_COMMENT_URL"` に変更する (→ AC1/AC2)
2. `## Notes` セクション末尾に次のポリシー項目を追加: 「MUST/SHOULD/CONSIDER、AI 判断・人手を問わず、すべてのレビュー起因修正は PR inline comment として元指摘を保存した上でコミットすること。修正コミットには `Refs: <PR inline comment URL>` を含め追跡性を確保する。この規則は `/review` Step 12 内の修正と、`/review` 完了後の追加修正コミットの両方に適用される」(→ AC1/AC2)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md に『PR レビュー後の修正は元指摘を PR インラインコメントとして必ず残す』ルールが追加されている" --> レビュー指摘の PR コメント記録ルールが追加されている
- <!-- verify: grep "inline.comment" "skills/review/SKILL.md" --> SKILL.md にインラインコメント記録ルールの説明が含まれる

### Post-merge

- `/review` 後に追加修正がある実 PR で、修正コミットの元レビュー指摘が PR インラインコメントとして残っていることを目視確認する <!-- verify-type: observation event=pr-review-full -->

## Notes

- ISSUE_TYPE=Task のため Uncertainty セクションは省略
- Step 11 の `gh-pr-review.sh` が既に各 review finding を PR inline comment として投稿している。そのため Step 12.2 の新手順は「未投稿の場合のみ投稿」という条件付きとし、二重投稿を防ぐ
- verify command AC2 の `grep "inline.comment"` は `.` がワイルドカードであり `"inline comment"` (スペース含む) にマッチする。実装テキストに "PR inline comment" と記述することで確実に通る
