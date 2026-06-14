# Issue #484: retro-proposals: Improvement Proposal の三層判定を導入（backlog ノイズ削減）

## Overview

`modules/retro-proposals.md` に Improvement Proposal の三層分類ロジックを追加する。現状はすべての提案が Issue 化されるため、backlog にノイズが蓄積している。3 Tier に分類し、Tier 1 のみ Issue 化、Tier 2 は memory 記載提案をターミナルに出力、Tier 3 は spec retrospective 記載に留めることで backlog ノイズを削減する。

**3 Tier 定義:**

| Tier | 判定基準 | アクション |
|------|---------|-----------|
| **Tier 1**: 構造課題 | 複数 skill/module の改修要 / 再発性高 / 影響範囲広 | Issue 起票（既存ロジック） |
| **Tier 2**: convention | 単発 lesson だが再発しうる / memory で十分 | memory 記載提案をターミナルに出力（ファイル自動生成なし） |
| **Tier 3**: 単発メモ | 一回限りの観察 / 再発確率低 | spec retrospective 記載のみ（Issue・memory なし） |

## Changed Files

- `modules/retro-proposals.md`: step 5 (deduplicate) 後・step 6 (HAS_SKILL_PROPOSALS gate) 前に Tier 分類ステップを挿入; 既存 step 6–10 を step 7–11 に繰り下げ

## Implementation Steps

1. `modules/retro-proposals.md` の step 5 と現 step 6 の間に **Tier 分類ステップ（新 step 6）** を追加する（→ AC1, AC2, AC3）:
   - 脱重複後の全提案リストに対して、LLM 判定 + 機械的ヒューリスティック補助で各提案を Tier 1/2/3 に分類する
   - **判定基準（LLM rubric スタイル）**:
     - Tier 1: 複数の skill/module の改修が必要 OR 再発性が高い OR 影響範囲が広い → Issue 起票
     - Tier 2: 単発 lesson だが再発しうる、memory への記載で十分 → ターミナル出力のみ
     - Tier 3: 一回限りの観察、再発確率が低い → spec retrospective 記載のみ
   - **機械的ヒューリスティック補助（非排他的）**:
     - 「複数 skill」「複数 module」「再発性」「影響範囲」含有 → Tier 1 寄り判定
     - 「convention」「パターン」「lesson」含有 → Tier 2 寄り判定
     - 「今回のみ」「一回限り」「単発」含有 → Tier 3 寄り判定
   - **デフォルト**: 判定困難な場合は Tier 1 に分類（false negative リスク回避、保守的設定）
   - **Tier 2 アクション**: 各提案に対してターミナルに出力 `"Memory proposal: {proposal title} — {proposal content}"` (memory ファイルの自動生成は行わない)
   - **Tier 3 アクション**: ターミナルに `"Skipping (Tier 3 — one-time memo): {proposal title}"` を出力し、Issue 化パイプラインから除外する
   - **Tier 1 アクション**: 提案を次ステップ（旧 step 6 → 新 step 7、HAS_SKILL_PROPOSALS gate）へ引き渡す
2. 既存 step 6–10 を step 7–11 に繰り下げる（→ Tier 1 提案が既存のゲート以降を通る backward-compatible 実装）

## Verification

### Pre-merge

- <!-- verify: rubric "modules/retro-proposals.md に Improvement Proposal の三層分類（Issue / memory / コメント終結）ロジックが追加されている" --> <!-- verify: grep "Tier 1" "modules/retro-proposals.md" --> 三層分類ロジックが実装されている
- <!-- verify: rubric "各 Tier の判定基準（再発性・影響範囲・実装規模）が明文化されている" --> <!-- verify: grep "再発性" "modules/retro-proposals.md" --> 判定基準が明文化されている
- <!-- verify: rubric "Tier 1 のみ Issue 化し、Tier 2 は memory 提案（ターミナル出力）・Tier 3 は spec retrospective に留める処理が実装されている" --> <!-- verify: grep "Tier 3" "modules/retro-proposals.md" --> 各 Tier のアクションが分岐実装されている

### Post-merge

- 代表的な `/verify` 実行で Improvement Proposals が3層に分類され、Tier 1 のみが Issue 化される <!-- verify-type: manual -->
- downstream プロジェクトで retro/verify Issue の発生量がノイズ Issue 削減方向に変化することを観察 <!-- verify-type: manual -->

## Notes

**Auto-resolved ambiguity points** (Issue body §Auto-Resolved Ambiguity Points から転記):

1. **三層分類と既存フロー（HAS_SKILL_PROPOSALS gate）の統合位置**: step 5 後・step 6 前に挿入。Tier 1 のみ既存ゲートに進む。理由: 既存ロジックを破壊せず最低リスク。
2. **Tier 2 memory 提案の実装形式**: ターミナル出力のみ（ファイル自動生成なし）。理由: memory 汚染リスク回避、手動 review を挟む設計。
3. **Tier 判定の実装方式**: LLM 判定主体 + 機械的ヒューリスティック補助を明文化。理由: 既存 domain-classifier.md との一貫性 + AC2 が「判定基準の明文化」を要求。

**Verify command 存在確認**: `grep "Tier 1"`, `grep "再発性"`, `grep "Tier 3"` の各パターンは実装後に `modules/retro-proposals.md` に導入されるため、現時点では存在しない。実装時に確実に含めること。
