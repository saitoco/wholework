# Issue #690: run-merge.sh の CI run query が merge 直後の in-progress run に当たり source=ci emit が失敗する事象を解消

## Overview

`scripts/run-merge.sh` の CI test_result emit ロジックが `--branch=main --limit=1` で run を query するため、merge 直後に main で trigger された in-progress run を取得してしまう。この run の log には TAP plan line (`1..N`) がまだ書かれておらず、`source=ci` 付き `test_result` event の emit が永続的にスキップされる。PR の latest SUCCESS run を参照することで確実に emit する。

## Reproduction Steps

1. `/auto N` で merge phase を実行する（PR route）
2. merge 完了後、`run-merge.sh` の CI fetch block が実行される
3. `gh run list --workflow=test.yml --branch=main --limit=1` が merge push で trigger された in-progress run を返す
4. `gh run view --log` でその run の log を取得すると TAP plan line がない
5. Warning が出力され、`source=ci` 付き `test_result` event が emit されない

## Root Cause

`gh run list --branch=main --limit=1` は status フィルターなしで query するため、merge 直後の新規 push が trigger した in-progress run が先頭に来る。完了済みの SUCCESS run（PR が green だった run）を直接参照するのが正しい。Candidate A（推奨）: `gh pr view "$PR_NUMBER" --json headRefName` で PR の feature branch 名を取得し、その branch の `--status=success` な最新 run を query する。

## Changed Files

- `scripts/run-merge.sh`: CI test_result emit block (line 154) で `_branch` 取得を追加し、`gh run list` を `--branch="$_branch" --status=success` に変更 — bash 3.2+ 互換
- `tests/run-merge.bats`: `test_result` 系テストの `gh` mock に headRefName レスポンスを追加；SUCCESS run query の regression test を追加

## Implementation Steps

1. `scripts/run-merge.sh` line 154 付近の CI test_result emit block を以下に変更（→ 受け入れ基準 AC1, AC2）:
   - 既存: `_run_id=$(gh run list --workflow=test.yml --branch=main --limit=1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)`
   - 変更後: `_branch` 取得を追加し、`_run_id=""` で初期化した後 `if [[ -n "$_branch" ]]` ガードの中で `gh run list --workflow=test.yml --branch="$_branch" --status=success --limit=1 --json databaseId --jq '.[0].databaseId'` を呼ぶ
   - 具体的には以下のように置換:
     ```
     _branch=$(gh pr view "$PR_NUMBER" --json headRefName --jq '.headRefName' 2>/dev/null || true)
     _run_id=""
     if [[ -n "$_branch" ]]; then
       _run_id=$(gh run list --workflow=test.yml --branch="$_branch" --status=success --limit=1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
     fi
     ```

2. `tests/run-merge.bats` の更新（→ 受け入れ基準 AC4）:
   - `@test "test_result: emit_event called with source=ci after merge"` の `gh` mock: `gh pr view --json` ブロック内に `headRefName` 分岐を追加し `"pr-feature-branch"` を返す
   - `@test "test_result: TAP format with not ok lines counts failures correctly"` の `gh` mock: 同じく `headRefName` 分岐を追加
   - `@test "test_result: SUCCESS run query uses PR branch with --status=success"` を新規追加: `gh run list` の引数ログを取得し `--status=success` と PR branch 名（headRefName）が含まれることを確認

## Verification

### Pre-merge

- <!-- verify: grep "gh pr view.*headRefName|--status=success|gh pr checks.*link" "scripts/run-merge.sh" --> `scripts/run-merge.sh` に PR branch query または status filter または gh pr checks link 抽出のいずれかが実装されている
- <!-- verify: rubric "scripts/run-merge.sh が merge 完了時点で in-progress run ではなく既に SUCCESS している run を query して bats TAP log を parse する。具体的には PR の latest SUCCESS run を取得、--status=success filter、または gh pr checks の link から run ID 抽出のいずれかが実装されている" --> rubric 基準を満たす
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 既存 bats テストが CI で green
- <!-- verify: grep "SUCCESS|--status|headRefName" "tests/run-merge.bats" --> SUCCESS run query の regression test が追加されている

### Post-merge

- 次回 pr route `/auto` 完走時に `.tmp/auto-events.jsonl` で `source=ci` 付き `test_result` event が emit されることを確認

## Notes

- Candidate A を採用: `PR_NUMBER` は `run-merge.sh` の引数として既知なので `gh pr view "$PR_NUMBER"` でブランチ名を取得できる。Candidate B (`--status=success` で main を query) は semantic がずれる（他 PR の merge 結果を参照する可能性）
- `_branch` が空の場合（PR 削除済み等）は graceful にスキップ（`_run_id=""` → emit 非実行）
- 既存テストの `gh` mock は headRefName を処理しないため、実装変更後に既存 test_result テストが FAIL する。Step 2 で既存テストの mock 更新も必須

## Code Retrospective

### Deviations from Design

- Spec では `--jq '.headRefName'` を使用する例示があったが、既存コード (line 143) が `-q` 形式を使っているため `-q '.headRefName'` に統一した。両者は `gh` CLI 上では同義だが、テスト mock の条件マッチが `-q` を想定しており `--jq` では FAIL した。

### Design Gaps/Ambiguities

- Spec の headRefName 取得例示 (`--jq`) と既存コードの慣用 (`-q`) が不一致だった。Spec が `-q` と明示していれば第1コミットでのバグを防げた。

### Rework

- `scripts/run-merge.sh` を 2 回コミット: 初回に `--jq` で実装したが bats テストが FAIL したため `-q` に修正。1 回のコミットで済ませるためには Spec に慣用形を明示すべきだった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #691 をスカッシュマージ: CI SUCCESS・レビュー承認済み・コンフリクトなし
- base branch が main のため `closes #690` により Issue は自動クローズ
- Phase Handoff は review phase のものを merge phase で置き換え（1フェーズ保持ルール）

### Deferred Items
- post-merge AC: 次回 `/auto` 完走時に `.tmp/auto-events.jsonl` で `source=ci` 付き `test_result` event が emit されるか確認
- 関連 Issues #679 / #662 / #630 の observation chain が本 PR merge 後に trigger されるか確認

### Notes for Next Phase
- `scripts/run-merge.sh` 変更: `--branch=main --limit=1` → PR branch の `--status=success` な最新 run を参照（確実な CI log parse）
- verify フェーズでの確認ポイント: post-merge AC（`source=ci` event emit）は次回 `/auto` 実行まで検証不可
- 既存 bats テスト mock の更新と regression test 追加も含む

## review retrospective

### Spec vs. 実装乖離パターン

- Nothing to note. Spec と実装の整合性は良好。Code phase の retrospective に記録された `-q` vs `--jq` の差異は既に解消済みで、Spec の example に慣用形を明示すれば防げた軽微な事案。

### 再発イシュー

- Nothing to note. 同種のイシューは見当たらない。

### 受け入れ基準検証難易度

- Nothing to note. AC3 (`github_check "gh pr checks" "Run bats tests"`) は CI 完了待ちが必要だが、実行時点で既に SUCCESS だったため問題なし。全 4 pre-merge AC が PASS で UNCERTAIN なし。verify command の syntax は適切。
