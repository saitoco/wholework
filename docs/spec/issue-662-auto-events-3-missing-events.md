# Issue #662: auto-events-log: token_usage / ci_wait / test_result が emit されない

## Overview

`/auto` 完走後に `.tmp/auto-events.jsonl` を解析したところ、6 種類の event のうち
`token_usage` / `ci_wait` / `test_result` の 3 種が一切記録されていなかった。
本 Issue では各 missing event の根本原因を修正し、次回 `/auto` 完走時にすべて記録されることを目指す。

## Reproduction Steps

1. `.wholework.yml` に設定なし（`AUTO_EVENTS_LOG` が set される状態）で `/auto N` を実行
2. 完走後 `.tmp/auto-events.jsonl` を確認する
3. `jq '.event' .tmp/auto-events.jsonl | sort | uniq -c` で種別カウントを確認
4. `token_usage` / `ci_wait` / `test_result` がすべて 0 件

## Root Cause

### token_usage（BUG 確定）

`run-code.sh:166`、`run-review.sh:89`、`run-merge.sh:80` で `claude-watchdog.sh` の起動に
`> "$TOKEN_USAGE_FILE" 2>&1` を使用しているため、watchdog の stderr 出力（"still waiting..."
メッセージ）が TOKEN_USAGE_FILE の先頭に混入する。`run-auto-sub.sh` がこのファイルを
`jq -r '.model // empty'` で parse しようとすると、先頭の非 JSON 行で parse error となり、
`token_usage` event が emit されない。

修正方針: 各スクリプトの `> "$TOKEN_USAGE_FILE" 2>&1` から `2>&1` を除去する。
stderr は caller（`run-auto-sub.sh`）の `> "$log_file" 2>&1` 経由で wrapper log に記録される。

### test_result（BUG 確定）

`run-auto-sub.sh:105` の条件が `[[ "$phase" == "code" ]]` だが、実際に渡されるフェーズ名は
`"code-patch"`（XS/S route）または `"code-pr"`（M/L route）であるため、条件が常に false となり
`test_result` event が emit されない。

修正方針: 条件を `[[ "$phase" == code* ]]` に変更する。

### ci_wait（env 伝播確認）

コード調査の結果、`run-auto-sub.sh` が `export AUTO_EVENTS_LOG` を行い、サブプロセスの
`run-review.sh` / `run-merge.sh` → `wait-ci-checks.sh` に正しく伝播している。
`wait-ci-checks.sh` の条件 `[[ -n "${AUTO_EVENTS_LOG:-}" ]] && [[ -f "$SCRIPT_DIR/emit-event.sh" ]]`
は両辺とも true になるはず。ci_wait=0 の観察は、当該テスト実行時のすべての sub-issue が
XS/S route（patch、review/merge なし）であった可能性がある。
既存の `@test "ci_wait: event emitted to AUTO_EVENTS_LOG when AUTO_EVENTS_LOG is set"` で
review phase の emit を確認済み。本 Issue では merge phase（`run-merge.sh` 経由）を
カバーするテストを追加し、propagation path を明示的に文書化する。

## Changed Files

- `scripts/run-code.sh`: L166 の `> "$TOKEN_USAGE_FILE" 2>&1` から `2>&1` を除去 — bash 3.2+ 互換
- `scripts/run-review.sh`: L89 の `> "$TOKEN_USAGE_FILE" 2>&1` から `2>&1` を除去 — bash 3.2+ 互換
- `scripts/run-merge.sh`: L80 の `> "$TOKEN_USAGE_FILE" 2>&1` から `2>&1` を除去 — bash 3.2+ 互換
- `scripts/run-auto-sub.sh`: L105 の `"$phase" == "code"` を `"$phase" == code*` に変更 — bash 3.2+ 互換
- `tests/run-auto-sub.bats`: `test_result` テストのモック修正（stdout に bats 出力を echo するよう変更）
- `tests/wait-ci-checks.bats`: merge phase（`EMIT_PHASE_NAME="merge"`）での ci_wait emission を確認するテストを追加

## Implementation Steps

1. **`2>&1` 除去**（→ ACs 1, 2, 3）:
   - `scripts/run-code.sh:166`: `> "$TOKEN_USAGE_FILE" 2>&1` → `> "$TOKEN_USAGE_FILE"`
   - `scripts/run-review.sh:89`: 同上
   - `scripts/run-merge.sh:80`: 同上

2. **`test_result` フェーズ条件修正**（→ AC 4）:
   - `scripts/run-auto-sub.sh:105`: `[[ "$phase" == "code" ]]` → `[[ "$phase" == code* ]]`
   - `tests/run-auto-sub.bats` の "test_result" テストのモック修正:
     現在の mock は `.tmp/wrapper-out-42-code.log` に直接書き込んでいるため（フェーズ名不一致で skip）、
     stdout への echo に変更して `.tmp/wrapper-out-42-code-patch.log` に正しくキャプチャされるようにする

3. **ci_wait merge phase テスト追加**（→ AC 5）:
   `tests/wait-ci-checks.bats` に以下のテストを追加:
   ```
   @test "ci_wait: event emitted with merge phase in run-auto-sub.sh env context" {
     AUTO_EVENTS_LOG, EMIT_ISSUE_NUMBER="101", EMIT_PHASE_NAME="merge", WHOLEWORK_SCRIPT_DIR を設定し
     bash "$SCRIPT" 101 を実行。 AUTO_EVENTS_LOG に '"event":"ci_wait"' と '"phase":"merge"' を確認。
   }
   ```

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/run-code.sh" "2>&1" --> `scripts/run-code.sh` の `--output-format json` 行から `2>&1` が除去され、TOKEN_USAGE_FILE に watchdog stderr が混入しない
- <!-- verify: file_not_contains "scripts/run-review.sh" "2>&1" --> `scripts/run-review.sh` の同箇所から `2>&1` が除去される
- <!-- verify: file_not_contains "scripts/run-merge.sh" "2>&1" --> `scripts/run-merge.sh` の同箇所から `2>&1` が除去される
- <!-- verify: rubric "scripts/run-auto-sub.sh の test_result emission 条件（L104-116 付近の if 条件）が code-patch / code-pr フェーズを含むよう拡張されている" --> `scripts/run-auto-sub.sh` の `test_result` emission が `code-patch` / `code-pr` フェーズでも発火するよう条件分岐を修正
- <!-- verify: command "bats tests/wait-ci-checks.bats" --> `wait-ci-checks.sh` の `AUTO_EVENTS_LOG` 伝播経路を確認し、`run-review.sh` / `run-merge.sh` 経由で env が届くことを bats test で検証

### Post-merge

- 次回 `/auto` 完走後に `.tmp/auto-events.jsonl` で `token_usage` / `ci_wait` / `test_result` 3 種が記録されることを観察

## Notes

- `run-auto-sub.sh:64` の `> "$log_file" 2>&1` は意図的な設定（runner 全体の stdout+stderr を wrapper log に記録するため）— 変更しない
- `run-merge.sh` の実際の `2>&1` 行は L80（Issue body では L78 と記載されているが、コード調査時点で L80 が正確）
- `file_not_contains "scripts/run-code.sh" "2>&1"` 等は各ファイルに `2>&1` が 1 箇所のみ存在することを確認済み（除去後は 0 件）
- ci_wait の既存テスト（`@test "ci_wait: event emitted to AUTO_EVENTS_LOG when AUTO_EVENTS_LOG is set"`、
  `EMIT_PHASE_NAME="review"` で動作確認済み）は変更不要

## Code Retrospective

### Deviations from Design

- `test_result` テストのモック修正方針として、Spec は「stdout に echo するよう変更」と記載していたが、加えて `skip` による条件付きスキップを proper assertion (`grep -q "test_result" "$BATS_TEST_TMPDIR/emit.log"`) に変更した。修正後は `code*` 条件が正しく機能し、テストが実際に PASS することを確認できたため、skip を外した方が正確な検証になる。

### Design Gaps/Ambiguities

- None

### Rework

- None

## review retrospective

### Spec vs. 実装の乖離パターン

- 乖離なし。3 つのバグ修正（`2>&1` 除去、`test_result` 条件拡張、`ci_wait` merge phase テスト追加）はすべて Spec の実装ステップと一致していた。`test_result` テストのモック修正方針（skip を proper assertion に昇格）は Code Retrospective で説明済み。

### 繰り返し指摘パターン

- `test_result` テストで skip を proper assertion に昇格させたが、同ファイルの `token_usage` テストに同じ skip パターンが残っていた。fix-and-forget パターン：同類の skip を同一 PR でまとめて修正する規律が必要。

### 受け入れ基準検証の難易度

- `file_not_contains` と `rubric` および `command` の 5 条件すべて UNCERTAIN なし。`command "bats tests/wait-ci-checks.bats"` は CI 参照フォールバック（`Run bats tests` SUCCESS）で PASS 判定。verify command の設計は適切だった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- PR #664 を squash merge（`--squash --delete-branch`）で main にマージ。conflicts なし、CI 全 SUCCESS
- `token_usage` skip 未修正（SHOULD）は既存の判断通りブロックせずマージ
- BASE_BRANCH=main のため `closes #662` により Issue #662 は自動クローズされる

### Deferred Items

- `tests/run-auto-sub.bats` L561-562 の `token_usage` skip を proper assertion に昇格 → 別 Issue で対処
- post-merge AC（`.tmp/auto-events.jsonl` で `token_usage` / `ci_wait` / `test_result` 3 種の記録確認）→ 次回 `/auto` 完走後に観察

### Notes for Next Phase

- verify では pre-merge の verify command（`bats tests/wait-ci-checks.bats` 等）を再実行して回帰がないことを確認
- post-merge AC は `.tmp/auto-events.jsonl` の観察が必要なため、verify では observable な成果物を対象に実施
- `token_usage` テストの skip 残存は SHOULD レベル（ブロックしない）
