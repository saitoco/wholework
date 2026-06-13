# Issue #569: reconcile-phase-state: fix cycle の code-patch 完了判定が既存 closes #N コミットに false positive

## Overview

`reconcile-phase-state.sh code-patch --check-completion` の完了判定ヒューリスティックが、fix cycle（verify FAIL → reopen → `run-code.sh --patch` 再実行）において false positive を返すバグを修正する。

現在の判定: `git log origin/main --grep="closes #N"` でコミットが 1 件以上あれば `matches_expected: true`。これはコミット作成時刻によらず全履歴を検索するため、reopen 前の初回実装コミットにマッチして誤判定する。

修正方針: GitHub API から最新 reopen イベントのタイムスタンプを取得し、そのタイムスタンプ以降のコミットのみを要求する（freshness 条件）。タイムスタンプ取得失敗時は既存ヒューリスティックへフォールバックしてサービス継続性を保つ。

## Reproduction Steps

1. Issue #N でコード実装し `closes #N` コミットを origin/main にプッシュ
2. `/verify` が FAIL → Issue を reopen
3. `run-code.sh --patch` が watchdog kill により 0 コミットで終了
4. `reconcile-phase-state.sh code-patch N --check-completion` を実行
5. 手順 1 の古いコミットにマッチして `matches_expected: true` が返る（false positive）

## Root Cause

`_completion_code_patch()` が全 git 履歴を検索するため、reopen 前に作成された既存コミットを区別できない。fix cycle の reopen タイムスタンプを基準にした freshness フィルタが存在しない。

## Changed Files

- `scripts/gh-graphql.sh`: `get-last-reopen` named query 追加 — bash 3.2+ 互換
- `scripts/reconcile-phase-state.sh`: `_completion_code_patch()` に freshness 条件追加 — bash 3.2+ 互換
- `modules/phase-state.md`: code-patch completion signature を freshness 条件反映に更新
- `tests/reconcile-phase-state.bats`: fix-cycle シナリオのテストケース 2 件追加

## Implementation Steps

1. `scripts/gh-graphql.sh` に named query `get-last-reopen` を追加（→ AC1）:
   ```
   get-last-reopen)
       printf '%s' 'query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){timelineItems(itemTypes:[REOPENED_EVENT],last:1){nodes{... on ReopenedEvent{createdAt}}}}}}'
       ;;
   ```
   `get-issue-types)` case の直前など既存 case の末尾付近に追加する。

2. `scripts/reconcile-phase-state.sh` の `_completion_code_patch()` を修正（→ AC1）:
   - `git fetch` 後、`$SCRIPT_DIR/gh-graphql.sh --query get-last-reopen -F "num=$ISSUE_NUMBER" --jq '.data.repository.issue.timelineItems.nodes[0].createdAt'` で reopen タイムスタンプを取得
   - 取得成功（空文字・`null` でない）: `git log origin/main --after="$reopen_ts" --oneline --grep="closes #${ISSUE_NUMBER}"` でフレッシュなコミットを確認
   - 取得失敗: 既存ヒューリスティック（`--after` なし）にフォールバック。diagnosis に `fallback: reopen timestamp unavailable; fix-cycle false positive possible` を付記

3. `modules/phase-state.md` の Phase Table 内 code-patch 行を更新（→ AC2）:
   - Completion 列を「`git log origin/main --after=<reopen_ts> --grep="closes #N"` で freshness 確認（reopen タイムスタンプ取得成功時）; 取得失敗時は `git log origin/main --grep="closes #N"` にフォールバック」に変更

4. `tests/reconcile-phase-state.bats` に fix-cycle テストケース 2 件追加（→ AC3）:
   - `@test "code-patch completion: fix-cycle false positive - pre-reopen commit only -> matches_expected false"`: `$MOCK_DIR/gh-graphql.sh` がタイムスタンプを返し、`git log --after=<ts>` が空文字を返す場合に `matches_expected: false`
   - `@test "code-patch completion: fix-cycle - fresh commit after reopen -> matches_expected true"`: `git log --after=<ts>` がコミットを返す場合に `matches_expected: true`

## Verification

### Pre-merge

- <!-- verify: grep "[Rr]eopen|REOPEN|since" "scripts/reconcile-phase-state.sh" --> code-patch 完了判定に fix-cycle 対応（reopen 後コミット要求または since-sha 比較）が実装されている
- <!-- verify: grep "[Rr]eopen" "modules/phase-state.md" --> `modules/phase-state.md` の code-patch completion signature が freshness 条件（fix-cycle 対応）を反映している
- <!-- verify: command "bats tests/reconcile-phase-state.bats" --> reconcile の既存テストが green（fix-cycle ケースのテスト追加を含む: reopen 後の false-positive シナリオ・reopen 後の正常完了シナリオの最低 2 ケース）

### Post-merge

- 次回の verify FAIL → reopen → code 再実行サイクルで、wrapper がコミットなしで終了した場合に completion check が matches_expected:false を返すことを観察

## Notes

- `gh-graphql.sh` の `get-issue-timeline` クエリ（既存）は `LABELED_EVENT` も含む `first:100` で取得するため、イベント数が多いと最新 reopen が切れる可能性がある。新たに `get-last-reopen`（`REOPENED_EVENT` のみ、`last:1`）を追加して対処。
- タイムスタンプ取得失敗時のフォールバックは、初回実行（reopen なし）でも既存ヒューリスティックが正しく動作するため後退しない。
- `git log --after="<ISO8601>"` はコミット author date を基準とする。reopen 後に作成されたコミットは reopen 以降の日時を持つため、フィルタが正しく機能する。

## Code Retrospective

### Deviations from Design

- `gh-graphql.sh` の `--jq` 出力はデフォルトで JSON 文字列クォートを含むため、`| tr -d '"'` でクォート除去を追加した。Spec にはこの処理の明示がなかったが、`git log --after=` に渡す際に必要なため追加。

### Design Gaps/Ambiguities

- Spec は `reopen_ts` の取得結果形式（jq がクォート付き文字列を返すこと）について言及していなかった。実装時に `"2024-01-01T00:00:00Z"` のようなクォート付き値が返ることを確認し、`tr -d '"'` で除去する処理を追加した。

### Rework

- 特になし。Spec の実装ステップに沿って実装でき、手戻りは発生しなかった。

## review retrospective

### Spec vs. Implementation Divergence Patterns

- Spec に `gh-graphql.sh --jq` 出力がクォート付き文字列を返すことへの言及がなく、`tr -d '"'` 処理が Code Retrospective で事後追記された。Spec の実装ステップではシェル出力のクォート処理を明示する習慣がない可能性がある。今後の Spec 記述では、外部コマンドの出力形式（特に jq の文字列クォート）を明示することを推奨する。

### Recurring Issues

- 特になし。今回の PR は範囲が小さく、同種の問題は検出されなかった。

### Acceptance Criteria Verification Difficulty

- 既存テスト（pre-PR のもの）が暗黙的に fallback パスをカバーしているが、null 値の明示的テストが欠如していた（SHOULD として検出・修正済み）。verify command は既存のテスト実行コマンド（`bats tests/reconcile-phase-state.bats`）のみで、フォールバックパスの入力境界値を個別に検証するヒントがなかった。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Size=M Bug fix に対して review-light（light mode）を適用。全 4 観点を 1 エージェントで確認する軽量統合レビューが適切と判断
- SHOULD issue（null fallback パステスト欠如）は解決済み（テスト追加）。CONSIDER issue（モックコメント不明確）はスタイル上の懸念のみのためスキップ
- MUST issues なし → COMMENT イベントで投稿、`/merge` 進行可

### Deferred Items
- CONSIDER: fix-cycle テストのモックコメント補足（スタイルのみ、機能影響なし）
- `code-pr` completion check の false positive リスク（コードフェーズから引き継ぎ、今回スコープ外）

### Notes for Next Phase
- tests/reconcile-phase-state.bats は 55 テスト（fix-cycle 3 件：false positive・正常完了・null fallback）
- CI 全ジョブ SUCCESS（DCO・bats・validate-skill-syntax・forbidden-expressions・macOS compat）
- MUST issues なし。/merge 実行可
