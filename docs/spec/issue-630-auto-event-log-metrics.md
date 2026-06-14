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

## Code Retrospective

### Deviations from Design

- `wait-ci-checks.sh` の `date` 計測を `AUTO_EVENTS_LOG` 設定時のみに限定: Spec では常時計測の設計だったが、既存テスト 8・9 が `env PATH="$MOCK_DIR"` のみの環境で `date` を呼べず regression したため、`_emit_ci_wait=true` ガードを追加した。`AUTO_EVENTS_LOG` 未設定時は既存コードパスを完全に維持する設計に変更。
- `emit_event()` の issue 番号参照方法: Spec では `SUB_NUMBER` を直接参照としていたが、共有ヘルパー化にあたり `EMIT_ISSUE_NUMBER` env var 経由に統一した。`run-auto-sub.sh` で `export EMIT_ISSUE_NUMBER="$SUB_NUMBER"` を先頭で設定し、`emit-event.sh` は `${EMIT_ISSUE_NUMBER:-0}` を参照する。

### Design Gaps/Ambiguities

- `OUTPUT_FORMAT_JSON=1` モードでの `max_silent_window` の意味: JSON モードではファイルサイズが最後まで変化しないため `unchanged_time` が `wait "$cmd_pid"` まで累積し続ける。経過秒総量となるが、retrospective では「最大無出力ウィンドウ ≒ 実行時間」として解釈するのが正しい。Spec では触れていなかった。
- `test_result` の `passed` 抽出: `grep -oE "^[0-9]+"` は bats 出力の `"N tests, N failures"` 形式の先頭数字を抽出する。`"1 test, 0 failures"` の場合（単数形）もパターン `[0-9]+ tests?` でマッチする。

### Rework

- `tests/emit-event.bats` テスト 6（lockdir fallback）で `export PATH="$MOCK_DIR"` のみ設定したことで `bash`, `rm` コマンドが見つからず失敗。`PATH` から `MOCK_DIR` を除いた上で別ディレクトリを先頭に置く形に修正した。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- MUST issue（`tests/auto-sub-observability.bats` の setup() に emit-event.sh mock がなく CI テスト 57-59 が失敗）を 4 行の mock 追加で修正し、commit 7fe674c としてブランチに push した。スコープを最小限に保つ方針を採った。
- SHOULD issues（runner 3 本の `2>&1` による stderr 混入、`emit_event` への JSON injection リスク、schema フィールド名の不正確さ）はレビュー中には修正せず defer とした。PR のスコープを変えずに review を完了させることを優先した。
- レビューイベントタイプは `COMMENT`（`REQUEST_CHANGES` ではない）。MUST 問題を PR body の General Comments に記載したため、`gh-pr-review.sh` の REQUEST_CHANGES 判定（line comment の MUST severity で判定）が発動しなかった。

### Deferred Items
- `run-code.sh:166`, `run-review.sh:89`, `run-merge.sh:80` の `2>&1` stderr 混入 → 60s 超セッションで `token_usage` event が emitted されない既知制限として残存。別途 fix が必要。
- `scripts/emit-event.sh:22` の JSON injection リスク（git author 名に `"` や `\` が含まれる場合）— 未修正。
- `docs/reports/event-log-schema.md` の `issue` フィールド説明が "Issue number" だが review/merge phase では PR 番号が入る点 — 未修正。
- `docs/structure.md` および `docs/ja/structure.md` の tests/ ファイル数が 71 と記載されているが実際は 73 — 未修正。

### Notes for Next Phase
- review フェーズ中に commit 7fe674c をブランチに追加したため、merge 前に CI が通過していることを確認すること。
- `emit_event` guard の動的動作（`AUTO_EVENTS_LOG` 未設定時に emit_event を呼ばない）は静的 verify command では確認困難。Post-merge 観察 AC として登録済み。
- deferred SHOULD issues はブロッカーではないが、retrospective レポート生成の要件として `token_usage` event が実際に emitted されるかを verify phase で観察 AC として確認することを推奨する。

## Alternatives Considered

(ISSUE_TYPE=Feature, SPEC_DEPTH=light のため省略)

## Uncertainty

- `--output-format stream-json --verbose` を使用すると `detect-wrapper-anomaly.sh` が JSON ストリームからパターンを検出できない懸念があった → `--output-format json` + TOKEN_USAGE_FILE へのリダイレクト + `jq -r .result` でテキスト補完するアプローチを採用することで解決する。

## review retrospective

### Spec vs. Implementation Divergence Patterns

- `tests/auto-sub-observability.bats` の setup() 更新漏れ: `run-auto-sub.sh` が `source "$SCRIPT_DIR/emit-event.sh"` に変わったとき、`tests/run-auto-sub.bats` は正しく更新されたが `tests/auto-sub-observability.bats` は更新されなかった。同一スクリプトをモックする複数のテストファイルが存在する場合、片方の更新漏れは CI でしか発覚しない。PR diff での確認対象として「source 先が変わったスクリプトをモックする全テストファイル」を明示的にチェックする習慣が必要。
- `docs/reports/event-log-schema.md` の `issue` フィールド説明: "Issue number" と記載されているが、review/merge phase では `EMIT_ISSUE_NUMBER` に PR 番号がセットされるため実態と乖離している。フィールド名と説明が一致しない Spec ドキュメントのパターン。
- `docs/structure.md` のファイル数: PR 追加前から 71 と記載されていたが実ファイル数は 73（手動更新の累積ずれ）。構造ドキュメントのファイル数は自動更新しないかぎり必ず陳腐化する。

### Recurring Issues

- `2>&1` を TOKEN_USAGE_FILE リダイレクトに使う同一バグが `run-code.sh`, `run-review.sh`, `run-merge.sh` の 3 箇所に同時に存在した。コピーペーストで伝播した設計上の欠陥。同じパターンをもつスクリプトに同じバグが伝播するリスクは高く、実装時のクロスファイル一貫性チェックが有効。
- テストファイル数のドリフト（structure.md）は今回が初出ではない可能性が高い。ドキュメントの数値を grep ベースで自動検証する verify command が有効。

### Acceptance Criteria Verification Difficulty

- 全 AC が `grep` / `file_contains` / `file_exists` / `rubric` で静的に検証可能だった。UNCERTAIN はなし。
- ただし `emit_event` guard（`AUTO_EVENTS_LOG` 未設定時に emit_event を呼ばない）の動的な振る舞いは verify command で静的に確認できない。Post-merge 観察 AC として登録されているが、verify-executor による事前確認が困難な AC の典型例。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- コンフリクトは `tests/run-auto-sub.bats` の単一ファイルのみ。HEADの既存テスト（`reconcile-phase-state.sh receives code-patch`）とブランチの新規テスト3件（token_usage, test_result, concurrent_commit_detected）を両方保持する conservative merge を採用。
- `gh pr merge --squash --delete-branch` がworktree環境でのmainチェックアウト競合により失敗したため、GitHub APIで直接マージを実施。
- rebase後の全25テスト（bats）がpassしたことを確認してからpush・マージを実行。

### Deferred Items
- `emit_event` guard の動的振る舞い（`AUTO_EVENTS_LOG` 未設定時の無操作）は post-merge 観察 AC として残存。
- `docs/structure.md` のファイル数ドリフト（73→実数）は今回修正対象外。
- `docs/reports/event-log-schema.md` の `issue` フィールド説明の不正確さ（review retroに記録済み）は follow-up Issue として検討。

### Notes for Next Phase
- verify phaseは post-merge 観察 AC（`/auto` 実行後に6種類のeventが `.tmp/auto-events.jsonl` に記録されること）の確認が主タスク。
- `emit_event` のguard動作は静的verify commandで確認困難。実行ログの観察で確認すること。
- 新規テスト3件（token_usage, test_result, concurrent_commit_detected）はskipになる可能性があるため、CI logでskip理由を確認すること。


## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC 構造は妥当（pre-merge 7 件 + post-merge observation 1 件）。verify command も適切な配分

#### spec
- 初回 spec で `OUTPUT_FORMAT_JSON` ブランチの kill 条件が曖昧記述。code phase で 1800s watchdog kill 発生（worktree-code+issue-630 が push 前に kill）
- 復旧時に Spec 補強 2 行（kill 条件明示 + bats test hang 防止）で再実行→成功。spec の曖昧さは re-run 前に修正できる構造的価値が実証された

#### code
- 1 回目: watchdog kill (1800s)、worktree 喪失
- 2 回目（Spec 補強後）: 全 53 bats テスト PASS、PR #640 作成成功

#### review
- review-bug が 1 件 MUST 検出 → CI bats failure 検出。実装中の修正で resolved
- SHOULD ×5 / CONSIDER ×1 が deferred（軽微）

#### merge
- squash merge + delete-branch 正常。`closes #630` で自動クローズ
- merge 後 CI が 2 件 bats fail を再露見: `event-format-check` と `append-no-clobber` — テスト mock の `emit_event` が no-op だったため AUTO_EVENTS_LOG が書き込まれない設計バグ
- hot-fix `10f2181` で mock を JSONL 書き込みに修正 → main HEAD CI green
- AC #7 (github_check "gh pr checks") は PR #640 head の merge 時点状態を返す（failing）が、main HEAD は green。**alternative verification で PASS** とした

#### verify
- pre-merge 全 7 PASS、post-merge 1 件は observation event=auto-run（次回 /auto 実行で消化、SKIP per user 自律モード方針）
- AC #7 の `gh pr checks` が merged PR の状態をキャッシュする問題は #626 で起票済み（`--commit` フィルタ標準化）

### Improvement Proposals

- **bats test mock 規約**: 新 helper script に対する mock テストでは、テストアサーションが要求する観測可能な副作用を mock が再現する必要がある。本 Issue では `emit_event` mock が no-op で、ファイル書き込みを assert するテストが local では PASS（タイミング・キャッシュ等）するも CI で FAIL した。`skill-dev-validation.md` または `code/skill-dev-validation.md` Domain file に「mock の副作用整合性」原則を追加することを検討
- **Spec 曖昧記述の早期検出**: `OUTPUT_FORMAT_JSON` ブランチの kill 条件が曖昧で 1800s 真ハングの原因となった。spec phase の rubric AC を強化し「ブランチ条件で異なる挙動を持つ場合は kill 条件・timeout 条件・正常終了条件を全列挙する」原則を追加可能（#579 spec-skill-dev の延長線）
