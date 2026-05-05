# Issue #394: detect-wrapper-anomaly: add reconciler-header-mismatch to Tier 2 catalog

## Overview

`run-review.sh` がwatchdogタイムアウト後に `reconcile-phase-state.sh` を呼び出した際、PR コメントに `## Review Response Summary` が存在しない（`matches_expected: false`）ケースを `detect-wrapper-anomaly.sh` で検出できるようにする。reconcilerのJSON出力（`_reconcile_out`）は現在ラッパーログ（`.tmp/wrapper-out-{issue}-review.log`）に書き出されていないため、`run-review.sh` のelse ブランチでログ出力を追加し、`detect-wrapper-anomaly.sh` に `reconciler-header-mismatch` パターンを追加する。

## Changed Files

- `scripts/run-review.sh`: reconciler check（行88–94）のelse ブランチに `echo "reconcile-phase-state result: $_reconcile_out"` を追加 — bash 3.2+ compatible
- `scripts/detect-wrapper-anomaly.sh`: `reconciler-header-mismatch` の elif ブロックを `dirty-working-tree` ブロック直後・`elif [[ "$EXIT_CODE" == "0" ]]` 直前に追加 — bash 3.2+ compatible
- `tests/detect-wrapper-anomaly.bats`: `reconciler-header-mismatch` パターンのテストケースを追加
- `modules/orchestration-fallbacks.md`: `## reconciler-header-mismatch` エントリを `## Operational Notes` 直前に追加

## Implementation Steps

1. `scripts/run-review.sh`: 行88–94 の reconciler チェックを変更し、`matches_expected: true` の if ブロックに else ブランチを追加して `echo "reconcile-phase-state result: $_reconcile_out"` を出力する（ラッパーログへの書き出しを有効化） (→ パターン検出の前提条件)
2. `scripts/detect-wrapper-anomaly.sh`: `dirty-working-tree` ブロック（`elif grep -q "VERIFY_FAILED"` の直下）の後・`elif [[ "$EXIT_CODE" == "0" ]]` の直前に、`reconciler-header-mismatch` の elif ブロックを追加する。検出条件: `grep -q '"matches_expected":false' "$LOG_FILE"` かつ `grep -q "Review Response Summary" "$LOG_FILE"` (→ AC1, AC2)
3. `tests/detect-wrapper-anomaly.bats`: `@test "reconciler header mismatch: detects matches_expected false with Review Response Summary"` テストケースを追加。ログに `"matches_expected":false` と `Review Response Summary not found` の両方を含む場合にパターン `reconciler-header-mismatch` が検出されることを検証する (→ AC3)
4. `modules/orchestration-fallbacks.md`: `## Operational Notes`（行229）直前に `## reconciler-header-mismatch` カタログエントリ（Symptom / Applicable Phases / Fallback Steps / Escalation / Rationale）を追加する (→ Issue title "Tier 2 カタログに追加")

## Verification

### Pre-merge

- <!-- verify: grep "Review Summary" "scripts/detect-wrapper-anomaly.sh" --> `detect-wrapper-anomaly.sh` に `Review Summary`（または `Review Response Summary`）関連パターンが追加される
- <!-- verify: grep "reconciler-header-mismatch" "scripts/detect-wrapper-anomaly.sh" --> `detect-wrapper-anomaly.sh` にパターン名 `reconciler-header-mismatch` が追加される
- <!-- verify: grep "Review.*Summary" "tests/detect-wrapper-anomaly.bats" --> `tests/detect-wrapper-anomaly.bats` に `reconciler-header-mismatch` パターンのテストケースが追加される

### Post-merge

- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI test が success

## Notes

- `_reconcile_out` のログ出力は `run-review.sh` のelse ブランチ追加で実現する。`detect-wrapper-anomaly.sh` 内での直接 reconciler 呼び出しは PR number の取得が必要で複雑なため不採用（Issue body auto-resolved ambiguity 3: `run-review.sh` 変更スコープは実装詳細に委任）
- 既存の `watchdog-kill` パターンが先に一致するシナリオ（watchdogタイムアウト後に reconciler も失敗する #386 のケース）では、`reconciler-header-mismatch` は検出されない（first-match-wins仕様）。本パターンはウォッチドッグ kill なしで reconciler が `matches_expected: false` を返すケース（ヘッダー乖離）を主ターゲットとする
- `detect-wrapper-anomaly.sh` は現在 `run-auto-sub.sh` から exit_code=0 の場合のみ呼び出される。非ゼロ exit_code でのパターン検出は将来的な `run-auto-sub.sh` 拡張に委ねる（本 Issue のスコープ外）
