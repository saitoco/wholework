# Issue #401: detect-wrapper-anomaly: dirty working tree (verify) パターンを Tier 2 カタログに追加

## Overview

`scripts/detect-wrapper-anomaly.sh` に VERIFY_FAILED + uncommitted changes シグネチャの検出ブランチを追加し、`modules/orchestration-fallbacks.md` に dirty-working-tree カタログ項目（git status フロー + 分岐リカバリ手順）を追加する。Issue #393 で発生した VERIFY_FAILED シナリオで anomaly detector が空出力を返した根本原因を解消し、次回以降は Tier 2 catalog による半自動リカバリが可能になる。

## Changed Files

- `scripts/detect-wrapper-anomaly.sh`: elif ブランチを追加して VERIFY_FAILED + uncommitted 両シグネチャを検出する — bash 3.2+ 互換
- `modules/orchestration-fallbacks.md`: `## dirty-working-tree` エントリを `## Operational Notes` の直前に追加
- `tests/detect-wrapper-anomaly.bats`: dirty-working-tree パターン検出のテストを追加

## Implementation Steps

1. `scripts/detect-wrapper-anomaly.sh` — watchdog-kill の elif ブランチの後、`elif [[ "$EXIT_CODE" == "0" ]]` チェックの前に新ブランチを挿入 (→ AC1, AC2):
   - 条件: `elif grep -q "VERIFY_FAILED" "$LOG_FILE" && grep -q "uncommitted" "$LOG_FILE"; then`
   - `PATTERN_NAME="dirty-working-tree"`
   - `ANOMALY_DESC`: phase・exit code・`VERIFY_FAILED`・uncommitted changes・`#393` を記載
   - `IMPROVEMENT_HINT`: `git status` 確認 → unrelated なら `run-verify.sh $ISSUE_NUMBER` でリトライ、related なら abort の手順、`modules/orchestration-fallbacks.md#dirty-working-tree` 参照を記載

2. `modules/orchestration-fallbacks.md` — `## Operational Notes` の直前に `## dirty-working-tree` エントリを追加 (→ AC3, AC4):
   - **Symptom**: `/verify` が `VERIFY_FAILED` と uncommitted changes を出力
   - **Applicable Phases**: verify
   - **Fallback Steps**: `git status` 実行 → 関連ファイルか判定 → unrelated なら通知して `run-verify.sh` リトライ、related なら abort
   - **Escalation**: 不明な uncommitted changes は recovery sub-agent (#316) にエスカレーション
   - **Rationale**: Issue #393 retrospective 参照、`detect-wrapper-anomaly.sh`（pattern: `dirty-working-tree`）

3. `tests/detect-wrapper-anomaly.bats` — ステップ 1 完了後、dirty-working-tree パターンのテストを追加 (→ AC1, AC2):
   - `@test "dirty working tree: detects VERIFY_FAILED with uncommitted changes"` を追加
   - ログに `VERIFY_FAILED` と `uncommitted` 両方を含む場合 → `dirty-working-tree` が出力されることを確認
   - `status` が 0、`output` に `dirty-working-tree`・`### Orchestration Anomalies`・`### Improvement Proposals` が含まれることをアサート

## Verification

### Pre-merge

- <!-- verify: grep "VERIFY_FAILED" "scripts/detect-wrapper-anomaly.sh" --> `scripts/detect-wrapper-anomaly.sh` に `VERIFY_FAILED` を検出するルールが追加されている
- <!-- verify: grep "uncommitted" "scripts/detect-wrapper-anomaly.sh" --> `scripts/detect-wrapper-anomaly.sh` に `uncommitted changes` を検出するルールが追加されている
- <!-- verify: grep "dirty-working-tree" "modules/orchestration-fallbacks.md" --> `modules/orchestration-fallbacks.md` に dirty working tree (verify) のカタログ項目が追加されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md の dirty working tree エントリに、uncommitted changes が発生した際に git status で関連ファイルか否かを判断し、関連しない場合は通知して iteration retry、関連する場合は abort するリカバリ手順が記述されている" --> <!-- verify: grep "git status" "modules/orchestration-fallbacks.md" --> カタログ項目に git status 確認フローと分岐リカバリ手順が含まれている

### Post-merge

- Issue #393 と同様の VERIFY_FAILED シナリオで、`detect-wrapper-anomaly.sh` が non-empty 出力を返し、Tier 2 catalog 経路に乗ることを確認

## Notes

- なし

## Code Retrospective

### Deviations from Design

- なし

### Design Gaps/Ambiguities

- `detect-wrapper-anomaly.sh` のパターンマッチ順序: 新しい `dirty-working-tree` パターンは `watchdog-kill` の後、`EXIT_CODE == 0` チェックの前に配置。Spec の挿入位置指定通りで問題なし。

### Rework

- なし

## review retrospective

### Spec vs. Implementation Divergence Patterns

- Spec の実装ステップ1で `ANOMALY_DESC` に `#393` 参照を含めることが指定されていたが、テストのアサーションでこの参照が検証されていなかった。Spec とコードは整合しているが、テストが Spec の要求を完全にカバーしていない漏れパターン。

### Recurring Issues

- なし。今回のレビューで発見した指摘は1件のみで、再発パターンとして記録できるほどの頻度ではない。

### Acceptance Criteria Verification Difficulty

- 全 AC が `grep` と `rubric` を組み合わせており、auto-verify は安定して PASS。UNCERTAIN は発生しなかった。
- CI の `Forbidden Expressions check` が PR とは無関係の既存ファイル（`docs/spec/issue-385-default-permission-mode-auto.md`）で失敗しており、PR 単位のアクセプタンス検証に外部ノイズが混入するパターン。既存ファイルの `verify hint` 表記を修正する別 Issue が必要。
