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
## Issue Retrospective

### 作成経緯

セッション中の #58（`docs: 日本語ドキュメント自動生成`）の Spec 設計議論から派生した Issue。翻訳品質の一貫性を担保するため、canonical な用語集が必要との判断。同時に既存の `Public Terms` / `Internal Terms` 区分が実質機能していない問題も解決する。

### 曖昧性解決の判断根拠

| 項目 | 判断 | 根拠 |
|------|------|------|
| Public/Internal の区分廃止 | 廃止 | `docs/product.md` 自体が開発者向け Steering Document であり、Public Terms に分類されていた用語（Skill, Spec, /auto 等）も実質的に開発者向け。区分基準が機能していない |
| 日本語訳列のみ追加（定義は英語のみ） | 単列追加で十分 | 定義を両言語で管理するとドリフトが発生しやすい。canonical 用語さえあれば `/doc translate` が定義文を翻訳できる |
| Context 列の扱い | 維持 | 用語が使用される文脈情報として有用 |
| `skills/doc/product-template.md` の同期更新 | 本 Issue スコープに含める | 将来 `/doc product` で新規生成される product.md との整合性維持のため |

### 日本語訳の方針

| タイプ | 方針 | 例 |
|-------|------|-----|
| 確立されたカタカナ技術用語 | カタカナ化 | Skill → スキル、Sub-agent → サブエージェント |
| プロダクト固有識別子 | 原語保持 | Spec、`/auto`、Steering Documents、Project Documents |
| 日本語に明確な対訳あり | 日本語訳 | Acceptance check → 受入チェック、Shared module → 共有モジュール |
| 混成 | 併記 | Fork context → fork コンテキスト |

### Related Issues

- #58: 本 Issue の整備した用語集を `/doc translate` 実装時に参照する
