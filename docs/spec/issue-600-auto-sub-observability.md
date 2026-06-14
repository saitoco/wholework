# Issue #600: auto: run-auto-sub.sh の parent 観測性改善（per-issue ログプレフィックス + JSONL イベントログ）

## Overview

`/auto` XL route での `run-auto-sub.sh` 並列実行時、parent セッションが出力インタリーブや phase 内沈黙により状況を把握しにくい。

Lv1（per-issue ログプレフィックス `[#N]`）と Lv2（構造化 JSONL イベントログ `.tmp/auto-events.jsonl`）を最小コストで追加し、観測性を改善する。

- Lv1: 全 `echo` を `${LOG_PREFIX}` プレフィックス付きに統一。並列実行時に `grep "^\[#N\]"` で 1 sub-issue の stdout を抽出可能にする
- Lv2: `emit_event()` 関数でイベントを JSON Lines として `flock` 排他付きで追記。`tail -f | jq` によるライブ監視を可能にする

## Changed Files

- `scripts/run-auto-sub.sh`: `LOG_PREFIX` 変数追加・全 echo プレフィックス化、`AUTO_EVENTS_LOG` 変数・`emit_event()` 関数追加、6 種類のイベント呼び出し挿入 — bash 3.2+ 互換
- `tests/auto-sub-observability.bats`: 新規ファイル — プレフィックス検証・JSONL 形式検証・append 動作の最低 3 ケース
- `docs/structure.md`: tests/ ファイル数コメントを 67 → 69 に更新
- `docs/ja/structure.md`: tests/ ファイル数コメントを 67 ファイル → 69 ファイル に更新（Japanese mirror sync）

## Implementation Steps

1. **`run-auto-sub.sh`: LOG_PREFIX 追加・全 echo プレフィックス化** (→ AC1, AC2)
   - `SIZE` 変数定義直後（行 39 の SCRIPT_DIR 設定後、`run_phase_with_recovery` 関数定義の前）に `LOG_PREFIX="[#${SUB_NUMBER}]"` を追加
   - メイン処理ブロック（行 85〜）の全 `echo "..."` を `echo "${LOG_PREFIX} ..."` に変換
   - `run_phase_with_recovery` 内の recovery echo（`[anomaly]`, `[recovery]`）にも `${LOG_PREFIX} ` プレフィックスを付加

2. **`run-auto-sub.sh`: AUTO_EVENTS_LOG + emit_event() 追加** (→ AC3, AC4, AC5)
   - `LOG_PREFIX` 定義の直後に `AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"` を追加
   - `run_phase_with_recovery` 関数定義の直前に `emit_event()` 関数を追加。JSON フィールドは positional `key=value` 引数で渡す。flock パターン:
     ```bash
     emit_event() {
       local event_type="$1"; shift
       local ts; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
       local json="{\"ts\":\"${ts}\",\"issue\":${SUB_NUMBER},\"event\":\"${event_type}\""
       while [[ $# -gt 0 ]]; do
         local kv="$1"; local k="${kv%%=*}"; local v="${kv#*=}"
         json="${json},\"${k}\":\"${v}\""
         shift
       done
       json="${json}}"
       mkdir -p "$(dirname "${AUTO_EVENTS_LOG}")"
       (flock -x 200; echo "${json}" >> "${AUTO_EVENTS_LOG}") 200>"${AUTO_EVENTS_LOG}.lock"
     }
     ```

3. **`run-auto-sub.sh`: emit_event 呼び出し 6 箇所挿入** (→ AC6)
   - `sub_start`: SIZE プリフェッチ（行 95）直後、spec フェーズ分岐前に `emit_event "sub_start" "size=${SIZE}"`
   - `phase_start`: `run_phase_with_recovery` 内、`log_file` 設定直後に `emit_event "phase_start" "phase=${phase}"`
   - `wrapper_exit`: `exit_code=$?` の直後に `emit_event "wrapper_exit" "phase=${phase}" "exit_code=${exit_code}"`
   - `recovery`: 各 tier の recovery echo 直後に `emit_event "recovery" "phase=${phase}" "tier=N" "result=recovered"`（N は 1/2/3）
   - `phase_complete`: `run_phase_with_recovery` が return 0 する各箇所の直前に `emit_event "phase_complete" "phase=${phase}"`
   - `sub_complete`: スクリプト末尾 `exit 0` 直前に `emit_event "sub_complete" "exit_code=0"`

4. **`tests/auto-sub-observability.bats`: 新規作成** (→ AC7)
   - setup は `run-auto-sub.bats` と同じモック構成（WHOLEWORK_SCRIPT_DIR + PATH 経由で gh/flock を差し替え）
   - `flock` モック: `$MOCK_DIR/flock` に `#!/bin/bash\nexit 0` を配置（macOS 非互換回避）
   - `AUTO_EVENTS_LOG="$BATS_TEST_TMPDIR/.tmp/auto-events.jsonl"` をエクスポートして隔離
   - テスト 3 ケース（最低限）:
     - **prefix-check**: `bash "$SCRIPT" 42` 実行、stdout に `[#42]` が含まれること
     - **event-format-check**: 実行後、`$AUTO_EVENTS_LOG` に `"event":` フィールドを含む JSON 行が存在すること
     - **append-no-clobber**: `bash "$SCRIPT" 42` を 2 回実行し、ログに 2 件以上のエントリが存在すること（append 動作の確認）

5. **`docs/structure.md` + `docs/ja/structure.md` テスト数更新** (SHOULD)
   - `docs/structure.md`: `tests/               # Bats test files for scripts (67 files)` → `(69 files)` に変更
   - `docs/ja/structure.md`: `（67 ファイル）` → `（69 ファイル）` に変更

## Verification

### Pre-merge

- <!-- verify: grep "LOG_PREFIX" "scripts/run-auto-sub.sh" --> `run-auto-sub.sh` に `LOG_PREFIX` 変数が定義されている
- <!-- verify: grep "\[#" "scripts/run-auto-sub.sh" --> `run-auto-sub.sh` の echo に `[#...` プレフィックスが付与されている
- <!-- verify: grep "emit_event" "scripts/run-auto-sub.sh" --> `emit_event()` 関数が実装されている
- <!-- verify: file_contains "scripts/run-auto-sub.sh" "auto-events.jsonl" --> JSONL イベントログへの書き込みパスが参照されている
- <!-- verify: grep "flock" "scripts/run-auto-sub.sh" --> 並列書き込み対策の flock が使用されている
- <!-- verify: rubric "scripts/run-auto-sub.sh emits at minimum 6 event types (sub_start, phase_start, wrapper_exit, recovery with tier+result, phase_complete, sub_complete) as JSON Lines to .tmp/auto-events.jsonl with flock for parallel safety" --> 6 種類の event が JSON Lines で append され、flock で排他制御されている
- <!-- verify: command "bats tests/auto-sub-observability.bats" --> bats テストが green（プレフィックス検証 / event 形式検証 / 並列 append 競合テストの最小 3 ケース）
- <!-- verify: command "bash -n scripts/run-auto-sub.sh" --> 構文エラーなし

### Post-merge

- 実 XL Issue で並列実行時に `grep "^\[#N\]" stdout` で 1 sub-issue のログ抽出ができることを確認 <!-- verify-type: observation event=auto-run -->
- `tail -f .tmp/auto-events.jsonl | jq` でライブ監視可能なことを確認 <!-- verify-type: observation event=auto-run -->

## Notes

- **flock macOS 非互換**: `flock` は macOS 標準では利用不可。bats テストでは `$MOCK_DIR/flock`（no-op シェルスクリプト）を PATH 先頭に置いて回避。CI（Ubuntu）では実 flock が利用可能
- **SPEC_DEPTH=light Simplicity rule**: 受入条件は Issue body 準拠（8 項目）。light の 5 項目上限を超えるが、Issue body 起源のため verify command sync rule を優先
- **docs/structure.md test count**: 現在実際のファイル数は 68（xl-decomposition.bats が既に追加済みだが structure.md が未更新）。本 Issue で +1 し合計 69 に修正
- **emit_event の sub_start タイミング**: SIZE は `get-issue-size.sh` プリフェッチ後に取得（空の場合あり）。route はこの時点では未確定のため、sub_start イベントには `size` のみ含め route は phase ごとのイベントから読み取ることとする
- **detect-wrapper-anomaly.sh モック**: 既存 run-auto-sub.bats と同じく `|| true` によりモック不要

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- REVIEW_DEPTH=light（Size=M、--light フラグ）で実行。review-light エージェント 1 本で 4 観点を網羅
- MUST 所見ゼロ、CONSIDER 所見 2 件（いずれも既知・対応不要）のため COMMENT イベントで投稿
- 全8件の受け入れ条件が PASS。`command` ヒントは CI 参照フォールバック（Run bats tests / macOS shell compatibility SUCCESS）で代替

### Deferred Items
- `sub_complete` のエラー終了パスへの emit（`trap` による改善）は別 Issue として保留（Spec スコープ外）
- `flock` macOS 非互換による `emit_event` 失敗の graceful fallback は引き続き別 Issue として保留

### Notes for Next Phase
- MUST 所見なし → `/merge 625` で即マージ可能
- Post-merge AC（observation event=auto-run 2件）は実 XL 実行時に確認が必要

## Code Retrospective

### Deviations from Design

- `emit_event "phase_start"` の配置を Spec の「`log_file` 設定直後」通りに実装した。ただし実際には `set +e` の前に置いたため、`emit_event` が失敗するとスクリプト全体が abort する点に注意（flock の macOS 非互換が本番で顕在化した場合に影響）。CI（Ubuntu）では問題なし
- 既存テスト `tests/run-auto-sub.bats` に `flock` mock 追加が必要になった（Spec の Notes には「detect-wrapper-anomaly.sh モック不要」と記載していたが、`flock` mock については言及なし）。`emit_event` 導入により bats 全テストが 127 で失敗することが判明し、1 repair attempt で修正

### Design Gaps/Ambiguities

- Spec は `run_phase_with_recovery` 内で「`log_file` 設定直後に `phase_start`」と指定しているが、既存コードで `set +e` が `log_file` の次にあるため、`phase_start` を `set +e` の前に置くべきか後に置くべかを Spec が明示していなかった。前に置く実装を採用（`set +e` 外でのイベント emitting は正常動作を前提とする）
- `run-auto-sub.bats` が `flock` モックを持たないことは Spec の Notes で言及されていなかった。macOS での `flock` 不在は Notes に記載があったが、既存テストへの影響は記載なし

### Rework

- `tests/run-auto-sub.bats` への `flock` mock 追加（Spec 未記載の修正。既存テストが全て 127 で失敗したため 1 repair attempt で対応）

## review retrospective

### Spec vs. Implementation Divergence Patterns

- `sub_complete` は Spec 指定通り `exit 0` 直前にのみ emit されているが、エラー終了パスへの emit が Spec に記載されていないため、失敗時は観測性ギャップとして残る。次回同類 Issue では「全終了パスで emit する場合は `trap` を使用する」旨を Spec に明記することで、code フェーズでの実装ミスを防げる
- `emit_event "phase_start"` の `set +e` 前後配置は Spec が明示していなかったため code フェーズで判断が発生した。shell スクリプトで `set -e` 環境依存の関数呼び出しを伴う場合は Spec に配置方針を明記するべき

### Recurring Issues

- Nothing to note（今回の review で繰り返しパターンの issue は確認されず）

### Acceptance Criteria Verification Difficulty

- `command "bats tests/auto-sub-observability.bats"` は safe モードで CI 参照フォールバックを使用した。"Run bats tests" ジョブとのマッピングが推論ベースであり、テスト名が変わった場合に UNCERTAIN になるリスクがある。`github_check "gh pr checks" "Run bats tests"` に変更するとより確実な verify になる
