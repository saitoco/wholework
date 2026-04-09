# Issue #66: docs: product.md の Terms を統合し日本語訳を追加

## Overview

`docs/product.md` の `## Terms` セクションで `### Public Terms (User-facing)` と `### Internal Terms (Developer-facing)` に分かれている2サブセクションを単一テーブルに統合し、`日本語訳` 列を追加する。`skills/doc/product-template.md` の `## Terms` テンプレートも同様に `日本語訳` 列を持つ構造に更新する。

翻訳方針（Issue body の Design Decisions より）:
- カタカナ技術用語: Skill → スキル、Sub-agent → サブエージェント
- プロダクト固有識別子: Spec、`/auto`、Steering Documents、Project Documents → 原語保持
- 明確な対訳あり: Acceptance check → 受入チェック、Shared module → 共有モジュール
- 混成: Fork context → fork コンテキスト

## Changed Files

- `docs/product.md`: `## Terms` セクションを単一テーブルに統合し `日本語訳` 列を追加、`### Public Terms (User-facing)` と `### Internal Terms (Developer-facing)` 見出しを削除
- `skills/doc/product-template.md`: `## Terms（Required）` テーブルに `日本語訳` 列を追加

## Implementation Steps

1. `docs/product.md` の `## Terms` セクションを編集:
   - `<!-- public: ... / internal: ... -->` コメント削除
   - `### Public Terms (User-facing)` および `### Internal Terms (Developer-facing)` 見出しを削除
   - 2つのテーブルを1つに統合し、`| Term | Definition | Context | 日本語訳 |` 形式に変更
   - 9用語すべての日本語訳を記入: スキル、Spec、`/auto`、受入チェック、Steering Documents、Project Documents、fork コンテキスト、共有モジュール、サブエージェント
   (→ 受入基準 A, B, C, D, E, F, G)

2. `skills/doc/product-template.md` の `## Terms（Required）` テーブルを編集:
   - `| Term | Definition | Context |` → `| Term | Definition | Context | 日本語訳 |` に列追加
   (→ 受入基準 H)

## Verification

### Pre-merge

- <!-- verify: section_contains "docs/product.md" "## Terms" "日本語訳" --> `docs/product.md` の `## Terms` セクションに `日本語訳` 列が追加されている
- <!-- verify: section_not_contains "docs/product.md" "## Terms" "### Public Terms" --> `### Public Terms (User-facing)` 見出しが削除されている
- <!-- verify: section_not_contains "docs/product.md" "## Terms" "### Internal Terms" --> `### Internal Terms (Developer-facing)` 見出しが削除されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "スキル" --> Skill の日本語訳「スキル」が記入されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "共有モジュール" --> Shared module の日本語訳「共有モジュール」が記入されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "サブエージェント" --> Sub-agent の日本語訳「サブエージェント」が記入されている
- <!-- verify: section_contains "docs/product.md" "## Terms" "受入チェック" --> Acceptance check の日本語訳「受入チェック」が記入されている
- <!-- verify: section_contains "skills/doc/product-template.md" "## Terms" "日本語訳" --> `skills/doc/product-template.md` の `## Terms` テンプレートも `日本語訳` 列を持つ構造に更新されている

### Post-merge

- Issue #58 の `/doc translate` 実装時に本用語集が翻訳指示から参照されること

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A
