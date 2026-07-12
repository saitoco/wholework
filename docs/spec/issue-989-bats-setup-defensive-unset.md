# Issue #989: tests: bats setup() に EMIT_* / AUTO_SESSION_ID の防御的 unset を追加

## Consumed Comments

| login | authorAssociation | trust tier | intent | URL |
|-------|--------------------|-----------|--------|-----|
| saito | MEMBER | first-class | Issue Retrospective (Triage 結果: Type=Bug, Size=M via CI Dependency Minimum Override, Value=4) と Auto-Resolve Log (setup() は「unset → 明示 export」の順で5変数を追加する方針であることを再確認) | https://github.com/saitoco/wholework/issues/989#issuecomment-4949782374 |

## Overview

Issue #987 の review フェーズで、`run-auto-sub.sh` の `run_phase_with_recovery()` が export する `EMIT_ISSUE_NUMBER` / `EMIT_PR_NUMBER` / `EMIT_PHASE_NAME` / `_EXTRA_SELF_ISSUE` / `AUTO_SESSION_ID` がテスト実行環境にアンビエントに漏れ込み、`set -u` 下でデフォルト値なしにこれらを参照するバグを隠蔽して false PASS を生んだ実例が発生した (PR #988)。`tests/run-auto-sub.bats` と `tests/emit-event.bats` の setup() にこの5変数の防御的 `unset` を追加し、ローカル実行環境の汚染に依存しない決定的なテスト結果を保証する。

## Reproduction Steps

1. シェルで `export AUTO_SESSION_ID=fake-session-id` のように、`run-auto-sub.sh` の `run_phase_with_recovery()` が export する変数のいずれかをアンビエントに設定する (または `/auto` セッションの子プロセスとして bats を実行し、同じ状況を自然発生させる)
2. `bats tests/run-auto-sub.bats tests/emit-event.bats` を実行する
3. テスト対象スクリプトや将来追加されるリグレッションテストのモックに、`set -u` 下でデフォルト値なしに該当変数を参照するバグが混入していても、ステップ1のアンビエント値が代入されるためテストは「PASS」してしまう
4. 変数が未定義のクリーンな環境 (GitHub Actions ランナー等) でのみ FAIL が顕在化し、レビュー時点で欠陥を検出できない (実例: PR #988, Issue #987 review retrospective)

## Root Cause

- `tests/run-auto-sub.bats` の setup() は既存の `unset EMIT_ISSUE_NUMBER EMIT_PR_NUMBER EMIT_PHASE_NAME _EXTRA_SELF_ISSUE` で対象5変数のうち4変数のみを unset しており、`scripts/run-auto-sub.sh` 207行目で `export AUTO_SESSION_ID` される `AUTO_SESSION_ID` が対象外だった (測定: `grep AUTO_SESSION_ID tests/run-auto-sub.bats` は実装前0件)
- `tests/emit-event.bats` の setup() は5変数のいずれも unset せず、`EMIT_ISSUE_NUMBER="42"` / `EMIT_PHASE_NAME="code"` を意図的に明示 export するのみだった (測定: `grep AUTO_SESSION_ID tests/emit-event.bats` は実装前0件)
- 結果として両ファイルとも、ライブな `/auto` セッションの子プロセスとして呼び出された場合のアンビエント env var 汚染に部分的に無防備であり、`docs/product.md` が掲げる "governance-and-verification harness" としての信頼性を損なう false PASS のリスクを残していた

## Changed Files

- `tests/run-auto-sub.bats`: setup() 内の既存 `unset EMIT_ISSUE_NUMBER EMIT_PR_NUMBER EMIT_PHASE_NAME _EXTRA_SELF_ISSUE` に `AUTO_SESSION_ID` を追記
- `tests/emit-event.bats`: setup() 内、`export EMIT_ISSUE_NUMBER="42"` の直前に `unset EMIT_ISSUE_NUMBER EMIT_PR_NUMBER EMIT_PHASE_NAME _EXTRA_SELF_ISSUE AUTO_SESSION_ID` を追加

## Implementation Steps

1. `tests/run-auto-sub.bats` の setup() ブロック冒頭にある既存の `unset EMIT_ISSUE_NUMBER EMIT_PR_NUMBER EMIT_PHASE_NAME _EXTRA_SELF_ISSUE` 行に `AUTO_SESSION_ID` を追記する (→ acceptance criteria 1)
2. `tests/emit-event.bats` の setup() で、`export AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/auto-events.jsonl"` の後・`export EMIT_ISSUE_NUMBER="42"` の直前に `unset EMIT_ISSUE_NUMBER EMIT_PR_NUMBER EMIT_PHASE_NAME _EXTRA_SELF_ISSUE AUTO_SESSION_ID` を追加する (unset → 明示 export の順を維持し、`EMIT_ISSUE_NUMBER=42` / `EMIT_PHASE_NAME=code` という既存テストの既知値前提を壊さない) (→ acceptance criteria 1)
3. `bats tests/run-auto-sub.bats tests/emit-event.bats` を実行し、全テスト (実装前ベースライン実測: 83件) が green であることを確認する (→ acceptance criteria 2)

## Verification

### Pre-merge
- <!-- verify: rubric "tests/run-auto-sub.bats と tests/emit-event.bats の setup() が EMIT_ISSUE_NUMBER, EMIT_PHASE_NAME, EMIT_PR_NUMBER, _EXTRA_SELF_ISSUE, AUTO_SESSION_ID を明示的に unset する防御的初期化を含んでいる" --> `tests/run-auto-sub.bats` と `tests/emit-event.bats` の setup() に `EMIT_ISSUE_NUMBER` / `EMIT_PHASE_NAME` / `EMIT_PR_NUMBER` / `_EXTRA_SELF_ISSUE` / `AUTO_SESSION_ID` の防御的 unset が追加されている
- <!-- verify: command "bats tests/run-auto-sub.bats tests/emit-event.bats" --> 対象テストスイートが green
- <!-- verify: file_contains "tests/run-auto-sub.bats" "AUTO_SESSION_ID" --> tests/run-auto-sub.bats に AUTO_SESSION_ID の参照が追加されている (rubric 判定の決定的な補強。実装前は0件)
- <!-- verify: file_contains "tests/emit-event.bats" "AUTO_SESSION_ID" --> tests/emit-event.bats に AUTO_SESSION_ID の参照が追加されている (rubric 判定の決定的な補強。実装前は0件)

### Post-merge
- CI (`.github/workflows/test.yml`) 上で bats フルスイートが green であることを確認する (対象2ファイル以外への副作用がないことの最終確認)

## Notes

- **SPEC_DEPTH=light (Size M) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップ。** ただし Issue 本文に `/issue` フェーズの non-interactive 自動解決結果が既に記載されている: setup() には「unset → 明示 export」の順で5変数を追加する方針を採用 (`tests/run-spec.bats` / `tests/run-merge.bats` / `tests/run-code.bats` の既存パターン (`unset EMIT_PHASE_NAME EMIT_ISSUE_NUMBER AUTO_SESSION_ID` を setup() 後半に配置) と整合)。不採用案 (emit-event.bats の明示 export を削除し各テスト個別に export させる) は影響範囲が広いため見送り。
- **Verify command 補強について**: rubric の grader 記述が `EMIT_ISSUE_NUMBER` / `EMIT_PHASE_NAME` / `EMIT_PR_NUMBER` / `_EXTRA_SELF_ISSUE` / `AUTO_SESSION_ID` という具体的な変数名 (定数名) を列挙しているため (`modules/verify-patterns.md` §9 の rubric+定数名補強ルールに該当)、決定的な補強として `file_contains "AUTO_SESSION_ID"` を両ファイルに追加した。この2件は Issue 本文の Pre-merge AC (2件) には存在しないため、Spec の Pre-merge Verification 件数 (4件) と Issue 本文の Pre-merge AC 件数 (2件) は意図的な差分 (Count alignment check の警告は許容する)。他4変数は実装前から両ファイル中に (異なる文脈で) 既に出現するため before/after のデルタシグナルとして機能しない一方、`AUTO_SESSION_ID` は両ファイルとも実装前0件のため補強対象として選定した。
- **ドキュメント同期は対象外と判断**: この防御的 unset パターンは `docs/tech.md` § BATS Mocking Convention (`WHOLEWORK_SCRIPT_DIR`) とは別の関心事であり、Issue 本文も変更対象を2ファイルに明示的に限定している (不採用案の理由と同じく影響範囲拡大を回避する方針)。パターンをテスト規約として `docs/tech.md` に文書化する提案は将来のフォローアップ候補として残すが、本 Issue の Acceptance Criteria には含めない。
