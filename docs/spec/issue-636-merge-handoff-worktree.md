# Issue #636: merge: Fix Phase Handoff to Write in Worktree Context

## Overview

`/merge` スキルの Phase Handoff 書き込み（Step 4）が、worktree ではなく main repo の作業ディレクトリを対象に行われる場合があり、未コミットの dirty ファイルを main repo に残す。この dirty ファイルが後続の `/verify` Step 1 (`check-verify-dirty.sh`) を exit 1 で abort させる。`skills/merge/SKILL.md` の Phase Handoff 書き込み手順に worktree 内ファイルであることを明示し、同内容シナリオ（same-content scenario）に対するガードレールを追加する。

## Reproduction Steps

1. `/auto --batch` で Issue を処理し、`/merge` が Phase Handoff を書き込む
2. `/verify` Step 1 が `check-verify-dirty.sh` を実行
3. `docs/spec/issue-N-*.md` に `## Phase Handoff (<!-- phase: merge -->)` セクションが追加されたまま未コミットの状態が残る
4. `check-verify-dirty.sh` が exit 1 を返し `/verify` が abort する

## Root Cause

`skills/merge/SKILL.md` Step 4 の Phase Handoff 書き込み手順が、対象 Spec ファイルの操作コンテキスト（worktree 内か main repo か）を明示していない。Step 2 で worktree に入っているにもかかわらず、Edit ツールが main repo の `docs/spec/issue-N-*.md` を直接変更するケースが発生した。worktree 内ファイルを対象にすることを明記し、commit/push 完了ガードを加えることで解決する。

## Changed Files

- `skills/merge/SKILL.md`: Phase Handoff write 手順（Step 4 内のサブ手順 2・4）を更新 — bash 3.2+ 互換

## Implementation Steps

1. `skills/merge/SKILL.md` の **Phase Handoff write** セクション（Step 4 内）のサブ手順 2 に、対象 Spec ファイルが Step 2 で作成した worktree-local コピー（`.claude/worktrees/merge+pr-$NUMBER/` 以下）であることを明記する（→ AC1）
2. 同セクションのサブ手順 4 において、`git add` 後に `git diff --cached --quiet` でステージング状態を確認し、変更がない場合（same-content scenario — Phase Handoff が既に main に存在するケース）は commit/push をスキップするガードを追加する（→ AC2）

## Verification

### Pre-merge

- <!-- verify: rubric "skills/merge/SKILL.md の Phase Handoff 書き込み手順（Step 4）において、Spec ファイルへの追記が Step 2 で作成した worktree 内のファイルに対して行われることが明示されており（例: worktree パスへの言及、.claude/worktrees 以下であることの記載 等）、かつ commit・push の手順が含まれている" --> `/merge` SKILL.md の Phase Handoff write 手順が worktree 内ファイルを対象にすることを明示している
- <!-- verify: rubric "skills/merge/SKILL.md に Phase Handoff 追記後の commit 完了確認手順、または main repo 側へリークしないためのガードレールが明示されている" --> commit 完了確認手順または main repo へのリーク防止ガードレールが追加されている

### Post-merge

- 次回以降の `/auto` 実行で `/verify` Step 1 (`check-verify-dirty.sh`) が Phase Handoff 起因の dirty file で exit 1 にならないことを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- Phase Handoff 書き込みは `git push origin HEAD:main` でworktree branch から直接 main に push する設計（merge SKILL.md Step 4 サブ手順 4）であり、これは worktree exit 前に完結する
- same-content scenario は、`/merge` が retry された場合や親セッションが Phase Handoff を先にコミット済みの場合に発生する
- `git diff --cached --quiet` は bash 3.2+ で動作する（macOS system bash 互換）
