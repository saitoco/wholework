# Issue #567: Consolidate finder agent Output Format into review-output-format.md shared template

## Overview

finder agent (review-bug, review-light, review-spec) の Output Format の `confidence: high / medium / low` フィールド定義が各 agent ファイルに分散しており、共通テンプレート `modules/review-output-format.md` の Shared Finding Format Pattern に集約されていない。Issue #555 で review-bug に `confidence` が追加された際に review-light への波及が漏れ（#555 Spec review retrospective に記録済み）、review-spec には対応がない。

`modules/review-output-format.md` に `confidence` を追加し、各 agent ファイルの重複定義を削除・整合することで、format 変更が 1 箇所で全 finder agent に反映される構造を実現する。

## Changed Files

- `modules/review-output-format.md`: Shared Finding Format Pattern の `- line:` 直後に `- confidence: high / medium / low` を追加
- `agents/review-bug.md`: Output Format finding ブロックから `- confidence: high / medium / low` を削除（1 箇所）
- `agents/review-light.md`: Output Format Perspective 1・2 の finding ブロックから `- confidence: high / medium / low` を削除（2 箇所）
- `agents/review-spec.md`: Output Format Perspective 1, 1.5, 2 の各 finding ブロックの `- line:` 直後に `- confidence: high / medium / low` を追加（3 箇所）

## Implementation Steps

1. `modules/review-output-format.md` の Shared Finding Format Pattern コードブロック内、`- line: line number (relevant line in diff; null if not identifiable)` の直後に `- confidence: high / medium / low` を追加 (→ AC1)
2. `agents/review-bug.md` の Output Format コードブロック内から `- confidence: high / medium / low` 行を削除（`- line:` の直後の 1 行）(→ AC2)
3. `agents/review-light.md` の Output Format コードブロック内の Perspective 1・2 それぞれから `- confidence: high / medium / low` 行を削除（計 2 箇所）(→ AC3)
4. (after 1) `agents/review-spec.md` の Output Format コードブロック内 Perspective 1, 1.5, 2 の各 finding ブロックの `- line:` 直後に `- confidence: high / medium / low` を追加（計 3 箇所）(→ AC4)

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/review-output-format.md" "confidence" --> 共通テンプレート (`modules/review-output-format.md`) の Shared Finding Format Pattern に `confidence` フィールドが追加されている
- <!-- verify: section_not_contains "agents/review-bug.md" "## Output Format" "confidence: high / medium / low" --> `agents/review-bug.md` の Output Format セクションから `confidence` の重複定義が削除されている
- <!-- verify: section_not_contains "agents/review-light.md" "## Output Format" "confidence: high / medium / low" --> `agents/review-light.md` の Output Format セクションから `confidence` の重複定義が削除されている
- <!-- verify: rubric "agents/review-spec.md の Output Format セクションが confidence を含む共通フォーマット（review-output-format.md 経由）に整合している" --> `agents/review-spec.md` の Output Format が confidence フィールドに対応している
- <!-- verify: file_contains "agents/review-spec.md" "review-output-format" --> `agents/review-spec.md` が共通テンプレートを参照している

### Post-merge

- 次回の format 変更時に共通テンプレート 1 箇所の更新で全 finder agent に反映されることを観察

## Notes

- `agents/review-spec.md` は既に `review-output-format` を参照している（AC5 は変更なしで既に PASS）。Step 4 は format 例示の整合のために必要
- review-bug/light の Output Format から `confidence` を削除しても、各 agent は `## Output Format` 末尾の「Read review-output-format.md and follow」指示経由で confidence を出力し続ける

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- None: the Spec clearly specified which lines to add/remove in each agent file, making implementation straightforward

### Rework
- None: all 4 implementation steps completed on the first attempt; all 5 pre-merge ACs PASS

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Used `replace_all=true` for review-light.md to remove both instances of `- confidence: high / medium / low` in a single Edit call (Perspective 1 and 2 had identical surrounding context)
- Used `replace_all=true` for review-spec.md to add `- confidence: high / medium / low` to all 3 perspectives in a single Edit call
- Kept descriptive prose about confidence on line 14 of review-light.md — it is a Purpose explanation, not a format field definition

### Deferred Items
- Post-merge AC: observing that future format changes propagate to all 3 finder agents via the single shared template is intentionally left as opportunistic verification

### Notes for Next Phase
- All 5 pre-merge ACs are verified PASS; verify phase can confirm the remaining post-merge AC opportunistically
- Implementation was a pure text reorganization with no behavioral change — the agents output confidence via `review-output-format.md` reference in both the before and after states; what changed is where the authoritative definition lives
