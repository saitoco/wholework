# Issue #71: doc: template からフロントマターを除去し SKILL.md 側で prepend

## Overview

`skills/doc/*-template.md`（product / tech / structure の 3 テンプレート）から frontmatter（`type: steering`, `ssot_for:` ブロック）を除去し、SSoT を `skills/doc/SKILL.md` 側に集約する。

現状の `Document Traversal (common procedure)` は `type: project|type: steering` を Grep で全リポジトリから収集しており、`skills/` 配下のテンプレートが除外されていないため、status display / sync / translate の各操作でテンプレートが実ドキュメントとして誤検出される問題が発生している。

対応方針：
- テンプレートから frontmatter を除去（誤検出の根本除去）
- `skills/doc/SKILL.md` の Template Definitions テーブルに `type` / `ssot_for` カラムを追加
- `docs/{doc}.md` への Write を行う全パス（Individual Create/Update Step 4 と sync reverse-generation Step 5）で frontmatter を prepend するよう SKILL.md を更新

## Changed Files

- `skills/doc/product-template.md`: frontmatter（`type: steering`, `ssot_for:` ブロック）を除去
- `skills/doc/tech-template.md`: frontmatter（`type: steering`, `ssot_for:` ブロック）を除去
- `skills/doc/structure-template.md`: frontmatter（`type: steering`, `ssot_for:` ブロック）を除去
- `skills/doc/SKILL.md`: Template Definitions テーブルに `type` / `ssot_for` カラムを追加；Individual Create/Update Step 4 に frontmatter prepend の記述を追加；sync Bidirectional Normalization Step 5 に frontmatter prepend の記述を追加

## Implementation Steps

1. 3 つのテンプレートファイルから frontmatter ブロックを除去する（→ acceptance criteria 1, 2, 3）
   - `skills/doc/product-template.md` の先頭 `---\ntype: steering\nssot_for:\n  - vision\n  - non-goals\n  - terminology\n---` を削除
   - `skills/doc/tech-template.md` の先頭 `---\ntype: steering\nssot_for:\n  - tech-stack\n  - coding-conventions\n  - forbidden-expressions\n---` を削除
   - `skills/doc/structure-template.md` の先頭 `---\ntype: steering\nssot_for:\n  - directory-layout\n  - agent-includes-catalog\n---` を削除

2. `skills/doc/SKILL.md` の `## Template Definitions` テーブルを拡張する（→ acceptance criteria 4, 5）
   - 既存の 2 列テーブル（Document, Template file）に `type` / `ssot_for` カラムを追加
   - 各行に以下の値を設定:

   | Document | Template file | type | ssot_for |
   |----------|--------------|------|----------|
   | product.md | `skills/doc/product-template.md` | steering | vision, non-goals, terminology |
   | tech.md | `skills/doc/tech-template.md` | steering | tech-stack, coding-conventions, forbidden-expressions |
   | structure.md | `skills/doc/structure-template.md` | steering | directory-layout, agent-includes-catalog |

3. `skills/doc/SKILL.md` の `### Step 4: Document Generation`（Individual Create/Update 配下）に frontmatter prepend の記述を追加する（→ acceptance criteria 6）
   - 「Fill in the template with collected information and save to `docs/{doc}.md` with Write.」の前に、Template Definitions テーブルから該当する `type` / `ssot_for` を取得し frontmatter を生成・prepend する旨の記述を挿入
   - 例: "Look up the `type` and `ssot_for` values for `{doc}` from the Template Definitions table and prepend the following frontmatter block before writing with Write:"

4. `skills/doc/SKILL.md` の `### Step 5: Execute Save`（sync Bidirectional Normalization 配下）に frontmatter prepend の記述を追加する（→ post-merge verification）
   - 新規ファイル作成時（docs/{doc}.md が存在しない場合）は、Template Definitions テーブルから frontmatter を prepend した上で Write する旨を記述
   - `sync {doc}`（個別逆生成）も同じ Write パスを通るため自動的にカバーされる

## Verification

### Pre-merge

- <!-- verify: file_not_contains "skills/doc/product-template.md" "type: steering" --> `skills/doc/product-template.md` から frontmatter（`type: steering`、`ssot_for:` を含むブロック）が除去されている
- <!-- verify: file_not_contains "skills/doc/tech-template.md" "type: steering" --> `skills/doc/tech-template.md` から frontmatter が除去されている
- <!-- verify: file_not_contains "skills/doc/structure-template.md" "type: steering" --> `skills/doc/structure-template.md` から frontmatter が除去されている
- <!-- verify: section_contains "skills/doc/SKILL.md" "## Template Definitions" "type: steering" --> `skills/doc/SKILL.md` の Template Definitions セクションに、3 テンプレートに対応する `type: steering` の定義が含まれている（SSoT は SKILL.md 側）
- <!-- verify: section_contains "skills/doc/SKILL.md" "## Template Definitions" "ssot_for" --> `skills/doc/SKILL.md` の Template Definitions セクションに、各テンプレートに対応する `ssot_for` カテゴリ定義が含まれている
- <!-- verify: section_contains "skills/doc/SKILL.md" "### Step 4: Document Generation" "prepend" --> `skills/doc/SKILL.md` Individual Create/Update Step 4 に、Write 時に frontmatter を prepend する旨の記述が含まれている

### Post-merge

- マージ後に `/doc product`（および `tech` / `structure`）を実行すると、生成される `docs/{doc}.md` が従来と同じ `type: steering` + `ssot_for` の frontmatter を含んでいる
- マージ後に `/doc`（status display）を実行したとき、`skills/doc/*-template.md` がテーブル一覧に含まれない
- マージ後に `/doc translate {lang}` を実行したとき、`skills/doc/*-template.md` が翻訳対象候補から自動的に除外される（手動除外が不要になる）
- `docs/spec/issue-58-doc-translate.md` で実装済みの翻訳対象判定ロジックが引き続き動作する（Document Traversal 経由のため、frontmatter 除去により自然に除外されることを確認）

## Notes

- **検証item数が light 上限 (5) を超える**: Issue body の `## Acceptance Criteria > Pre-merge` が 6 件あるため、verify command sync ルールに従い 6 件を verbatim でコピーした。実装ステップは 4 件（上限内）。
- **auto-resolved**: Issue body の「Auto-Resolved Ambiguity Points」より、以下が既に確定済み:
  - SKILL.md mapping 配置: 既存 Template Definitions テーブルに `type` / `ssot_for` カラムを拡張
  - prepend 対象フロー: Individual Create/Update Step 4 と sync reverse-generation Step 5 の両パス
  - translate-phase.md の変更は不要（Document Traversal で自然に除外）
