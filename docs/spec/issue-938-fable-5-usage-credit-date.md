# Issue #938: fable-5: --fable 警告と tech.md の usage-credits 日付表現を現在形に更新

## Overview

Fable 5 (`claude-fable-5`) は 2026-06-13 から政府指令により一時停止されていたが 2026-07-01 に再デプロイされた (`docs/reports/claude-sonnet-5-impact-strategy.md` §3.5)。停止注記自体は既に削除済み (b8be966d) だが、subscription プランの usage-credit ゲート開始日 (2026-06-22) を未来の予定として言及する表現が `scripts/run-spec.sh` と `docs/tech.md` の2箇所に残っており、既に過去日付となっている。この2箇所を現在形の表現に更新し、ゲートが既に有効であることを正確に伝える。`docs/ja/tech.md` の対応段落も手動で同期する。

## Changed Files

- `scripts/run-spec.sh`: `--fable` 警告 (117行目) から過去日付表現 "after 2026-06-22" を除去 — bash 3.2+ 互換 (文字列変更のみ、構文への影響なし)
- `docs/tech.md`: Fable 5 段落 (111行目) の "usage-credit gated on subscription plans after 2026-06-22" から "after 2026-06-22" を除去
- `docs/ja/tech.md`: [Steering Docs sync candidate / 翻訳ミラー] `docs/tech.md` の Fable 5 段落 (109行目) と同内容を日本語で同期 (`docs/translation-workflow.md` 準拠。verify command は付与しない)

## Implementation Steps

1. Fable 5 の 2026-07-01 再デプロイ後、usage-credit ゲート条件 (subscription プランでの課金開始) に変更がないかを確認する。`docs/reports/claude-sonnet-5-impact-strategy.md` §3.5 (2026-07-02 付、再デプロイ後に作成) は「redeployment は Fable 5 のコスト・retention・subscription-gating 制約を変更しない」と明記しており、変更なしの裏付けとなる。実装時にこの前提が現状も成立しているかを再確認し (可能であれば Anthropic 公式発表を追加確認)、確認結果を Issue #938 のコメントとして記録する。変更なしの場合は Step 2-4 の文言をそのまま採用し、変更ありの場合は実際の条件を文言に反映する
2. `scripts/run-spec.sh` の `--fable` 警告 (117行目) を更新: `WARNING: Usage credits required after 2026-06-22 (subscription plans)` → `WARNING: Usage credits required (subscription plans)` (after 1) (→ acceptance criteria 1, 2)
3. `docs/tech.md` の Fable 5 段落 (111行目) を更新: "...usage-credit gated on subscription plans after 2026-06-22." → "...usage-credit gated on subscription plans." (after 1) (→ acceptance criteria 3, 4, 5)
4. `docs/translation-workflow.md` の同期手順に従い、`docs/ja/tech.md` の Fable 5 段落 (109行目) を更新: "...2026-06-22 以降はサブスクリプションの usage credit ゲート。" → "...サブスクリプションの usage credit ゲート。" (after 3) (verify command なし — 翻訳ファイル)

## Verification

### Pre-merge
- <!-- verify: file_not_contains "scripts/run-spec.sh" "after 2026-06-22" --> `scripts/run-spec.sh` の `--fable` 警告から過去日付表現 "after 2026-06-22" が除去されている
- <!-- verify: grep "[Uu]sage credits required" "scripts/run-spec.sh" --> usage credits 警告自体は現在形で維持されている
- <!-- verify: file_not_contains "docs/tech.md" "2026-06-22" --> `docs/tech.md` から過去日付 "2026-06-22" が除去されている
- <!-- verify: grep "usage-credit gated" "docs/tech.md" --> Fable 5 段落のゲート制約の記述自体は維持されている
- <!-- verify: rubric "docs/tech.md の Fable 5 段落が subscription プランの usage-credit ゲートを過去日付への言及なしの現在形で記述している" --> Fable 5 段落の記述が現状 (ゲート有効) を正確に反映している

### Post-merge

なし

## Notes

- **Auto-Resolved Ambiguity Points (Issue Retrospective より引き継ぎ)**: `/issue` フェーズ (非対話モード) で以下3点が自動解決済み。本 spec はそのまま引き継ぐ
  - 再開後のゲート条件確認の扱い → AC 化せず実装時手順として本文記載 (外部情報の確認は機械検証不能なため)
  - `docs/ja/tech.md` の同期方法 → 実装時に手動同期 (翻訳ファイルは verify command 付与対象外)
  - `docs/reports/` / `docs/spec/` 配下の同日付言及 → 対象外 (point-in-time 文書は更新しない既存運用)
- **スコープ境界の確認**: リポジトリ全体で "2026-06-22" を grep した結果、対象3ファイル (`scripts/run-spec.sh`, `docs/tech.md`, `docs/ja/tech.md`) 以外に該当するのは `docs/reports/claude-fable-5-impact-strategy.md` (en/ja、point-in-time レポート)、`docs/spec/issue-559-*.md` / `issue-904-*.md` (disposable spec、historical record)、`docs/sessions/98856-.../session.md` (ディレクトリ名がたまたま日付を含むのみで実質的な言及ではない) のみで、いずれも Issue 本文が明記する対象外に該当する。追加の変更対象なし
- **Steering Docs sync candidate check**: `scripts/run-spec.sh` の変更に伴い `docs/migration-notes.md` / `docs/structure.md` / `docs/ja/structure.md` / `docs/ja/migration-notes.md` を grep したが、いずれも `run-spec.sh` をスクリプト一覧として言及するのみで、変更対象の日付表現・usage-credit 文言は含まれていない (grep で確認済み)。追加の変更不要
- **AC 設計の補足 (Issue Retrospective より)**: 削除検証 (`file_not_contains`) と維持ガード (`grep`) のペア構成。維持ガード単体は変更前から PASS するが、「日付表現の除去時に警告/制約記述ごと削除してしまう」誤実装の検出が目的
- **前提の裏付け**: `docs/reports/claude-sonnet-5-impact-strategy.md` §3.5 (2026-07-02 付、Fable 5 再デプロイ後に作成) が「redeployment は Fable 5 のコスト・retention・subscription-gating 制約を変更しない」と明記しており、Step 1 の確認手順の前提 (変更なしの可能性が高い) を補強する。ただし最終判断は実装時の確認に委ねる

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: `/issue` フェーズ (非対話モード) の Issue Retrospective — 曖昧性自動解決ログ3点 (ゲート確認手順・docs/ja/tech.md 同期方法・docs/reports 等の対象外化) と AC設計補足 (削除検証+維持ガードのペア構成の意図、docs/tech.md 内の該当文字列が単一箇所であることの事前確認) を記録。新規の指示・要求は含まれず、本 spec はその判断根拠をそのまま引き継ぐ / URL: https://github.com/saitoco/wholework/issues/938#issuecomment-4886082111
- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: `/code` 実装時の usage-credit ゲート条件確認結果 — `docs/reports/claude-sonnet-5-impact-strategy.md` §3.5 (再デプロイ後作成) に基づき、ゲート条件に変更なしと確認。Spec の提案文言をそのまま採用して実装 / URL: https://github.com/saitoco/wholework/issues/938#issuecomment-4886620991

## Autonomous Auto-Resolve Log

- `phase/ready` ラベルが Issue に付与されていなかったが (`phase/code` ラベルのみ)、Spec ファイル (`docs/spec/issue-938-fable-5-usage-credit-date.md`) は既に存在し設計内容も完備していたため、実行を継続 (auto-resolve: proceed)。ラベル遷移状態の不整合であり、Spec 内容自体に問題はないと判断

## Code Retrospective

### Deviations from Design
- N/A — Spec の Implementation Steps をそのまま実施 (Step 1 のゲート条件確認は先行する `/code` セッションで既に Issue コメントとして記録済みだったため、本セッションでは新規コメント投稿を省略し Step 2-4 のファイル編集から再開)

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の提案文言 (日付表現の除去のみ、ゲート条件記述自体は維持) をそのまま採用。usage-credit ゲート条件の再確認は先行セッションで完了済みで変更なしと確認されていたため、追加確認は行わなかった
- `scripts/run-spec.sh` / `docs/tech.md` / `docs/ja/tech.md` の3ファイルのみを変更対象とし、Spec の Notes に記載されたスコープ境界確認 (docs/reports/ 等は対象外) をそのまま踏襲した

### Deferred Items
- None

### Notes for Next Phase
- Pre-merge AC 5件はすべて機械検証 (grep/file_not_contains) 済みで PASS。rubric AC も目視確認済み。`/verify` フェーズでは特別な追加確認は不要と見込まれる
