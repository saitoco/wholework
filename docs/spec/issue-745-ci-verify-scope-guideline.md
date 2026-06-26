# Issue #745: CI verify command (github_check) scope design guideline

## Overview

`github_check "gh pr checks"` checks CI results for the entire PR, including tests unrelated to the PR's changes. When pre-existing failing tests on `main` fail, the acceptance condition receives a false FAIL — requiring human judgment to determine whether the failure is within scope. This issue extends `modules/verify-patterns.md` §7 with a scope design guideline explaining this risk and recommending scope-limited alternatives: specific workflow (`gh run list --workflow=<specific>.yml`) or direct test execution (`command "bats tests/<specific>.bats"`).

Concrete cases: #695 (audit-auto-session) and #702 (recoveries-auto-fire) — both encountered false FAILs from pre-existing test failures unrelated to the PR's changes.

## Changed Files

- `modules/verify-patterns.md`: extend §7 "Note on `gh run list` vs `gh pr checks`" — add CI verify command scope design guidance (scope creep risk, preferred patterns, usage criteria table) — markdown doc; bash compat not applicable

## Implementation Steps

1. In `modules/verify-patterns.md` §7, after the existing "**Note on `gh run list` vs `gh pr checks`:**" paragraph (immediately after the line "See `${CLAUDE_PLUGIN_ROOT}/modules/verify-classifier.md` for details."), add a new "**CI verify command scope design (PR route):**" subsection. The subsection must cover:
   - Scope creep risk: `github_check "gh pr checks"` checks all CI on the PR, including results from tests unrelated to the PR's changes (e.g., pre-existing failing tests on `main`), causing false FAILs (observed in #695, #702)
   - Preferred pattern 1 — specific workflow: `github_check "gh run list --workflow=<specific>.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"`
   - Preferred pattern 2 — direct test execution: `command "bats tests/<specific>.bats"`
   - Usage criteria table (three rows: `gh pr checks` / specific workflow / direct command) × Scope × When to use
   - Fallback guidance: when `gh pr checks` must be used, write "all CI green" in the AC text to clarify scope and signal that out-of-scope failure handling is delegated to the verify phase
   (→ acceptance criteria 1, 2)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-patterns.md §7 (または skills/spec/SKILL.md の AC 生成セクション) に、github_check 'gh pr checks' が当該 PR と無関係な test failure を拾うリスクと、CI verify command scope を限定する推奨パターン (specific workflow または command 直接実行) が追加されている" --> CI verify command scope 設計ガイドラインが追加されている
- <!-- verify: rubric "skills/spec/SKILL.md または skills/issue/SKILL.md または modules/verify-patterns.md に、github_check 'gh pr checks' と specific workflow 限定 / command 直接実行の使い分け基準が明示されている" --> guideline 使い分け基準の文書化を満たす
- <!-- verify: section_contains "modules/verify-patterns.md" "7. GitHub Actions" "pre-existing" --> §7 に pre-existing キーワードを含む新規ガイドラインが追加されている

### Post-merge

- CI passes

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: AC を rubric に変更した根拠 (日本語 grep パターンが英語実装で FAIL するため) と実装ターゲットを verify-patterns.md §7 に推奨した理由 (SSoT、一箇所で両スキルに適用) を記録 / https://github.com/saitoco/wholework/issues/745#issuecomment-4805857721

## Notes

### Auto-resolved ambiguity points (from /issue phase)

These decisions were made in the `/issue` phase and recorded in the Issue Retrospective comment:

1. **Implementation target**: `modules/verify-patterns.md` §7 — SSoT for verify command patterns, referenced by both `/issue` and `/spec`; §7 already covers `github_check` usage; one change reaches both skills.
2. **AC1 verify command**: Changed to `rubric` (target-agnostic) — the original `grep "CI verify command の scope" "skills/spec/SKILL.md"` would FAIL when implementation uses English text (per CLAUDE.md English rule); also, target file became an OR condition (`modules/verify-patterns.md` or `skills/spec/SKILL.md`), making `file_contains` supplementary infeasible.

### Supplementary section_contains AC

The third pre-merge item (`section_contains ... "pre-existing"`) is a supplementary mechanical check added in the Spec phase per §9 of verify-patterns.md. It is not in the Issue body's original ACs. The Issue body will be updated to include it (see count alignment below).

### Count alignment

- Issue body Pre-merge criteria: 2 items
- Spec Pre-merge verification: 3 items

Warning: acceptance criteria count does not match verification item count.
  Issue body pre-merge criteria: 2 items
  Spec pre-merge verification: 3 items
The third item is a supplementary `section_contains` check added per §9 of verify-patterns.md. Issue body will be updated.

## Code Retrospective

### Deviations from Design

- None. Implementation followed the Spec exactly: added "CI verify command scope design (PR route)" subsection to §7 immediately after the "Note on `gh run list` vs `gh pr checks`" paragraph.

### Design Gaps/Ambiguities

- The Spec's count alignment notes flagged the Issue body as having 2 items vs. 3 in the Spec. At execution time, the Issue body already had 3 items (updated during the /spec phase). No corrective action was needed.

### Rework

- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added the new subsection under §7 (not as a new §7a or separate section) to keep it co-located with the existing `gh pr checks` vs `gh run list` note — reviewers reading §7 see the full picture in one pass.
- Included "pre-existing" keyword in three places (risk description, usage criteria table, fallback guidance) to satisfy AC3 `section_contains` and reinforce the concept.
- Used a usage criteria table (three rows) to make the pattern differentiation scannable.

### Deferred Items
- None. This is a documentation-only change; no code logic was modified.

### Notes for Next Phase
- All 3 pre-merge ACs are expected to PASS: `rubric` AC1 and AC2 (semantic coverage confirmed), `section_contains` AC3 (keyword "pre-existing" present in §7, confirmed by grep).
- The Issue body checkboxes have been updated to [x] by /code.
- Post-merge AC is "CI passes" — verify that the CI run after merge is clean.
