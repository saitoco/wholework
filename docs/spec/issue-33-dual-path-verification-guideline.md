# Issue #33: docs: Add guideline for verifying both ~/.claude/ and $HOME/.claude/ in path replacement tasks

## Issue Retrospective

### Changes from Initial Issue

- **verify hint 修正**: `section_contains "docs/migration-notes.md" "path" "HOME"` → `grep "grep.*HOME" "docs/migration-notes.md"` に変更。元の heading "path" が曖昧で実際のセクション見出しと一致しないリスクがあったため、grep ベースの hint に統一。
- **受け入れ条件フォーマット整備**: Pre-merge (auto-verified) セクション形式に整備。verify hint をインライン HTML コメント形式で条件テキストの前に配置。
- **推奨パターン例の汎用化**: ハードコードパス `/Users/saito/.claude/` → `$HOME/.claude/` に修正する方針を Auto-Resolved に記録。

### Ambiguity Auto-Resolution

- 3 点すべて自動解決（ハードコードパスの汎用化、セクション配置、verify hint 修正）。ユーザー確認不要な明確な改善のみ。
