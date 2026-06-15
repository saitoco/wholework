# Issue #460: Add git_committed verify command for async external commit paths

## Overview

`file_exists` is structurally weak when verifying artifacts under external-tool-managed paths (e.g., Obsidian Git, Logseq Sync) because the file may be on disk but not yet committed. This issue adds `git_committed "path"` as a built-in verify command in `modules/verify-executor.md`, providing git-tracking-based verification equivalent in simplicity to `file_exists` but resilient to async commit timing.

The issue also removes the `(future)` label from the Priority 1 row in `modules/verify-patterns.md` §15, reflecting that `git_committed` is now available.

Ambiguity points were auto-resolved before spec creation (see Notes).

## Changed Files

- `modules/verify-executor.md`: add `git_committed "path"` row to the translation table in `## Processing Steps`
- `modules/verify-patterns.md`: update §15 Priority 1 row — remove `(future)` label from `| 1 (future) |` and update description to reflect current availability

## Implementation Steps

1. In `modules/verify-executor.md`, insert the `git_committed "path"` row immediately after the `file_not_exists "path"` row in the Step 4 translation table. Entry:
   - **Processing**: If `PR_BRANCH` is set: run `git show origin/<PR_BRANCH>:<path>` — exit 0 → PASS (file tracked in PR branch), error → FAIL (file absent in PR branch). If `PR_BRANCH` is not set: run `git ls-files --error-unmatch -- "path"` in Bash — exit 0 → PASS (file is tracked by git), non-zero → FAIL (file absent or untracked).
   - **Permission**: `always_allow` (local read-only git operation; no network, no side effects — same guarantee as `file_exists`)
   - **Safe mode**: runs in both safe and full modes (since `always_allow`)
   (→ AC 1, 2, 3)

2. In `modules/verify-patterns.md` §15 (heading: `### 15. Async External-Commit Area — Verify Command Patterns`), update the Priority table row:
   - Change `| 1 (future) |` → `| 1 |`
   - Change description from `"Preferred once Issue #460 ships. Checks that the path appears in `git log` — resilient to async commit timing"` to `"Recommended. PASS when path is tracked by git; resilient to async commit timing"`
   (→ AC 4, 5)

## Verification

### Pre-merge

- <!-- verify: grep "git_committed" "modules/verify-executor.md" --> `git_committed "path"` が `modules/verify-executor.md` の翻訳テーブルに追加されている
- <!-- verify: grep "git_committed.*always_allow" "modules/verify-executor.md" --> `git_committed` のパーミッション列が `always_allow` になっている（ローカル read-only git 操作のため `file_exists` と同等）
- <!-- verify: rubric "modules/verify-executor.md の git_committed エントリが、追跡済み（PASS）と未追跡または存在しない（FAIL）の動作仕様を記述している" --><!-- verify: section_contains "modules/verify-executor.md" "Processing Steps" "git_committed" --> `git_committed` の PASS/FAIL 動作仕様がエントリに明記されている
- <!-- verify: section_not_contains "modules/verify-patterns.md" "Async External-Commit" "(future)" --> `verify-patterns.md` §15 の Priority 1 行から `(future)` タグが除去されている
- <!-- verify: section_contains "modules/verify-patterns.md" "Async External-Commit" "git_committed" --> `verify-patterns.md` §15 に `git_committed` が引き続き記述されている

### Post-merge

なし

## Notes

### Auto-Resolved Ambiguity Points

The following points were resolved before spec creation (recorded in Issue body):

- **パーミッションレベル** → `always_allow`。`git ls-files --error-unmatch -- "path"` はローカル read-only 操作（ネットワーク・副作用なし）。`file_exists` / `dir_exists` と同じパターンに従う。
- **safe mode 動作** → `always_allow` のため `/review`（safe mode）でも実行可能。`file_exists` と同様に pre-merge でも機械的に検証できる。
- **PR_BRANCH 対応** → `file_exists` と同様に `PR_BRANCH` が設定されている場合は `git show origin/<PR_BRANCH>:<path>` で確認。フォールバックは `git ls-files --error-unmatch -- "path"` in Bash。

### Insertion Position in verify-executor.md

The new row is inserted after `file_not_exists "path"` and before `dir_exists "path"` to keep file-related existence checks grouped together. This is consistent with the logical grouping in the existing table (file → dir → content → pattern → command).

### Out of Scope

- Updating the "Pattern to use today" section and checkpoint text in `verify-patterns.md` §15 — tracked in Issue #462.
- Updating `modules/orchestration-fallbacks.md` "See also" reference (informational text remains accurate as a historical reference).

## Code Retrospective

### Deviations from Design

- None. Implementation followed the Spec exactly: inserted `git_committed` row after `file_not_exists` and before `dir_exists` in the translation table; updated `verify-patterns.md` §15 Priority 1 row from `(future)` to available.

### Design Gaps/Ambiguities

- None. The Spec's auto-resolved ambiguity points (permission level, safe mode behavior, PR_BRANCH handling) were clear and complete — no new ambiguities surfaced during implementation.

### Rework

- None.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `git_committed` inserted after `file_not_exists` row (before `dir_exists`) to keep file-existence checks grouped together — consistent with logical table ordering.
- Permission set to `always_allow`: local read-only git operation, same guarantee as `file_exists` / `dir_exists`.
- PR_BRANCH handling mirrors `file_exists`: `git show origin/<PR_BRANCH>:<path>` when set; `git ls-files --error-unmatch` in Bash when not set.

### Deferred Items
- `verify-patterns.md` §15 "Pattern to use today" section and checkpoint text update deferred to Issue #462 (explicitly out of scope in Spec).
- `modules/orchestration-fallbacks.md` "See also" reference left as-is (informational, still accurate as historical reference).

### Notes for Next Phase
- All 5 pre-merge verify commands PASS locally.
- No forbidden expression violations detected.
- BATS tests (827 tests) all pass — no test changes needed for this purely documentation-level change.
- Post-merge ACs: none specified in this Issue.
