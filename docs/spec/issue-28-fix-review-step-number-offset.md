# Issue #28: review: Fix systematic step number offset in SKILL.md and external-review-phase.md

## issue レトロスペクティブ

### 判断経緯
- 条件1の `grep "### 7.0."` が Step 8 下の同名サブステップにもマッチし false positive になる問題を検出。`section_contains` に変更して Step 7 セクション内に限定した
- 受け入れ条件が Step 7・10 のみだったが、コードベース調査で Step 8, 12, 13, 14 にも同様のオフセットを確認。条件5のバリデーションスクリプトが全体整合性を担保するため、代表チェックとして Step 8 の条件を追加した

### 重要な方針決定
- 自動解決2件をユーザーが承認。質問なしで完了

### 受け入れ条件の変更理由
- 条件1: `grep` → `section_contains` に変更（false positive 回避）
- 条件2追加: `## Step 8` 内の `### 8.0.` チェック（Step 8 も修正対象であることを明示）

## verify レトロスペクティブ

### 各フェーズの振り返り

#### spec
- Issue レトロスペクティブのみ。XS/S サイズのためフルSpec は未作成
- 受け入れ条件に `section_contains` を使用した精度改善（false positive 回避）が事前に行われており、verify で検証漏れなし

#### design
- 特になし（設計フェーズなし）

#### code
- コミット `6e541c6` 1件、fixup/amend なしのクリーンな実装
- 3ファイル（SKILL.md、external-review-phase.md、skill-dev-recheck.md）を一括修正、手戻りゼロ

#### review
- パッチルート（XS/S）のため PR・コードレビューなし
- バリデーションスクリプト（`validate-skill-syntax.py`）が全体整合性を担保しており、レビュー省略のリスクを軽減している

#### merge
- main へ直接コミット（パッチルート）。コンフリクトなし

#### verify
- 全5条件PASS。自動検証不可条件なし
- `section_contains` を使用した条件が正しく機能し、false positive を回避できた

### 改善提案
- 特になし
