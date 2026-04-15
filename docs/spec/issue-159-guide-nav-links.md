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

## Spec Retrospective

（/spec フェーズが記入）

## Code Retrospective

### Deviations from Design
- なし。Spec の実装ステップ通りに実施した。

### Design Gaps/Ambiguities
- なし。Spec は明確で実装に迷う箇所がなかった。

### Rework
- なし。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受入条件は `file_contains` を使用し、明確・自動検証可能に設計されている。`quick-start.md` の除外判断もIssue本文内で事前解決済みであり、曖昧性のない良質なSpec。
- `## Spec Retrospective` セクションは "(記入待ち)" のままで未記入。/specフェーズでの振り返りが実施されていない可能性がある。

#### design
- 変更ファイルのリストと実装ステップが1対1で対応しており、設計の一貫性が高い。
- 日本語ミラーファイル（`docs/ja/`）を受入条件の範囲外として明示した上で同時更新する方針は適切。

#### code
- リワークなし。実装コミット1件（202d035）でSpec通りに6ファイルを更新。シンプルかつ明快な実装。

#### review
- パッチルートのため PRなし・レビューなし。ドキュメント追加のみの変更であり、PRレビューなしでも品質リスクは低い。

#### merge
- パッチルートでmainに直接コミット。コンフリクトなし。クリーンなマージ。

#### verify
- 3条件すべてPASS。`file_contains` の検証は高精度で誤検知・見逃しなし。

### Improvement Proposals
- N/A
