# Issue #29: docs: Update structure.md Directory Layout to reflect skill sub-files pattern

## Issue Retrospective

### Ambiguity Resolution
- **サブファイルパターンの記載粒度**: 自動解決。既存の Directory Layout が `<placeholder>` 形式で抽象化しているパターンに倣い、パターン記述 + Key Files セクションでの説明で対応。全ファイル列挙は行わない判断。

### Policy Decisions
- 受け入れ条件に `section_contains` を追加し、Directory Layout セクションと Key Files セクションそれぞれでの記載を検証するよう改善。

### Acceptance Criteria Changes
- 元の `grep "mcp-call-guidelines"` を特定ファイル名依存から汎用パターンチェックに変更。
- `section_contains` による Key Files セクション内の補助ファイル説明検証を追加。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件が `grep` + `section_contains` で適切に構造化されており、曖昧さなく自動検証可能だった。

#### design
- N/A（spec phase のみで完結するシンプルな変更）

#### code
- `a561725` で `docs/structure.md` を5行の差分で修正。リワークなし。

#### review
- PRではなく直接 main へのコミットで完結。XS サイズのため patch ルート適用。

#### merge
- 直接 main コミット（patch ルート）。衝突なし。

#### verify
- 全4条件 PASS。PRなしでも `grep`/`section_contains` による静的検証が有効に機能した。

### Improvement Proposals
- N/A
