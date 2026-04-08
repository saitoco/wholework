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

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- XS パッチルートのため spec フェーズなし。Issue Retrospective で3つの曖昧性ポイントを自動解決しており、受入条件が明確で検証容易な形式で記述されていた。`file_not_exists`・`file_not_contains`・`section_not_contains` の各ヒントが適切に設定されており、全条件を自動検証できた。

#### design
- N/A（XS パッチルート）

#### code
- 単一コミット `f9dd442` で5箇所の機械的修正を完了。リワークなし。`docs/migration-notes.md` のスコープ外判断が明示されており、変更範囲が適切に制御されていた。

#### review
- XS パッチルートのため正式レビューなし。受入条件が自動検証可能な形式で記述されていたため、verify フェーズでの事後確認が機能した。

#### merge
- main への直接コミット（パッチルート）。コンフリクトなし、クリーン。

#### verify
- 全5件のプレマージ条件が PASS。Post-merge の opportunistic 条件（`/doc init` 実行時のエラーメッセージ確認）はユーザー検証待ち（`phase/verify` ラベル付与）。
- `section_not_contains` ヒントが正確に動作し、特定セクション内の文字列不在を検証できた。

### Improvement Proposals
- N/A
