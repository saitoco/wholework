# Issue #788: issue skill Step 4 test file existence check

## Overview

`/issue` skill の Step 4 (Classify Acceptance Criteria and Assign Verify Commands) において、verify command 引数として test file パス (例: `tests/*.bats`) を指定する AC を生成する際、対象ファイルの存在確認ガイダンスを追加する。

現状、`/issue` は test 関連 AC を書く際に対象 test file の存在を確認しない。そのため `/spec` フェーズで「AC が未存在の test ファイルを既存前提として参照している」という conflict が検出される (例: #781 で `tests/issue.bats` を参照した AC が書かれたが当時ファイルは未作成)。本 Issue は conflict 検出を `/issue` フェーズへ前倒しする。

## Consumed Comments

- saito (MEMBER / first-class): Issue Retrospective — Auto-Resolved Ambiguity Points (post-merge verify-type 修正 + rubric AC への supplementary section_contains 追加)
  URL: https://github.com/saitoco/wholework/issues/788#issuecomment-4823235080

## Changed Files

- `skills/issue/SKILL.md`: Step 4 (Classify Acceptance Criteria and Assign Verify Commands) の「Translation document exclusion」直後に **Test file existence check** サブセクションを追加 — bash 3.2+ 互換 (shell script 変更なし; 本変更は Markdown テキスト追加のみ)

## Implementation Steps

1. `skills/issue/SKILL.md` の Step 4 「Translation document exclusion」セクション末尾 ("Assign hints on a best-effort basis. Inaccuracies are handled by `/verify`'s AI fallback.") の直後に以下サブセクションを挿入する (→ AC1, AC2, AC3):

```
**Test file existence check (for verify commands referencing test files):**

When generating an AC whose verify command references a test file path (e.g., `tests/*.bats`, `tests/*.py`), confirm whether the referenced file exists before writing the verify command:

1. Run `ls tests/<filename>` or use Glob to check file presence
2. **File exists**: proceed with the verify command as normal
3. **File does not exist**: the file is a new creation target in this Issue — note this explicitly in the AC or alongside it (e.g., "test file `tests/<filename>.bats` will be created as part of implementation"). Avoid referencing a non-existent file in verify commands that presuppose its existence (e.g., `file_contains`, `section_contains`); prefer `command "bats tests/<filename>.bats"` which validates execution rather than static content.

This check shifts conflict detection from the `/spec` phase (codebase investigation) to the `/issue` phase, reducing rework.
```

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md Step 4 に、test file (例: tests/*.bats) を verify command 引数として指定する AC を生成する際、対象 file の存在を確認するガイダンスが追加されている" --> Issue skill Step 4 に test file 存在確認ガイダンスが追加されている
- <!-- verify: section_contains "skills/issue/SKILL.md" "### Step 4: Classify" "tests/" --> Step 4 (Classify) セクションに tests/ パスへの言及が追加されている
- <!-- verify: grep "tests/.*\\.bats" "skills/issue/SKILL.md" --> SKILL.md に test file 言及が追加されている

### Post-merge

- 実 Issue で test ファイルを参照する AC を書いた場合に、未存在 file の警告が出ることを観察 <!-- verify-type: opportunistic -->

## Notes

- Step 4 (New Issue Creation) と Step 7 (Existing Issue Refinement → Step 7: Classify) の 2 箇所があるが、Step 7 は「Follow the full procedure defined in "New Issue Creation → Step 4"」と参照しているため、Step 4 の追加のみで Step 7 にも自動適用される
- 挿入位置: 「Translation document exclusion」直後。両者ともに verify command 生成時の特殊考慮事項であり文脈的に隣接させるのが適切
- Step 7 の参照テキスト (line 417 付近) に新規サブセクション名の追記は不要 — "full procedure" 参照が包含する
- `tests/*.bats` は例示であり、`tests/*.py` など他の test file 形式にも適用されることを本文に含める
- `section_contains "skills/issue/SKILL.md" "### Step 4: Classify" "tests/"` は section_contains の heading partial match ルールにより "### Step 4: Classify Acceptance Criteria and Assign Verify Commands" に一致する

## Consumed Comments (code phase)

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- None

### Design Gaps/Ambiguities
- None

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Single subsection inserted immediately after "Translation document exclusion" in Step 4 — the Spec-specified position. No other locations required because Step 7 inherits via "Follow the full procedure defined in Step 4".
- Used `ls tests/<filename>` as the existence check command in the guidance (Glob also mentioned); both are valid for the LLM executing this step.
- Text was kept concise with 3-point numbered list and a one-sentence rationale for the shift.

### Deferred Items
- Post-merge opportunistic AC (observe warning when a non-existent test file is referenced) — deferred to real-usage observation, not automatable at this time.

### Notes for Next Phase
- All 3 pre-merge ACs pass (rubric, section_contains, grep).
- Implementation is Markdown-only (no shell script changes); bats test suite 981/981 PASS confirms no regressions.
- validate-skill-syntax.py: 0 errors, 1 pre-existing warning in auto/SKILL.md (unrelated).
- check-forbidden-expressions.sh: 0 issues in skills/issue/SKILL.md; 1 pre-existing issue in docs/spec/issue-802 (unrelated).
