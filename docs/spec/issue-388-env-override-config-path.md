# Issue #388: scripts: get-config-value.sh に WHOLEWORK_CONFIG_PATH env override を導入

## Overview

`scripts/get-config-value.sh` が CWD 相対で `.wholework.yml` を固定参照しているため、テスト容易性がスクリプト自身に内蔵されていない。`WHOLEWORK_CONFIG_PATH` env override を導入し、テスト側が env 1 行で config ファイル参照を切り替えられる構造にする。

変更内容:
- env が設定されていれば、その path を config ファイルとして使う
- env が未設定または空なら、従来どおり CWD 相対 `.wholework.yml` を読む
- `WHOLEWORK_CONFIG_PATH=/dev/null` 時: `-f` 判定が false → DEFAULT 値が返る（現行の `.wholework.yml` 不在時と同挙動）

Issue #386 で各 `tests/run-*.bats` の `setup()` に追加した CWD 隔離 block は defense-in-depth として残す（本 Issue は構造改善側）。

## Changed Files

- `scripts/get-config-value.sh`: `CONFIG_FILE=".wholework.yml"` を `CONFIG_FILE="${WHOLEWORK_CONFIG_PATH:-.wholework.yml}"` に変更 — bash 3.2+ 互換
- `tests/get-config-value.bats`: `WHOLEWORK_CONFIG_PATH` env override の単体テスト 3 ケースを追加 — bash 3.2+ 互換
- `docs/tech.md`: Environment Variables テーブルに `WHOLEWORK_CONFIG_PATH` 行を追加
- `docs/ja/tech.md`: 環境変数テーブルに `WHOLEWORK_CONFIG_PATH` 行を日本語で追加

## Implementation Steps

1. `scripts/get-config-value.sh:59` の `CONFIG_FILE=".wholework.yml"` を `CONFIG_FILE="${WHOLEWORK_CONFIG_PATH:-.wholework.yml}"` に変更する (→ 受入条件 1, 4)

2. `tests/get-config-value.bats` に以下 3 テストを追加する (→ 受入条件 2, 3):
   - `WHOLEWORK_CONFIG_PATH` に任意 path (tmp ファイル) を設定したとき、そのファイルを読む
   - `WHOLEWORK_CONFIG_PATH=/dev/null` のとき `-f` 判定が false となり DEFAULT 値にフォールバックする
   - `WHOLEWORK_CONFIG_PATH` 未設定のとき、CWD の `.wholework.yml` を読む（従来挙動との互換）

   テスト名パターン例 (既存命名規則 `"category: description"` に従う):
   - `@test "WHOLEWORK_CONFIG_PATH: custom path is used when set" {`
   - `@test "WHOLEWORK_CONFIG_PATH: falls back to default when path is non-regular file" {`
   - `@test "WHOLEWORK_CONFIG_PATH: reads CWD .wholework.yml when unset" {`

   各テスト内での `WHOLEWORK_CONFIG_PATH` の設定は `local` スコープで行い、他テストへの漏れを防ぐ。テストランナー (`run bash "$SCRIPT" ...`) への伝達は `WHOLEWORK_CONFIG_PATH=/dev/null bash "$SCRIPT" ...` 形式か `export` + `unset` で制御する。

3. `docs/tech.md` の `## Environment Variables` テーブルに以下の行を追加する (既存の `WHOLEWORK_SCRIPT_DIR` 行の直後) (→ SHOULD: docs sync):
   ```
   | `WHOLEWORK_CONFIG_PATH` | *(unset)* | Override the config file path used by `scripts/get-config-value.sh`. When set, the script reads the specified path instead of CWD-relative `.wholework.yml`. Set to `/dev/null` in BATS tests to force default values. When unset or empty, falls back to `.wholework.yml` (CWD-relative). |
   ```

4. `docs/ja/tech.md` の `## 環境変数` テーブルに以下の行を追加する (既存 `WHOLEWORK_CI_TIMEOUT_SEC` 行の直後) (→ SHOULD: docs sync):
   ```
   | `WHOLEWORK_CONFIG_PATH` | *(未設定)* | `scripts/get-config-value.sh` が参照する設定ファイルパスを上書きする。設定されている場合、CWD 相対 `.wholework.yml` の代わりに指定したパスを読む。BATS テストでは `/dev/null` を設定してデフォルト値を強制できる。未設定または空の場合は `.wholework.yml`（CWD 相対）にフォールバックする |
   ```

## Verification

### Pre-merge

- <!-- verify: grep "WHOLEWORK_CONFIG_PATH" "scripts/get-config-value.sh" --> `scripts/get-config-value.sh` で `WHOLEWORK_CONFIG_PATH` env を参照する実装が追加される
- <!-- verify: grep "WHOLEWORK_CONFIG_PATH" "tests/get-config-value.bats" --> `tests/get-config-value.bats` に `WHOLEWORK_CONFIG_PATH` の単体テストが追加される
- <!-- verify: rubric "tests/get-config-value.bats に WHOLEWORK_CONFIG_PATH env が (1) 任意 path を指定したとき有効化される (2) /dev/null 等の存在しない/regular でない path のときデフォルトに fallback する (3) 未設定/空のとき従来どおり .wholework.yml を読む の 3 ケースを網羅するテストが追加されている" --> env override の有効化、fallback、未設定時の互換挙動が単体テストでカバーされている
- <!-- verify: rubric "scripts/get-config-value.sh は WHOLEWORK_CONFIG_PATH が未設定または空のとき従来の .wholework.yml (CWD 相対) を読む現状互換挙動を維持している" --> production paths の現状互換が維持されている

### Post-merge

- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 修正コミット後の main で `Test / Run bats tests` workflow が success する
- `scripts/run-*.sh` の現状ユーザー (production paths) の挙動に回帰がないことを後続作業で確認する

## Notes

- `${WHOLEWORK_CONFIG_PATH:-.wholework.yml}` は bash parameter expansion で、空文字列もデフォルト展開対象 (`:-` は unset または空の場合) — bash 3.2+ 互換
- `WHOLEWORK_CONFIG_PATH=/dev/null` のとき `[ ! -f "$CONFIG_FILE" ]` が true (character device は `-f` 判定が false) → DEFAULT 値が返る。これは `.wholework.yml` 不在時と同じコードパスを通るため追加処理不要
- `docs/ja/tech.md` の `## 環境変数` テーブルは `WHOLEWORK_SCRIPT_DIR` が現在欠落しているため (`WHOLEWORK_CI_TIMEOUT_SEC` の次が `WHOLEWORK_CONFIG_PATH` 行になる)。既存欠落は本 Issue のスコープ外
- テスト内で `WHOLEWORK_CONFIG_PATH` を export した場合は teardown または test スコープ内で必ず `unset WHOLEWORK_CONFIG_PATH` する

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- bats の `run` コマンドに env var を渡す方法として Spec は `VAR=value bash "$SCRIPT"` 形式または `export + unset` を提示していたが、`run` 組み込み関数は prefix env var を引数コマンドに渡さないため `export + unset` 形式を採用した。各 test はサブシェルで実行されるため `unset` は次テストへの漏れ防止として明示的に記述した

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `${WHOLEWORK_CONFIG_PATH:-.wholework.yml}` の bash `:-` 演算子で unset・空文字どちらも fallback — 既存の `[ ! -f ]` チェックと組み合わせて `/dev/null` 時のデフォルト返却も追加実装不要
- bats テストの env 伝達は `export + unset` 形式を採用（`run` 関数は prefix env を引き継がないため）
- `docs/ja/tech.md` にも `WHOLEWORK_CONFIG_PATH` 行を追加して translation-workflow を遵守

### Deferred Items
- `WHOLEWORK_SCRIPT_DIR` の `docs/ja/tech.md` 欠落は本 Issue スコープ外（既知欠落として Notes に記録）

### Notes for Next Phase
- 変更は単一行の bash parameter expansion。実装はシンプルで regress リスクは低い
- CI の `Test / Run bats tests` workflow で 3 新規テスト（#196-198）の PASS を確認済み（bats ローカル実行で全 317 tests PASS）
- Post-merge の production paths 回帰確認は opportunistic verify として残存
