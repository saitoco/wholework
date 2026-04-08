# Issue #45: docs: Migrate project documents workflow.md and figma-best-practices.md

## Overview

claude-config から残り 2 つの Project Documents (`workflow.md`, `figma-best-practices.md`) を Wholework に英語化・汎用化して移植する。#43 (product.md 移植) と同パターン。

移植対象:
- `~/src/claude-config/docs/workflow.md` (202 行) — 開発ワークフロー全体像
- `~/src/claude-config/docs/figma-best-practices.md` (164 行) — Figma MCP UI デザインガイドライン

`docs/product.md` は既に `docs/workflow.md` への参照を含むため、本移植により参照リンクが解決される。

## Changed Files

- `docs/workflow.md`: 新規作成。`~/src/claude-config/docs/workflow.md` を英語化。1 箇所の `（claude-config）` 参照を "Wholework" に置換。`.wholework.yml`、スキル名 (`/issue` 等)、相対パス参照 (`../skills/`, `../modules/`) は維持
- `docs/figma-best-practices.md`: 新規作成。`~/src/claude-config/docs/figma-best-practices.md` を英語化。claude-config 固有参照なし
- `docs/structure.md`: Directory Layout セクション (line 36-46) の `docs/` リストに `workflow.md` と `figma-best-practices.md` の 2 行を追加

## Implementation Steps

1. Create `docs/workflow.md` by translating Japanese content from `~/src/claude-config/docs/workflow.md` to English. Preserve frontmatter (`type: project`, `ssot_for: workflow-phases, label-transitions`). Replace `（claude-config）` at the verify phase description with "Wholework". Keep skill names (`/issue`, `/spec`, etc.), `.wholework.yml`, and relative paths (`../skills/...`, `../modules/...`) as-is. (→ workflow.md acceptance criteria)
2. Create `docs/figma-best-practices.md` by translating Japanese content from `~/src/claude-config/docs/figma-best-practices.md` to English. Preserve frontmatter (`type: project`, `ssot_for: figma-workflow`). No claude-config references to remove. (→ figma-best-practices.md acceptance criteria)
3. Update `docs/structure.md` Directory Layout section: add `│   ├── workflow.md     # Development workflow phases and label transitions (project)` and `│   ├── figma-best-practices.md # Figma MCP UI design guidelines (project)` entries under the `docs/` listing. (→ shared acceptance criteria)

## Verification

### Pre-merge

#### workflow.md
- <!-- verify: file_exists "docs/workflow.md" --> `docs/workflow.md` が作成されている
- <!-- verify: grep "type: project" "docs/workflow.md" --> frontmatter に `type: project` が含まれる
- <!-- verify: grep "ssot_for" "docs/workflow.md" --> frontmatter に `ssot_for` が含まれる
- <!-- verify: file_not_contains "docs/workflow.md" "claude-config" --> claude-config への直接参照が除去されている
- <!-- verify: grep "Phase" "docs/workflow.md" --> 翻訳後のフェーズ記述 (Phase) が含まれる
- <!-- verify: file_contains "docs/workflow.md" "/issue" --> Issue スキルへの参照が含まれる

#### figma-best-practices.md
- <!-- verify: file_exists "docs/figma-best-practices.md" --> `docs/figma-best-practices.md` が作成されている
- <!-- verify: grep "type: project" "docs/figma-best-practices.md" --> frontmatter に `type: project` が含まれる
- <!-- verify: grep "ssot_for" "docs/figma-best-practices.md" --> frontmatter に `ssot_for` が含まれる
- <!-- verify: file_not_contains "docs/figma-best-practices.md" "claude-config" --> claude-config への直接参照が除去されている
- <!-- verify: grep "Figma" "docs/figma-best-practices.md" --> Figma 関連の記述が含まれる

#### structure.md
- <!-- verify: grep "workflow.md" "docs/structure.md" --> `docs/structure.md` に workflow.md の記載が追加されている
- <!-- verify: grep "figma-best-practices.md" "docs/structure.md" --> `docs/structure.md` に figma-best-practices.md の記載が追加されている

### Post-merge

- `/issue` 実行時に `docs/workflow.md` が Project Document として認識される

## Notes

- #43 (product.md 移植) のパターンを踏襲: 英語化 + claude-config 固有参照の除去 + 汎用化
- 言語規約 (CLAUDE.md): Source code / Documentation は English。Spec files は Japanese (本 spec も日本語のまま)
- workflow.md には `（claude-config）` という参照が 1 箇所のみ存在 (verify phase 説明箇所)。"Wholework" に置換する
- figma-best-practices.md には claude-config 固有参照なし。純粋な英語化のみ
- workflow.md 内の skill 名 (`/issue`, `/spec`, etc.)、相対パス (`../skills/...`)、`.wholework.yml`、`docs/product.md` 等の参照はそのまま維持 (Wholework でも有効)
- structure.md は #43 で更新済み (`product.md` のエントリ追加)。同じパターンで 2 ファイルを追加
- `~/.claude/docs/workflow.md` (グローバル版) とは別管理。本ファイルはリポ内 Project Document として配置
- Verify hints: Issue 本文の `section_contains` で heading が `## ` だけのパターンは不正なため、`grep` / `file_contains` ベースに改善。Issue 本文も同期更新

## Auto-Resolved Ambiguity Points

- 書き換え範囲: #43 と同パターンで決定 (英語化 + claude-config 参照除去)
- figma-best-practices.md の適合性: ユーザーが移植対象として明確に指定

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
