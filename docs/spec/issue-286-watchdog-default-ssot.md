# Issue #286: scripts/watchdog-timeout default SSoT

## Overview

6つの `scripts/run-*.sh` に `WATCHDOG_TIMEOUT` デフォルト値 `1800` がハードコードされており（`get-config-value.sh` 呼び出し第2引数と検証フォールバックの計2箇所/ファイル）、`modules/detect-config-markers.md` にも同値が記述されている（計7箇所）。SSoT が確立していないためデフォルト変更時に同期漏れが生じるリスクがある。

共有 bash ライブラリ `scripts/watchdog-defaults.sh` を新設し、`WATCHDOG_TIMEOUT_DEFAULT=1800` 定数と `load_watchdog_timeout` 関数を定義することで SSoT を確立する。全 `run-*.sh` は `source` してこの関数を呼び出すよう更新する。

## Changed Files

- `scripts/watchdog-defaults.sh`: new file — `WATCHDOG_TIMEOUT_DEFAULT=1800` 定数と `load_watchdog_timeout` 関数を定義する source 可能な shared lib。bash 3.2+ 互換
- `scripts/run-issue.sh`: `source "$SCRIPT_DIR/watchdog-defaults.sh"` 追加、WATCHDOG_TIMEOUT 設定 4 行を `load_watchdog_timeout "$SCRIPT_DIR"` 1 行に置換。bash 3.2+ 互換
- `scripts/run-spec.sh`: 同上。bash 3.2+ 互換
- `scripts/run-code.sh`: 同上。bash 3.2+ 互換
- `scripts/run-review.sh`: 同上。bash 3.2+ 互換
- `scripts/run-merge.sh`: 同上。bash 3.2+ 互換
- `scripts/run-verify.sh`: 同上。bash 3.2+ 互換
- `modules/detect-config-markers.md`: `watchdog-timeout-seconds` デフォルト値記述に `scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_DEFAULT` を SSoT として参照する注記を追加
- `tests/run-spec.bats`: `setup()` に `watchdog-defaults.sh` モックを追加（`WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` 使用のため必須）
- `tests/watchdog-defaults.bats`: `watchdog-defaults.sh` 単体テスト（新規）
- `docs/structure.md`: scripts/ 37→38 ファイル、tests/ 44→45 ファイルに更新、Key Files > Scripts に `watchdog-defaults.sh` エントリを追加
- `docs/ja/structure.md`: 同上（日本語版）

## Implementation Steps

1. `scripts/watchdog-defaults.sh` を新規作成（→受入条件 C）：
   - `WATCHDOG_TIMEOUT_DEFAULT=1800` を定義（SSoT）
   - `load_watchdog_timeout()` 関数：引数 `$1` に `SCRIPT_DIR` パスを受け取り、`"$1/get-config-value.sh" watchdog-timeout-seconds "$WATCHDOG_TIMEOUT_DEFAULT"` を呼び出す。バリデーション（非数値・0以下チェックで `${WATCHDOG_TIMEOUT_DEFAULT}` へ warning 付きフォールバック）を実行して `WATCHDOG_TIMEOUT` 変数にセット
   - bash 3.2+ で動作すること（`local`、`grep -qE`、`[[ ]]` のみ使用）
   - 実行権限不要（source 専用のため shebang のみ記述、chmod 不要）

2. 全 6 つの `scripts/run-*.sh` を更新（→受入条件 A, B）：
   - `source "$SCRIPT_DIR/phase-banner.sh"` の直後に `source "$SCRIPT_DIR/watchdog-defaults.sh"` を追加
   - 各ファイルの WATCHDOG_TIMEOUT 設定 4 行（`get-config-value.sh watchdog-timeout-seconds 1800`、`|| echo 1800`、if バリデーション、`WATCHDOG_TIMEOUT=1800` 再代入）を `load_watchdog_timeout "$SCRIPT_DIR"` 1 行に置換

3. `modules/detect-config-markers.md` を更新（→受入条件 D）：
   - マーカー定義テーブルの `watchdog-timeout-seconds` 行の「Value When false/Unset」セルを `` `1800` (see `scripts/watchdog-defaults.sh` `WATCHDOG_TIMEOUT_DEFAULT`) `` に変更
   - Processing Steps の `watchdog-timeout-seconds` 説明行に同様の参照注記を追加
   - Output Format の `WATCHDOG_TIMEOUT_SECONDS` 行に同様の参照注記を追加

4. `tests/run-spec.bats` の `setup()` を更新：
   - `$MOCK_DIR/phase-banner.sh` モック作成の直後に `watchdog-defaults.sh` モックを追加：`WATCHDOG_TIMEOUT_DEFAULT=1800` と `load_watchdog_timeout() { WATCHDOG_TIMEOUT=1800; }` を定義するだけの最小実装

5. `tests/watchdog-defaults.bats` を新規作成、`docs/structure.md` と `docs/ja/structure.md` を更新：
   - テスト内容: source 後に `WATCHDOG_TIMEOUT_DEFAULT=1800` が設定されること、`load_watchdog_timeout` が有効値取得時に `WATCHDOG_TIMEOUT` をその値にセットすること、無効値（"abc"、"-1"）で warning を stderr に出力して `1800` にフォールバックすること（`get-config-value.sh` はモックで差し替え）
   - `docs/structure.md`: `scripts/ (37 files)` → `(38 files)`、`tests/ (44 files)` → `(45 files)`、Key Files > Scripts > **Process management** セクションに `scripts/watchdog-defaults.sh — sourceable helper providing WATCHDOG_TIMEOUT_DEFAULT constant and load_watchdog_timeout function for run-*.sh scripts` エントリを追加（`claude-watchdog.sh` の直前）
   - `docs/ja/structure.md`: 同上（ファイル数更新とエントリ追加を日本語で）

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/run-issue.sh" "watchdog-timeout-seconds 1800" --> `scripts/run-issue.sh` の `get-config-value.sh` 呼び出し第2引数から `1800` ハードコードが除去されている
- <!-- verify: rubric "scripts/run-spec.sh, run-code.sh, run-review.sh, run-merge.sh, run-verify.sh のすべてにおいて get-config-value.sh 呼び出しの watchdog-timeout-seconds 第2引数 1800 が除去され、バリデーション時の echo 1800 フォールバックも除去されている" --> 残り5つの `run-*.sh` からもハードコード `1800` が除去されている
- <!-- verify: rubric "WATCHDOG_TIMEOUT のデフォルト値が単一の共有ファイル（shared lib / get-config-value.sh 内部 / 共通 init スクリプトのいずれか）で定義され、全 run-*.sh がそれを参照している" --> デフォルト値の SSoT が確立されている
- <!-- verify: rubric "modules/detect-config-markers.md の watchdog-timeout-seconds デフォルト値記述（テーブル行・説明文・Output セクション）が、新たに確立した SSoT の値または参照先と一貫した形で更新されている" --> `modules/detect-config-markers.md` のデフォルト値記述が更新されている

### Post-merge

- `.wholework.yml` に `watchdog-timeout-seconds` 未設定の環境で全 `run-*.sh` が従来通り 1800 秒でタイムアウト動作する

## Notes

**自動解決（非対話モード）: 実装アプローチ選択**

Issue Proposal の3案のうち「shared bash lib 方式」（案1）を採用。

- 根拠：全 `run-*.sh` がすでに `source "$SCRIPT_DIR/phase-banner.sh"` パターンを使用しており、同一方式で追加可能。既存パターンとの一貫性を優先
- `load_watchdog_timeout` 関数として検証ロジックも共通化することで、4行×6ファイルの重複を1行×6ファイルに削減し可読性が向上
- 案2（get-config-value.sh 内部 default 方式）は汎用 helper に特定キーのデフォルトを持たせる点で責務混在となるため不採用
- 案3（共通 init スクリプト方式）は案1と実質同一だが命名の観点で案1がより限定的かつ明確

**tests/run-spec.bats 更新が必須な理由**

`run-spec.bats` のみ `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定しているため、`source "$SCRIPT_DIR/watchdog-defaults.sh"` が `$MOCK_DIR/watchdog-defaults.sh` を参照する。モックなしでは file not found エラーが発生する。
他の run-*.bats は PATH モックのみ使用のため更新不要（実 `watchdog-defaults.sh` が source される）。

**測定スコープ（実装前確認）**

ハードコード `1800` 分布: 各 run-*.sh の WATCHDOG_TIMEOUT ブロック2箇所（get-config-value.sh 呼び出し第2引数 + echo フォールバック）× 6ファイル = 計12箇所（`grep -rn "watchdog-timeout-seconds 1800\|echo 1800" scripts/run-*.sh` で確認）。`watchdog-defaults.sh` 内の `WATCHDOG_TIMEOUT_DEFAULT=1800` のみ残存（SSoT として許容）。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- `tests/watchdog-defaults.bats` のテスト3・4（fallback テスト）で、bats の `run` コマンドが stderr を `$output` にマージするため、warningメッセージが混入して `[ "$output" = "1800" ]` が失敗した。回避策として `2>/dev/null` を追加。Spec にはこの bats の挙動についての言及がなく、テスト作成時に1回の修正が必要となった。

### Rework

- `tests/watchdog-defaults.bats` のfallbackテスト（2件）: bats stderr マージ挙動への対応のため `load_watchdog_timeout` 呼び出しに `2>/dev/null` を追加（1 repair attempt で修正完了）

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

- N/A。Spec の Changed Files リストと実際の diff が完全に一致。スコープ外変更なし。

### Recurring Issues

- N/A。同種の問題は検出されなかった。

### Acceptance Criteria Verification Difficulty

- 全4条件 PASS（UNCERTAIN なし）。`file_not_contains` + `rubric` の組み合わせは検証容易。ただし rubric 条件3件はグレーダー評価のため、CI で代替できない判断（SSoT 確立の意図的確認）に適切に活用された。
- docs/ja/structure.md の `get-config-value.sh` エントリ欠落（既存不整合）が documentation consistency チェックで検出されたが、今回 PR スコープ外。別 Issue 化を推奨（verify コマンドでのカバーは不要 — 今後の docs-sync 系 Issue で管理が望ましい）。
