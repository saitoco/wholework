# Issue #48: cleanup: Remove obsolete package.json and install.sh references after plugin migration

## Issue Retrospective

### 判断根拠

3つの曖昧性ポイントをすべて自動解決:

1. **エラーメッセージの書き換え**: README の Install セクション（`/plugin install wholework@saitoco-wholework`）を ground truth として、plugin 方式に整合した表現に統一する
2. **installation path 説明**: plugin 方式では `${CLAUDE_PLUGIN_ROOT}` 経由で参照されるため、symlink ベースの説明を「plugin manifest 経由」に書き換える
3. **install.sh スキャン対象**: plugin manifest（`.claude-plugin/plugin.json` 等）は別途管理されるため単純削除でよい

### スコープ判断

- `docs/migration-notes.md` の `install.sh` 参照は移植時の履歴記録として残す（スコープ外）
- 5箇所すべてが小規模な機械的修正で、相互依存なし → XS パッチルートが適切

### 受入条件の変更理由

なし（初回作成）
