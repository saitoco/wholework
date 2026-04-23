# Issue #360: /audit drift Add Domain Frontmatter vs environment-adaptation.md Layer 3 Consistency Check

## Overview

`/audit drift` の drift subcommand Step 2 Drift Detection に、bundled Domain file の frontmatter (`type: domain`, `skill:`, `load_when:`) と `docs/environment-adaptation.md` Layer 3 の Domain Files 表との整合チェックカテゴリを追加する。

検出する drift の種類（3種）:
1. `type: domain` frontmatter を持つが表に未掲載の Domain file
2. 表に掲載されているが対応 file が存在しない、または `type: domain` frontmatter を持たない
3. 表の `load_when` 列と frontmatter の `load_when:` 値の乖離

`docs/structure.md` 側には Domain Files 表が存在しないため、対象は `docs/environment-adaptation.md` のみ。

## Changed Files

- `skills/audit/SKILL.md`: drift subcommand Step 2 Drift Detection の **Project Documents categories** テーブルに Domain frontmatter ⇔ environment-adaptation.md Layer 3 整合チェック行を追加

## Implementation Steps

1. `skills/audit/SKILL.md` の drift subcommand `### Step 2: Drift Detection` セクション内の **Project Documents categories (examples):** テーブルに、以下の行を末尾に追加する（→ 受け入れ基準 1, 2）:

   ```
   | environment-adaptation.md Layer 3 Domain Files table vs bundled Domain file frontmatter | Glob `skills/**/*.md` and `modules/*.md` to find files with `type: domain` frontmatter (via Read) → Read `$STEERING_DOCS_PATH/environment-adaptation.md` Layer 3 Domain Files table → report (1) Domain files with `type: domain` frontmatter but missing from table, (2) table rows without a matching file or without `type: domain` frontmatter, (3) `load_when` value mismatch between table column and frontmatter |
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/audit/SKILL.md drift subcommand Step 2 Drift Detection includes a category that compares bundled Domain file frontmatter (type: domain, skill:, load_when:) against the Domain Files table rows in docs/environment-adaptation.md Layer 3. The category reports three drift types: (1) Domain files with frontmatter but missing from the table, (2) table rows without a matching file or without type: domain frontmatter, (3) load_when mismatches between the table column and the frontmatter value." --> `/audit drift` Step 2 に Domain frontmatter ⇔ `docs/environment-adaptation.md` Layer 3 表の整合チェックカテゴリが含まれる
- <!-- verify: section_contains "skills/audit/SKILL.md" "### Step 2: Drift Detection" "environment-adaptation.md" --> Step 2 本文に `environment-adaptation.md` への参照が含まれる（Domain 整合チェックカテゴリの存在を機械的に担保する supplementary check）

### Post-merge

- テスト用 Domain file（例: `skills/spec/_phase3-drift-test.md` に `type: domain` と `skill: spec` の最小 frontmatter のみを持つ file を置き、`docs/environment-adaptation.md` Layer 3 の表には追記しない状態）を配置して `/audit drift` を実行した際、Domain 整合カテゴリで当該 file が「表に未掲載」として drift 検出されることを手動確認。確認後テスト file は削除

## Notes

- ISSUE_TYPE=Task のため Uncertainty・UI Design セクション省略
- drift subcommand の Integrated Execution (`/audit` 引数なし) は Step 1–3 を drift subcommand へ委譲しているため、drift subcommand Step 2 への追加のみで統合実行にも反映される
