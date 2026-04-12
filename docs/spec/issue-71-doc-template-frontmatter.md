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

## Spec Retrospective

N/A

## Code Retrospective

### Deviations from Design
- Spec Implementation Step 2 specifies "3 つのテンプレートファイルから frontmatter ブロックを除去する" first, and Step 2 was "Template Definitions テーブルを拡張する". These were implemented in the correct order, but an additional micro-step was added: a descriptive sentence about `type: steering` was inserted into the section text (not just the table) to satisfy the `section_contains "type: steering"` verify command. The Spec's table-only approach would have failed the verify check since the string "type: steering" would not appear as a combined string in the table rows (which only show "steering" in the type column).

### Design Gaps/Ambiguities
- The verify command `section_contains "skills/doc/SKILL.md" "## Template Definitions" "type: steering"` searches for the literal string "type: steering", but the Template Definitions table only includes "steering" as the value (without the "type:" prefix). To make this verify command PASS, a prose note was added to the section explicitly containing the string "type: steering".

### Rework
- Initial commit of SKILL.md changes (steps 2-4) was followed by a fix commit to add the "type: steering" string to the Template Definitions section description, because the verify command failed in the first pass.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body の「Auto-Resolved Ambiguity Points」セクションで事前に曖昧さが解消されており、Spec 作成時の方針決定は明確だった。
- `## Spec Retrospective` は N/A — 特筆すべき問題はなし。

#### design
- `## Spec Retrospective` は N/A。設計方針（Template Definitions テーブル拡張 + prepend）は妥当で、実装との乖離も最小限。

#### code
- **verify command と実装の齟齬**: `section_contains "## Template Definitions" "type: steering"` はテーブルのカラム値が "steering" のみであることを考慮しておらず、初回実装でfail → fixup コミット（2e15115）が発生。
- rework はコミット1回分にとどまったが、verify command の文字列設計（テーブル値 vs 複合キー）を spec 段階で精査することで防げた。

#### review
- PRなし（patch route で直接 main にコミット）。コードレビューは実施されていない。rework はコードレビューでは検出できない性質（verify command 文字列設計の問題）だったため、影響は軽微。

#### merge
- PRなし。patch route（直接 main コミット）で実装 → fixup コミットの計3コミット構成。conflictなし、CI failures なし。

#### verify
- 全6条件 PASS。post-merge 条件4件は `verify-type: manual` のため自動検証対象外。
- `section_contains "## Template Definitions" "type: steering"` の PASS は、code フェーズのfixup（prose文追加）によって達成されたもの。verify command 設計時点でのテーブル値と検索文字列の整合性チェックが今後の改善点。

### Improvement Proposals
- **verify command 設計ガイドライン**: `section_contains` でテーブルのカラム値を検索する場合、テーブルセルに含まれる値（例: `steering`）と、"key: value" 形式の複合文字列（例: `type: steering`）は同一視できない。Spec 策定時に verify command の検索文字列がファイル内に実際に出現するかを確認する習慣、または `/issue` スキルに「verify command 文字列の出現確認ステップ」を追加することが有効。

## Notes

- **検証item数が light 上限 (5) を超える**: Issue body の `## Acceptance Criteria > Pre-merge` が 6 件あるため、verify command sync ルールに従い 6 件を verbatim でコピーした。実装ステップは 4 件（上限内）。
- **auto-resolved**: Issue body の「Auto-Resolved Ambiguity Points」より、以下が既に確定済み:
  - SKILL.md mapping 配置: 既存 Template Definitions テーブルに `type` / `ssot_for` カラムを拡張
  - prepend 対象フロー: Individual Create/Update Step 4 と sync reverse-generation Step 5 の両パス
  - translate-phase.md の変更は不要（Document Traversal で自然に除外）
