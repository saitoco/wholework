# Issue #40: spec: Add step-number reference check convention for migration tasks

## Overview

Add a convention to `modules/skill-dev-checks.md` for migration tasks: when translating step-number references from a source repository, add `file_not_contains` verify commands for the source step numbers that should not appear in the migrated file. Detected in #36 where claude-config's `Code review (Step 6)` reference survived migration.

## Changed Files

- `modules/skill-dev-checks.md`: add "Migration Step-Number Reference Check" subsection under "### Design-Time Checks", after the existing "#### SKILL.md Validation Constraint Check" subsection

## Implementation Steps

1. Add a new `#### Migration Step-Number Reference Check` subsection to `modules/skill-dev-checks.md` under "### Design-Time Checks", placed after the "#### SKILL.md Validation Constraint Check" subsection. Content: when changed files include migration from another repository, add `file_not_contains` verify commands for source-specific step numbers, workflow names, or other repository-specific references that should not survive migration. Include the #36 `Code review (Step 6)` example. (→ acceptance criteria A, B, C)

## Verification

### Pre-merge

- <!-- verify: grep "migration" "modules/skill-dev-checks.md" --> skill-dev-checks.md includes guidance for migration tasks
- <!-- verify: grep "file_not_contains" "modules/skill-dev-checks.md" --> The guidance includes an example pattern using `file_not_contains`
- <!-- verify: section_contains "modules/skill-dev-checks.md" "### Design-Time Checks" "migration" --> The migration check guidance is placed under the "Design-Time Checks" section

### Post-merge

- (none)

## Notes

- Placement after "SKILL.md Validation Constraint Check" follows the convention that migration-specific checks are less frequently triggered than general constraints, so they go last in the Design-Time Checks section.

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Issue Retrospective

### Ambiguity Resolution

All 3 ambiguity points were auto-resolved:
- **Placement**: Under "Design-Time Checks" section in `modules/skill-dev-checks.md`, following existing subsection patterns
- **Target file**: Resolved from acceptance criteria explicitly targeting `modules/skill-dev-checks.md`
- **Content scope**: Derived from #36 background — `file_not_contains` checks for source repo step-number references

### Acceptance Criteria Changes

- Fixed false positive: `grep "Step"` → `grep "file_not_contains"` (original pattern matched existing "Processing Steps" heading)
- Added `section_contains` check to verify placement under the correct section
- Added pre-merge/post-merge section structure
- Clarified Purpose text (removed "or" ambiguity)
- Added "Related Issues" section linking to #36

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- All ambiguity points were auto-resolved in the Issue Retrospective, indicating the Issue body was well-structured with enough background to resolve ambiguity without human intervention.
- Acceptance criteria self-corrected during spec phase (false positive `grep "Step"` → `grep "file_not_contains"`), demonstrating good spec-time verification hygiene.

#### design
- Single-file, single-step design with no deviations. The placement decision (after "SKILL.md Validation Constraint Check") was documented in Notes, providing clear rationale.

#### code
- No rework or fixup commits. Implementation matched spec directly (1 commit: `dbe9fec`).

#### review
- Patch route (direct to main) — no PR review. The small scope (single subsection addition) justified skipping the review phase.

#### merge
- Direct commits to main. No conflicts or CI failures.

#### verify
- All 3 pre-merge acceptance conditions passed cleanly. `grep` and `section_contains` checks were well-chosen for this type of documentation addition.

### Improvement Proposals
- N/A
