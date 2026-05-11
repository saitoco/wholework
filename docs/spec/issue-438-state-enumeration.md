# Issue #438: spec: visual reproduction state enumeration scaffold を Domain file 化

## Overview

UI 再現案件の Spec 化時に `(viewport × page × interactive_state × navigation_context)` の **完全直積** での AC 生成を体系的に scaffold する Domain file `skills/spec/visual-state-enumeration.md` を新設する。`#441` で確立した `skills/spec/visual-diff-guidance.md` と完全同パターン (`type: domain`, `skill: spec`, `domain: visual-reproduction`, `load_when: capability: visual-diff`) で実装し、domain-loader 経由で capability gate 越しに自動 load される。

Domain 外プロジェクト (`HAS_VISUAL_DIFF_CAPABILITY=false`) では `domain-loader` が gate で skip するため eager Read されず、overhead はゼロ。`/spec` SKILL.md 本体の変更は不要 — domain-loader 機構が既に対応している (#441 visual-diff-guidance.md と同経路)。

## Changed Files

- `skills/spec/visual-state-enumeration.md`: 新規 — Domain file (`type: domain`, `skill: spec`, `domain: visual-reproduction`, `load_when: capability: visual-diff`)。State Enumeration template + project-local override 機構 + AC generator の Processing Steps を記述。`skills/spec/visual-diff-guidance.md` と同形式
- `docs/environment-adaptation.md`: change Layer 3 「Domain Files (exhaustive)」テーブルに `skills/spec/visual-state-enumeration.md` 行を追加 (`visual-diff-guidance.md` 行の直後に挿入、`HAS_VISUAL_DIFF_CAPABILITY=true` / `capability: visual-diff` / `visual-reproduction` domain)
- `docs/ja/environment-adaptation.md`: docs/environment-adaptation.md 変更に追随する日本語ミラー同期 (`docs/translation-workflow.md` 準拠)

## Implementation Steps

1. `skills/spec/visual-state-enumeration.md` を新設 — frontmatter (`type: domain`, `skill: spec`, `domain: visual-reproduction`, `load_when: capability: visual-diff`) + Purpose + Processing Steps を記述 (→ V1)。Processing Steps の構成:
   - **State Enumeration template 生成**: Spec の `## State Enumeration` section に `Viewports` / `Pages` / `Interactive States` / `Navigation Contexts` の 4 サブセクションを `- [ ]` チェックリストで scaffold
   - **State list の override 解決順序** (project-local 最優先): (a) `.wholework/domains/spec/visual-state-enumeration.md` (project-local Domain file、存在すれば state list を frontmatter or 本文 list から抽出) → (b) `AskUserQuestion` で user 確認 (interactive mode のみ) → (c) bundled default list (`[default, hover, focus, menu-open]` 等の汎用候補)
   - **AC entry auto-generation**: state 直積から `<!-- verify: visual_diff "<ref_url>/<page>" "<impl_url>/<page>" --viewports="<vw>" --states="<state>" -->` 形式の AC エントリを emit。state label は opaque (`visual-diff-guidance.md` の State Label Convention を参照)
   - **`/spec` SKILL.md からの呼び出し**: Step 10 (Create Spec) で `HAS_VISUAL_DIFF_CAPABILITY=true` のとき本 Domain file の Processing Steps を State Enumeration セクション生成 step として実行
2. `docs/environment-adaptation.md` Layer 3 Domain Files テーブルに `skills/spec/visual-state-enumeration.md` 行を追加 (parallel with 1)。`visual-diff-guidance.md` 行の直後に挿入、形式: `| skills/spec/visual-state-enumeration.md | /spec | HAS_VISUAL_DIFF_CAPABILITY=true | capability: visual-diff | Visual reproduction state enumeration scaffold |` (→ V3)
3. `docs/ja/environment-adaptation.md` ミラーを `docs/translation-workflow.md` 準拠で同期 (after 2)。同位置に日本語化された行を挿入: `| skills/spec/visual-state-enumeration.md | /spec | HAS_VISUAL_DIFF_CAPABILITY=true | capability: visual-diff | 視覚再現 state enumeration scaffold |` (→ V4)

## Verification

### Pre-merge

- <!-- verify: file_exists "skills/spec/visual-state-enumeration.md" --> <!-- verify: file_contains "skills/spec/visual-state-enumeration.md" "type: domain" --> <!-- verify: file_contains "skills/spec/visual-state-enumeration.md" "capability: visual-diff" --> <!-- verify: rubric "skills/spec/visual-state-enumeration.md は visual-diff-guidance.md と同パターンの Domain file frontmatter (type: domain, skill: spec, domain: visual-reproduction, load_when: capability: visual-diff) を持ち、Processing Steps に State Enumeration template (Viewports / Pages / Interactive States / Navigation Contexts) と project-local override (.wholework/domains/spec/visual-state-enumeration.md) + AskUserQuestion + bundled default list の 3-tier 解決順序、および visual_diff verify command 形式の AC entry auto-generation を記述している" --> V1: `skills/spec/visual-state-enumeration.md` Domain file が frontmatter + Processing Steps を含み実装されている
- <!-- verify: rubric "skills/spec/SKILL.md 本体に visual-state-enumeration 専用の Read 分岐は追加されておらず、Step 5 で既に呼ばれている modules/domain-loader.md 経由で本 Domain file が capability gate 越しに自動 load される設計になっている (Core/Domain 分離準拠、visual-diff-guidance.md と同経路)" --> V2: `/spec` SKILL.md 本体に専用分岐が追加されていない (Lazy load by capability gate、Core/Domain 分離)
- <!-- verify: section_contains "docs/environment-adaptation.md" "Domain Files" "skills/spec/visual-state-enumeration.md" --> V3: `docs/environment-adaptation.md` Layer 3 Domain Files テーブルに行が追加されている
- <!-- verify: section_contains "docs/ja/environment-adaptation.md" "Domain" "skills/spec/visual-state-enumeration.md" --> V4: `docs/ja/environment-adaptation.md` ミラーが同期されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> V5: bats test CI が PASS

### Post-merge

- サンプル UI 再現 Issue (`capabilities.visual-diff: true` 宣言済) で `/spec` を実行し、`## State Enumeration` セクションが Spec に含まれ、state 直積から `<!-- verify: visual_diff ... -->` 形式の AC entry が auto-generate されることを実機で確認 <!-- verify-type: opportunistic -->

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Notes

- 三位一体: #441 (visual_diff 実装、`skills/spec/visual-diff-guidance.md`) / 本 Issue #438 (state enumeration scaffold) / #439 (methodology guide `docs/visual-reproduction.md`) は同じ `capability: visual-diff` gate で連動し、いずれも domain 外プロジェクトでは lazy load (eager overhead ゼロ)
- `skills/spec/visual-diff-guidance.md` (#441) 本文 line 96 で「State enumeration scaffolding (how to systematically identify which states to test) is addressed in Issue #438.」と既に参照されており、本 Issue 完了で trinity の参照経路が閉じる
- project-local override pattern: `.wholework/domains/spec/visual-state-enumeration.md` は既存の domain-loader Phase 2 (project-local Domain files discovery) で自動 pickup される (`docs/environment-adaptation.md` 表内の `.wholework/domains/{skill}/*.md` 行を参照)。新規メカニズム不要
- 旧案撤回 (Issue body の「設計再考の経緯」セクションで明記): `/spec --visual` flag (Core 改修)、`topic/visual-reproduction` label 新規定義、`.wholework.yml` `visual_states` config key は全て撤回し、capability gate + Domain file + project-local override の組み合わせで代替
- AC 数値の整合: 本 Spec の Verification > Pre-merge は 5 items (Issue body も 5 items に同期更新; 元の Issue body は 10 items だったが light template Simplicity Rule に従い consolidate)
- 同様の Domain file pattern を持つ参考実装: `skills/spec/visual-diff-guidance.md` (#441 で確立)、`skills/verify/browser-verify-phase.md` (browser capability)、`skills/issue/mcp-call-guidelines.md` (mcp capability)
