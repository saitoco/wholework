# Issue #33: docs: Add guideline for verifying both ~/.claude/ and $HOME/.claude/ in path replacement tasks

## Issue Retrospective

### Changes from Initial Issue

- **verify hint 修正**: `section_contains "docs/migration-notes.md" "path" "HOME"` → `grep "grep.*HOME" "docs/migration-notes.md"` に変更。元の heading "path" が曖昧で実際のセクション見出しと一致しないリスクがあったため、grep ベースの hint に統一。
- **受け入れ条件フォーマット整備**: Pre-merge (auto-verified) セクション形式に整備。verify hint をインライン HTML コメント形式で条件テキストの前に配置。
- **推奨パターン例の汎用化**: ハードコードパス `/Users/saito/.claude/` → `$HOME/.claude/` に修正する方針を Auto-Resolved に記録。

### Ambiguity Auto-Resolution

- 3 点すべて自動解決（ハードコードパスの汎用化、セクション配置、verify hint 修正）。ユーザー確認不要な明確な改善のみ。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue Retrospective のみ存在し、Spec Retrospective は未記録（Spec フェーズ省略のため）。
- verify hint の修正（`section_contains` → `grep` ベース）は Issue フェーズで自動解決されており、受け入れ条件の品質向上が実証された。

#### design
- 専用の設計フェーズは省略。シンプルなドキュメント追加タスクのため適切な判断。

#### code
- コミット `718b7da` 1件でタスク完了（`docs/migration-notes.md` に34行追加）。rework なし、スムーズな実装。
- `patch` ルートによる main への直接コミットが採用された。

#### review
- PR を作成せず main への直接コミット（patch ルート）。コードレビューは実施されていない。
- ドキュメント追加のみの変更なので、レビューコストを省いたトレードオフは妥当。

#### merge
- 直接コミットのため merge プロセスなし。コンフリクトなし。

#### verify
- 全2条件 PASS。`grep` ベースの verify hint が期待通りに機能。
- `section_contains` から `grep` への hint 変更が正しい判断だったことが検証で確認された。

### Improvement Proposals
- N/A
