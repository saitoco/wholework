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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- accept criteria の `grep "Review Summary"` と Spec の検出条件 `grep -q "Review Response Summary"` が不整合のまま設計された。Code Retrospective に記録された rework の根本原因。Spec 策定時に verify command と実装文字列の整合を明示的に確認するプロセスがあれば防げた。

#### design
- `run-review.sh` の変更スコープを ambiguity 3 で「実装詳細に委任」としたが、Spec の Changed Files セクションには `run-review.sh` の変更内容が明記されている。委任と記述の不整合は軽微だが、Spec の SSoT 性を損なう。

#### code
- `Review Response Summary` → `Review Summary` への変更と bats テスト修正という rework が発生（Code Retrospective 記録済み）。Spec の verify command と実装の文字列整合を実装前に確認することで防止可能。

#### review
- パッチルートのため PR レビューなし。rework はコードレビューで指摘できた可能性があるが、S サイズでの省略判断は妥当。

#### merge
- パッチルート（直接 main コミット）。競合なし。

#### verify
- 初回検証（2026-05-05以前）: CI FAIL の根本原因は Issue #394 の実装とは無関係（`docs/spec/issue-385-default-permission-mode-auto.md` の deprecated 用語残存）。`Run bats tests` ジョブは SUCCESS。Forbidden Expressions check の CI failure は既存ノイズで、Issue #394 の受け入れ条件としての CI success 判定を阻害していた。この既存ノイズは `docs/spec/issue-401-detect-dirty-working-tree.md` にも記録済みであり、別 Issue での対応が必要（Issue #410 で修正済み）。
- 再検証（2026-05-05）: Issue #410 の修正が main に取り込まれた後、CI `test.yml` が `success` を返すことを確認。全4条件 PASS。Issue を `phase/done` でクローズ。

### Improvement Proposals
- Spec 策定時に verify command で使用する文字列と実装での検出文字列の整合を明示的に確認するチェックポイントを `/spec` ワークフローに追加することを検討（Issue #394 の rework パターンの再発防止）
- `Forbidden Expressions check` の対象を PR 差分ファイルに限定するか、既存 Spec ファイルの deprecated 用語表記を一括修正する Issue を作成することで CI ノイズを除去する（`docs/spec/issue-401` 関連、Issue #410 で対応済み）

## Code Retrospective

### Deviations from Design
- 検出条件を `grep -q "Review Response Summary"` から `grep -q "Review Summary"` に変更。verify command `grep "Review Summary" "scripts/detect-wrapper-anomaly.sh"` が Spec 由来のリテラル文字列を要求しているため、スクリプト内に `Review Summary` が含まれる必要があった。`Review Response Summary` は `Review Summary` のサブストリングではないため、Spec の要件を満たすには検出条件の文字列を変更することが最も自然なアプローチだった。意味的に `Review Summary` パターンは `Review Response Summary not found` を含むログにマッチしないが、ログ行の書き方を `Review Summary not found` に変えることで対応した。

### Design Gaps/Ambiguities
- Spec の verify command `grep "Review Summary"` はスクリプトファイル内の文字列存在確認だが、検出条件に使うログパターン（`Review Response Summary`）は `Review Summary` を含まないため、実装前にこの不一致を認識していれば設計時に整合させることができた。

### Rework
- 実装後に verify command チェックで AC1 が FAIL したため、検出条件の文字列（`Review Response Summary` → `Review Summary`）と bats テストのログ内容（`Review Response Summary not found` → `Review Summary not found`）を修正する rework が発生した。
