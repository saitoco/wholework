# Issue #81: docs: .claude/settings.json のホットリロード非対応挙動を tech.md に記録

## Issue Retrospective (`/issue` refinement)

### 曖昧点の解決

**[ユーザ確認] 記録先ファイルを `docs/tech.md` の新規 `## Gotchas` セクションに確定**

選択肢:
1. 新規 `docs/notes.md` を作成（Issue 初稿の提案）
2. `docs/tech.md` の Architecture Decisions セクションに追記
3. 新規 `docs/gotchas.md` を作成
4. `docs/tech.md` に新規 `## Gotchas` セクションを作成（ユーザ提案、採用）

選択: 4

判断根拠:
- 新規ファイルを作らないことで `docs/structure.md` の更新が不要になり変更スコープが最小化される
- `docs/tech.md` は既存の steering document であり、Claude Code ツール固有の運用知見を集約する場所として自然な置き場
- 汎用的な `docs/notes.md` はスコープが曖昧になりがちだが、「Gotchas」は意味が明確（運用上の罠・予期しない挙動の集約）で将来の追記時に判断がブレにくい
- `ssot_for:` への `gotchas` 追記により、steering document の SSoT 宣言との整合を維持

**[自動解決] 記述の粒度は Purpose の 3 bullet をすべてカバーする方針に確定**

Purpose セクションに列挙された 3 論点（hot-reload 非対応の事実 / セッション再起動の含意 / in-session プローブ方式の偽陰性リスク）を Gotchas セクション内でそれぞれカバーする。受入条件では section_contains により `settings.json` / `hot-reload` / `restart` / `probe` の 4 キーワードを個別検証し、粒度を機械的に担保する。

**[自動解決] `docs/structure.md` への登録は不要**

新規ファイルを作らず既存の `docs/tech.md` に追記する方針のため、`docs/structure.md` の Directory Layout / Key Files セクションへの変更は発生しない。

### 受入条件の変更

初稿（`docs/notes.md` ベース、3 条件）から改訂（`docs/tech.md` ベース、6 条件）。

- 検証コマンドを `file_exists` / `file_contains` / `grep (OR pattern)` から `section_contains` / `grep` 中心に変更
- section_contains で `## Gotchas` スコープを明示することで、tech.md の他セクション（Architecture Decisions 等）での偶発マッチを回避
- frontmatter `ssot_for:` への `gotchas` 追記を新たに必須化（steering document SSoT 整合のため）
- `grep "セッション|session"` の OR pattern は `section_contains "restart"` に置換（verify-patterns.md のガイドラインに基づき OR pattern を回避）

### Risk Notes

- `docs/tech.md` の frontmatter `ssot_for:` に新エントリ (`gotchas`) を追加する行為自体は、steering document の SSoT 範囲を拡張する変更であり、`/doc` や `/audit drift` の振る舞いに影響する可能性がある。ただし本 Issue のスコープでは `ssot_for` の名前を宣言するのみで、`/doc` side の処理ロジック変更は行わない。将来 `/doc` 側で gotchas の normalize 処理を追加する場合は別 Issue で対応する。
- `## Gotchas` セクションは tech.md 末尾の追加を想定しており、既存の Architecture Decisions / Testing Strategy / Forbidden Expressions セクションには影響しない。
