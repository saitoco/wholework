# Issue #522: worktree-merge-push: 長時間フェーズ中の base 前進による ff-only 失敗の rebase フォールバックを追加

## Overview

`/auto` や `/verify` などの長時間フェーズ実行中に別の Issue が `main` にマージされると、worktree ブランチの fork 元（base）が前進し、`git merge --ff-only` が失敗する。既存の `git pull --rebase origin main` リトライは「local main が origin より遅れているケース」向けで、local main が既に origin と同期済みの場合は無効。手動 `git cherry-pick` を要する復旧を自動化する。

## Reproduction Steps

1. `/auto` または `/verify` で長時間フェーズ（verify/spec/code、数分〜十数分）を開始
2. 実行中に別の Issue が main にマージされ、local main が前進（例: Issue #517 実行中に #505/PR #519 がマージ）
3. フェーズ完了後 `worktree-merge-push.sh --from worktree-verify+issue-N` が実行される
4. `git merge worktree-verify+issue-N --ff-only` → "Not possible to fast-forward" で失敗
5. `git pull --rebase origin main` → no-op（local main は既に origin と同期済み）
6. 2回目の `git merge --ff-only` も失敗 → スクリプトが abort

## Root Cause

`scripts/worktree-merge-push.sh` の ff-only フォールバックが「origin が前進したケース」のみ対処し、「local main が origin と同期済みだが、worktree ブランチの fork 元より前進しているケース」を処理しない。2回目の ff-only 失敗時に worktree ブランチ自体を最新 base へ rebase するフォールバックを追加することで解決する。

## Changed Files

- `scripts/worktree-merge-push.sh`: ff-only 2回失敗時に、worktree パス検出と rebase フォールバックを追加 — bash 3.2+ compatible
- `modules/orchestration-fallbacks.md`: `#ff-only-merge-fallback` エントリに新ケース（base 前進分岐）の対処手順を追記
- `modules/worktree-lifecycle.md`: スクリプト動作説明に新 rebase フォールバックを記載
- `tests/worktree-merge-push.bats`: base 前進シナリオ（ff-only が2回失敗 → rebase → 3回目成功）の bats テスト追加

## Implementation Steps

1. `modules/orchestration-fallbacks.md` `#ff-only-merge-fallback` エントリを更新: Step 4（現行: 「失敗を伝播」）を「まだ失敗する場合は、`git worktree list --porcelain` で FROM_BRANCH の worktree パスを検出し、worktree 内で `git -C <path> rebase origin/<base>` を実行（worktree 未発見時は `git rebase <base> <from>` に fallback）→ 競合時は `rebase --abort` して exit 1、成功時は `git merge --ff-only` を3回目実行」に置き換え (→ AC1)

2. `scripts/worktree-merge-push.sh` を修正: 既存の2回目 `git merge "$FROM_BRANCH" --ff-only`（line 85）をネストした `if !` ブロックに変更し、失敗時に以下を実行 (→ AC1, AC2):
   - `echo "FF merge still failed; base may have diverged. Rebasing ..."` を stderr 出力
   - `git worktree list --porcelain | awk -v b="refs/heads/${FROM_BRANCH}" '/^worktree /{p=$2} $0 == "branch " b {print p; exit}'` で worktree パスを検出
   - worktree パスが存在する場合: `git -C "$worktree_path" rebase "origin/${BASE_BRANCH}"` を実行、失敗時は `git -C "$worktree_path" rebase --abort 2>/dev/null || true` して exit 1
   - worktree パスが存在しない場合: `git rebase "$BASE_BRANCH" "$FROM_BRANCH"` を実行、失敗時は `git rebase --abort 2>/dev/null || true` して exit 1
   - 成功時: `git merge "$FROM_BRANCH" --ff-only` を再実行（`set -e` により失敗時は自動 exit）

3. `modules/worktree-lifecycle.md` を更新: `git merge --ff-only` のリトライ説明（"with `git pull --rebase` retry on FF failure"）に「base-diverged ケース向けの worktree-branch rebase フォールバック」を追記 (→ AC1)

4. `tests/worktree-merge-push.bats` に新テスト `@test "--from with base-diverged triggers worktree rebase fallback"` を追加: `git merge` を2回失敗させる git モック（3回目は成功）、`git worktree list --porcelain` がモック worktree パスを返す、`git -C $path rebase origin/main` が成功する mock を設定し、status=0・"base may have diverged" 文字列の出力・GIT_LOG に `rebase origin/main` が含まれること・`push origin main` が実行されることを検証 (→ AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/worktree-merge-push.sh または modules/orchestration-fallbacks.md の ff-only-merge-fallback に、base（main）が worktree ブランチ作成後に前進して分岐した場合（origin 同期済みでも ff-only マージが失敗するケース）に、worktree ブランチを最新 base へ rebase もしくは非競合マージして自動復旧するロジックが追加されており、競合時は従来通り abort する" --> base 前進による分岐の自動復旧フォールバックが実装されている
- <!-- verify: grep "rebase\|no-ff\|diverge" scripts/worktree-merge-push.sh --> worktree-merge-push.sh に分岐ケースの処理記述がある
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI（bats 等）が green
- <!-- verify: rubric "scripts/worktree-merge-push.sh の新ロジックを検証する bats テスト（base 前進シナリオ）が tests/ に追加されている" --> 分岐ケースの bats テストが追加されている

### Post-merge

- 長時間フェーズ中に base が前進する状況を再現し、`/verify` 等の worktree exit が手動介入なしで完了することを確認 <!-- verify-type: manual -->

## Notes

- **worktree パス検出**: `git worktree list --porcelain` の出力を `awk -v b="refs/heads/$FROM_BRANCH"` でパース。`worktree ` 行でパスを取得し、`branch refs/heads/...` 行がマッチしたらそのパスを返す。FROM_BRANCH が worktree で checked out されていない場合は直接 `git rebase $BASE_BRANCH $FROM_BRANCH` を実行（ENTERED_WORKTREE=false で --from なし呼び出し時は新ブロック自体が実行されない）。
- **worktree checked out 中の rebase 問題**: `git rebase $BASE $FROM_BRANCH` は worktree で checkout 中のブランチに対して失敗（"already checked out"）するため、`git -C "$worktree_path" rebase origin/$BASE_BRANCH`（worktree 内での rebase）を優先する。
- **bash 3.2+ 互換**: `awk -v` は POSIX awk で対応済み、`git -C` は git 1.8.5+ で利用可能。`mapfile` 等の bash 4+ 機能は不使用。
- **競合時の挙動変更なし**: 既存の競合時 abort（conflict-marker-residual チェック）は維持される。新フォールバックも競合時は rebase --abort して exit 1 し、従来同様にユーザーへ委ねる。

## review retrospective

### Spec vs. 実装乖離パターン

- 乖離なし。Spec記載の4ファイルがすべて変更されており、Implementation Steps と PR diff が 1:1 で対応している。

### 繰り返しイシュー

- 特になし。CONSIDERイシュー1件（elseブランチのテスト）のみで、同種の繰り返しパターンはなし。

### 受け入れ条件検証の難易度

- verify commandはすべて適切に機能した（rubric×2, grep×1, github_check×1）。
- `github_check "gh run list ..."` はsafeモードのallowlistに含まれないが、PR statusCheckRollupで代替検証できた。今後、CI green検証には `github_check "gh pr checks $PR_NUMBER" "Run bats tests"` 形式を使うとsafeモードでも直接実行可能になる（改善余地）。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #532 を `--squash --delete-branch` でmainへマージ。全CI（bats, lint, DCO）SUCCESS確認後マージ実施。
- ローカルブランチ削除時に別worktree（`code+issue-522`）が使用中でエラーが発生したが、リモートブランチ削除・squash merge自体は成功。ローカルブランチはworktree削除時に手動クリーンアップ。
- `--non-interactive` モードで実行、コンフリクトなし（mergeable=MERGEABLE、Step 3スキップ）。

### Deferred Items
- `code+issue-522` worktreeが残存している（ローカルブランチ `worktree-code+issue-522` も含む）。worktree削除後にブランチを手動削除することを推奨。
- Post-merge手動verify（長時間フェーズ中のbase前進再現テスト）は `/verify` フェーズで実施予定。

### Notes for Next Phase
- closes #522 がPR bodyに含まれ、BASE_BRANCH=main → Issue #522は自動クローズ済み。
- 変更対象は `scripts/worktree-merge-push.sh`、`modules/orchestration-fallbacks.md`、`modules/worktree-lifecycle.md`、`tests/worktree-merge-push.bats` の4ファイル。
- Post-merge verify commandは「長時間フェーズ中のbase前進を再現し手動確認」（verify-type: manual）のみ残存。
