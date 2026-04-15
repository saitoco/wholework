# Issue #159: docs/guide/ ページ間のナビゲーションリンクを追加

## Overview

`docs/guide/workflow.md`・`docs/guide/customization.md`・`docs/guide/troubleshooting.md` の3ページに、ガイドインデックスページ（`index.md`）へのナビゲーションリンクが存在しない。ユーザーが各ガイドページ間で迷子にならないよう、各ページから `index.md` および関連ページへの Navigation リンクを追加する。

`quick-start.md` は既存の「🧭 Next Steps」セクションに Customization・Troubleshooting へのナビゲーションリンクが存在するため対象外（Issue スコープの明示的な記述と既存ファイルの状態に基づく判断）。

## Changed Files

- `docs/guide/workflow.md`: "Further Reading" セクションに `[User Guide](index.md)` リンクを追加
- `docs/guide/customization.md`: ファイル末尾にナビゲーションフッター（`index.md` リンク）を追加
- `docs/guide/troubleshooting.md`: "Further Help" セクションに `[User Guide](index.md)` リンクを追加
- `docs/ja/guide/workflow.md`: 「さらに読む」セクションに `[ユーザーガイド](index.md)` リンクを追加
- `docs/ja/guide/customization.md`: ファイル末尾にナビゲーションフッター（`index.md` リンク）を追加
- `docs/ja/guide/troubleshooting.md`: 「さらに助けが必要なとき」セクションに `[ユーザーガイド](index.md)` リンクを追加

## Implementation Steps

1. `docs/guide/workflow.md` の "## Further Reading" セクション末尾に `- [User Guide](index.md) — Overview of all guide pages` を追加 (→ 受入条件 1)

2. `docs/guide/customization.md` のファイル末尾に `---` 区切りと `← [User Guide](index.md)` ナビゲーションフッターを追加 (→ 受入条件 2)

3. `docs/guide/troubleshooting.md` の "## Further Help" セクション末尾に `- [User Guide](index.md) — Overview of all guide pages` を追加 (→ 受入条件 3)

4. 日本語ミラーファイルを対応して更新（ステップ 1〜3 と並列可能）:
   - `docs/ja/guide/workflow.md`: "## さらに読む" セクション末尾に `- [ユーザーガイド](index.md) — ガイドページ一覧` を追加
   - `docs/ja/guide/customization.md`: ファイル末尾に `---` 区切りと `← [ユーザーガイド](index.md)` を追加
   - `docs/ja/guide/troubleshooting.md`: "## さらに助けが必要なとき" セクション末尾に `- [ユーザーガイド](index.md) — ガイドページ一覧` を追加

## Verification

### Pre-merge

- <!-- verify: file_contains "docs/guide/workflow.md" "index.md" --> `docs/guide/workflow.md` に `index.md` へのリンクが追加されている
- <!-- verify: file_contains "docs/guide/customization.md" "index.md" --> `docs/guide/customization.md` に `index.md` へのリンクが追加されている
- <!-- verify: file_contains "docs/guide/troubleshooting.md" "index.md" --> `docs/guide/troubleshooting.md` に `index.md` へのリンクが追加されている

### Post-merge

- `/verify 159` がすべての受入条件について PASS を報告する

## Notes

- Issue #154 レビュー時に SHOULD レベルの問題として検出された項目
- `quick-start.md` を対象外とする判断は自動解決済み（Issue 本文の自動解決済み曖昧性ポイント参照）
- 日本語ミラーファイル（`docs/ja/guide/`）は Issue の受入条件に含まれないが、翻訳の一貫性を維持するため同時に更新する
