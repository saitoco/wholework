# Issue #1312: get-auto-session-report: silent-window 警告閾値を watchdog の実解決経路に揃える

## Overview

`scripts/get-auto-session-report.sh` の Sub-Issue Completion Timeline は、phase の silent window が `<phase watchdog default> - 600s` を超えると "at-risk" 警告 (`within 600s of watchdog limit`) を出す。この閾値は `scripts/watchdog-defaults.sh` のグローバル既定値 (`WATCHDOG_TIMEOUT_*_DEFAULT`) から直接計算されており、同じファイルが公開する `load_watchdog_timeout()` — `.wholework.yml` の phase timeout override を解決する唯一の経路であり、`run-*.sh` 各フェーズラッパーが実際に watchdog kill を判定する際に使う関数 — を経由していない。プロジェクトが phase timeout を override すると (この repo は `spec`/`code`/`review` を override 済み)、警告基準と実 kill 基準が乖離する。本 Issue は `SILENT_THRESHOLD_*` の算出を `load_watchdog_timeout()` 経由に揃え、両基準を一致させる。

## Reproduction Steps

1. `.wholework.yml` に phase override を設定する — 例: `watchdog-timeout-spec-seconds: 2340` (この repo は #1301 により既に設定済み)。
2. spec フェーズの silent window が、既定閾値 (`1800-600=1200s`) と override 後閾値 (`2340-600=1740s`) の間に収まる `/auto` セッションを実行する — 例: 1310s。これは #1301 に対する実測値であり、session `92769-1786252094` (2026-08-09) で記録された (Issue 本文 Background の実測セクション参照)。
3. セッションの Metrics セクションを生成する: `scripts/get-auto-session-report.sh <session-id> --metrics-only`。
4. Sub-Issue Completion Timeline の Notes 列に `Silent 1310s phase=spec (within 600s of watchdog limit)` が表示される — 実際の余裕 (`2340-1310=1030s`) は 600s 以内ではなく、実 watchdog が kill に近づいた事実はない。

## Root Cause

`scripts/get-auto-session-report.sh:22-29`:

```bash
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
[[ -f "$SCRIPT_DIR/emit-event.sh" ]] && source "$SCRIPT_DIR/emit-event.sh" || true
[[ -f "$SCRIPT_DIR/watchdog-defaults.sh" ]] && source "$SCRIPT_DIR/watchdog-defaults.sh" || true
SILENT_MARGIN=600
SILENT_THRESHOLD_SPEC=$(( ${WATCHDOG_TIMEOUT_SPEC_DEFAULT:-1800} - SILENT_MARGIN ))
SILENT_THRESHOLD_CODE=$(( ${WATCHDOG_TIMEOUT_CODE_DEFAULT:-1800} - SILENT_MARGIN ))
SILENT_THRESHOLD_REVIEW=$(( ${WATCHDOG_TIMEOUT_REVIEW_DEFAULT:-2000} - SILENT_MARGIN ))
SILENT_THRESHOLD_ISSUE=$(( ${WATCHDOG_TIMEOUT_ISSUE_DEFAULT:-1200} - SILENT_MARGIN ))
```

`watchdog-defaults.sh` は `WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800` などのグローバル既定値定数 (`scripts/watchdog-defaults.sh:29-33`) を source するためだけに使われており、同ファイルが公開する `load_watchdog_timeout()` (`scripts/watchdog-defaults.sh:35-57`) は呼ばれない。`load_watchdog_timeout()` は `watchdog-timeout-<phase>-seconds` (project override) → `watchdog-timeout-seconds` (global override) → phase 別 `*_DEFAULT` 定数、の順で `get-config-value.sh` 経由で解決する関数で、`run-spec.sh:168` / `run-code.sh:249` / `run-review.sh:235` / `run-issue.sh:109` / `run-merge.sh:141` の全フェーズラッパーが実際の kill 判定に使っている。`get-auto-session-report.sh` はこの解決を経ずに `*_DEFAULT` 定数を直読みするため、この repo が現在設定している 3 件の override (`watchdog-timeout-spec-seconds: 2340`, `watchdog-timeout-code-seconds: 7200`, `watchdog-timeout-review-seconds: 5400`) はすべて at-risk 警告から見えない。

## Changed Files

- `scripts/get-auto-session-report.sh`: `SILENT_THRESHOLD_SPEC`/`_CODE`/`_REVIEW`/`_ISSUE` の算出を、`WATCHDOG_TIMEOUT_*_DEFAULT` グローバル変数の直接参照から `load_watchdog_timeout()` 経由 (`.wholework.yml` の phase override を解決) へ変更する — bash 3.2+ compatible を維持
- `tests/get-auto-session-report.bats`: `.wholework.yml` の phase override が at-risk 閾値に反映されること、および override 未設定時は phase 既定値へフォールバックすることを検証する bats テストを 2 件追加する
- `tests/audit-auto-session.bats`: 既存の「phase silent window threshold violation」テスト (:118-138) に `WHOLEWORK_CONFIG_PATH=/dev/null` を追加し、この repo 自身の `.wholework.yml` override (`watchdog-timeout-spec-seconds: 2340`) に依存しない hermetic 実行にする (Step 6 のコードベース調査で発見した回帰リスクへの対処)

## Implementation Steps

1. `scripts/get-auto-session-report.sh` の `SILENT_THRESHOLD_*` 算出 (:25-29) を修正する (→ AC1, AC2)

   `SILENT_MARGIN=600` 定数はそのまま維持し、以降の 4 行を `load_watchdog_timeout()` 呼び出しに置き換える:

   ```bash
   SILENT_MARGIN=600
   if command -v load_watchdog_timeout >/dev/null 2>&1; then
     load_watchdog_timeout "$SCRIPT_DIR" "spec";   SILENT_THRESHOLD_SPEC=$(( WATCHDOG_TIMEOUT - SILENT_MARGIN ))
     load_watchdog_timeout "$SCRIPT_DIR" "code";   SILENT_THRESHOLD_CODE=$(( WATCHDOG_TIMEOUT - SILENT_MARGIN ))
     load_watchdog_timeout "$SCRIPT_DIR" "review"; SILENT_THRESHOLD_REVIEW=$(( WATCHDOG_TIMEOUT - SILENT_MARGIN ))
     load_watchdog_timeout "$SCRIPT_DIR" "issue";  SILENT_THRESHOLD_ISSUE=$(( WATCHDOG_TIMEOUT - SILENT_MARGIN ))
   else
     # watchdog-defaults.sh was not sourced (missing sibling script; guarded at :24 above).
     # Disable the at-risk breakdown via the same "$at_risk_limit > 0" sentinel already used
     # to exclude the merge phase (:241, :403), instead of duplicating stale default constants.
     SILENT_THRESHOLD_SPEC=-1
     SILENT_THRESHOLD_CODE=-1
     SILENT_THRESHOLD_REVIEW=-1
     SILENT_THRESHOLD_ISSUE=-1
   fi
   ```

   `load_watchdog_timeout` は呼び出しごとに単一のグローバル変数 `WATCHDOG_TIMEOUT` を設定する関数のため、4 回連続で呼び出し、都度 `SILENT_MARGIN` を引いた値を phase 別変数へ読み出す。`:24` の `[[ -f ... ]] && source ... || true` (このスクリプト固有の任意依存パターン) は変更しない — `command -v load_watchdog_timeout` によるガードは、その既存パターンと整合させて sourcing 失敗時も安全に degrade させるためのもの (詳細は Notes 参照)。

2. (after 1) `tests/audit-auto-session.bats` の既存テスト「success: phase silent window threshold violation appears in Summary and Notes」(:118-138) を hermetic 化する (→ AC5 の回帰防止)

   フィクスチャ書き込み後・`run bash "$SCRIPT" ...` の前に以下を追加する:

   ```bash
   export WHOLEWORK_CONFIG_PATH=/dev/null
   ```

   `tests/get-auto-session-report.bats` 側の既存 2 テスト (Tier 2 candidate surfacing 系, :111 / :139) と同じ hermetic 化パターンを踏襲する。

3. (parallel with 2) `tests/get-auto-session-report.bats` に override 反映とフォールバック検証の bats テストを 2 件追加する (→ AC4)。挿入位置: 既存最終テスト「Timeline route: Size downgrade and upgrade fixtures report executed-phase route in the row」(:342-359) の直後。

   両テストとも issue=1301, phase=spec, `max_sec` は実測値 "1310" (Issue Background の実測値と同一 — 文字列として emit される実際の `max_silent_window` イベント形式に合わせ、`"max_sec":"1310"` とクォートする) を共有し、`WHOLEWORK_CONFIG_PATH` のみを差し替える:

   ```bash
   @test "at-risk threshold honors .wholework.yml phase override: no false positive within headroom" {
       cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
   {"ts":"2026-08-09T10:00:00Z","issue":1301,"event":"sub_start","session_id":"session-1312-override","size":"S"}
   {"ts":"2026-08-09T10:01:00Z","issue":1301,"event":"phase_start","session_id":"session-1312-override","phase":"spec"}
   {"ts":"2026-08-09T10:22:50Z","issue":1301,"event":"max_silent_window","session_id":"session-1312-override","phase":"spec","max_sec":"1310"}
   {"ts":"2026-08-09T10:22:51Z","issue":1301,"event":"phase_complete","session_id":"session-1312-override","phase":"spec"}
   {"ts":"2026-08-09T10:22:52Z","issue":1301,"event":"sub_complete","session_id":"session-1312-override","exit_code":"0"}
   FIXTURE_EOF
       CONFIG_FIXTURE="$BATS_TEST_TMPDIR/wholework-override.yml"
       cat > "$CONFIG_FIXTURE" << 'YAML_EOF'
   watchdog-timeout-spec-seconds: 2340
   YAML_EOF
       export WHOLEWORK_CONFIG_PATH="$CONFIG_FIXTURE"

       run bash "$SCRIPT" "session-1312-override" --metrics-only --no-github
       [ "$status" -eq 0 ]
       # override threshold = 2340 - 600 = 1740s; observed 1310s stays under it
       if echo "$output" | grep -q "within 600s of watchdog limit"; then false; fi
       echo "$output" | grep -q "Phase silent windows > threshold | 0"
   }

   @test "at-risk threshold falls back to phase default when no override is configured" {
       cat > "$AUTO_EVENTS_LOG" << 'FIXTURE_EOF'
   {"ts":"2026-08-09T10:00:00Z","issue":1301,"event":"sub_start","session_id":"session-1312-default","size":"S"}
   {"ts":"2026-08-09T10:01:00Z","issue":1301,"event":"phase_start","session_id":"session-1312-default","phase":"spec"}
   {"ts":"2026-08-09T10:22:50Z","issue":1301,"event":"max_silent_window","session_id":"session-1312-default","phase":"spec","max_sec":"1310"}
   {"ts":"2026-08-09T10:22:51Z","issue":1301,"event":"phase_complete","session_id":"session-1312-default","phase":"spec"}
   {"ts":"2026-08-09T10:22:52Z","issue":1301,"event":"sub_complete","session_id":"session-1312-default","exit_code":"0"}
   FIXTURE_EOF
       export WHOLEWORK_CONFIG_PATH=/dev/null
       run bash "$SCRIPT" "session-1312-default" --metrics-only --no-github
       [ "$status" -eq 0 ]
       # default threshold = 1800 - 600 = 1200s; observed 1310s exceeds it
       echo "$output" | grep -q "within 600s of watchdog limit"
       echo "$output" | grep -q "Phase silent windows > threshold | 1 (spec:1)"
   }
   ```

4. (after 1, 2, 3) `bats tests/get-auto-session-report.bats tests/audit-auto-session.bats` を実行し、両ファイル全件が PASS することを確認する (→ AC5)

## Verification

### Pre-merge

- <!-- verify: rubric "get-auto-session-report.sh の SILENT_THRESHOLD_* 算出が、WATCHDOG_TIMEOUT_*_DEFAULT のグローバル変数を直接参照するのではなく、.wholework.yml の override を解決する load_watchdog_timeout() 経由になっている" --> SILENT_THRESHOLD_* の算出が load_watchdog_timeout() 経由になっている
- <!-- verify: grep "load_watchdog_timeout" "scripts/get-auto-session-report.sh" --> get-auto-session-report.sh が load_watchdog_timeout を参照している
- <!-- verify: rubric "load_watchdog_timeout() が .wholework.yml を解決できない環境での SILENT_THRESHOLD_* のフォールバック値と、その選択理由が Spec に記載されている" --> config 解決に失敗する環境でのフォールバック挙動と理由が Spec に記録されている
- <!-- verify: grep "load_watchdog_timeout|watchdog-timeout-spec-seconds" "tests/get-auto-session-report.bats" --> phase timeout override フィクスチャで at-risk 判定が override 後の値を基準にすることを検証する bats テストが追加されている
- <!-- verify: command "bats tests/get-auto-session-report.bats tests/audit-auto-session.bats" --> 両 bats ファイル全件が PASS する (回帰保護 — 単独では常時 PASS のため上記の新規テスト追加 AC と組で機能する。`tests/audit-auto-session.bats` は同一スクリプトを対象とする既存 silent-window テストを含み、この repo の override 適用後は hermetic 化が必要)

### Post-merge

- 次回 `/auto --batch` の完走後、`watchdog-timeout-spec-seconds: 2340` に対して余裕のある spec silent window (例: 1310s) が at-risk 警告を出さないことを観察する <!-- verify-type: observation event=auto-run -->

## Notes

- **AC3 フォールバック挙動の決定と理由 (Issue 本文の Auto-Resolved Ambiguity Points を正式記録)**: config 解決に失敗する環境 (リポジトリ外 / `.wholework.yml` にキー未設定 / hermetic bats で `WHOLEWORK_CONFIG_PATH=/dev/null`) では、`load_watchdog_timeout()` 自身の既存フォールバックラダー — `get-config-value.sh` が空値/失敗を返した場合は無条件で phase 別グローバル既定値 (`WATCHDOG_TIMEOUT_SPEC_DEFAULT` 等) に倒す — をそのまま踏襲する。新規の分岐は追加しない。理由: `run-issue.sh`/`run-spec.sh`/`run-code.sh`/`run-review.sh`/`run-merge.sh` の 5 箇所全てが同一関数を同じ意味で使用しており一貫性がある。`get-config-value.sh` 自体が「`.wholework.yml` 不在時はデフォルト値を返す」設計 (`scripts/get-config-value.sh` ヘッダコメント) のため、追加の分岐なしに安全にフォールバックする。
- **`watchdog-defaults.sh` が source されない場合の追加フォールバック (Implementation Step 1 の `else` 節)**: AC3 が扱う「config 解決失敗」とは別に、`watchdog-defaults.sh` 自体が sourced されない (`:24` の `[[ -f ]]` ガードが false になる — 通常operationでは起こらない壊れたチェックアウトのみ) 場合、`load_watchdog_timeout` 関数自体が未定義になる。この場合に旧来の stale な `${VAR:-1800}` 形式のインライン既定値を再導入すると、#939 の Spec Retrospective (`docs/spec/issue-939-fable-5-spec-watchdog-recalib.md:84`) が既に "stale fallback" として指摘した状態 (実際の既定値が #903 で 1800→4680/2000→5400 と更新された後も、インライン fallback の `:-1800`/`:-2000` だけが更新されず古いままになる) を再発させる。そのため `-1` センチネルを採用した — 既存の jq クエリ (`:241`, `:403` 付近) が merge フェーズを除外するのに使っている `$at_risk_limit > 0` ガードと同じ仕組みで、この場合は at-risk 判定自体を無効化する (新しい stale 値を作らない)。
- **`tests/audit-auto-session.bats` の hermetic 化が必要と判明した経緯**: `scripts/get-auto-session-report.sh` を対象とする bats テストは `tests/get-auto-session-report.bats` と `tests/audit-auto-session.bats` の 2 ファイルに分かれている (`grep -rln "get-auto-session-report" docs/ tests/ scripts/` で確認)。後者の「phase silent window threshold violation」テスト (:118-138) は `max_sec=1500`, phase=spec のフィクスチャで、`WHOLEWORK_CONFIG_PATH` を設定せず `--no-github` のみで実行される。bats はこの repo のルートで実行されるため、`WHOLEWORK_CONFIG_PATH` 未設定時は CWD 相対の実際の `.wholework.yml` (この repo 自身の `watchdog-timeout-spec-seconds: 2340`) が読まれる。Implementation Step 1 適用後、この override により閾値が `1200s` (既定) から `1740s` (override) に変わり、既存フィクスチャの `max_sec=1500` は `1740` を超えないため at-risk 判定されなくなり、`within 600s of watchdog limit` を assert する既存テストが FAIL する。Issue 本文には元々このファイルへの言及がなく (`tests/get-auto-session-report.bats` のみが AC4/AC5 の対象)、`/spec` のコードベース調査で発見したため、この Spec 作成時に Issue 本文 AC5 の verify command を拡張し (`bats tests/get-auto-session-report.bats` → `bats tests/get-auto-session-report.bats tests/audit-auto-session.bats`)、Spec の Verification 側と同期させた。`tests/get-auto-session-report.bats` 自体の既存 15 テストはいずれも `max_silent_window` イベントを生成しないため、この regression の影響を受けない (`grep -n "max_silent_window" tests/get-auto-session-report.bats` で 0 件を確認済み)。
- **Steering Docs sync candidate check 実施済み・変更不要**: `grep -rn "get-auto-session-report.sh\|load_watchdog_timeout\|SILENT_THRESHOLD\|SILENT_MARGIN\|within 600s of watchdog limit" docs/ tests/ scripts/` で横断検索した。`docs/structure.md`・`docs/tech.md` にヒットはあるが、いずれも `--metrics-only` の出力先や `WHOLEWORK_ISSUE_BODY_DIR` など本修正が変更しない一般的な説明であり、`SILENT_THRESHOLD_*` の解決経路には触れていない。`docs/spec/issue-666-*.md`・`issue-939-*.md`・`issue-1300-*.md` は過去の disposable Spec (docs/tech.md の "Spec-first (disposable)" 方針により編集対象外)。`docs/sessions/**` は過去セッションの記録でありビルド対象外。以上より追加のドキュメント変更は不要と判断した。
- **`SILENT_MARGIN=600` の妥当性は本 Issue のスコープ外**: Issue 本文 Notes の判断を踏襲し、固定マージンの是非は変更しない。
- Issue 本文には元々 CI 検証 AC (`github_check`) を含めていない (route 依存の形式選択は Size 確定後にしか決まらないため) — Size が M/L (pr route) と確定した場合、`/code` フェーズで `github_check` AC の追加要否を再検討する。

## Consumed Comments
No new comments since last phase.
