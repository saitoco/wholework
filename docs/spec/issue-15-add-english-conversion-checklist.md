# Issue #15: scripts: Add English conversion checklist to migration spec steps

## issue レトロスペクティブ

### 判断経緯
- 既存の verify ヒント（`grep "English"` / `grep "English conversion"`）が既存コンテンツに既にマッチして TRUE になる問題を検出し、より具体的なパターン（`section_contains` / テスト未カバー文字列を検証する grep）に改善した

### 重要な方針決定
- 特になし（自動解決2件はユーザー承認済み）

### 受け入れ条件の変更理由
- マージ前/マージ後のセクション分けを追加（元の Issue にはなかった）
- verify ヒントを改善: 既存コンテンツとの誤マッチを防ぐため、`section_contains` と具体的な grep パターンに変更
- 自動解決済みの曖昧ポイントセクションを追記
