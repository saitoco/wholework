# Issue #507: audit/stats: Outcome 計算から retro/verify ラベル付き Issue を除外する

## Overview

`/audit stats` の Section 5 (Outcome) で First-try 成功率・Completed 率・Rework 数・Phase 後戻りポイントを集計する際、`retro/verify` ラベル付き Issue を母集団から除外する。現状は除外が行われていないため、実装失敗ではない upstream 移管 close Issue が「失敗」扱いとなり、Highlights 自動検出が偽陽性を起こす。Section 4 (Work Origin) の集計には影響させない（既に独立カテゴリ扱い）。

## Reproduction Steps

1. `retro/verify` ラベル付きで `not planned` close された Issue が複数存在するリポジトリで `/audit stats` を実行する
2. Section 5 Outcome の特定 Content segment の First-try 失敗率が実態より大幅に高い値になる
3. Highlights に 2x 超の偽陽性検出が現れる

## Root Cause

Step 2 Computation の Outcome 計算母集団が `filtered_issues` 全体であり、`retro/verify` ラベル付き Issue（実装失敗ではなく wholework インフラ改善提案）が除外されていない。Section 4 (Work Origin) は既に `retro/verify` を独立カテゴリとして扱っているが、Outcome との整合性が取れていない。

## Changed Files

- `skills/audit/SKILL.md`: Step 2 Computation に Outcome Exclusion Filter サブセクションを追加。Section 5: Outcome の説明を更新し、除外母集団を明示・集計対象件数の注記表示を追加

## Implementation Steps

1. `skills/audit/SKILL.md` の Step 2 Computation 内 `#### Work Origin Classification` セクションの直後に `#### Outcome Exclusion Filter` サブセクションを追加する (→ acceptance criteria AC3)
   - 内容: `retro_verify_count`（filtered_issues 内の retro/verify ラベル付き件数）と `outcome_population`（filtered_issues から retro/verify ラベル付き Issue を除外した集合）を定義
   - 明記: Section 4 (Work Origin) の集計には retro/verify ラベルによる除外を適用しない。Section 4 は全 `filtered_issues` を母集団として使用する

2. `skills/audit/SKILL.md` の Step 3 Report Generation 内 `#### Section 5: Outcome` を更新する (→ acceptance criteria AC1, AC2)
   - `outcome_population` を使用して全 Outcome サブ項目（By Size、Phase 後戻りポイント、By Content segment、Trend）を集計することを明示
   - セクション先頭に "Outcome 集計対象: N 件 (うち retro/verify ラベル付き M 件を除外)" の注記表示を追加（N = count(outcome_population)、M = retro_verify_count）

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/audit/SKILL.md" "Section 5" "retro/verify" --> `skills/audit/SKILL.md` の Section 5 (Outcome) で `retro/verify` ラベルによる除外仕様が明示されている
- <!-- verify: section_contains "skills/audit/SKILL.md" "Outcome" "除外" --> Outcome セクションの説明に除外母集団の明示がある
- <!-- verify: rubric "skills/audit/SKILL.md の stats Subcommand 内に Section 4 (Work Origin) の集計には retro/verify ラベルによる除外を適用しないことが明記されている" --> Section 4 (Work Origin) の集計には除外を適用しない旨が SKILL.md に記載されている

### Post-merge

- saito/trading リポジトリで `/audit stats --since 2026-05-01` を実行し、backend segment の First-try 成功率が #279, #280 を除外した値に変化することを確認 <!-- verify-type: manual -->
- Outcome レポートに「対象 N 件 / 除外 M 件」表示が含まれることを確認 <!-- verify-type: manual -->
- 既存の trading レポート (`docs/stats/2026-05-26.md`) で Highlights "backend 75% failure rate" が再計算後に消える/変わることを確認 <!-- verify-type: manual -->

## Notes

- 変更対象は `skills/audit/SKILL.md` のみ（SKILL.md は仕様記述ファイルであり、テキスト追記のみで対応可能）
- bats テストファイル `tests/audit-stats.bats` は存在しないため、テスト追加は不要
- Section 5 の"Outcome 集計対象"注記は retro_verify_count が 0 の場合も常に表示する（除外処理が機能していることを明示するため）
- Highlights 自動検出の 2x failure rate criterion は Section 5 の Outcome データを参照するため、Outcome Exclusion Filter 適用後のデータが自動的に使用される（Highlights セクション自体の変更は不要）
- Section 4 (Work Origin) は `retro/verify` を独立カテゴリ "retrospective" として集計しており、除外適用外とすることで整合性が保たれる

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- SPEC_DEPTH=light (Size S / patch route) を採用。変更対象は `skills/audit/SKILL.md` 1ファイルのみでテキスト追記だけで完結するため full spec は不要と判断
- Outcome Exclusion Filter は Step 2 Computation の独立サブセクションとして追加。Step 3 Section 5 への "出力" 参照とセットにすることで responsibility を明確化
- Section 4 (Work Origin) の除外非適用はコードコメント型ではなくサブセクション内の明記で対応（AC3 rubric 要件を満たすため）

### Deferred Items
- `tests/audit-stats.bats` が存在しないため、テストカバレッジは追加なし。将来の bats テスト整備は別 Issue
- saito/trading リポジトリでの実機確認（Post-merge AC 3件）は post-merge manual 扱い

### Notes for Next Phase
- 変更は `skills/audit/SKILL.md` の 2箇所: (1) `#### Work Origin Classification` 直後に `#### Outcome Exclusion Filter` を追加、(2) `#### Section 5: Outcome` 先頭に集計対象注記と `outcome_population` 使用の明記を追加
- AC1: `section_contains "Section 5" "retro/verify"` — Section 5 内に "retro/verify" を含む文字列が必要
- AC2: `section_contains "Outcome" "除外"` — Section 5 内に "除外" を含む文字列が必要（どちらも同じ "Section 5: Outcome" セクションにヒット）
- AC3: rubric で Section 4 非適用明記を評価する。Outcome Exclusion Filter サブセクション内で明示すれば十分
