# Issue #397: scripts: permission-mode auto 失敗時の lazy-catch 診断と remediation 表示を導入

## Overview

`#385` で `.wholework.yml` の `permission-mode` デフォルトを `bypass` → `auto` に反転する前に、Pro plan ユーザー（`--permission-mode auto` 非対応）への UX セーフガードを整備する。

`scripts/run-*.sh` 6 ファイルで `claude -p $PERMISSION_FLAG` を実行した直後に、共通ヘルパー `scripts/handle-permission-mode-failure.sh` を呼ぶ。ヘルパーは `PERMISSION_MODE == "auto"` かつ `exit_code != 0` かつ `elapsed <= 30` の条件で診断 stderr を出力し、`.wholework.yml` への `permission-mode: bypass` 設定方法を案内する。それ以外は silent return。ヘルパー自身は常に exit 0 で、既存の `EXIT_CODE` 保存・後段ロジック（reconcile / 終了 banner / exit 伝播）には一切手を入れない。

threshold 30 秒の根拠: claude CLI cold start (3-8s) + auth/plan check + auto-mode soft_deny abort のラウンドトリップを安全側に包含し、かつ mid-flow 失敗（通常 60s+）を拾わない。

## Changed Files

- `scripts/handle-permission-mode-failure.sh`: new file — bash 3.2+ compatible 診断ヘルパー（args: exit_code, elapsed, permission_mode）
- `scripts/run-code.sh`: insert `SECONDS=0` immediately before `set +e` (around line 147), insert helper call immediately after `set -e` (around line 155)
- `scripts/run-spec.sh`: same wrap pattern (around lines 83 / 91)
- `scripts/run-review.sh`: same wrap pattern (around lines 72 / 80)
- `scripts/run-merge.sh`: same wrap pattern (around lines 63 / 71)
- `scripts/run-verify.sh`: same wrap pattern (around lines 117 / 125)
- `scripts/run-issue.sh`: same wrap pattern (around lines 71 / 79)
- `tests/handle-permission-mode-failure.bats`: new file — 4 cases (auto+short=5s, auto+long=60s, bypass, exit-zero) — bash 3.2+ compatible

## Implementation Steps

1. Create `scripts/handle-permission-mode-failure.sh` with 3 positional args (`exit_code`, `elapsed`, `permission_mode`). Print diagnostic to stderr only when all conditions match (`permission_mode == "auto"` AND `exit_code != 0` AND `elapsed -le 30`). Exit 0 unconditionally. (→ acceptance criteria: helper file_exists / "Claude Max" grep / "permission-mode: bypass" grep)

2. In each `scripts/run-*.sh` (6 files), insert `SECONDS=0` immediately before `set +e` and `"$SCRIPT_DIR/handle-permission-mode-failure.sh" "$EXIT_CODE" "$SECONDS" "$PERMISSION_MODE"` immediately after `set -e` (before the existing `if [[ $EXIT_CODE -eq 143 ]]` block). Do not modify existing reconcile / banner / exit propagation logic. (parallel with 1) (→ acceptance criteria: 6 run-*.sh grep checks)

3. Create `tests/handle-permission-mode-failure.bats` with 4 `@test` cases: (a) auto + elapsed=5 + exit=1 → stderr non-empty + status 0, (b) auto + elapsed=60 + exit=1 → stderr empty + status 0, (c) bypass + elapsed=5 + exit=1 → stderr empty + status 0, (d) auto + elapsed=5 + exit=0 → stderr empty + status 0. Use `BATS_TEST_TMPDIR` isolation pattern consistent with `tests/get-config-value.bats`. (after 1) (→ acceptance criteria: bats file_exists / rubric / `bats tests/` PASS)

## Verification

### Pre-merge

- <!-- verify: file_exists "scripts/handle-permission-mode-failure.sh" --> `scripts/handle-permission-mode-failure.sh` が新規作成されている
- <!-- verify: grep "Claude Max" "scripts/handle-permission-mode-failure.sh" --> 診断メッセージに plan 要件の記述（Max / Team / Enterprise / API）が含まれる
- <!-- verify: grep "permission-mode: bypass" "scripts/handle-permission-mode-failure.sh" --> remediation として `permission-mode: bypass` 設定方法が含まれる
- <!-- verify: grep "handle-permission-mode-failure" "scripts/run-code.sh" --> `run-code.sh` がヘルパーを呼ぶ
- <!-- verify: grep "handle-permission-mode-failure" "scripts/run-spec.sh" --> `run-spec.sh` がヘルパーを呼ぶ
- <!-- verify: grep "handle-permission-mode-failure" "scripts/run-review.sh" --> `run-review.sh` がヘルパーを呼ぶ
- <!-- verify: grep "handle-permission-mode-failure" "scripts/run-merge.sh" --> `run-merge.sh` がヘルパーを呼ぶ
- <!-- verify: grep "handle-permission-mode-failure" "scripts/run-verify.sh" --> `run-verify.sh` がヘルパーを呼ぶ
- <!-- verify: grep "handle-permission-mode-failure" "scripts/run-issue.sh" --> `run-issue.sh` がヘルパーを呼ぶ
- <!-- verify: file_exists "tests/handle-permission-mode-failure.bats" --> bats テストが新規作成されている
- <!-- verify: rubric "tests/handle-permission-mode-failure.bats が (1) permission-mode auto + 短時間 (elapsed=5) + exit_code=1 で診断 stderr が出る (2) permission-mode auto + 長時間 (elapsed=60) + exit_code=1 で診断 stderr が出ない (3) permission-mode bypass + elapsed=5 + exit_code=1 で診断 stderr が出ない の 3 ケースを網羅し、いずれも helper が exit 0 で終了することを assert している" --> heuristic の 3 ケースとヘルパー exit code 0 が単体テストでカバーされている
- <!-- verify: command "bats tests/" --> 全 bats テストが PASS する

### Post-merge

- Pro プラン環境（または mock）で `permission-mode: auto` のまま `/auto N` を実行し、診断 stderr が表示されること、および `permission-mode: bypass` に切り替えれば動作することを確認する

## Notes

### bats テストの長時間ケース再現

「`elapsed=60` の長時間ケース」は実時間を 60 秒待たず、ヘルパーの第 2 引数に `60` を直接渡すことで再現する。`SECONDS` builtin の挙動を模倣する必要はない（ヘルパーは引数を受け取るのみ）。`elapsed=60` は threshold 30s の境界から十分離れた値として選択。

### bash 3.2 互換性

`scripts/handle-permission-mode-failure.sh` は macOS の system bash (3.2) で動作する必要がある（既存 `scripts/*.sh` と同じ前提）。`mapfile` / `readarray` / `[[ ... =~ ]]` の高度な機能は使わず、`[ ... ]` test と `case` 文で条件分岐する。

### bats `@test` 名キーワード

`rubric` verify は file 限定なので `@test` 名規約は厳密に問わないが、PASS 条件を後から人間が grep しやすくするため、各 `@test` 名の冒頭に `permission-mode auto:` / `permission-mode bypass:` などの prefix を入れることを推奨（implementation 時の judgment）。

### Auto-Resolved Ambiguity Points (引き継ぎ)

`/issue 397` の retrospective で 3 点が auto-resolve 済み（Issue body の "Auto-Resolved Ambiguity Points" セクション参照）。本 Spec はこれを前提とする:

1. Helper exit code: 常に 0
2. Threshold: 固定 30 秒（`/issue` 後の議論で 10 秒 → 30 秒に再調整、claude CLI cold start を包含）
3. `run-*.sh` の exit 伝播: 既存パターン維持

### `run-*.sh` 改変の影響範囲

`set +e` 直前の `SECONDS=0` 挿入は副作用なし（`SECONDS` は bash builtin で自動リセット）。`set -e` 直後のヘルパー呼び出しは `set -e` 解除後・143 reconcile 前で、ヘルパーが exit 0 を返す前提なので `set -e` の再有効化を待たずに進む。既存 `EXIT_CODE` 変数は保持される。
