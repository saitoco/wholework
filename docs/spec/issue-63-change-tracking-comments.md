# Issue #63: skills: 後続スキルの仕様変更を Issue コメントで追跡

## Overview

`/issue` と `/spec` の完了後、後続スキル（`/code`、`/review`）が Issue body や Spec を修正した際に、変更サマリーを新規 Issue コメントとして自動投稿し、変更履歴を追跡できるようにする。対象はスキル内修正のみ（ad-hoc 会話での修正は対象外）。

## Changed Files

- `skills/code/SKILL.md`: Step 10 末尾と Step 11 の auto-append 後に change tracking comment 投稿ステップを追加
- `skills/review/SKILL.md`: Step 13.3 のセクションタイトルに "change tracking" 用語を追加し、既存のコメント投稿機構を change tracking として明示

## Implementation Steps

1. `/code` SKILL.md の Step 11 末尾（"Auto-append acceptance conditions to Issue" 段落の後）に change tracking comment セクションを追加する。Step 10 での verify command 書き換え（case 2: FAIL → 修正）や Spec sync、Step 11 での acceptance condition 自動追加が行われた場合に、変更サマリーコメントを Issue に投稿するステップを記述する。コメントフォーマットは `## Change Tracking (by /code)` 見出しで、各変更の概要と理由を箇条書きにする。投稿は `gh-issue-comment.sh` を使用する。(→ acceptance criteria A)
2. `/review` SKILL.md の Step 13.3 セクションタイトルを `Post Change Reason Comment` から `Post Change Tracking Comment` に変更する。コメント見出しも `## Acceptance Criteria Update` から `## Change Tracking (by /review)` に変更する。既存のコメント内容（Change Reason、Updated Conditions、Updated Verify Commands テーブル）はそのまま維持する。(→ acceptance criteria B)

## Verification

### Pre-merge

- <!-- verify: grep "Change.Track" "skills/code/SKILL.md" --> `/code` スキルに change tracking comment 投稿ステップが追加されている
- <!-- verify: grep "Change.Track" "skills/review/SKILL.md" --> `/review` スキルに change tracking 用語が追加されている

### Post-merge

- `/code` 実行時に Issue body/Spec が変更された場合、スキル名・変更概要・変更理由を含む変更追跡コメントが Issue に投稿される <!-- verify-type: opportunistic -->
- `/review` 実行時に Issue body が変更された場合、スキル名・変更概要・変更理由を含む変更追跡コメントが Issue に投稿される <!-- verify-type: opportunistic -->

## Notes

- `/review` Step 13.3 は既に policy change 検出時にコメントを投稿する仕組みを持っている。本 Issue の実装はこの既存機構に change tracking の用語を追加し、明示的に位置づけるもの。新たなロジックの追加は不要。
- `/code` Step 10 の case 1（全 PASS、チェックボックス更新のみ）は仕様変更に該当しないため、change tracking の対象外とする。case 2（verify command 書き換え）と Step 11 の auto-append のみが対象。
- コメント投稿は条件付き：Issue body/Spec に実際の変更がなかった場合はスキップする。

## Code Retrospective

### Deviations from Design

- verify command パターン `change.track` が実装後のテキスト（`Change Tracking`、大文字始まり）にマッチしないことが verify 実行時に判明し、パターンを `Change.Track` に修正した。Spec では実装前の想定パターンを記載していたが、実装後の実際のテキストと不一致になった。設計フェーズでの verify command 記述時にコンテンツの大文字小文字を事前確認する必要がある

### Design Gaps/Ambiguities

- N/A

### Rework

- verify command パターン修正のため、Issue body・Spec の両方を追加コミットで更新する必要が生じた（実装コミットとは別に `fix:` コミットが発生）
