# Issue #760: audit: auto-session report の Improvement Candidates に Tier 2 リカバリも含める

## Overview

`/audit auto-session` の session レポートでは Improvement Candidates Surfaced セクションに Tier 3 リカバリのみを浮上させる。Tier 2 fallback catalog リカバリが同一 session で複数回発火した場合 (count ≥ `recoveries-auto-fire.threshold - 1`) を improvement candidate として出力することで、session 単位で orchestration risk の累積トレンドを可視化する。

## Changed Files

- `scripts/get-auto-session-report.sh`: `recoveries-auto-fire.threshold` 読み取り追加 + IMPROVEMENT_CANDIDATES に Tier 2 candidate ロジック追加 — bash 3.2+ compatible
- `skills/audit/SKILL.md`: §6 (Improvement Candidates Surfaced) の説明に Tier 2 candidates を追記
- `tests/get-auto-session-report.bats`: Tier 2 candidate surfacing の bats テスト追加

## Implementation Steps

1. `scripts/get-auto-session-report.sh` の変数宣言ブロック (PERIOD_MODE=false の直後あたり) に、`.wholework.yml` から `recoveries-auto-fire.threshold` を読み取るコードを追加する。読み取りは `awk` で実施 (get-config-value.sh はネスト key 非対応のため)。`WHOLEWORK_CONFIG_PATH` env var を尊重して CWD 非依存にする。値が 0 以下・非数値・空の場合はデフォルト 3 にフォールバック。 (→ AC1 supplementary: `file_contains "scripts/get-auto-session-report.sh" "recoveries-auto-fire"`)

2. `scripts/get-auto-session-report.sh` の IMPROVEMENT_CANDIDATES 計算ブロック (lines 593-600) を以下の形に再構築する: (→ AC1 rubric)
   - Tier 3 候補: 既存の jq クエリを分離して `TIER3_CANDIDATES` 変数に入れる
   - Tier 2 候補: `jq` で session 内の Tier 2 recovery events を phase 別に集計し、count ≥ RECOVERIES_APPROACH (threshold-1) のものを `TIER2_CANDIDATES` として出力する。count ≥ threshold なら "threshold reached"、threshold-1 以上なら "approaching threshold" のラベルを付ける
   - 最終 IMPROVEMENT_CANDIDATES: Tier 2 → Tier 3 の順で連結し、両方空の場合は "(none — no Tier 3 recoveries or Tier 2 approaching recoveries-auto-fire threshold)" とする

3. `skills/audit/SKILL.md` line 1009: `§6 **Improvement Candidates Surfaced**` の説明 `(Tier 3 recoveries, unknown patterns)` を `(Tier 3 recoveries, Tier 2 recoveries approaching or reaching recoveries-auto-fire.threshold, unknown patterns)` に変更する。 (→ AC2 rubric + file_contains)

4. `tests/get-auto-session-report.bats` に新テスト追加: fixture に同一 session で 2 件の Tier 2 recovery event (phase=code-patch) を含めて実行し、レポートに "Tier 2 recovery" と "approaching" が出力されることを確認する。`WHOLEWORK_CONFIG_PATH=/dev/null` を設定しデフォルト threshold=3 を使用 (2 events ≥ threshold-1=2 → 浮上)。

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/get-auto-session-report.sh が session 内の Tier 2 リカバリイベントを集計し、recoveries-auto-fire threshold (.wholework.yml: recoveries-auto-fire.threshold) と比較して、threshold-1 以上 (閾値接近) または threshold 到達した symptom を Improvement Candidates Surfaced セクションに candidate として出力する" --> <!-- verify: file_contains "scripts/get-auto-session-report.sh" "recoveries-auto-fire" --> get-auto-session-report.sh が Tier 2 candidate を session レポートに含めるように拡張されており、recoveries-auto-fire threshold 参照が追加されている
- <!-- verify: rubric "skills/audit/SKILL.md の auto-session Subcommand § Output Template Structure §6 (Improvement Candidates Surfaced) に、Tier 2 candidate も対象とすることが明記されている" --> <!-- verify: file_contains "skills/audit/SKILL.md" "Tier 2" --> SKILL.md ドキュメントの更新 (§6 に Tier 2 candidate が対象と明記)

### Post-merge

- 次回 batch session で Tier 2 リカバリが発生した際、`/audit auto-session <id>` レポートの Improvement Candidates Surfaced に当該 symptom が表示されることを観察 <!-- verify-type: manual -->

## Notes

### Auto-Resolved Ambiguity (non-interactive mode)

- **「接近」の定義**: Issue 本文の「例: threshold-1 以上」を根拠に `threshold-1 以上 (count ≥ threshold - 1)` を閾値接近の定義と確定。Issue コメントで既に確認済み。

### 実装詳細

- `recoveries-auto-fire.threshold` は get-config-value.sh がネスト key 非対応のため、`awk` でブロック YAML を直接パースして読み取る。`WHOLEWORK_CONFIG_PATH` env var を優先し、未設定の場合は `.wholework.yml` (CWD 相対) を参照する。
- Tier 2 events のみの count 比較であり、orchestration-recoveries.md の累積 count は参照しない (session 内 count で threshold 比較)。
- 既存テスト (`empty jsonl`, `session_id filter`, etc.) は変更不要。新テストのみ追加。

### Consumed Comments

- saito (MEMBER / first-class): Issue Retrospective コメント (2026-06-26T23:16:04Z) — AC2 削除 (always-PASS 修正)、AC1 に `file_contains "recoveries-auto-fire"` 補足追加、AC3 に `file_contains "Tier 2"` 補足追加、rubric+file_contains パターン統一。コメント内容を反映して AC 構造を設計。
