# Issue #713: review: add prose-literal consistency check to review-spec rubric

## Overview

`agents/review-spec.md` に Perspective 3 "Prose-Literal Consistency Check" を追加する。
同一ファイル内の code fence 内で定義された形式例と、条件文/検出ロジックで参照される literal 文字列の不整合を MUST レベルで指摘できるようにする。

発生元: #705 `modules/l0-surfaces.md` の bot exception 検出ロジックにて、prose で定義したマーカー形式 (`<!-- wholework-event: type=<type> phase=<phase> issue=<n> -->`) と実際の検出 literal (`<!-- wholework-event: -->`) が齟齬していた事例を `/review --full` が検出できなかった。

## Changed Files

- `agents/review-spec.md`: add "### 3. Prose-Literal Consistency Check" to Processing Steps and "### Perspective 3: Prose-Literal Consistency" to Output Format

## Implementation Steps

1. `agents/review-spec.md` の `### 2. Documentation Consistency Check` セクション末尾と `## Output Format` セクションの間に `### 3. Prose-Literal Consistency Check` セクションを追加する (→ AC1, AC2, AC3)

   追加するセクション:
   ```
   ### 3. Prose-Literal Consistency Check

   For each file changed in the PR that is a `modules/*.md` or `skills/*/SKILL.md` file:

   1. **Identify format examples in code fences**: Find format examples shown inside fenced code blocks (` ```yaml `, ` ```html `, ` ```bash `, ` ```json `, etc.) that represent canonical marker formats, command patterns, or schema fragments.
   2. **Identify detection/matching literals**: Find literal strings used elsewhere in the **same file** for detection, string matching, condition checking, or parsing (e.g., `startsWith("...")`, `contains("...")`, literal pattern strings in conditions, inline code examples used for matching).
   3. **Cross-reference for consistency**: Compare each code-fence format example against detection literals that reference the same format. If the code-fence example and the detection literal diverge (e.g., required attributes present in the example are absent in the detection literal, or format fields differ), flag as MUST.

   **If no prose-literal pairs exist in the changed files**: Skip this perspective and report no issues.
   ```

2. `agents/review-spec.md` の Output Format セクションで `### Perspective 2: Documentation Consistency` ブロックの後、`### No Issues Found` の前に `### Perspective 3: Prose-Literal Consistency` セクションを追加する (→ AC1, AC3)

   追加するセクション:
   ```
   ### Perspective 3: Prose-Literal Consistency

   **[Prose-Literal Inconsistency] filename:line-number vicinity**
   - path: file path (relative to repository root; null if not identifiable)
   - line: line number (corresponding line in diff; null if not identifiable)
   - confidence: high / medium / low
   Issue description. Severity: MUST / SHOULD / CONSIDER

   Recommended fix:
   (specific fix suggestion)
   ```

## Verification

### Pre-merge

- <!-- verify: file_contains "agents/review-spec.md" "Prose-Literal" --> `agents/review-spec.md` に prose-literal consistency rubric が追加されている
- <!-- verify: grep "code fence" "agents/review-spec.md" --> rubric の検出基準 (code fence と外側 literal の一致確認) が記述されている
- <!-- verify: section_contains "agents/review-spec.md" "Prose-Literal" "MUST" --> 不整合検出時の severity (MUST) が新設 Prose-Literal セクション内に明記されている

### Post-merge

- 次回 module / SKILL.md を変更する Issue で `/review --full` が走った際、prose-literal 不整合が存在すれば MUST として指摘されることを観察 <!-- verify-type: observation event=pr-review-full -->

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: 曖昧ポイント 3 件自動解決 (rubric 言語=英語, AC3 verify command を section_contains へ変更, AC1 大文字 L 統一) / [#issuecomment-4759304155](https://github.com/saitoco/wholework/issues/713#issuecomment-4759304155)

## Notes

**Auto-resolved ambiguity points (from Issue retrospective comment):**

1. **Rubric テキストの言語**: 英語を選択。CLAUDE.md「Source code | English」「Documentation | English」に準拠。`agents/review-spec.md` 自体が全編英語。
2. **AC3 verify command**: `section_contains "agents/review-spec.md" "Prose-Literal" "MUST"` に変更。`file_contains "MUST"` は既存テキストに "MUST" が存在するため実装前から常時 PASS してしまう問題を回避。
3. **AC1 文字列ケース**: `"Prose-Literal"` (大文字 L) を使用。既存 Perspective 見出し (title case) パターンに合わせる。

**新設 Perspective の位置**: `### 2. Documentation Consistency Check` の直後、`## Output Format` の直前に追加する。Output Format セクションでは既存の `### Perspective 2: Documentation Consistency` ブロックの後、`### No Issues Found` の前に追加する。

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Implemented Spec steps in order: added `### 3. Prose-Literal Consistency Check` in Processing Steps, then `### Perspective 3: Prose-Literal Consistency` in Output Format section
- Rubric text is in English per CLAUDE.md convention; all three ACs verified PASS locally before commit
- Patch route chosen per --patch flag (Size S)

### Deferred Items
- Post-merge observation: next L-size PR that changes `modules/*.md` or `skills/*/SKILL.md` should be observed to confirm new perspective fires on prose-literal mismatches

### Notes for Next Phase
- All 3 pre-merge ACs verified PASS (file_contains, grep, section_contains) — Issue checkboxes updated
- No test changes needed; bats suite passed 889 tests, 0 failures
- Forbidden expressions check PASS; skill syntax validation PASS (existing warning about loop-paths-fallback unrelated to this change)
