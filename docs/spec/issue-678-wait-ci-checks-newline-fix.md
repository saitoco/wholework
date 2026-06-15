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
