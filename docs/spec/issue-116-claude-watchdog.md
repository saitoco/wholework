# Issue #116: auto: run-*.sh の claude -p ハング検出・リトライ機構を追加

## Overview

`claude -p` を直接呼び出す `run-*.sh` スクリプト 6 本（run-code/spec/review/verify/merge/issue.sh）に共有ウォッチドッグスクリプト `scripts/claude-watchdog.sh` を導入する。ウォッチドッグは `WATCHDOG_TIMEOUT` 秒間出力がない場合に `claude -p` を kill し、1 回リトライする。`run-auto-sub.sh` は `claude -p` を直接呼ばず他の `run-*.sh` を呼ぶオーケストレーターのため対象外。

## Changed Files

- `scripts/claude-watchdog.sh`: 新規作成。`claude -p` ラッパー ウォッチドッグスクリプト
- `scripts/run-code.sh`: `claude` 呼び出しを `"$SCRIPT_DIR/claude-watchdog.sh" claude` に変更
- `scripts/run-spec.sh`: 同上
- `scripts/run-review.sh`: 同上
- `scripts/run-verify.sh`: 同上（`2>&1 | tee` パイプパターン維持）
- `scripts/run-merge.sh`: 同上
- `scripts/run-issue.sh`: 同上
- `tests/claude-watchdog.bats`: 新規作成。ウォッチドッグのユニットテスト
- `docs/structure.md`: Scripts セクションに `scripts/claude-watchdog.sh` エントリ追加

## Implementation Steps

1. Create `scripts/claude-watchdog.sh` (→ criteria 1, 3, 4)
   - Standalone executable (`chmod +x`)
   - `WATCHDOG_TIMEOUT` env var, default `600` (seconds; 10 minutes is sufficient to avoid false positives since real hangs produce 0 bytes from startup)
   - Takes full command as positional args (`"$@"`) and runs it in background, redirecting output to a temp file
   - Streams output in real-time using `tail -f "$tmpout" &` — allows `run-verify.sh`'s `tee` pipe to receive output incrementally
   - Check interval: `_CHECK_INTERVAL=$(( WATCHDOG_TIMEOUT < 10 ? WATCHDOG_TIMEOUT : 10 ))` — dynamically derived as `min(WATCHDOG_TIMEOUT, 10)` so small timeout values (e.g., `WATCHDOG_TIMEOUT=2` in tests) work without waiting a full 10-second polling interval
   - Watchdog loop: checks `wc -c < "$tmpout"` every `_CHECK_INTERVAL` seconds; kills process if file size unchanged for `WATCHDOG_TIMEOUT` seconds
   - Tracks watchdog-triggered kills with a local flag (`_watchdog_killed=true`)
   - Contains variable named `retry` and/or comment "retry" to satisfy acceptance criteria grep
   - Retries once (`retry`) only when `_watchdog_killed=true`; normal non-zero exits are passed through without retry
   - After command exits (or is killed): kills the `tail -f` background process, removes temp file, returns final exit code

2. Update `scripts/run-{code,spec,review,verify,merge,issue}.sh` — 6 files (after step 1) (→ criterion 2)
   - Change the `env -u CLAUDECODE claude -p` line in each file to `env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p`
   - `run-verify.sh` only: insert watchdog as above; keep the existing `2>&1 | tee "$VERIFY_TMPOUT"` suffix and `EXIT_CODE=$?` (with `pipefail` intact, exit code of watchdog propagates through pipeline)

3. Create `tests/claude-watchdog.bats` (after step 1) (→ criterion 5)
   - Use a mock command script placed in `$BATS_TEST_TMPDIR/mocks/` at front of PATH
   - Test cases (examples):
     - Normal exit 0: output and exit code pass through
     - Normal exit non-zero: exit code passes through without retry
     - Watchdog timeout: command producing no output is killed after `WATCHDOG_TIMEOUT`; use small value (e.g., `WATCHDOG_TIMEOUT=2`) with `sleep 60` as mock
     - Retry: verify a second invocation occurs after watchdog kill (use a counter file in mock)
     - `WATCHDOG_TIMEOUT` env var: verify custom value takes effect

4. Update `docs/structure.md` Scripts section (parallel with step 1)
   - Add new "**Process management:**" category after the "Skill runners:" block with entry: `scripts/claude-watchdog.sh` — watchdog wrapper for `claude -p` invocations (hang detection + 1 retry)

## Verification

### Pre-merge
- <!-- verify: file_exists "scripts/claude-watchdog.sh" --> ウォッチドッグ共有スクリプト `scripts/claude-watchdog.sh` が作成されている
- <!-- verify: grep "claude-watchdog" "scripts/run-code.sh" --> `run-*.sh` がウォッチドッグスクリプトを使用している（run-code.sh で代表検証）
- <!-- verify: grep "retry" "scripts/claude-watchdog.sh" --> ウォッチドッグに 1 回リトライロジックが含まれている
- <!-- verify: grep "WATCHDOG_TIMEOUT" "scripts/claude-watchdog.sh" --> タイムアウト値が環境変数でカスタマイズ可能
- <!-- verify: command "bats tests/" --> 全 bats テストが PASS する

### Post-merge
- `/auto N` 実行時に `claude -p` がハングした場合、ウォッチドッグが自動で kill + リトライして処理が継続する（手動確認）

## Notes

- **デフォルト `WATCHDOG_TIMEOUT=600`（10分）**: 実際のハングは起動直後から 0 バイトが継続する。正常実行では 1〜2 分以内に何らかの出力が生成されるため、10 分は十分な猶予であり誤検知リスクも低い
- **`run-verify.sh` の tee パターン**: `claude-watchdog.sh` の `tail -f` が stdout にストリームし、それが `tee "$VERIFY_TMPOUT"` を通過する。VERIFY_FAILED 検出に影響なし
- **`run-auto-sub.sh` 除外確認**: `grep -n "claude -p" scripts/run-auto-sub.sh` でヒットなし。`run-*.sh` を呼ぶオーケストレーターのみ（Issue 本文と一致）
- **リトライ条件**: ウォッチドッグによる kill 時のみリトライ（`_watchdog_killed=true`）。`claude` の通常エラー終了はリトライしない
- **`tail -f` のフラッシュ遅延**: `sleep 1` 後に `tail` を kill することで残存出力を確実にフラッシュする

## Code Retrospective

### Deviations from Design
- **`_CHECK_INTERVAL` の動的計算**: Spec は "10秒固定" としていたが、`WATCHDOG_TIMEOUT=2` などの小さい値でテストが10秒待ち状態になる問題を回避するため、`min(WATCHDOG_TIMEOUT, 10)` で CHECK_INTERVAL を動的に計算した。これにより小タイムアウト値のテストも高速に動作する。

### Design Gaps/Ambiguities
- Spec の test cases に `WATCHDOG_TIMEOUT=2` + `sleep 60` を使う想定があったが、固定 CHECK_INTERVAL=10 だと最初のチェックまで10秒待つため test が遅くなる懸念があった。動的計算で解決した。

### Rework
- N/A（設計変更は事前に気づいて初回実装で対応済み）
