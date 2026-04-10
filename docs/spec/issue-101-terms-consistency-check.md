# Issue #101: /doc sync --deep に Terms 整合性チェックを追加

## Overview

`/doc sync --deep` の Narrative Semantic Drift Check に Terms テーブルに特化した 2 つのサブチェックを追加する。(1) Terms の "Formerly called" 旧称がコードベースで使用されている非推奨用語の残存検出、(2) コードベースで広く使用されるがTerms に未登録のドメイン固有用語の検出。検出結果は既存の drift report パイプラインに乗せる（auto-fix なし）。

## Changed Files

- `skills/doc/SKILL.md`: Narrative Semantic Drift Check セクション（L471 付近）の直後に "Terms Consistency Check" サブステップを追加

## Implementation Steps

1. **Terms テーブルのパース処理を記述** (→ acceptance criteria A)
   - product.md の `## Terms` セクションからテーブルを読み取り、各エントリの Term 名と "Formerly called" 旧称を抽出する手順を記述
   - パースは AI 判定（Grep/Read で Terms セクションを読み、テーブル行から抽出）

2. **非推奨用語の残存検出ロジックを記述** (→ acceptance criteria B)
   - 抽出した "Formerly called" 旧称ごとに、実装ファイル（`skills/*/SKILL.md`, `modules/*.md`, `agents/*.md`）を Grep
   - docs/spec/ は除外（使い捨て Spec）、Terms テーブル自体の "Formerly called" 記載は除外
   - ヒットした場合、drift report に "Deprecated term in use" カテゴリとして出力
   - 出力フォーマット: ファイルパス、該当行、正しい用語名

3. **未登録用語候補の検出ロジックを記述** (→ acceptance criteria C)
   - 実装ファイルから反復的に使用されるドメイン固有用語を AI 判定で抽出
   - Terms テーブルの既存エントリと照合し、未登録の用語を "Missing term candidate" カテゴリとして drift report に出力
   - 汎用プログラミング用語（PR, Issue, commit 等）は除外

4. **drift report への統合** (after 1, 2, 3)
   - 既存の Narrative Semantic Drift Check と同じ出力パスで findings を蓄積
   - Step 7 の normalization proposals で "Drift report" として表示（auto-fix なし）

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/doc/SKILL.md" "Narrative Semantic Drift Check" "Terms" --> `/doc sync --deep` の Narrative Semantic Drift Check セクションに Terms 整合性チェックが追加されている
- <!-- verify: grep "Formerly called" "skills/doc/SKILL.md" --> Terms の "Formerly called" 旧称のコードベース残存検出ロジックが記述されている
- <!-- verify: grep "Missing term" "skills/doc/SKILL.md" --> 未登録用語の検出ロジックが記述されている

### Post-merge

- `/doc sync --deep` を wholework リポジトリで実行し、Terms 整合性チェックの結果が drift report に含まれる (opportunistic)

## Notes

- 検出結果は全て drift report として出力し、auto-fix は行わない（既存パターンと一致）
- #98 完了後は Forbidden Expressions に用語エントリがなくなるため、Terms "Formerly called" のみをチェック対象とする設計で前方互換性あり
- 未登録用語候補の検出は AI 判定に依存するため、精度よりも recall（検出漏れの少なさ）を優先する
