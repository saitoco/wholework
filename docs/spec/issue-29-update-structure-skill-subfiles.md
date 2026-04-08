# Issue #29: docs: Update structure.md Directory Layout to reflect skill sub-files pattern

## Issue Retrospective

### Ambiguity Resolution
- **サブファイルパターンの記載粒度**: 自動解決。既存の Directory Layout が `<placeholder>` 形式で抽象化しているパターンに倣い、パターン記述 + Key Files セクションでの説明で対応。全ファイル列挙は行わない判断。

### Policy Decisions
- 受け入れ条件に `section_contains` を追加し、Directory Layout セクションと Key Files セクションそれぞれでの記載を検証するよう改善。

### Acceptance Criteria Changes
- 元の `grep "mcp-call-guidelines"` を特定ファイル名依存から汎用パターンチェックに変更。
- `section_contains` による Key Files セクション内の補助ファイル説明検証を追加。
