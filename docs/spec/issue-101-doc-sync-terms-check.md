# Issue #101: doc: /doc sync --deep に Terms 整合性チェックを追加

## Overview

`/doc sync --deep` の Narrative Semantic Drift Check に Terms 整合性チェックを追加する。
検出対象は以下の2種類:
1. **非推奨用語の残存**: Terms テーブルの "Formerly called" に記録された旧称がコードベースで使用されているケース
2. **未登録用語の追加漏れ**: コードベースで広く使用されているが Terms テーブルに未登録のドメイン固有用語

## Changed Files

- `skills/doc/SKILL.md`: Narrative Semantic Drift Check セクション内に Terms 整合性チェックを追加

## Implementation Steps

1. `skills/doc/SKILL.md` の `**Narrative Semantic Drift Check (--deep only):**` セクション内の「**Output findings as drift report:**」段落の直後に「**Terms consistency check:**」サブセクションを追加する (→ 受入条件 A, B, C)

   追加する内容:
   - **見出し**: `**Terms consistency check:**`
   - **説明**: このチェックは `--deep` フラグが有効な場合のみ実行する
   - **Step 1 — Deprecated term detection**:
     - Steering Documents（product.md 等）のTermsテーブルをスキャンして「Formerly called」エントリを抽出する
     - 各旧称をキーワードとしてコードベース（`skills/*/SKILL.md`, `modules/*.md`, `agents/*.md`）を Grep する
     - ヒットした箇所を drift report に「非推奨用語の残存」として追加する。各項目は Steering Document 名・セクション名・ドリフトカテゴリ・旧称・出現場所・更新方向を含む
   - **Step 2 — Missing term detection**:
     - Steering Documents の Terms テーブルに登録済みの用語一覧を取得する
     - `skills/*/SKILL.md`, `modules/*.md`, `agents/*.md` から 3 ファイル以上に出現するドメイン固有の名詞・概念語を候補として AI 判断で抽出する
     - Terms テーブルに未登録の候補を「Missing term」として drift report に追加する。各項目は未登録用語・出現ファイル数・出現箇所例・追加提案を含む
   - **出力**: 両チェックの結果を既存の drift report に統合し、Step 7 の normalization proposals に渡す（自動修正なし）

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/doc/SKILL.md" "Narrative Semantic Drift Check" "Terms" --> Narrative Semantic Drift Check セクションに Terms 整合性チェックが追加されている
- <!-- verify: grep "Formerly called" "skills/doc/SKILL.md" --> Terms の "Formerly called" 旧称のコードベース残存検出ロジックが記述されている
- <!-- verify: grep "Missing term" "skills/doc/SKILL.md" --> 未登録用語の検出ロジックが記述されている

### Post-merge

- `/doc sync --deep` を wholework リポジトリで実行し、Terms 整合性チェックの結果が drift report に含まれることを確認する

## Notes

- Terms テーブルのスキャン対象は `ssot_for: terminology` を持つ Steering Document（現状は `docs/product.md`）。frontmatter の `ssot_for` フィールドで動的に判定する
- Missing term 検出はAI判断に依拠するため、閾値（3ファイル以上）は誤検知抑制の目安。一般的な英単語（"step", "file", "skill" 等）は除外対象とする
- 両チェックとも drift report への追加のみ行い、自動修正は行わない（既存の Narrative Semantic Drift Check と同方針）
- `section_contains` が `**Narrative Semantic Drift Check (--deep only):**`（bold 形式の見出し）を section 境界として認識できるかは verify 実行時に確認する

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- 2つの Spec ファイル（`issue-101-doc-sync-terms-check.md` と `issue-101-terms-consistency-check.md`）が存在したが、両者は同じ要件を記述しており内容は一致していた。`doc-sync-terms-check.md` をメインとして採用した

### Rework
- N/A
