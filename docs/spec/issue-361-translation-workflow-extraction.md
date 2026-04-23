# Issue #361: sub-4a: docs/translation-workflow.md を新設し docs/ja/ 同期ロジックを 3 skill から退避

## Overview

Core/Domain 分離 Phase 4 (#295) の一部。`skills/code/SKILL.md:235`、`skills/spec/SKILL.md:229-231`、`skills/review/SKILL.md:784` に散在する `docs/ja/` ミラー同期ロジック（同期条件・除外対象リスト・更新指示）を、新規 Project Document `docs/translation-workflow.md` へ退避する。

3 skill は inline ロジックを削除し、`docs/translation-workflow.md` が存在する場合にそれを参照する形に変更する。他プロジェクト（`docs/ja/` 多言語運用を採用しないリポ）ではファイルが不在のため当該ガイダンスが混入しなくなる。

退避対象外: `skills/spec/SKILL.md` の `docs/ja/*` ファイル向け verify command 設計ガイダンス（"Japanese-format patterns in verify commands"）は翻訳運用知識ではなく verify command 品質に関する Core ガイダンスのため保持する。

## Changed Files

- `docs/translation-workflow.md`: 新規作成 — `type: project`、docs/ja/ 同期ルール（同期タイミング・除外対象・参照 skill）を文書化
- `docs/ja/translation-workflow.md`: 新規作成 — 上記の日本語ミラー
- `skills/code/SKILL.md`: line 235 の inline docs/ja/ 同期ロジック（除外リスト付き）を `docs/translation-workflow.md` 参照に置き換え — bash 3.2+ compat 影響なし
- `skills/spec/SKILL.md`: lines 229-231 の inline docs/ja/ 同期ロジック（除外リスト付き）を `docs/translation-workflow.md` 参照に置き換え（line ~301 の verify command 設計ガイドは変更しない）— bash 3.2+ compat 影響なし
- `skills/review/SKILL.md`: line 784 の inline docs/ja/ 同期ロジック（レビューチェックリスト内）を `docs/translation-workflow.md` 参照に置き換え — bash 3.2+ compat 影響なし
- `docs/structure.md`: Directory Layout に `translation-workflow.md` エントリを追加
- `docs/ja/structure.md`: 上記の日本語ミラー更新

## Implementation Steps

1. `docs/translation-workflow.md` を新規作成する。frontmatter に `type: project` と `ssot_for: ja-translation-sync` を宣言。内容: 同期タイミング（top-level `docs/*.md` 追加・変更時）、除外対象（`docs/spec/`、`docs/reports/`、`docs/ja/` サブディレクトリ）、参照 skill 一覧（`/code`・`/spec`・`/review` と各 SKILL.md パス）、同期手順（除外リストを適用後、対応する `docs/ja/<filename>.md` を英語の変更内容に合わせて更新）。先頭に `English | [日本語](ja/translation-workflow.md)` 行を付与する。(→ 受け入れ基準 1, 2, 3)

2. 3 つの skill ファイルを更新する。各ファイルで inline 同期ロジック（除外リスト・更新指示）を削除し、"If `docs/translation-workflow.md` exists, read it and follow the sync procedure." という一文に置き換える。`skills/spec/SKILL.md` では `docs/ja/*` ファイル向け verify command 設計ガイドは変更しない。(→ 受け入れ基準 4, 5, 6, 7)

3. `docs/ja/translation-workflow.md` を新規作成する（step 1 の日本語版）。先頭に `[English](../translation-workflow.md) | 日本語` 行を付与する。(→ docs/ja/ 同期ルール準拠)

4. `docs/structure.md` の Directory Layout に `translation-workflow.md` エントリを追加（`routines-adoption.md` の直後）。`docs/ja/structure.md` も同様に更新する。(→ doc-checker 構造変更ルール)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/translation-workflow.md" --> `docs/translation-workflow.md` が作成されている
- <!-- verify: file_contains "docs/translation-workflow.md" "type: project" --> frontmatter に `type: project` が宣言されている
- <!-- verify: rubric "docs/translation-workflow.md documents the docs/ja/ mirror sync rule (when to sync, exclusions for docs/spec/, docs/reports/, and docs/ja/ subdirectories, and which skills consult it)" --> docs/ja/ 同期手順・除外対象・参照 skill が文書化されている
- <!-- verify: file_contains "skills/code/SKILL.md" "docs/translation-workflow.md" --> `skills/code/SKILL.md` が `docs/translation-workflow.md` を参照する
- <!-- verify: file_contains "skills/spec/SKILL.md" "docs/translation-workflow.md" --> `skills/spec/SKILL.md` が `docs/translation-workflow.md` を参照する
- <!-- verify: file_contains "skills/review/SKILL.md" "docs/translation-workflow.md" --> `skills/review/SKILL.md` が `docs/translation-workflow.md` を参照する
- <!-- verify: rubric "skills/code/SKILL.md, skills/spec/SKILL.md, and skills/review/SKILL.md no longer contain the wholework-internal docs/ja/ mirror sync procedure inline (the explicit exclusion list, the update instruction). They delegate to docs/translation-workflow.md instead. skills/spec/SKILL.md:297 (docs/ja/* Japanese-format patterns in verify commands) is preserved as Core-level verify design guidance" --> 3 skill から inline 同期ロジックが退避され、参照のみ残る。spec SKILL.md の verify command 設計ガイドは Core に保持

### Post-merge

- wholework 自身で `/code` を実行し、`docs/*.md` を変更するタスクで `docs/translation-workflow.md` 経由の同期指示が発動することを手動確認

## Notes

- `skills/spec/SKILL.md` の "docs/ja/* files (Japanese mirror files): use Japanese-format patterns in verify commands" は Issue body では line 297 と記載されているが、現在のファイルでは line 301 付近に位置する（編集によりシフト）。いずれにせよこのガイダンスは翻訳運用ではなく verify command 品質に関するものであり、今回の退避対象外。
- `docs/translation-workflow.md` は top-level `docs/*.md` ファイルであるため、`docs/ja/translation-workflow.md` を同時作成することで自らの同期ルールに準拠する（step 3）。
- `check-translation-sync.sh` は変更不要 — 同スクリプトは `docs/*.md` ↔ `docs/ja/` 間の timestamp 差分を検出するものであり、新規ファイルは自動的に対象に含まれる。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- Spec の実装ステップ 2 では「inline 同期ロジック（除外リスト・更新指示）を削除し、一文に置き換える」と記載されていた。`skills/spec/SKILL.md` の docs/ja/ translation sync check セクションは「除外リスト・更新指示」に加えて「Changed Files に翻訳ミラーを追加し Implementation Steps に追加する」という記述を含んでいたが、これらも同期手順として `docs/translation-workflow.md` に移譲できる内容であり、まとめて一文に置き換えた。

### Rework

- N/A
