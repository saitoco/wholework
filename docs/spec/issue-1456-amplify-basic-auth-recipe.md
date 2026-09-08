# Issue #1456: adapter-guide: preview-basic-auth-command に .env ベースの production-proven レシピ (Amplify Basic 認証) を追加

Size XS のため spec フェーズはスキップし、`/auto` の patch route (code → verify) で実行した。本ファイルは `/verify` の Improvement Proposal パイプラインが issue retrospective を収集できるようにするための転記先。

## Issue Retrospective

`/issue 1456 --non-interactive` による Existing Issue Refinement を実行した。

### Triage 自動チェーン結果

- Type: Task
- Size: XS (docs/guide/adapter-guide.md と docs/guide/customization.md の 2 ファイルのみ変更、ドキュメントのみの変更で複雑度調整 -1)
- Value: 2 (Impact=0, Alignment=2)
- Theme: 該当なし (未分類)
- 重複候補: なし (#1417 / #1429 は解決済み Related、#1423 はスコープの異なる Related)
- AC verify command 監査: 問題なし (5 件の verify command すべて健全)
- Stale チェック: 停滞パターンなし
- 依存関係チェック: ブロッカーなし

### 判断根拠 (Ambiguity Auto-Resolve)

非対話モードのため、以下 2 点をモデル判断で自動解決し、Issue 本文に `## Auto-Resolved Ambiguity Points` として記録した。

1. **既存の「generic CI secret template (illustrative, unproven)」節の扱い**: 削除せず残し、`preview-url-command` と同じ構造 (「Preview URL / Basic Auth Command Recipes」節配下に `### `preview-basic-auth-command` — AWS Amplify Hosting (production-proven)` を新規追加) を採用。根拠: `docs/guide/adapter-guide.md` に既に `preview-url-command` 用の production-proven サブセクションが存在し、末尾に「provider ごとにサブセクションを追記する」という方針が明記されているため、既存パターンから一意に推論可能だった。
2. **AC3 (`no adopted implementation yet` の削除) の実現方法**: illustrative 節自体は残し、文言のみ「Amplify 向け production-proven 実装が存在する」旨に修正する方針とした。illustrative 節の完全削除は既存パターン (他プロバイダ向けの出発点として維持) と矛盾するため不採用。

### Acceptance Criteria の変更

なし (Pre-merge / Post-merge の条件文・verify command は起票時点から変更していない)。

### Consumed Comments

No new comments since last phase.
