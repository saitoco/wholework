# Issue #495: spec: setdefault Anti-pattern Guideline

## Overview

When implementation hints in a Spec include methods like `setdefault` or `dict.update` where the side-effect direction is counterintuitive, it causes implementation bugs. This Issue adds a guideline to `skills/spec/SKILL.md` Step 10 that flags these methods as anti-patterns and recommends explicit algorithmic descriptions instead.

Background: In a priority-ordered dict construction Issue, Spec instructions said "write with `setdefault` starting from lowest priority." Because `setdefault` does not overwrite existing keys, iterating from low priority first locks in the lowest-priority values — high-priority values cannot overwrite them. The developer discovered this during Code Retrospective and switched to a "high-priority-first with `if key not in dict` check" pattern, but 2 bats tests failed due to the Spec error.

## Changed Files

- `skills/spec/SKILL.md`: add "Side-effect direction anti-patterns in implementation steps" guideline to Step 10 (after "read-then-write jq failure guard", before "SHOULD-level acceptance criteria consideration")

## Implementation Steps

1. In `skills/spec/SKILL.md`, locate the "read-then-write jq failure guard" block in Step 10 (immediately before "**SHOULD-level acceptance criteria consideration:**"). Insert the following new guideline block between the two:

   ```markdown
   **Side-effect direction anti-patterns in implementation steps:**

   When writing implementation steps that involve priority-ordered data construction (e.g., building dicts with multiple priority sources), avoid methods where the side-effect direction is counterintuitive:

   - **Anti-pattern**: `setdefault` or `dict.update` in low-priority-first order — `setdefault` does not overwrite existing keys, so calling it from lowest priority upward locks in the lowest-priority value; `dict.update` in high-priority-first order overwrites previously set higher-priority values with lower-priority ones
   - **Recommended**: explicit algorithmic description — e.g., "iterate sources in high-priority-first order; for each key, set `dict[key] = value` only if the key is not yet present (`if key not in dict`)"

   When the overwrite direction of a method is non-obvious, spell out the algorithm explicitly rather than specifying the method by name.
   ```

   (→ acceptance criteria 1, 2)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md の Step 10 に副作用の方向性が直感と逆になりやすいメソッド (setdefault 等) をアンチパターンとして明記し、明確なアルゴリズム記述を推奨する旨が追加されている" --> Spec 記述ガイドにアンチパターン + 推奨パターンが追加されている
- <!-- verify: section_contains "skills/spec/SKILL.md" "### Step 10: Create Spec" "setdefault" --> Step 10 に `setdefault` アンチパターンの説明が含まれる

### Post-merge

- 優先順位付き辞書構築や類似の副作用パターンを含む実 Issue で `/spec` 実行 → 生成される実装ヒントに setdefault が含まれず、明確な if 条件付きアルゴリズムが記述されることを目視確認する <!-- verify-type: opportunistic -->

## Notes

- `dict.update` の記述は `setdefault` の説明内で参照（別 AC は不要、Issue の Auto-Resolved Ambiguity Points 参照）
- 挿入位置: "read-then-write jq failure guard" ブロック直後 ("**SHOULD-level acceptance criteria consideration:**" 直前)
- SKILL.md はスキル定義ファイルのため `docs/ja/` 翻訳同期対象外
