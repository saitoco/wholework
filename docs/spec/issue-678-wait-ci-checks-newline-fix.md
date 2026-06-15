# Issue #678: wait-ci-checks: grep -c || echo 0 で checks_failed/passed 値に newline が混入し events JSONL を破壊

## Overview

`scripts/wait-ci-checks.sh` の `grep -c ... || echo 0` パターンが原因で `checks_passed`/`checks_failed` 変数に literal newline が混入し、`scripts/emit-event.sh` がそれを escape せずに JSON 挿入するため `.tmp/auto-events.jsonl` の JSONL 1 行制約が破壊される。batch session で `jq -s` parse error が発生し session report が全 0 件になる。2 層の防御（入力側 sanitization + 出力側 escape）で根本解決する。

## Reproduction Steps

1. batch session で `wait-ci-checks.sh` が `AUTO_EVENTS_LOG` 付きで呼び出される
2. `grep -c ... "pass|success"` が 0 match → exit 1 → `|| echo 0` が発火
3. stdout = `0\n0\n`、`$()` が trailing newline を 1 つだけ strip → `_passed="0\n0"` (literal newline 混入)
4. `emit_event "ci_wait" ... "checks_passed=${_passed}"` が literal newline 含む JSON を生成
5. JSONL 1 行制約違反 → `jq -s . .tmp/auto-events.jsonl` が parse error → session report が全 0 件

## Root Cause

`wait-ci-checks.sh` L34-35: `grep -c` は 0 match 時に exit 1 を返す。`|| echo 0` が発火して追加の `0\n` を stdout に出力し、`$()` が trailing newline を 1 つだけ strip するため変数に `0\n0` (literal newline 含む) が入る。

`emit-event.sh` の emit_event() 内 value 挿入処理が control character を escape せず JSON に直接挿入するため、JSONL 1 行制約が破壊される。

## Changed Files

- `scripts/wait-ci-checks.sh`: `_passed`/`_failed` の計算を `grep -c ... || true` + `${var:-0}` fallback に変更 — bash 3.2+ 互換
- `scripts/emit-event.sh`: value を JSON に挿入する前に newline 除去・tab 置換・backslash/double-quote escape の sanitization を追加 — bash 3.2+ 互換
- `tests/wait-ci-checks.bats`: `ci_wait` event の `checks_passed`/`checks_failed` 値が literal newline を含まない regression test を追加
- `tests/emit-event.bats`: newline / tab / backslash / double-quote を含む value の sanitization regression test を追加

## Implementation Steps

1. `scripts/wait-ci-checks.sh` の `_passed`/`_failed` 計算を修正 — `|| echo 0` を `|| true` に変更し、`:-0` fallback を次行に追加する (→ AC1, AC2):

   ```bash
   _passed=$(echo "${_ci_checks_output:-}" | grep -c -i "pass\|success" 2>/dev/null || true)
   _passed=${_passed:-0}
   _failed=$(echo "${_ci_checks_output:-}" | grep -c -i "fail\|error" 2>/dev/null || true)
   _failed=${_failed:-0}
   ```

   `|| true` 採用理由: grep が "0" を出力して exit 1 の場合、`true` は何も出力しないため `$()` は grep の出力 "0" のみキャプチャする。`:-0` は `_passed=""` (空) の安全 fallback。

2. `scripts/emit-event.sh` の `emit_event()` 内で `json="${json},\"${k}\":\"${v}\""` の行を以下に置き換える (→ AC3):

   ```bash
   # sanitize value: strip newlines, replace tabs, escape backslash and double-quote
   local v_sanitized="${v//$'\n'/}"
   v_sanitized="${v_sanitized//$'\t'/ }"
   v_sanitized="${v_sanitized//\\/\\\\}"
   v_sanitized="${v_sanitized//\"/\\\"}"
   json="${json},\"${k}\":\"${v_sanitized}\""
   ```

   backslash escape を double-quote escape より先に実行することで二重 escape を防ぐ。

3. `tests/wait-ci-checks.bats` に regression test を追加: gh mock が pass/success に一致する行を出力しない場合でも、emit された `ci_wait` event の JSON が `jq .` でパース可能なことを検証する (→ AC4)。

4. `tests/emit-event.bats` に regression test を追加: newline / tab / backslash / double-quote を含む value を渡した際に生成される JSON が `jq .` でパース可能なことを検証する (→ AC4)。

## Verification

### Pre-merge

- <!-- verify: grep -E "_passed=.*grep -c.*\|\| true|_passed=.*awk" "scripts/wait-ci-checks.sh" --> `wait-ci-checks.sh` で `grep -c ... || echo 0` パターンが除去され、normalized 整数のみ変数に入る形式に修正されている
- <!-- verify: grep -E "_failed=.*(\|\| true|awk)" "scripts/wait-ci-checks.sh" --> 同じく `_failed` も修正される
- <!-- verify: grep -E "sanitize|strip|escape" "scripts/emit-event.sh" --> `emit-event.sh` で value sanitization 処理が追加される
- <!-- verify: command "bats tests/wait-ci-checks.bats tests/emit-event.bats" --> 既存 bats テストが green、かつ control character エッジケース（newline / tab / backslash / double-quote 含む値）の regression test が追加されている

### Post-merge

- 次回 `/auto --batch` 完走後の `.tmp/auto-events.jsonl` を `jq -s . > /dev/null` で parse してエラーが 0 件であることを確認

## Notes

- 発生元: `/audit auto-session 22090-1781508629` 実行時 (2026-06-15)、batch session で 5 件発生し session 22090 / 24236 / 58975 を跨いで影響
- 暫定対処: Python スクリプトで破損行を修復し再生成成功 (483 → 476 lines)
- Auto-Resolved: AC2 verify command を `grep "_failed=.*$"` → `grep -E "_failed=.*(\|\| true|awk)"` に強化済み（旧パターンは修正前も `_failed=` が存在し常時 PASS になる false-positive のため）
- 関連: #662 (ci_wait event 配線), #630 (event log 基盤), #654 (auto-session-report-published event)

## Code Retrospective

### Deviations from Design

- None. Spec の案 A (`|| true` + `:-0` fallback) をそのまま採用。案 B (awk) は不採用（Spec の推奨案 A の方がシンプルで bash 3.2+ 互換性も明確）。

### Design Gaps/Ambiguities

- `emit-event.sh` の `local` 変数宣言 (`local v_sanitized`) は bash 関数スコープ内での使用を前提にしており、sourceして使う使い方と整合していることを確認（emit_event() 内部で `local` を使う既存パターンに倣った）。

### Rework

- None. 実装は1パスで完了。

## review retrospective

### Spec vs. Implementation Divergence Patterns

- 構造的な乖離なし。Spec 案 A (`|| true` + `:-0` fallback) がそのまま実装されており、diff と Spec の対応は完全一致。
- AC1〜4 の verify command は実装と正確に対応しており、FAIL や UNCERTAIN は発生しなかった。

### Recurring Issues

- 同種イシューの繰り返しはなし。CONSIDER 1 件（`\r` 未サニタイズ）は今回修正スコープ外の軽微なギャップ。
- 今後 `emit-event.sh` に非数値 value を渡す呼び出し元が追加された場合に顕在化しうる。

### Acceptance Criteria Verification Difficulty

- 4 件の pre-merge AC すべてが自動検証成功（`grep` verify × 3 + CI 参照フォールバック × 1）。UNCERTAIN ゼロ。
- AC2 は code phase で `grep -E "_failed=.*(\|\| true|awk)"` に強化済みで false-positive を回避できていた。verify command の精度は良好。
- post-merge AC は observation 型（event=auto-run 待ち）で正常動作。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- PR #680 を `--squash --delete-branch` でマージ完了。BASE_BRANCH=main のため `closes #678` により Issue は自動クローズ。
- コンフリクトなし（mergeable=true, CI=success, review=approved）のため conflict resolution はスキップ。
- non-interactive モードで実行、AskUserQuestion なしで全ステップ完了。

### Deferred Items
- post-merge observation AC: 次回 `/auto --batch` 完走後に `.tmp/auto-events.jsonl` を `jq -s . > /dev/null` でパースし error 0 件を確認。
- `\r` sanitization gap（review フェーズから引き継ぎ）: 必要に応じて別 Issue 起票。

### Notes for Next Phase
- verify フェーズでは pre-merge AC（grep verify × 3 + bats × 1）が全 PASS 済みのため、post-merge AC（jq parse 確認）のみ確認すれば十分。
- flaky テスト（`post_merge_check.bats` テスト 7）は本 Issue と無関係、verify に影響しない。
- マージコミットは squash 済み、feature ブランチ（`worktree-code+issue-678`）は削除済み。
