# Issue #587: Opus 4.8 Parent Session /auto Continuous-Run Performance Spike

## Overview

Fable 5 親セッション停止下（2026-06-13 以降）で、Opus 4.8 を親オーケストレータとした `/auto` 連続実行のパフォーマンスを計測し、Fable 5 時代（`docs/reports/auto-session-performance-2026-06-13.md`）との差分を定量化する。

Phase 1 として単一セッション (A) モードで 5 Issue を連続実行し、以下のメトリクスを収集する:
- 完走 Issue 数 / 起票数
- 各 Issue end-to-end 時間（分）
- watchdog kill 数
- Tier 1〜3 recovery 発火数
- 親セッションが手動介入した数

劣化兆候（context anxiety、early-stop、誤判断）が観測されれば `--batch` List mode の評価（Phase 2）を推奨。観測されなければ「現運用維持」と結論して本レポートを完了とする。

## Changed Files

- `docs/reports/auto-parent-session-comparison-2026-06-14.md`: 新規作成（spike 計測結果レポート）
- `docs/ja/reports/auto-parent-session-comparison-2026-06-14.md`: 新規作成（日本語版）
- `docs/ja/environment-adaptation.md`: 英語版（commit 679252d で更新済み）に合わせて sync
- `docs/ja/product.md`: 英語版（commit 753e919 で更新済み）に合わせて sync（diff 確認後に最小限更新）
- `docs/ja/tech.md`: 英語版（commit 753e919 で更新済み）に合わせて sync（diff 確認後に最小限更新）

## Implementation Steps

1. オープンバックログから spike 実行候補 5 Issue を選定（Size XS/S/M 優先、XL 除外；`gh issue list --state open` で確認）(→ AC なし)

2. Opus 4.8 親セッションで `/auto N1 → N2 → N3 → N4 → N5` を単一セッション逐次実行し、以下を手動記録: 各フェーズ所要時間、watchdog kill 発生有無、Tier 1/2/3 recovery 発火数、親セッション手動介入数、劣化兆候（誤判断・early-stop・context anxiety）の有無 (→ 全 AC の基礎データ)

3. `docs/reports/auto-parent-session-comparison-2026-06-14.md` を作成（記載内容: サマリー表、Issue 別所要時間表、watchdog 観察記録、品質ループイベント、Fable 5 比較差分、結論「現運用維持 or --batch List mode 推奨」）(after 2) (→ AC 1-8)

4. `docs/ja/reports/auto-parent-session-comparison-2026-06-14.md` を作成（Step 3 の日本語訳；既存の `docs/ja/reports/auto-session-performance-2026-06-13.md` のスタイルに準拠）(after 3) (→ AC 9)

5. `docs/ja/environment-adaptation.md`、`docs/ja/tech.md`、`docs/ja/product.md` を対応英語版との diff を確認して最小限 sync（`check-translation-sync.sh --fail-if-outdated` が pass するよう 3 ファイルの ja 版を更新）(after 4) (→ AC 10)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/auto-parent-session-comparison-2026-06-14.md" --> 比較レポートが存在する（日付は spike 実施日）
- <!-- verify: grep "単一セッション" "docs/reports/auto-parent-session-comparison-2026-06-14.md" --> 単一セッション計測の記録がある
- <!-- verify: grep "劣化兆候" "docs/reports/auto-parent-session-comparison-2026-06-14.md" --> 劣化兆候の判定が記録されている
- <!-- verify: grep "batch" "docs/reports/auto-parent-session-comparison-2026-06-14.md" --> --batch List mode の評価が記録されている
- <!-- verify: grep "Opus 4.8" "docs/reports/auto-parent-session-comparison-2026-06-14.md" --> Opus 4.8 親での計測実績が記載されている
- <!-- verify: grep "親オーケストレータ" "docs/reports/auto-parent-session-comparison-2026-06-14.md" --> 親オーケストレータの記述がある
- <!-- verify: rubric "the comparison report records: number of issues processed, end-to-end time per issue, watchdog kill count, recovery tier invocations, manual interventions; and concludes whether single-session continuous execution is sustainable under Opus 4.8 or whether --batch List mode is recommended" --> 計測項目と結論が rubric 基準を満たす
- <!-- verify: file_contains "docs/reports/auto-parent-session-comparison-2026-06-14.md" "watchdog" --> レポートに watchdog 計測値が含まれる（rubric 補完）
- <!-- verify: file_exists "docs/ja/reports/auto-parent-session-comparison-2026-06-14.md" --> ja 版が存在する
- <!-- verify: command "scripts/check-translation-sync.sh --fail-if-outdated" --> translation-sync pass（Step 5 の ja 更新後に pass する）

### Post-merge

- Fable 5 復帰後、本レポートの結論が再評価され、必要なら follow-up spike が起票されていること

## Notes

### Auto-Resolve Log（非対話モード自動解決）

1. **`check-translation-sync.sh --fail-if-outdated` の pre-existing 失敗**
   - 検出: `docs/product.md`、`docs/tech.md`、`docs/environment-adaptation.md` の 3 件が現時点で OUTDATED（英語版は commits 679252d/753e919 で更新済み、ja 版が未追従）
   - 解決: これらの ja docs 更新を Implementation Step 5 として本 Issue にスコープ追加。理由: `check-translation-sync.sh` が `docs/reports/` を対象外とするため、本 Issue の主成果物（reports）は翻訳同期 AC に直接影響しない。ja docs 更新は最小限（該当コミットの diff のみ適用）で、scope 拡張は軽微と判断。
   - 他の候補: AC から `--fail-if-outdated` を削除（現実的だが AC 弱体化）、別 Issue 化（オーバーヘッド）

2. **`docs/ja/reports/` の作成** — `docs/translation-workflow.md` は `docs/reports/` を翻訳対象外と定義しているが、`docs/ja/reports/` ディレクトリが存在し複数の ja 版レポートが実際に存在する。Issue AC が明示的に ja 版レポートを要求しているため、既存の実態に従い ja 版を作成する方針。

### レポートファイル名の日付

`2026-06-14`（本 Issue 作成・spike 実施日）。実施日が翌日以降にずれる場合は、レポートファイル名と AC 内の日付を実施日に合わせて更新すること。

### Fable 5 ベースライン参照先

`docs/reports/auto-session-performance-2026-06-13.md` — Fable 5 親 + Sonnet 子、14 Issue 処理、watchdog kill 2 回（35+ 実行中）。レポート内での比較対象として引用すること。

### docs/reports/ は translation-sync スコープ外

`scripts/check-translation-sync.sh` は `docs/*.md` と `docs/guide/*.md` のみをスキャン（`-maxdepth 1`）。本 Issue で追加する `docs/reports/*.md` および `docs/ja/reports/*.md` は同スクリプトのスコープ外であり、翻訳同期 AC には直接影響しない。
