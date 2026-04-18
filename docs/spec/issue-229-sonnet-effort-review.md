# Issue #229: run-*.sh: Sonnet 5 スクリプトの effort 設定を Opus 4.7 指針と独立に再評価

## Overview

Sonnet で動作する 5 つの `run-*.sh` (code / review / merge / verify / issue) の effort 設定 (`high` / `medium` / `low`) を Sonnet 独自視点で再評価し、判断根拠と recommendations をドキュメント化する。必要であれば effort を調整する。`run-spec.sh` は Opus/xhigh 路線のため本 Issue スコープ外 (別 Issue #217 管轄)。

## Changed Files

- `docs/reports/sonnet-effort-recalibration.md`: 新規作成。5 スクリプトの現行 effort、Sonnet としての workload 評価、各スクリプトごとの recommendations (現状維持 or 変更) と判断根拠を記載
- `scripts/run-code.sh` / `scripts/run-review.sh` / `scripts/run-merge.sh` / `scripts/run-verify.sh` / `scripts/run-issue.sh`: 調査の結果として effort 変更が必要になった場合のみ該当スクリプトの `--effort` フラグを更新 (bash 3.2+ 互換、変更は 1 行のみ)

## Implementation Steps

1. **各 phase の workload 調査** (→ AC: レポートの現行評価セクション)
   - 5 スクリプトを読んで各 phase の処理内容を整理 (code: 実装 + PR/patch、review: 4 アスペクト + CI 待ち、merge: マージ + conflict、verify: AC 検証 + AI 回顧、issue: triage + refinement)
   - 現行 effort (high/high/low/medium/high) と各 phase の複雑さを対応付ける

2. **Sonnet effort 妥当性評価** (after 1) (→ AC: Recommendations)
   - 各スクリプトについて以下の観点で判断:
     - **run-merge.sh (low)**: コンフリクト解消を含む場合に `medium` 必要か
     - **run-verify.sh (medium)**: AC 検証の精度向上を狙って `high` 昇格すべきか
     - **run-code.sh / run-review.sh / run-issue.sh (high)**: 過剰でないか、`medium` でも品質維持可能か
   - time / cost / quality トレードオフを考察。実測データがない項目は「要観察」と明記

3. **レポート作成** (after 2) (→ AC: レポート作成 + Recommendations)
   - `docs/reports/sonnet-effort-recalibration.md` を新規作成
   - 構成: `## Background` / `## Current Configuration` / `## Workload Analysis` / `## Recommendations` / `## Notes`
   - Recommendations には各スクリプトごとに「現状維持」または「変更: A → B」と理由を記載

4. **必要な場合のみ run-*.sh 更新** (after 3) (→ AC: CI tests pass)
   - レポート結論で effort 変更を推奨したスクリプトのみ、`--effort` フラグを変更 (例: `--effort medium` → `--effort high`)
   - 変更がない場合は本ステップスキップ
   - 変更時は bats 3.2+ 互換を維持 (単純な 1 行変更のみ)

5. **bats テスト PASS 確認** (after 4) (→ AC: CI tests pass)
   - ローカルで `bats tests/` を実行して全 PASS を確認
   - 変更がなければスクリプト関連テストは影響なし (冪等)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/sonnet-effort-recalibration.md" --> `docs/reports/sonnet-effort-recalibration.md` が作成され、5 スクリプトの現行 effort と再評価結果 / 判断根拠 (time / cost / quality トレードオフ) が文書化されている
- <!-- verify: section_contains "docs/reports/sonnet-effort-recalibration.md" "Recommendations" "." --> レポートに `## Recommendations` セクションがあり、各スクリプトについて「現状維持 / 変更」とその理由が記載されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 変更対象スクリプトが更新された場合、bats テストが CI で成功する

### Post-merge

- effort 変更を反映した状態で `/auto` を複数 Issue に対して実行し、品質劣化がないことを主観確認する

## Notes

- **スコープ境界**: `run-spec.sh` は Opus/xhigh 路線のため本 Issue 対象外。Issue #217 で別途扱う
- **xhigh 非適用**: `xhigh` effort は Opus 専用。Sonnet 5 スクリプトには適用不可のため recommendations から除外
- **実測データの扱い**: 本 Issue では workload 調査と判断根拠を残すことが主目的。定量ベンチマーク (tokens / time 計測) は #226 (Opus 4.7 vs 4.6 ベンチマーク) の範囲。本レポートでは「要観察」として次回ベンチマーク対象に言及するに留める
- **変更なしのケース**: Recommendations が全て「現状維持」となった場合、Implementation Step 4/5 はスキップし、レポートのみ追加する (ドキュメントのみの変更 = Size S 相当)。この場合 CI verify command は PASS する (テスト差分ゼロ)
- **auto-resolve 記録** (Issue body の Auto-Resolved Ambiguity Points):
  - xhigh 昇格の要否 → 本 Issue 対象外
  - Opus 4.7 との関連 → 直接なし
  - レポート配置先 → `docs/reports/sonnet-effort-recalibration.md` に固定
- **structure.md 更新不要**: `docs/reports/` は既に `docs/structure.md` に記載済み (line 55)
