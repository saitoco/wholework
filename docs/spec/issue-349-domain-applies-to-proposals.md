# Issue #349: domain-registry: Domain file frontmatter に domain / applies_to_proposals キーを追加

## Overview

`type: domain` + `skill:` + `load_when:` frontmatter スキーマは #293 で確立済み。本 Issue では retro (`/verify` Step 13) で生成される改善提案 Issue が Core/Domain 分離を事前に遵守できるよう、各 Domain file が「自 Domain に属する提案の識別方法」と「Core → Domain への書き換えルール」を frontmatter で自己申告する仕組みを追加する。

具体的には:
- `docs/environment-adaptation.md` のスキーマ記述に `domain:` キーと `applies_to_proposals:` ブロック (file_patterns / content_keywords / rewrite_target with from/to) を追加
- Domain 用語 3 層 (`.wholework/domains/{skill}/` ディレクトリ / frontmatter `skill:` / frontmatter `domain:`) の canonical 定義を新設
- skill-dev 特化 7 本に `domain: skill-dev` + `applies_to_proposals` を追記（汎用 7 本は省略）

将来的な分類実装（#350 domain-classifier、#351 /verify Step 13 書き換え）が消費するスキーマ層を本 Issue で確立する。

## Changed Files

- `docs/environment-adaptation.md`: § Domain Terminology 新設 + § Domain File Frontmatter Schema に `domain` と `applies_to_proposals` 追加
- `docs/ja/environment-adaptation.md`: 同等内容を翻訳同期
- `skills/spec/skill-dev-constraints.md`: frontmatter に `domain: skill-dev` + `applies_to_proposals` を追記
- `skills/code/skill-dev-validation.md`: 同上
- `skills/code/stale-test-check.md`: 同上
- `skills/review/skill-dev-recheck.md`: 同上
- `skills/issue/spec-test-guidelines.md`: 同上
- `skills/doc/skill-dev-sync.md`: 同上
- `modules/skill-dev-doc-impact.md`: 同上（`skill:` キー無し、複数 skill から `doc-checker.md` 経由でロードされるため維持）

## Implementation Steps

1. `docs/environment-adaptation.md` Layer 3 を更新（→ AC1, AC2）:
   - § Domain File Frontmatter Schema より前に `### Domain Terminology` サブセクションを新設し、`.wholework/domains/{skill}/` (配置先ディレクトリ) / frontmatter `skill:` (アタッチ先 skill) / frontmatter `domain:` (意味的識別子) の 3 層を表で定義。「classifier output の `domain` 値は frontmatter `domain:` キーを直接 echo する」旨を明示
   - § Domain File Frontmatter Schema の YAML 例に `domain: {identifier}` と `applies_to_proposals:` (sub-fields: `file_patterns`, `content_keywords`, `rewrite_target` with `from`/`to`) を追加。「`domain:` は `applies_to_proposals` 宣言時に必須、宣言しないファイルでは省略可」のセマンティクスを散文で追記

2. 7 本の skill-dev 特化 Domain file の frontmatter を更新（→ AC3, AC4、parallel with 1）:
   - `skills/spec/skill-dev-constraints.md` / `skills/code/skill-dev-validation.md` / `skills/code/stale-test-check.md` / `skills/review/skill-dev-recheck.md` / `skills/issue/spec-test-guidelines.md` / `skills/doc/skill-dev-sync.md` / `modules/skill-dev-doc-impact.md` の 7 本それぞれに以下を追記:
     - `domain: skill-dev`
     - `applies_to_proposals:` ブロック with:
       - `file_patterns:` — 当該 Domain がカバーする Core ファイルの glob (例: `skills/code/SKILL.md`)
       - `content_keywords:` — 提案本文を Domain 候補として識別するキーワード (OR 評価、各 Domain の関心領域に応じて 3-5 個)
       - `rewrite_target:` — `from` (Core path) / `to` (当該 Domain file 自身の path) のペア配列。スキーマ上は `to` にワイルドカード可だが本 Issue では各ファイルが自分自身の exact path を宣言

3. `docs/ja/environment-adaptation.md` Layer 3 を Step 1 と同等内容で翻訳同期（→ AC1、after 1）

4. 自動検証: `grep -l "applies_to_proposals" skills/ modules/` (recursive) で 7 件マッチを確認（→ AC4、after 2）

## Verification

### Pre-merge

- <!-- verify: rubric "docs/environment-adaptation.md documents the new domain frontmatter key and the applies_to_proposals key with sub-fields file_patterns, content_keywords, and rewrite_target (with from/to sub-keys). It also documents the three senses of 'Domain' (.wholework/domains/{skill}/ directory, frontmatter skill: key, frontmatter domain: key) as canonical terminology." --> `docs/environment-adaptation.md` に新スキーマと Domain 用語定義が記述されている
- <!-- verify: section_contains "docs/environment-adaptation.md" "### Domain File Frontmatter Schema" "applies_to_proposals" --> Frontmatter Schema セクションに applies_to_proposals が含まれている
- <!-- verify: grep "applies_to_proposals" "skills/review/skill-dev-recheck.md" --> 代表 skill-dev Domain file (skill-dev-recheck.md) に applies_to_proposals 宣言が追加されている
- <!-- verify: rubric "All 7 skill-dev specific bundled Domain files (skills/spec/skill-dev-constraints.md, skills/code/skill-dev-validation.md, skills/code/stale-test-check.md, skills/review/skill-dev-recheck.md, skills/issue/spec-test-guidelines.md, skills/doc/skill-dev-sync.md, modules/skill-dev-doc-impact.md) declare applies_to_proposals with at least file_patterns and content_keywords. Every file that declares applies_to_proposals also declares domain: skill-dev (required when applies_to_proposals is present). The 7 non-skill-dev bundled Domain files (figma-design-phase.md, codebase-search.md, external-spec.md, external-review-phase.md, mcp-call-guidelines.md, browser-verify-phase.md, translate-phase.md) may omit applies_to_proposals." --> skill-dev 特化 7 本に applies_to_proposals + domain: skill-dev が宣言されており、汎用 7 本は宣言を省略している

### Post-merge

- Issue B (#350 domain-classifier) 実装時に Domain file の frontmatter を読んで `applies_to_proposals` が正しく parse できることを手動確認

## Notes

### スコープ外（既知のドリフト）

`docs/environment-adaptation.md` の Domain Files (exhaustive) 表に未収載の Domain file が 3 本ある:
- `skills/code/skill-dev-validation.md`
- `skills/code/stale-test-check.md`
- `skills/doc/skill-dev-sync.md`

これは #293 Phase 2 後に追加されたファイルが表に追記されていない既存ドリフト。`/audit drift` で検出される性質のものであり、本 Issue のスキーマ拡張とは独立。本 Spec では表更新は行わず、別 Issue として `/audit drift` 経由で起票を推奨。

### `modules/skill-dev-doc-impact.md` の `skill:` キー無し

このファイルは frontmatter に `skill:` キーを持たない（複数 skill から `doc-checker.md` 経由で間接ロードされる設計）。`applies_to_proposals` 追記時もこの構造を維持し、`skill:` は追加しない。

### `rewrite_target.to` のワイルドカード

スキーマ上は `to: skills/code/skill-dev-*.md` のような glob 表記が許容されるが、本 Issue の実装では各 Domain file が自分自身の exact path を宣言する方針。複数 Domain が同一 `from` に対して候補となる場合の解決ルール（content_keywords による分岐など）は #350 (domain-classifier) で設計する。

### product.md Terms との関係

`docs/product.md` § Terms には既に "Domain file" のエントリがある。新たに導入する semantic identifier としての "domain" は `docs/environment-adaptation.md` の Domain Terminology セクションで canonical 定義を持たせる方針（環境適応アーキテクチャの内部概念のため product.md への昇格は #350/#351 完了後に検討）。

## Code Retrospective

### Deviations from Design

- N/A（Spec の実装ステップに沿って実施、順番・内容の逸脱なし）

### Design Gaps/Ambiguities

- `modules/skill-dev-doc-impact.md` は `skill:` キーを持たない（複数 skill から間接ロードされる設計）。この場合、`rewrite_target.from` に何を指定するかが Spec に明示されていなかった。`doc-checker.md` 経由でロードされる設計なので `from: modules/doc-checker.md` を採用したが、#350 の classifier 実装時に調整が必要な可能性がある。

### Rework

- N/A

## review retrospective

### Spec vs. Implementation Divergence Patterns

Nothing to note. PR diff は Spec の実装ステップに完全に沿っており、構造的な逸脱なし。承認基準 4 件すべてが PASS（自動検証可能な形式で記述されており、verify コマンドが効果的に機能した）。

### Recurring Issues

Nothing to note. skill-dev Domain file 7 本にほぼ同一の frontmatter ブロックを追記する繰り返し作業だったが、各ファイルで `file_patterns`/`content_keywords` の内容がファイル用途に応じて適切に分化されており、品質問題は発見されなかった。

### Acceptance Criteria Verification Difficulty

Nothing to note. `rubric`・`section_contains`・`grep` コマンドで 4 件全て自動判定可能な形式で記述されており、UNCERTAIN ゼロ。`rewrite_target.from` の妥当性（`modules/skill-dev-doc-impact.md` の `from: modules/doc-checker.md` 選択）は Code Retrospective で設計判断が文書化されていたため、レビュー時の確認コストが低かった。
