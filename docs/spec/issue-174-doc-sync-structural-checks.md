# Issue #174: /doc sync --deep に構造的アンチパターン検出を追加

## Overview

`/doc sync --deep` の検出範囲に3種類の構造的アンチパターン検出を追加する。

1. **SSoT Reverse Reference Check**: `ssot_for` フロントマターを持つファイルが、自カテゴリの内容を他ファイルへ逆方向参照していないかを検出
2. **Pointer-only Section Detection**: SSoT ファイルのセクションが実質コンテンツなしに外部ファイルへのポインタ参照のみを含んでいないかを検出
3. **Skill Coverage Gap** (Narrative Semantic Drift Check 拡張): `skills/*/SKILL.md` に存在するスキルが Steering Document 内で独立した見出しを持たない状態を検出

いずれも `--deep` フラグ時のみ動作し、検出結果は drift report として Step 7 の提案表に統合される（auto-fix なし）。

## Changed Files

- `skills/doc/SKILL.md`:
  - Step 6 → Narrative Semantic Drift Check "Detect drift in 3 categories" テーブルに "Skill Coverage Gap" 行を追加
  - Step 6 → Terms consistency check の `**Output:**` ブロック末尾後・`**Content classification based on dynamic SSoT mapping:**` の直前に "Structural Antipattern Detection (--deep only)" サブセクションを追加（SSoT Reverse Reference Check + Pointer-only Section Detection）
  - Step 7 → "Drift report" 箇条書きに structural antipattern findings への言及を追加
- `docs/workflow.md`: `/doc sync --deep` 説明文に structural antipattern detection を追記
- `docs/ja/workflow.md`: 対応する日本語ミラー更新

## Implementation Steps

1. `skills/doc/SKILL.md` Step 6 の Narrative Semantic Drift Check → "Detect drift in 3 categories" テーブルの `Obsolete mention` 行の直後に4行目として追加する:

   ```
   | Skill Coverage Gap | A skill exists in `skills/*/SKILL.md` but has no independent top-level section heading in the Steering Document | `/triage` exists in `skills/` but is mentioned only within a subsection, without an independent heading |
   ```

   (→ 受け入れ条件 C)

2. `skills/doc/SKILL.md` Step 6 の Terms consistency check の `**Output:**` ブロック末尾後・`**Content classification based on dynamic SSoT mapping:**` の直前に以下のサブセクションを追加する:

   ```
   **Structural Antipattern Detection (--deep only):**

   This sub-step runs only when the `--deep` flag is enabled.

   **SSoT Reverse Reference Check:**

   For each file with `ssot_for` frontmatter, scan all sections. If a section's content primarily consists of a reference pointing to another file (e.g., "See docs/X.md for Y") where the referenced content logically belongs in the current file's `ssot_for` category, flag it as a "SSoT Reverse Reference" antipattern — the SSoT file is delegating its own content outward.

   **Pointer-only Section Detection:**

   For each `type: steering` file, scan all sections. If a section contains no substantive content — only pointer/reference text (e.g., "See README.md for the skill list.") with no bullets, tables, or descriptive sentences beyond the pointer — flag it as a "Pointer-only Section" antipattern.

   Accumulate all findings as drift report items and pass them to Step 7 (normalization proposals). Do not auto-fix any detected structural antipatterns.
   ```

   (→ 受け入れ条件 A、B、5)

3. `skills/doc/SKILL.md` Step 7 → "Drift report" 箇条書きの末尾を以下のように更新する（"narrative semantic drift check findings" への言及の後に structural antipatterns を追記）:

   変更前（抜粋）: `narrative semantic drift check findings (Missing coverage / Partial description / Obsolete mention) are also surfaced through this path and never auto-fixed`

   変更後（抜粋）: `narrative semantic drift check findings (Missing coverage / Partial description / Obsolete mention / Skill Coverage Gap) and structural antipattern detection findings (SSoT Reverse Reference, Pointer-only Section) are also surfaced through this path and never auto-fixed`

   (→ 受け入れ条件 D)

4. `docs/workflow.md` line 139 の `/doc sync --deep` 説明文の `4-pattern classification, absorption target determination` の後に ` plus structural antipattern detection (SSoT Reverse Reference, Pointer-only Section, Skill Coverage Gap)` を追記する。`docs/ja/workflow.md` line 23 も同様に `4 パターン分類、吸収対象判定` の後に `、構造的アンチパターン検出（SSoT 逆方向参照、ポインタのみセクション、Skill Coverage Gap）` を追記する（after 1, 2, 3）。

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/doc/SKILL.md" "Reverse Reference" --> SSoT Reverse Reference Check が `skills/doc/SKILL.md` の sync --deep セクションに記載されている
- <!-- verify: file_contains "skills/doc/SKILL.md" "Pointer-only" --> Pointer-only Section Detection が `skills/doc/SKILL.md` の sync --deep セクションに記載されている
- <!-- verify: file_contains "skills/doc/SKILL.md" "Skill Coverage" --> Skill Coverage Coherence が `skills/doc/SKILL.md` の sync --deep セクションに Narrative Semantic Drift Check 拡張として記載されている
- <!-- verify: file_contains "skills/doc/SKILL.md" "drift report" --> 新検出ロジックの結果が drift report として Step 7 の提案表に統合される仕様が記載されている
- 新検出ロジックはすべて `--deep` フラグ時のみ動作する（verify コマンドなし: ステップ 2 で追加するサブセクションの "This sub-step runs only when the `--deep` flag is enabled." 記述で仕様明示）

### Post-merge

- wholework リポジトリ上で `/doc sync --deep` を実行し、SSoT Reverse Reference / Pointer-only Section / Skill Coverage Gap のアンチパターン相当ケース（または既存テストフィクスチャ）が検出されることを確認

## Notes

- Non-Goals: 既存の Narrative Semantic Drift Check / Terms consistency check / SSoT duplication check の振る舞い変更なし；すべての新検出結果は drift report のみ（auto-fix なし）；`/doc sync`（--deep なし）への追加なし
- Step 7 の "Drift report" 説明はStep 6 の新サブセクションで "drift report items" と記述していることとの整合性を保つこと

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## review retrospective

### Spec vs. implementation divergence patterns

The heading "Detect drift in 3 categories" was not updated to "4 categories" when Skill Coverage Gap was added as a 4th category. This is a text-level consistency gap between a heading and its associated table — the verify commands (file_contains) only check keyword existence and cannot detect numerical or enumeration inconsistencies within prose. Future Specs should add explicit verify conditions for heading text when a count or enumeration in a heading is expected to change.

### Recurring issues

- None in this PR. Single isolated heading-count inconsistency.

### Acceptance criteria verification difficulty

- All 4 verify commands were PASS-able via automated file_contains checks. The 5th condition (--deep flag scope) required reading the SKILL.md section text, which was clear and unambiguous.
- The heading-count inconsistency (the only issue found) was not coverable by any of the existing verify commands — it required AI judgment during the review. Adding a `file_contains "skills/doc/SKILL.md" "4 categories"` verify condition to the acceptance criteria would have caught this automatically.
