# Issue #336: spec: MUST/SHOULD Constraint Checklist を skill-dev-constraints.md へ抽出

## Overview

Phase 2 (#293) の抽出作業。`skills/spec/SKILL.md` Step 10 の MUST/SHOULD Constraint Checklist (L285-L328、MUST 4 行 + SHOULD 約 25 行の表) は skill-dev プロジェクト固有の validator 依存知識である。

非 skill-dev プロジェクトでは読む必要がないため、frontmatter 駆動 Domain file `skills/spec/skill-dev-constraints.md` として抽出する。既存 `skill-dev-checks.md` と同様に `SPEC_DEPTH=full` AND `scripts/validate-skill-syntax.py` 存在の AND 条件でのみロードする。

## Changed Files

- `skills/spec/skill-dev-constraints.md`: 新規 Domain file — MUST/SHOULD Constraint Checklist を収録 — bash 非依存
- `skills/spec/SKILL.md`: Step 10 の3箇所を変更
  - L225: `skill-dev-checks.md` ロード条件から `validate-skill-syntax.py` 言及を除去 (→ SPEC_DEPTH=full のみに縮約)
  - L285-L329: MUST/SHOULD Constraint Checklist セクションを条件付き Read instruction (2行) に縮約
  - L510 (テンプレート内): `validate-skill-syntax.py` を使うコマンド例を汎用例に差し替え
- `docs/environment-adaptation.md`: Layer 3 Domain Files 表に新 Domain file 行を追加
- `docs/ja/environment-adaptation.md`: 上記の翻訳ミラーを同期

## Implementation Steps

1. `skills/spec/skill-dev-constraints.md` を新規作成する。frontmatter に `type: domain`、`skill: spec`、`load_when: file_exists_any: [scripts/validate-skill-syntax.py]` + `spec_depth: full` を宣言し、`skills/spec/SKILL.md` L285-L329 の `**Constraint checklist (MUST/SHOULD):**` セクション全体をファイル本文として移譲する (→ 検証 1〜4)
2. `skills/spec/SKILL.md` を3箇所編集する (→ 検証 5〜6):
   a. L225: `and \`scripts/validate-skill-syntax.py\` exists` および末尾の `or the file does not exist` を除去し、`If SPEC_DEPTH=full, read ... Skip if SPEC_DEPTH=light.` に変更
   b. L285-L329: `**Constraint checklist (MUST/SHOULD):**` セクション全体を削除し、2行の Read instruction に置換: `**Constraint checklist (MUST/SHOULD):** When designing implementation steps for SKILL.md/modules/agents changes, read \`${CLAUDE_PLUGIN_ROOT}/skills/spec/skill-dev-constraints.md\` and follow the constraint checklist if loaded in Step 5.`
   c. L510 (テンプレート Verification 例): `command "python3 scripts/validate-skill-syntax.py skills/"` を `command "bash scripts/validate-permissions.sh"` に変更
3. `docs/environment-adaptation.md` の Layer 3 Domain Files 表 (`### Domain Files (exhaustive)`) に新行を追加する。挿入位置は `skills/spec/external-spec.md` 行の直後 (→ 検証 7):
   `| \`skills/spec/skill-dev-constraints.md\` | \`/spec\` | \`SPEC_DEPTH=full\` and \`validate-skill-syntax.py\` present | \`file_exists_any: [scripts/validate-skill-syntax.py]\` and \`spec_depth: full\` | Skill development MUST/SHOULD constraint checklist |`
4. `docs/ja/environment-adaptation.md` の対応する表に日本語訳の行を追加する (translation sync)。挿入位置は `skills/spec/external-spec.md` 行の直後:
   `| \`skills/spec/skill-dev-constraints.md\` | \`/spec\` | \`SPEC_DEPTH=full\` かつ \`validate-skill-syntax.py\` が存在 | \`file_exists_any: [scripts/validate-skill-syntax.py]\` AND \`spec_depth: full\` | スキル開発 MUST/SHOULD 制約チェックリスト |`

## Verification

### Pre-merge

- <!-- verify: file_exists "skills/spec/skill-dev-constraints.md" --> 新 Domain file が作成されている
- <!-- verify: file_contains "skills/spec/skill-dev-constraints.md" "type: domain" --> 新 Domain file に frontmatter が宣言されている
- <!-- verify: rubric "skills/spec/skill-dev-constraints.md load_when combines file_exists_any: [scripts/validate-skill-syntax.py] AND spec_depth: full" --> load_when が validate-skill-syntax.py 存在 AND SPEC_DEPTH=full の AND 条件で記述されている
- <!-- verify: rubric "skills/spec/skill-dev-constraints.md contains the MUST/SHOULD Constraint Checklist tables previously at skills/spec/SKILL.md L285-L328" --> MUST/SHOULD Constraint Checklist 表が Domain file に移譲されている
- <!-- verify: file_not_contains "skills/spec/SKILL.md" "validate-skill-syntax.py" --> skills/spec/SKILL.md 本文から validate-skill-syntax.py の直接言及が除去されている
- <!-- verify: rubric "skills/spec/SKILL.md Step 10 contains only a conditional Read instruction (not the full checklist) pointing to skill-dev-constraints.md" --> SKILL.md 本体は条件付き Read instruction のみに縮約されている
- <!-- verify: rubric "docs/environment-adaptation.md Layer 3 Domain Files table lists skill-dev-constraints.md with its load_when conditions" --> environment-adaptation.md の Domain Files 表に新 Domain file が追加されている

### Post-merge

- 非 skill-dev プロジェクトで `/spec --full` 実行時に MUST/SHOULD checklist が混入しないことを手動確認
- skill-dev プロジェクトで `/spec --full` 実行時に MUST/SHOULD checklist が Domain 経由で適用されることを手動確認

## Notes

- `skills/spec/SKILL.md` L225 の `skill-dev-checks.md` ロード条件から `validate-skill-syntax.py` 言及を除去する理由: `skill-dev-checks.md` が持つ settings.json・shared module・tool dependency チェックは `validate-skill-syntax.py` の存在を前提としない。MUST/SHOULD Constraint Checklist (validator 依存知識) を domain file に分離したことにより、L225 の条件から `validate-skill-syntax.py` 言及が不要となる
- L510 テンプレート例の変更: `validate-skill-syntax.py` 固有コマンドを汎用コマンドに差し替えるため `bash scripts/validate-permissions.sh` に変更。テンプレートの説明目的は維持される

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受入条件はすべて verify コマンド付きで記述されており、自動検証率が高い設計だった。`file_exists`、`file_contains`、`file_not_contains`、`rubric` を組み合わせて7条件をカバー。

#### design
- Spec の Changed Files リストが正確で、実装との乖離がゼロだった。Notes セクションで L225 条件変更の理由（`validate-skill-syntax.py` 非依存化）を明示しており、将来の変更時の参照価値が高い。

#### code
- 単一コミット（11478d3）で実装完結。fixup/amend パターンなし。Code Retrospective は全て N/A で、Spec に忠実な実装だった。

#### review
- パッチルート（直接 main コミット）のため PR レビューなし。変更規模（小規模な抽出作業）に対して適切なルート選択。

#### merge
- main 直コミット。コンフリクトなし。クリーンなマージ。

#### verify
- 7つの pre-merge 条件すべてが初回 verify で PASS。verify コマンドの精度が高かった。
- Post-merge の manual/opportunistic 条件 2件は手動確認待ち（phase/verify 割り当て済み）。

### Improvement Proposals
- N/A
