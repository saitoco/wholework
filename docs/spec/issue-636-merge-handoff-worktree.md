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

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- 曖昧ポイント3件を自動解決し、AC1 verify command を `file_contains` から `rubric` に置換した判断は適切。`file_contains "skills/merge/SKILL.md" "worktree"` は Step 2 で既出だったため、実装前から PASS する偽陽性を回避できた。

#### spec
- Phase Handoff 書き込み手順への worktree-local パス明示と same-content scenario ガードという2点の小さく独立した変更にスコープを絞った設計が機能した。bash 3.2+ 互換性も明記され実装の制約が明確だった。

#### code
- `skills/merge/SKILL.md` Step 4 の修正は spec 通り。`git diff --cached --quiet` ガードと worktree path 明示の両方が単一コミット `4e459f4` に整理されている。

#### review
- patch route のためレビューフェーズはスキップ。pre-merge AC が rubric ベースで semantic check されるため、実装内容が文書化されていれば検知可能。

#### merge
- patch route 直 push のため `/merge` 経由せず。本 Issue の修正対象がまさに `/merge` であるという構造のため、修正効果は本 verify では観測できない。
- code phase 中に「All 1 recovery subagent slot(s) occupied; aborting tier3」で wrapper が exit 143 終了したが、worktree 内にはコミットが既に作成済みで、parent session が `worktree-merge-push.sh` で main へ FF push して Tier 1 recovery が成功した（reconcile-phase-state: matches_expected=true）。

#### verify
- pre-merge AC（rubric 2件）は両方 PASS。post-merge AC は observation event=auto-run で event-driven、次回 M/L route Issue が `/merge` を経由した際に opportunistic-search が判定する設計。

### Improvement Proposals
- run-auto-sub.sh の Tier 3 recovery subagent slot 競合（exit 143）は、本 batch session の `/triage --backlog` または別 /auto セッションとの並列実行で発生した可能性がある。slot 確保失敗時のフォールバック設計（Tier 2 detector 未検知 → 単純リトライ）を検討する価値があるが、本 Issue では retro/verify の improvement-proposal Issue 生成は不要と判断（既存の orchestration recovery 系 Issue の系譜に統合される性質のため）。

