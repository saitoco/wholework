# Issue #446: issue/spec: Add adapter pattern survey step to verify command design

## Overview

`/issue` と `/spec` の verify command 設計段階で「既存 adapter pattern の網羅確認」を必須 step として SKILL.md に明示する。Issue #441 で `adapter-resolver.md` の 3-layer resolution と機能重複した B 案を採択した事例を防ぐため、新規 verify command type を提案する前に既存パターンの確認を強制する。

- `/issue` SKILL.md Step 4 (New Issue Creation: Classify Acceptance Criteria and Assign Verify Commands) 冒頭に prerequisite check を追加
- `/spec` SKILL.md Step 6 (Codebase Investigation) に条件付き adapter pattern survey sub-step を追加
- 両箇所とも `docs/environment-adaptation.md` Extension Guide Step 0 を直接参照

## Changed Files

- `skills/issue/SKILL.md`: Step 4 の "Read verify-patterns.md" instruction の直前に「既存 adapter pattern survey」prerequisite ブロックを追加
- `skills/spec/SKILL.md`: Step 6 の Tool detection pattern consistency check の後、Step 7 の前に「Adapter pattern survey」条件付き sub-step を追加

## Implementation Steps

1. `skills/issue/SKILL.md` を編集 — Step 4 の "Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-patterns.md`" 行の直前に以下のブロックを挿入する (→ 受入条件 1, 3):

   ```
   **Existing adapter pattern survey (only when proposing a new verify command type):**

   If a requirement cannot be expressed using any command from the supported commands table below, before proposing a new custom handler mechanism, follow `docs/environment-adaptation.md` Extension Guide Step 0:
   - Enumerate all rows in `modules/verify-executor.md` translation table that delegate via `adapter-resolver.md` (e.g., `browser_check`, `lighthouse_check`)
   - List all bundled adapters under `modules/{capability}-adapter.md`
   - Confirm that the new requirement cannot be expressed by adding a new capability following the existing `adapter-resolver` pattern before proposing a new mechanism

   If expressible via existing `adapter-resolver` patterns, prefer that approach over proposing a new mechanism.
   ```

2. `skills/spec/SKILL.md` を編集 — Step 6 の "**Skip** if no tool detection is included in the implementation steps." の直後（`### Step 7:` の前）に以下のブロックを挿入する (→ 受入条件 2, 3):

   ```
   **Adapter pattern survey (regardless of SPEC_DEPTH; only when applicable):**

   If the Issue body's verify commands include command types not present in the `modules/verify-executor.md` built-in translation table, follow `docs/environment-adaptation.md` Extension Guide Step 0 before accepting the new command type:
   1. Enumerate all rows in `modules/verify-executor.md` that delegate via `adapter-resolver.md`
   2. List all bundled adapters under `modules/{capability}-adapter.md`
   3. Confirm whether the proposed command type can be expressed using existing `adapter-resolver` patterns
   4. If expressible, note the recommended approach in the Spec's "Notes" section

   **Skip** if all Issue body verify commands use built-in command types.
   ```

3. `python3 scripts/validate-skill-syntax.py skills/` を実行して syntax validation が PASS することを確認する (→ 受入条件 4)

## Verification

### Pre-merge

- <!-- verify: grep "adapter-resolver" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` に「既存 adapter pattern 網羅確認」step が追加されている
- <!-- verify: grep "adapter-resolver" "skills/spec/SKILL.md" --> `skills/spec/SKILL.md` に同等の step が追加されている
- <!-- verify: grep "Extension Guide" "skills/issue/SKILL.md" --> <!-- verify: grep "environment-adaptation.md" "skills/spec/SKILL.md" --> 両 step が `docs/environment-adaptation.md` Extension Guide Step 0 を reference として参照している
- <!-- verify: command "python3 scripts/validate-skill-syntax.py skills/" --> tests/ で skill syntax validation が PASS

### Post-merge

- サンプル Issue (新 verify command 提案) で `/issue` 実行し、既存 adapter pattern 確認 step が機能することを手動確認 <!-- verify-type: manual -->
- 同様に `/spec` 実行で確認 <!-- verify-type: manual -->

## Notes

- Step 6 (Existing Issue Refinement) の Classify ステップは New Issue Creation Step 4 を参照しているため、Step 4 への追加で両パスをカバーされる（Issue body の Auto-Resolved Ambiguity Points を踏襲）
- AC3 は 2 つの verify command を 1 つの受入条件にまとめたもの（issue/SKILL.md は "Extension Guide"、spec/SKILL.md は "environment-adaptation.md" でそれぞれ確認）
- 追加するテキストに半角 `!` は含まない（validate-skill-syntax.py の forbidden expression チェックに対応済み）
- `docs/environment-adaptation.md` 自体は変更しない（Extension Guide Step 0 は commit `fcecee2` で既に明文化済み）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## spec retrospective

### Minor observations

- Issue body の AC3 は 2 つの verify command を 1 チェックボックスにまとめている（issue/SKILL.md: "Extension Guide"、spec/SKILL.md: "environment-adaptation.md"）。verify executor での実行順序に依存しないため問題なし。
- 調査の結果、変更対象は SKILL.md 2 ファイルのみで複雑性は低かった。既存の Extension Guide Step 0 が well-defined だったため、参照するだけで設計が完結した。

### Judgment rationale

- non-interactive モードで実行。Issue body の Auto-Resolved Ambiguity Points（挿入位置: issue/SKILL.md → Step 4 冒頭、spec/SKILL.md → Step 6）をそのまま採用。
- ISSUE_TYPE=Task のため Uncertainty・UI Design セクションを省略。
- Changed Files は 2 ファイルのみ（skills/issue/SKILL.md, skills/spec/SKILL.md）。docs/structure.md 等への波及なし。

### Uncertainty resolution

- 調査時点で不確実な点なし。environment-adaptation.md の Extension Guide Step 0 が既に整備されており、参照文言の確認も完了。
