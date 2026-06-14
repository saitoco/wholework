# Issue #630: auto event log metrics extension

## Overview

`/auto` セッション完走後の retrospective レポート自動生成に必要なデータを蓄積するため、`.tmp/auto-events.jsonl` に 6 種類の新 event を追加する。

追加 event:
- `token_usage` — `claude -p` 完了時のトークン消費量（モデル別）
- `watchdog_kill` — watchdog による kill の発生（pid・silent window 秒数）
- `max_silent_window` — phase 単位の最大無出力時間
- `concurrent_commit_detected` — phase 実行中のリモート並行コミット検出
- `ci_wait` — CI 待機の開始〜終了（wait_sec・checks 件数）
- `test_result` — code phase でのテスト実行結果（framework・passed/failed）

既存 event (`sub_start`, `phase_start`, `wrapper_exit` 等) との後方互換は維持する（フィールド追加のみ）。

## Changed Files

- `scripts/emit-event.sh`: 新規。`emit_event()` 関数を `run-auto-sub.sh` から抽出した共有ヘルパー（sourceble）
- `scripts/run-auto-sub.sh`: `emit-event.sh` を source; `run_phase_with_recovery()` に `token_usage` / `concurrent_commit_detected` / `test_result` emission を追加; `EMIT_ISSUE_NUMBER` / `EMIT_PHASE_NAME` を phase ごとに export — bash 3.2+ compatible
- `scripts/claude-watchdog.sh`: `OUTPUT_FORMAT_JSON=1` 時のプロセス死活ベース待機モードを追加（ファイルサイズ増加なしでも誤 kill しない）; `AUTO_EVENTS_LOG` が設定済みの場合に `watchdog_kill` / `max_silent_window` event を emit — bash 3.2+ compatible
- `scripts/wait-ci-checks.sh`: 開始時刻・終了時刻を記録し `ci_wait` event を emit; `EMIT_ISSUE_NUMBER` / `EMIT_PHASE_NAME` env var を参照 — bash 3.2+ compatible
- `scripts/run-code.sh`: `AUTO_EVENTS_LOG` が設定済みの場合に `--output-format json` + `OUTPUT_FORMAT_JSON=1` を使用し `.tmp/token-usage-${ISSUE_NUMBER}.json` に JSON を書き出す; `jq -r .result` でテキストを log_file へ補完 — bash 3.2+ compatible
- `scripts/run-review.sh`: 同上（`--output-format json` / TOKEN_USAGE_FILE 対応）— bash 3.2+ compatible
- `scripts/run-merge.sh`: 同上 — bash 3.2+ compatible
- `docs/reports/event-log-schema.md`: 新規。6 新 event の必須フィールド・任意フィールド・emission point・後方互換保証を文書化
- `docs/structure.md`: scripts ファイル数を 53 → 54 に更新（`emit-event.sh` 追加）
- `tests/emit-event.bats`: 新規。`emit_event()` のロックあり/なし書き込みテスト
- `tests/run-auto-sub.bats`: `emit-event.sh` のモックを `setup()` に追加; `token_usage` / `concurrent_commit_detected` / `test_result` emission のテストを追加
- `tests/claude-watchdog.bats`: `OUTPUT_FORMAT_JSON` モードのテスト（プロセス死活ベース待機）; `watchdog_kill` event emission のテストを追加
- `tests/wait-ci-checks.bats`: `ci_wait` event emission のテストを追加

## Implementation Steps

1. **`scripts/emit-event.sh` 新規作成 + `run-auto-sub.sh` 移行**（→ AC: emit 関数が scripts/ 全体に利用可能）
   - `run-auto-sub.sh` 内の `emit_event()` 関数定義をそのまま `scripts/emit-event.sh` に移動する（source 先として使用）
   - `run-auto-sub.sh` の `emit_event()` 定義を削除し、その直前に `source "$SCRIPT_DIR/emit-event.sh"` を追加する
   - `run-auto-sub.sh` の `sub_start` emit より前に `export EMIT_ISSUE_NUMBER="$SUB_NUMBER"` を追加する
   - `run_phase_with_recovery()` 関数の先頭（`emit_event "phase_start"` の直前）に `export EMIT_ISSUE_NUMBER="$issue" EMIT_PHASE_NAME="$phase"` を追加する（watchdog・wait-ci-checks が参照）
   - `run-auto-sub.sh` の spec phase 呼び出しの直前に `export EMIT_ISSUE_NUMBER="$SUB_NUMBER" EMIT_PHASE_NAME="spec"` を追加する
   - `tests/run-auto-sub.bats` の `setup()` に `emit-event.sh` のモックを追加: `cat > "$MOCK_DIR/emit-event.sh" <<'MOCK'` / `emit_event() { :; }` / `MOCK`
   - `tests/emit-event.bats` を新規作成: JSONL への書き込み・flock による排他の基本テストを追加

2. **`scripts/claude-watchdog.sh` 修正**（→ AC: `watchdog_kill` kill コードパスに event emission）
   - `_run_with_watchdog()` の先頭で `_max_unchanged_time=0` を初期化する
   - 既存の `unchanged_time` 更新コード（`unchanged_time=$((unchanged_time + _CHECK_INTERVAL))`）の直後に `(( unchanged_time > _max_unchanged_time )) && _max_unchanged_time=$unchanged_time` を追加する
   - `OUTPUT_FORMAT_JSON` が `1` の場合はファイルサイズ検査をスキップし、プロセス死活（`kill -0 "$cmd_pid"`）のみで待機するブランチを追加する（`unchanged_time` は経過秒としてカウントし続ける）
   - **kill 条件の明示**: 新ブランチでも `unchanged_time >= WATCHDOG_TIMEOUT` を検出したら従来同様に `kill` する。違いは「ファイルサイズが増えなくても kill しない」だけで、total timeout による kill は維持する。これがないと OUTPUT_FORMAT_JSON モードで watchdog が永遠にハングする（2026-06-14 #630 復旧時の知見）。
   - 既存の `kill "$cmd_pid"` の直前（`_watchdog_killed=true` より前）に `_auto_emit_watchdog_kill()` を呼ぶ: `AUTO_EVENTS_LOG` が設定済みかつ `emit_event` 関数が利用可能な場合に `emit_event "watchdog_kill" "phase=${EMIT_PHASE_NAME:-unknown}" "pid=${cmd_pid}" "silent_window_sec=${unchanged_time}" "timeout_setting=${WATCHDOG_TIMEOUT}"` を実行する
   - `wait "$cmd_pid" 2>/dev/null` の直後に `_auto_emit_max_silent()` を呼ぶ: 同条件で `emit_event "max_silent_window" "phase=${EMIT_PHASE_NAME:-unknown}" "max_sec=${_max_unchanged_time}"` を実行する
   - `emit_event` を watchdog 内で利用するため、スクリプト先頭（`set -uo pipefail` 直後）に `[[ -n "${AUTO_EVENTS_LOG:-}" ]] && [[ -f "$(dirname "$0")/emit-event.sh" ]] && source "$(dirname "$0")/emit-event.sh" || true` を追加する
   - `tests/claude-watchdog.bats` に `OUTPUT_FORMAT_JSON=1` での正常終了テストと `AUTO_EVENTS_LOG` 設定時の `watchdog_kill` event ファイル記録テストを追加する
   - **テスト hang 防止**: bats テストでは `WATCHDOG_TIMEOUT` を小さい値（例: 2-5 秒）に上書きしてから fixture プロセス（`sleep 1` 等）を実行する。本番の `1800s` で待つテストは禁止（2026-06-14 #630 で 1800s 真ハングを観測）。kill コードパスのテストは `WATCHDOG_TIMEOUT=2 ... claude-watchdog.sh sleep 10` 形式で 2 秒で kill されることを assert する。

3. **`scripts/wait-ci-checks.sh` 修正**（→ AC: `ci_wait` event emission）
   - スクリプト先頭（PR_NUMBER 取得直後）に `_ci_wait_start=$(date +%s)` を追加する
   - `gh pr checks` の出力を `_ci_checks_output` 変数に保存するよう修正する（既存の `|| true` パターンを維持）
   - スクリプト末尾の `echo "CI check wait complete..."` の直前に以下を追加する:
     - `_ci_wait_end=$(date +%s); _wait_sec=$(( _ci_wait_end - _ci_wait_start ))`
     - `_passed=$(echo "${_ci_checks_output:-}" | grep -c "pass\|success" 2>/dev/null || echo 0)`
     - `_failed=$(echo "${_ci_checks_output:-}" | grep -c "fail\|error" 2>/dev/null || echo 0)`
     - `emit_event "ci_wait" "phase=${EMIT_PHASE_NAME:-review}" "wait_sec=${_wait_sec}" "checks_passed=${_passed}" "checks_failed=${_failed}"`
   - `emit_event` を wait-ci-checks 内で利用するため: `SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"` を追加し、`[[ -n "${AUTO_EVENTS_LOG:-}" ]] && source "$SCRIPT_DIR/emit-event.sh" || true` を追加する
   - `tests/wait-ci-checks.bats` に `AUTO_EVENTS_LOG` 設定時の `ci_wait` event 記録テストを追加する

4. **`scripts/run-code.sh` / `run-review.sh` / `run-merge.sh` 修正 + `run-auto-sub.sh` への event 追加**（→ AC: token_usage / concurrent_commit_detected / test_result が scripts/ に存在）
   - 各 `run-*.sh` で、`AUTO_EVENTS_LOG` が設定済みの場合に `--output-format json` + `OUTPUT_FORMAT_JSON=1` を使用し TOKEN_USAGE_FILE へキャプチャするブランチを追加する:
     ```bash
     # 挿入箇所: claude-watchdog.sh 呼び出しの直前
     if [[ -n "${AUTO_EVENTS_LOG:-}" ]]; then
       TOKEN_USAGE_FILE=".tmp/token-usage-${ISSUE_NUMBER}.json"
       ANTHROPIC_MODEL=... OUTPUT_FORMAT_JSON=1 \
         "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
           --model ... --effort ... --output-format json $PERMISSION_FLAG \
           > "$TOKEN_USAGE_FILE" 2>&1
       EXIT_CODE=$?
       # テキスト内容を log_file に補完（detect-wrapper-anomaly 互換）
       jq -r '.result // empty' "$TOKEN_USAGE_FILE" 2>/dev/null || true
     else
       # 既存の watchdog 呼び出し（変更なし）
       ...
     fi
     ```
   - `run-auto-sub.sh` の `run_phase_with_recovery()` 内、`emit_event "wrapper_exit"` の直後に以下を追加する:
     - **token_usage**: `TOKEN_USAGE_FILE=".tmp/token-usage-${issue}.json"` が存在する場合、`jq` で `usage` を抽出し `emit_event "token_usage" "phase=${phase}" "model=..." "input_tokens=..." "output_tokens=..." "cache_read_tokens=..."` を実行する; ファイルが存在しない場合はスキップ
     - **concurrent_commit_detected**: `PHASE_START` 変数（`phase_start` emit 直前に `PHASE_START=$(date +%s)` として記録）を使い `git log origin/main --since="@${PHASE_START}" --format="%H %an" 2>/dev/null` を実行; 1行以上あれば各コミットに対し `emit_event "concurrent_commit_detected" "phase=${phase}" "commit_sha=..." "author=..." "since_phase_start_sec=..."` を実行する
     - **test_result**: `log_file` に bats 出力パターン (`grep -E "[0-9]+ tests?, [0-9]+ failures?"`) がある場合、`emit_event "test_result" "phase=${phase}" "framework=bats" "passed=..." "failed=..." "pattern=unit"` を実行する（code phase のみ）

5. **`docs/reports/event-log-schema.md` 新規作成 + `docs/structure.md` 更新**（→ AC: schema が文書化されている）
   - `docs/reports/event-log-schema.md` を新規作成する。内容:
     - 既存 event (`sub_start`, `phase_start`, `wrapper_exit`, `recovery`, `phase_complete`, `sub_complete`, `anomaly`, `size_refresh`) の一覧と後方互換保証の宣言
     - 6 新 event それぞれについて: JSON example, 必須フィールド（`ts`, `issue`, `event`, `phase` など）, 任意フィールド, emission point, 後方互換保証（フィールド追加のみ・削除/型変更なし）
   - `docs/structure.md` の `scripts/` ファイル数コメントを `(53 files)` → `(54 files)` に更新する（`emit-event.sh` 追加）と、Key Files の Scripts セクションに `scripts/emit-event.sh` の説明行を追加する

## Verification

### Pre-merge

- <!-- verify: grep "token_usage|watchdog_kill|max_silent_window|concurrent_commit_detected|ci_wait|test_result" "scripts/" --> 各 `run-*.sh` で新 event の emit_event が実装されている
- <!-- verify: grep "watchdog_kill" "scripts/claude-watchdog.sh" --> kill コードパスに event emission がある
- <!-- verify: grep "ci_wait" "scripts/wait-ci-checks.sh" --> CI 待機開始/終了に event emission がある
- <!-- verify: file_exists "docs/reports/event-log-schema.md" --> event schema が文書化されている
- <!-- verify: rubric "docs/reports/event-log-schema.md documents all 6 new event types (token_usage, watchdog_kill, max_silent_window, concurrent_commit_detected, ci_wait, test_result) with required fields, optional fields, emission point, and backward-compatibility guarantee" --> schema が rubric 基準（6 event 種・必須/任意フィールド・emission point・後方互換）を満たす
- <!-- verify: file_contains "docs/reports/event-log-schema.md" "token_usage" --> schema が token_usage event を含む（rubric の補足確認）
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テストが green（各 event 種の最小 1 ケースずつ・PR route）

### Post-merge

- 次回 `/auto` 実行で `.tmp/auto-events.jsonl` に 6 種類の新 event が記録されることを観察 <!-- verify-type: observation event=auto-run -->

## Notes

- `token_usage` emission スコープ: code / review / merge phase のみ（`run_phase_with_recovery()` 経由のもの）。spec phase は `run-auto-sub.sh` から直接呼び出されるため対象外。
- `OUTPUT_FORMAT_JSON=1` は `claude-watchdog.sh` のプロセス死活ベース待機モードのシグナル。`--output-format json` との組み合わせで使用する。ファイルサイズ非増加のまま全出力が最後に来る json モードでも誤 kill を防ぐ。
- TOKEN_USAGE_FILE のテキスト補完（`jq -r .result`）は `detect-wrapper-anomaly.sh` との互換維持のため必須。log_file にはテキスト内容が補完されることで既存のパターンマッチが機能し続ける。
- `concurrent_commit_detected` のポーリング間隔は phase 完了時の一括チェック（30s 周期ポーリングなし、オーバーヘッド最小化）。
- `wait-ci-checks.sh` の `checks_passed` / `checks_failed` は `gh pr checks` の stdout テキストから `grep -c` で推定するため精度は近似値。
- **Issue body との不一致**: Issue body の verify command 第 1 項は `grep "token_usage|watchdog_kill|..."` と `|` を用いた OR パターンが指定されているが、`verify-executor` はパスを単一引数として解釈するため、`"scripts/"` ディレクトリ指定に変更し、event ごとに個別 verify command に分割した（Auto-Resolved Ambiguity Point 1 の実装反映）。Spec の verify command を Issue body の `<!-- verify: ... -->` と同期更新済み（Step 10 verify-type tag check の結果）。
- `docs/structure.md` の scripts ファイル数は `grep -c "^- " docs/structure.md` ではなく実ファイル数（54）を使用する。verify command: `grep "(54 files)" "docs/structure.md"`。

## Alternatives Considered

(ISSUE_TYPE=Feature, SPEC_DEPTH=light のため省略)

## Uncertainty

- `--output-format stream-json --verbose` を使用すると `detect-wrapper-anomaly.sh` が JSON ストリームからパターンを検出できない懸念があった → `--output-format json` + TOKEN_USAGE_FILE へのリダイレクト + `jq -r .result` でテキスト補完するアプローチを採用することで解決する。
