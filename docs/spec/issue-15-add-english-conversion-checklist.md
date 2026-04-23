# Issue #15: scripts: Add English conversion checklist to migration spec steps

## issue レトロスペクティブ

### 判断経緯
- 既存の verify command（`grep "English"` / `grep "English conversion"`）が既存コンテンツに既にマッチして TRUE になる問題を検出し、より具体的なパターン（`section_contains` / テスト未カバー文字列を検証する grep）に改善した

### 重要な方針決定
- 特になし（自動解決2件はユーザー承認済み）

### 受け入れ条件の変更理由
- マージ前/マージ後のセクション分けを追加（元の Issue にはなかった）
- verify commandを改善: 既存コンテンツとの誤マッチを防ぐため、`section_contains` と具体的な grep パターンに変更
- 自動解決済みの曖昧ポイントセクションを追記

## verify レトロスペクティブ

### 各フェーズの振り返り

#### spec
- verify commandの精度が高く、既存コンテンツとの誤マッチを事前に回避する設計になっていた（`section_contains` と具体的な grep パターンへの改善）

#### design
- 特になし（issue レトロスペクティブに統合記録済み）

#### code
- 実装コミット1件（`a07f9b3`）のみ、手戻りなし
- XS サイズの patch ルートで main に直接コミット

#### review
- patch ルートのため PR レビューなし

#### merge
- patch ルートのため PR マージなし。main への直接コミット・push

#### verify
- 全条件 PASS。受け入れチェック（`section_contains` / `grep`）が適切に設計されており、自動検証が問題なく機能した

### 改善提案
- 特になし
