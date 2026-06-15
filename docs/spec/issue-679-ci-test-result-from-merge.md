# Issue #679: auto-events-log: CI run から test_result を fetch して emit

## Overview

`scripts/run-merge.sh` の merge 完了後、`gh run list --workflow=test.yml` で最新 CI run を取得し、`gh run view --log` で bats summary を parse して `test_result` event を `source=ci` 付きで emit する。これにより Claude が local で bats を実行しなかった Issue でも `test_result` が捕捉できるようになる。

対象ルート: PR route のみ（run-merge.sh は常に PR number を受け取るため条件は `EXIT_CODE=0` + `AUTO_EVENTS_LOG` 設定済みの確認のみ）。

## Changed Files

- `scripts/run-merge.sh`: merge 成功後（EXIT_CODE=0）に CI test_result emit ブロックを追加 — bash 3.2+ compatible
- `tests/run-merge.bats`: `source=ci` 付き test_result emit の regression test を追加 — bash 3.2+ compatible

## Implementation Steps

1. `scripts/run-merge.sh` の merge reconcile ブロック（`if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]; then ... fi`）の直後に CI test_result emit ブロックを追加する (→ AC1, AC2, AC3)

   追加する処理の流れ（`EXIT_CODE=0` かつ `AUTO_EVENTS_LOG` 設定済みの場合のみ実行）:
   ```
   _run_id ← gh run list --workflow=test.yml --branch=main --limit=1 --json databaseId --jq '.[0].databaseId'
   if _run_id is non-empty:
     _bats_summary ← gh run view "$_run_id" --log | grep -E "[0-9]+ tests?, [0-9]+ failures?" | tail -1
     if _bats_summary is non-empty:
       _passed ← parse from _bats_summary (grep -oE "^[0-9]+")
       _failed ← parse from _bats_summary (grep -oE "[0-9]+ failures?" → grep -oE "^[0-9]+")
       emit_event "test_result" "phase=merge" "framework=bats" "source=ci" "passed=$_passed" "failed=$_failed" "run_id=$_run_id"
     else:
       echo "Warning: run-merge.sh: gh run view $run_id --log: no bats summary found" >&2
   fi
   ```

   失敗時（gh コマンドエラー、run_id 取得失敗）は `|| true` で no-op にする。

2. `tests/run-merge.bats` に `@test "test_result: emit_event called with source=ci after merge"` テストを追加する (→ AC4, AC5)

   テストで必要な mock:
   - `emit-event.sh` を override して `emit_event $*` を emit.log に記録
   - `gh` mock で `run list --workflow=test.yml` → `run_id=12345`, `run view 12345 --log` → `"5 tests, 0 failures"` を返す

   assert: `grep "source=ci" emit.log` が PASS すること

## Verification

### Pre-merge

- <!-- verify: grep "source=ci|source=\"ci\"" "scripts/run-merge.sh" --> `scripts/run-merge.sh` で CI 経由 test_result emit ロジックが追加されている
- <!-- verify: grep "gh run.*test.yml|gh run view.*--log" "scripts/run-merge.sh" --> gh runs API で test workflow log を fetch するコードがある
- <!-- verify: rubric "scripts/run-merge.sh が pr route の merge 完了時に gh runs API で最新 test workflow log を取得し、bats summary 行を parse して test_result event を source=ci 付きで emit する。失敗時は no-op で warning 出力" --> rubric 基準を満たす
- <!-- verify: command "bats tests/run-merge.bats" --> 既存 bats テストが green
- <!-- verify: grep "source=ci" "tests/run-merge.bats" --> CI test_result emit パターンの regression test が追加されている

### Post-merge

- 次回 `/auto` pr route 完走後の `.tmp/auto-events.jsonl` で `source=ci` 付き `test_result` event が emit されることを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- `source=local` を run-auto-sub.sh の既存 emit に追加することは本 Issue の AC 範囲外（既存 AC に対応する verify command なし）。必要なら後続 Issue で対応。
- CI workflow 名 `test.yml` はハードコード。複数 workflow リポジトリへの対応は別 Issue scope。
- patch route 対応: scope 外（run-merge.sh は PR number を必須引数として受け取るため常に PR route 前提）。
- `gh run view --log` は大量出力になる可能性があるが、`grep -E "[0-9]+ tests?, [0-9]+ failures?" | tail -1` でフィルタするため実害なし。
- bats test でのセルフ参照除外は不要（grep パターンが tests/run-merge.bats 内のコメント/文字列と干渉しない）。
- `grep -oE` は bash 3.2+ / macOS GNU grep 互換。`||echo 0` で値が取れない場合に 0 を代入するパターンは既存コード (run-auto-sub.sh L130-131) と一致。

## Code Retrospective

### Deviations from Design

- `_passed` の parse パターンを Spec の `grep -oE "^[0-9]+"` から `grep -oE "[0-9]+ tests?" | grep -oE "^[0-9]+"` に変更。理由: `gh run view --log` のログ行にはタイムスタンプ prefix (例: `2026-01-01T12:00:00.000Z`) が付くため、`^[0-9]+` では年 (`2026`) を誤マッチする。`_failed` と同様の2ステップ pattern に統一した。

### Design Gaps/Ambiguities

- None

### Rework

- None

## review retrospective

### Spec vs. Implementation Divergence Patterns

- `_passed` の2ステップ grep 変更はCode Retrospectiveに記録済みで、構造的なSpec-PR乖離なし。全5 AC verify commandが正常動作し、PRレビューの整合性確認は高精度だった。

### Recurring Issues

- null `_run_id` による偽陽性 warning（CONSIDER）: `gh run list` が run 不在で `"null"` を返すケースへの非対応。稀なエッジケースで実害なし。
- warning path の regression test 未追加（CONSIDER）: success path のみテストされており、warning path（`_bats_summary` 空）のテストが不足。Type=Feature 案件ではエラーパステスト補完を推奨。

### Acceptance Criteria Verification Difficulty

- 全AC にvalidな verify command が設定されており、UNCERTAIN ゼロ。rubric AC3 は merge完了後の CI log fetch という外部依存ロジックの意味的検証として特に有効だった。`command "bats tests/run-merge.bats"` は safe mode のため CI fallback 経由でPASS（"Run bats tests" SUCCESS）。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- MUST/SHOULDイシューなし → `COMMENT` event で PR Review投稿（`REQUEST_CHANGES` ではない）
- CONSIDER 2件: null run_id guard、warning path テスト。いずれも skip 判断（稀なケース、実害なし）
- Acceptance Criteria 全 5/5 PASS、CI 全 SUCCESS

### Deferred Items
- null run_id guard 追加（CONSIDER level、本Issue scope外）
- warning path regression test 追加（CONSIDER level、後続Issueで検討可）
- post-merge AC (`verify-type: observation event=auto-run`) は次回 `/auto` 完走後に自動評価

### Notes for Next Phase
- MUST イシューなし → merge をブロックする理由なし。`/merge 681` を直接実行可
- Spec の verify command 品質は高く、verify phase での再実行もスムーズなはず
- post-merge AC のみ未評価（observation待ち）のため verify 完了後に observation log 確認を推奨
