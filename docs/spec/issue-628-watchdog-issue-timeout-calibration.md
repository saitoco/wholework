# Issue #628: watchdog: ISSUE phase timeout の Sonnet/Opus 親モデル向けキャリブレーション（600s → 1200s + モデル別注記）

## Overview

`WATCHDOG_TIMEOUT_ISSUE_DEFAULT` を 600 から 1200 に引き上げ、Sonnet 4.6/Opus 4.7 親モデル下での高負荷 issue triage による誤 kill を防ぐ。
同時に `scripts/watchdog-defaults.sh` に親モデル依存性のコメント注記を追加し、`docs/tech.md` および `docs/ja/tech.md` にも watchdog timeout のキャリブレーション指針を 1-2 行追記する。

## Changed Files

- `scripts/watchdog-defaults.sh`: `WATCHDOG_TIMEOUT_ISSUE_DEFAULT` を 600 → 1200 に変更、フェーズ別タイムアウト定数ブロックの直前に親モデル依存性コメントを追加 — bash 3.2+ compatible
- `docs/tech.md`: Phase state reconciliation 以降の Architecture Decisions セクションに watchdog timeout キャリブレーション指針の 1-2 行注記を追加
- `docs/ja/tech.md`: `docs/tech.md` の変更内容を日本語で反映（translation sync）

## Implementation Steps

1. `scripts/watchdog-defaults.sh` の `WATCHDOG_TIMEOUT_ISSUE_DEFAULT=600` を `WATCHDOG_TIMEOUT_ISSUE_DEFAULT=1200` に変更。（→ AC 1）

2. `scripts/watchdog-defaults.sh` のフェーズ別タイムアウト定数ブロック（`WATCHDOG_TIMEOUT_SPEC_DEFAULT` 行の直前）に以下のコメントブロックを追加する。（→ AC 2）

   ```bash
   # Phase-specific watchdog timeouts (in seconds).
   # Calibrated against typical silent windows observed under the dominant parent
   # orchestrator model. Lower-latency parent models (e.g. Fable 5) can use tighter
   # values; high-effort triage under Sonnet 4.6 / Opus 4.7 requires more headroom.
   #
   # Recalibration guidance:
   #   - If watchdog kills become frequent on a phase, raise that phase's *_DEFAULT
   #   - If true-stall detection becomes too slow, consider per-effort tuning (Icebox #596)
   #   - Empirical baseline: docs/reports/auto-session-performance-2026-06-13.md (Fable 5),
   #     docs/reports/auto-batch-list-mode-2026-06-14.md (Sonnet 4.6)
   ```

3. `docs/tech.md` の Architecture Decisions セクション末尾（`## Wholework Label Management` の直前）に以下の 1 項目を追加する。（→ AC 3）

   ```markdown
   - **Watchdog timeout calibration**: Phase-specific timeout constants in `scripts/watchdog-defaults.sh` are calibrated against the dominant parent orchestrator model's per-token latency. Recalibrate when the default parent model changes (e.g., Fable 5 → Sonnet 4.6 transition in #628 required raising `WATCHDOG_TIMEOUT_ISSUE_DEFAULT` from 600 to 1200).
   ```

4. `docs/ja/tech.md` の「アーキテクチャ決定」セクション末尾（英語版と対応する位置）に Step 3 の日本語版を追加する。（→ AC 4）

   ```markdown
   - **watchdog タイムアウトのキャリブレーション**: `scripts/watchdog-defaults.sh` のフェーズ別タイムアウト定数は、支配的な親モデルの per-token レイテンシに対してキャリブレーションされている。デフォルト親モデルが変更された場合は再キャリブレーションが必要（例: Fable 5 → Sonnet 4.6 移行で `WATCHDOG_TIMEOUT_ISSUE_DEFAULT` を 600 → 1200 に引き上げ: #628）。
   ```

## Verification

### Pre-merge

- <!-- verify: grep "WATCHDOG_TIMEOUT_ISSUE_DEFAULT=1200" "scripts/watchdog-defaults.sh" --> ISSUE phase デフォルトが 1200 に更新されている
- <!-- verify: grep "Sonnet|Fable 5|親モデル|parent orchestrator" "scripts/watchdog-defaults.sh" --> 親モデル依存性のコメント注記がある
- <!-- verify: grep "親モデル|parent.*model" "docs/tech.md" --> tech.md に親モデル依存の注記がある
- <!-- verify: command "scripts/check-translation-sync.sh" --> ja 同期 pass
- <!-- verify: command "bats tests/watchdog-defaults.bats" --> 既存 bats テストが green
- <!-- verify: command "bash -n scripts/watchdog-defaults.sh" --> 構文エラーなし

### Post-merge

- 次回 Sonnet 4.6 親下の high-effort triage で issue phase が 600s 超過しても誤 kill されないことを観察

## Notes

- `check-translation-sync.sh` は `--fail-if-outdated` なしで常に exit 0（informational モード）。AC 4 の自動検証は「スクリプト実行成功」の確認のみ。`docs/ja/tech.md` の実際の同期は実装の完全性で保証する。
- 既存 bats テストには `WATCHDOG_TIMEOUT_ISSUE_DEFAULT` の値を明示的に検証するケースが存在しない（MERGE=600 のテストはあるが ISSUE は未テスト）。新規テスト追加は AC スコープ外。
- per-effort 動的 timeout および モデル別 timeout 自動切替は本 Issue スコープ外（#596 Icebox）。
