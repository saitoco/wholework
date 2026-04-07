# Issue #25: migration: Add comprehensive Japanese residual check to acceptance criteria

## issue レトロスペクティブ

### 判断経緯
- 元の受け入れ条件2つがほぼ同一の検証対象（migration-notes.md 内の日本語チェック関連テキスト）を重複して検証していたため、1つに統合した
- verify ヒントの grep パターンを `"3000.*9FFF"` に変更し、Unicode 範囲の記載を直接検証する設計に改善した

### 重要な方針決定
- 特になし

### 受け入れ条件の変更理由
- 重複する2条件を1条件に統合（migration-notes.md 内の日本語残留チェックコマンド記載確認）
- マージ前/マージ後のセクション分けを追加
- 目的を「テンプレートまたはガイドライン」から具体的に「English Conversion Checklist」に明確化
