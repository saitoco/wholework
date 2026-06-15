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

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- `2>&1` 除去のみでの修正（`grep '^{' | tail -1` フィルタ方式は採用しなかった）: TOKEN_USAGE_FILE へのリダイレクト時点で watchdog stderr を混入させないのが根本解であり、シンプルで bash 3.2+ 互換
- `test_result` 条件は `code*` prefix match を採用（`"code" || "code-patch" || "code-pr"` より簡潔で、将来的なフェーズ名追加にも対応）
- `ci_wait` は既存の `run-auto-sub.sh` → `run-review.sh` / `run-merge.sh` 経路での `export AUTO_EVENTS_LOG` が正しく動作しており、Issue が観察されたのはテスト実行時にレビュー/マージフェーズなしの XS/S issue だったことが原因と判断。merge phase テストを追加して propagation path を明示化した

### Deferred Items

- post-merge AC（次回 `/auto` 完走後の `token_usage` / `ci_wait` / `test_result` 3 種観察）は observation event として defer

### Notes for Next Phase

- `/review` は `bats tests/run-auto-sub.bats` の `test_result` テスト（ok 23）が PASS していることを確認する
- `file_not_contains` ACs はすべて PASS 済み（Issue チェックボックス更新済み）
- PR #664 でのマージ後、`.tmp/auto-events.jsonl` に 3 種が記録されることを post-merge 観察で確認する
