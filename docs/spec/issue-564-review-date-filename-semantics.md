# Issue #564: review: Date/File-Naming Semantics Cross-Check Perspective

## Overview

A bug was found in a downstream project where a CI workflow pre-check step built a report file path from the **job execution date** (`date -u +%Y-%m-%d`), but the generator script named files by the **previous business day**. The existence check could never match — the guard was permanently inoperative. This bug was deterministic and verifiable from off-diff context but `/review` missed it because the semantic mismatch required reading files outside the diff.

Add a "date/file-naming semantics cross-check" perspective to `agents/review-bug.md` (full-mode bug detection) and `agents/review-light.md` (light-mode M-size review). When the PR diff contains `date +%` or `date -u +%` used to build a file path, both agents must cross-check the date convention against the generator code's naming function and existing artifact file names.

## Changed Files

- `agents/review-bug.md`: add "Date/File-Naming Semantics Cross-Check" detection block to Step 1 (Bug/Logic Error Detection), immediately after the `**Test Replacement Scenario Coverage**` block (before `### 2. False Positive Filtering`)
- `agents/review-light.md`: add "Date/File-Naming Semantics Cross-Check" detection block to Step 1, Perspective 2 (Edge Cases and Robustness), immediately after the "Temporary file cleanup omissions" bullet (before `**Perspective 3`)]

## Implementation Steps

1. In `agents/review-bug.md`, add the following block immediately after the `**Test Replacement Scenario Coverage**` block (before `### 2. False Positive Filtering`) (→ AC 1, 2):

   ```
   **Date/File-Naming Semantics Cross-Check:**
   When the PR diff contains `date +%` or `date -u +%` used in a file path expression (e.g., constructing a path like `report-$(date +%Y-%m-%d).md`):
   - Grep for the generator function or script that produces files with the same artifact family to confirm the date naming convention (e.g., whether it uses execution date vs. most-recent-closed-business-day offset)
   - Check `ls` of the artifact output directory to confirm actual file name patterns
   - If the date convention in the diff differs from the generator's convention, report at MUST level — the constructed path will deterministically never match the generated file names
   - If no existing generated artifacts can be found for comparison, report at SHOULD level to flag the unverified assumption
   ```

2. In `agents/review-light.md`, add the following block immediately after the "Temporary file cleanup omissions" bullet under "**Perspective 2: Edge Cases and Robustness**" (→ AC 1, 3):

   ```
   **Date/File-Naming Semantics Cross-Check:**
   When the PR diff contains `date +%` or `date -u +%` used in a file path expression:
   - Check the generator function or script for the same artifact family (off-diff context) and existing artifact file names (`ls` of the output directory) to confirm the date naming convention
   - If the naming convention in the diff differs from the generator (e.g., execution date vs. previous business day), report at MUST level — the path match will deterministically fail
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "agents/review-bug.md と agents/review-light.md に、diff が date +% または date -u +% を使ってファイルパスを構築する場合に、リポジトリ内の生成側コードの命名規約（関数）・既存生成物のファイル名と突合するクロスチェックの観点が追加されている" --> `agents/review-bug.md` and `agents/review-light.md` include the date/file-naming semantics cross-check perspective
- <!-- verify: grep "date +%" "agents/review-bug.md" --> Trigger pattern (`date +%`) referenced in `agents/review-bug.md`
- <!-- verify: grep "date +%" "agents/review-light.md" --> Trigger pattern (`date +%`) referenced in `agents/review-light.md`

### Post-merge

- A subsequent review run on a change that builds date-based file paths demonstrates the cross-check perspective in its output

## Notes

- The trigger pattern `date +%` covers both `date +%Y-%m-%d` and `date -u +%Y-%m-%d` since `grep "date +%"` matches both forms
- The cross-check is an off-diff context read: the agent must actively look at the generator script and the existing artifact directory, not just the diff lines
- MUST severity is appropriate because the mismatch is deterministic — the guard is permanently inoperative, not just flaky

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
- Added the cross-check block to `review-bug.md` immediately before `### 2. False Positive Filtering` as specified — placement within Step 1 keeps all detection patterns grouped together
- Added to `review-light.md` under Perspective 2 (Edge Cases and Robustness) rather than a new perspective — date/file-naming mismatches are a robustness issue (deterministic failure mode), not a security or spec deviation issue
- Used `date +%` as the trigger pattern (covering both `date +%Y-%m-%d` and `date -u +%Y-%m-%d`) as specified in Notes

### Deferred Items
- Post-merge verification (opportunistic): a review run on a date-based file path change that demonstrates the new perspective in its output — cannot be verified pre-merge
- No follow-up issues were created (implementation was straightforward, no scope-out remediations found)

### Notes for Next Phase
- Both verify commands (grep "date +%") PASS; rubric also PASS — all pre-merge ACs satisfied
- The implementation is purely additive (no existing behavior changed); regression risk is minimal
- The SHOULD/MUST severity logic is consistent with the existing `review-bug.md` pattern (MUST for deterministic failures, SHOULD for unverifiable assumptions)
