# Issue #696 Spec: migrate auto-session docs to docs/sessions/{SID}-{DATE}/ layout

## Overview

XS size — no formal spec. Implementation derived directly from Issue body.

## Implementation Steps

1. Create target directories `docs/sessions/49779-1781466317-2026-06-15/` and `docs/sessions/22090-1781508629-2026-06-15/`
2. `git mv docs/reports/auto-session-49779-1781466317-2026-06-15.md docs/sessions/49779-1781466317-2026-06-15/session.md`
3. `git mv docs/ja/reports/auto-session-49779-1781466317-2026-06-15.md docs/sessions/49779-1781466317-2026-06-15/session.ja.md`
4. `git mv docs/reports/auto-session-22090-1781508629-2026-06-15.md docs/sessions/22090-1781508629-2026-06-15/session.md`
5. `git mv docs/ja/reports/auto-session-22090-1781508629-2026-06-15.md docs/sessions/22090-1781508629-2026-06-15/session.ja.md`
6. Commit with DCO sign-off

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- N/A — Implementation followed Issue body exactly.

### Design Gaps/Ambiguities

- N/A — Issue body was fully specified; auto-resolved ambiguity log in Issue body covered all edge cases.

### Rework

- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Used `git mv` for all 4 files to preserve git history (enables `git log --follow` from new path back to original)
- JA files placed in same directory as EN files as `session.ja.md` (consistent with Issue body spec and `docs/structure.md` layout)
- No `docs/structure.md` update needed — both `docs/reports/` and `docs/sessions/` were already documented

### Deferred Items
- `docs/reports/auto-session-58975-1781511640-2026-06-16.md` migration is explicitly out of scope (follow-up Issue)
- Post-merge manual check: confirm `session.md` / `session.ja.md` are accessible at expected paths

### Notes for Next Phase
- All pre-merge ACs verified PASS (file_exists/file_not_exists checks + rubric for git history)
- Commit c0d31fd shows 4 renames at 100% similarity — git mv confirmed
- No test failures; bats suite passed 889/889 tests
