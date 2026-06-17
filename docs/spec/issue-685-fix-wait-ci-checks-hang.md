# Issue #685: scripts: wait-ci-checks.sh の gh pr checks --watch hang を解消

## Overview

`scripts/wait-ci-checks.sh` が `gh pr checks --watch --interval 60` を使用しているため、CI 全 SUCCESS 状態でも終了せずに長時間 hang する。`timeout 1200` が SIGTERM を送信しても `gh` プロセスが終了しない事象が発生。

Candidate C（polling ループ + `--kill-after` の両方）を採用し、`--watch` 依存を完全に除去する。

## Reproduction Steps

1. PR route の `/auto` を実行
2. `run-merge.sh` が `wait-ci-checks.sh` を呼び出す
3. `gh pr checks --watch --interval 60` が全 SUCCESS 後も終了しない（観測: PR #683 で 3h15m hang）
4. `timeout 1200` のタイムアウトが効かず、手動 kill が必要になる

## Root Cause

`gh pr checks --watch` が内部的に CI 状態の "terminal" 判定に失敗し、全 SUCCESS 後も待ち続ける。`timeout` コマンドが SIGTERM を送信しても `gh` プロセスが SIGTERM を無視するため、`timeout` のみでは強制終了できない。

根本的な解決策: `--watch` 依存を廃止し、`--json name,state` を使った polling ループに置き換える（各 poll 呼び出しに `--kill-after` でフォールバック強制終了を追加）。

## Changed Files

- `scripts/wait-ci-checks.sh`: `--watch` コードパスを polling ループ（`--json name,state` + `--kill-after` per-poll）に置き換え、`ci_wait` イベント emission を jq ベースに更新 — bash 3.2+ compatible
- `tests/wait-ci-checks.bats`: `gh` / `timeout` / `sleep` モック更新、タイムアウト・失敗ケーステストを再設計

## Implementation Steps

1. **`scripts/wait-ci-checks.sh`** — `--watch` を polling ループに置き換え + 各種更新 (→ AC1, AC2)

   以下の変更を行う:

   a. **コードパス統合**: `_emit_ci_wait` による if/else 分岐を廃止し、polling ループを共通パスとして実装

   b. **polling ループ本体**（`echo "Waiting..."` の直後に配置）:
   ```
   _ci_checks_output=""
   _poll_start=$(date +%s)
   while true; do
     _elapsed=$(( $(date +%s) - _poll_start ))
     if [[ "$_elapsed" -ge "$TIMEOUT_SEC" ]]; then
       echo "CI check wait timed out after ${TIMEOUT_SEC}s for PR #${PR_NUMBER}" >&2
       break
     fi
     _poll_result=""
     if command -v timeout >/dev/null 2>&1; then
       _poll_result=$(timeout --kill-after=10 30 gh pr checks "$PR_NUMBER" --json name,state 2>/dev/null) || true
     elif command -v gtimeout >/dev/null 2>&1; then
       _poll_result=$(gtimeout 30 gh pr checks "$PR_NUMBER" --json name,state 2>/dev/null) || true
     else
       _poll_result=$(gh pr checks "$PR_NUMBER" --json name,state 2>/dev/null) || true
     fi
     if [[ -n "$_poll_result" ]]; then
       _ci_checks_output="$_poll_result"
       _in_progress=$(echo "$_poll_result" | jq '[.[] | select(.state == "IN_PROGRESS")] | length' 2>/dev/null || echo "1")
       if [[ "$_in_progress" -eq 0 ]]; then
         break
       fi
       echo "CI checks in progress: ${_in_progress} check(s) still running..." >&2
     fi
     sleep 60
   done
   ```

   c. **`ci_wait` イベント emission** — polling ループ後（event 有効時のみ）:
   ```
   _ci_wait_end=$(date +%s)
   _wait_sec=$(( _ci_wait_end - _ci_wait_start ))
   _passed=$(echo "${_ci_checks_output:-}" | jq '[.[] | select(.state == "SUCCESS")] | length' 2>/dev/null || echo "0")
   _passed=${_passed:-0}
   _failed=$(echo "${_ci_checks_output:-}" | jq '[.[] | select(.state == "FAILURE")] | length' 2>/dev/null || echo "0")
   _failed=${_failed:-0}
   emit_event "ci_wait" ... (既存の emit_event 呼び出しを保持)
   ```

   d. 旧 `--watch` コードブロック（else ブランチ含む）を削除

2. **`tests/wait-ci-checks.bats`** — モック更新とテスト再設計 (→ AC3)

   a. **`setup()` 内モック更新**:
   - `gh` モック: `--json` 引数を含む呼び出しは JSON を返す（`[{"name":"Run bats tests","state":"SUCCESS"}]`）、その他は既存動作を維持
   - `timeout` モック: `--kill-after=N` プレフィックスを処理（`if [[ "$1" == --kill-after* ]]; then shift; fi; shift; exec "$@"` パターン）
   - `sleep` モックを追加（`exit 0` の no-op）

   b. **既存テスト更新**:
   - "success: passes PR number to timeout and gh pr checks": `--json` フラグ付きで呼び出されることを確認（`--watch` は消えるので必要に応じて assertion 調整）
   - "success: continues even when timeout exits non-zero": `gh` モックを `IN_PROGRESS` 返しに変更 + `WHOLEWORK_CI_TIMEOUT_SEC=1` 設定でタイムアウト動作を検証
   - "success: continues even when gh pr checks fails": `gh` モックが `[]` 空配列を返す形に変更（in_progress=0 なので即 break）または `WHOLEWORK_CI_TIMEOUT_SEC=1` 設定
   - "ci_wait: event JSON is parseable when gh output has no pass/success matches": `gh` モックを `[{"name":"c1","state":"FAILURE"}]` 形式の JSON に変更し、jq ベースの counting を検証

## Verification

### Pre-merge

- <!-- verify: grep "gh pr checks.*--json|--kill-after" "scripts/wait-ci-checks.sh" --> `scripts/wait-ci-checks.sh` が polling ループ（`--json` フラグ付き `gh pr checks` を使用）または `--kill-after` オプション追加のいずれかを実装している
- <!-- verify: rubric "scripts/wait-ci-checks.sh が CI 全 SUCCESS 時に TIMEOUT_SEC を超えず終了するロジックを持つ。具体的には gh pr checks --watch のリプレース（polling loop で SUCCESS/SKIPPED で break）または timeout の --kill-after 追加、もしくは両方が実装されている" --> rubric 基準を満たす
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> `tests/wait-ci-checks.bats` を含む全 bats テストが CI で PASS (PR route)

### Post-merge

- 次回 pr route `/auto` 完走時に merge phase が TIMEOUT_SEC 内に完了することを確認

## Notes

- **`--json conclusion` vs `--json name,state`**: Issue body は `--json conclusion` を提案しているが、`modules/verify-executor.md` のコメントでは `gh pr checks` に対して `conclusion` は有効でないと記載されている。`verify-executor.md` のコードベース定義を優先し、`--json name,state`（state 値: `SUCCESS`, `FAILURE`, `IN_PROGRESS`）を採用する（auto-resolve）。
- **`gtimeout` の `--kill-after`**: GNU coreutils `timeout` を macOS 向けにリネームした `gtimeout` も `--kill-after` をサポートするが、バージョンに依存する可能性がある。リスクを最小化するため、`gtimeout` パスでは `--kill-after` なしの 30s タイムアウトを使用し、`timeout` パスのみ `--kill-after=10` を付与する。
- **polling ループの最小間隔**: 各 poll は `gh pr checks --json` の単発実行（非 `--watch`）なので、通常は数秒で返る。per-poll タイムアウトは 30s（`--kill-after=10` で最大 40s）。
- **Issue body の `--watch` 旧コードの削除確認**: `grep -n "\-\-watch" scripts/wait-ci-checks.sh` で 0 件であることを実装後に確認する。
