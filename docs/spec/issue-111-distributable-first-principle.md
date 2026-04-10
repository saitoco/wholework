# Issue #111: tech: 配布可能コンポーネント優先の改善反映原則を追加

## Issue Retrospective

### 曖昧さ解決の判断根拠

3点の曖昧さを検出し、すべて自動解決:

1. **配置場所**: Architecture Decisions セクション → ユーザーが「原則セクションに追加」を選択。設計判断の記録場所として最適
2. **原則の適用範囲**: レトロスペクティブ限定ではなく、改善の反映先に関する一般原則 → ユーザーの背景説明から推論（「Wholework ユーザー向けに必要な改善は Skills, Agents, Modules, Scripts に反映する必要がある」）
3. **Skill への影響範囲**: tech.md 追記のみ、Skill 変更は別 Issue → ユーザーが「この観点を tech.md に追加したい」と明示

### 主要な方針決定

- 受入条件は pre-merge のみ（ドキュメント変更のため post-merge 検証不要）
- `section_contains` で Architecture Decisions セクション内の記述を検証する設計

### 受入条件変更理由

初回作成のため変更なし。
