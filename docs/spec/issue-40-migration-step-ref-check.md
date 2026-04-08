# Issue #40: spec: Add step-number reference check convention for migration tasks

## Overview

Add a convention to `modules/skill-dev-checks.md` for migration tasks: when translating step-number references from a source repository, add `file_not_contains` acceptance checks for the source step numbers that should not appear in the migrated file. Detected in #36 where claude-config's `Code review (Step 6)` reference survived migration.

## Changed Files

- `modules/skill-dev-checks.md`: add "Migration Step-Number Reference Check" subsection under "### Design-Time Checks", after the existing "#### SKILL.md Validation Constraint Check" subsection

## Implementation Steps

1. Add a new `#### Migration Step-Number Reference Check` subsection to `modules/skill-dev-checks.md` under "### Design-Time Checks", placed after the "#### SKILL.md Validation Constraint Check" subsection. Content: when changed files include migration from another repository, add `file_not_contains` acceptance checks for source-specific step numbers, workflow names, or other repository-specific references that should not survive migration. Include the #36 `Code review (Step 6)` example. (→ acceptance criteria A, B, C)

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
