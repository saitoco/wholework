# Issue #580: Review skill-dev: Add transcription divergence detection perspective

## Overview

Add a "Transcription Divergence Check" section to `skills/review/skill-dev-recheck.md` so the `/review` skill detects when aspirational expressions in spike reports or design documents (e.g., "N-vote adversarial verify") are transcribed unchanged into Domain files or SKILL.md despite the actual implementation being simpler (e.g., 1 refutation agent per finding).

Background: In Issue #575 review retrospective, the workflow-adapter spike (#565 `docs/reports/workflow-adapter-spike.md`) aspirational expressions were preserved unchanged in `skills/review/workflow-guidance.md` even though the actual implementation was 1-vote. This is a "transcription divergence" pattern where spike-stage aspirational ideas are kept verbatim when the spec is materialized into implementation files.

Adding this detection perspective to `skill-dev-recheck.md` enables future reviews to flag similar divergences early.

## Changed Files

- `skills/review/skill-dev-recheck.md`: add "## Transcription Divergence Check" section after "## Retrospective Guard"
- `skills/review/SKILL.md`: add conditional reference to the new section in Step 10.2 between step 2.5 and step 3

## Implementation Steps

1. Add "## Transcription Divergence Check" section to `skills/review/skill-dev-recheck.md`, immediately after the "## Retrospective Guard" section. The section content should include:
   - Trigger condition: any changed Domain file or SKILL.md references a spike report
   - Steps: (1) identify spike references in changed files, (2) read spike chapter and extract aspirational expressions, (3) grep implementation files, (4) compare expressed vs. actual behavior
   - Aspirational expression examples: "N-vote", "adversarial verify", loop counts, "ループ until dry", "最大 N 件", parallelism counts
   - Output: SHOULD-level finding when transcription divergence is detected
   (→ AC1, AC2)

2. Add a conditional reference to the new section in `skills/review/SKILL.md` Step 10.2, inserting between the current step 2.5 ("Get steering doc paths") and step 3 ("Launch agents in parallel") as step 2.6:
   `If scripts/validate-skill-syntax.py exists, read ${CLAUDE_PLUGIN_ROOT}/skills/review/skill-dev-recheck.md and follow "Transcription Divergence Check". Record any findings for inclusion in the review results.`
   (after Step 1)

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/review/skill-dev-recheck.md" "transcription" --> review phase の transcription divergence チェック観点が `skill-dev-recheck.md` に追加されている
- <!-- verify: grep "spike|aspirational|N-vote" "skills/review/skill-dev-recheck.md" --> spike からの転記乖離を検出する具体例が記載されている

### Post-merge

- 次回 spike レポート（`docs/reports/*-spike.md`）を参照する実装 Issue の review phase で、transcription check が機能することを確認 <!-- verify-type: opportunistic -->

## Notes

- Section named "## Transcription Divergence Check" (no step number prefix) to match the "## Retrospective Guard" naming style for cross-step concerns
- The check is SHOULD-level: aspirational-vs-implementation divergence is a documentation quality issue, not a correctness bug
- SKILL.md reference step numbered 2.6 to fit between existing steps 2.5 and 3 in Step 10.2 — the existing 2.5 numbering is already non-sequential (historical), so 2.6 is consistent
- No docs/ files need updating (changed files are under `skills/`, not `docs/`)
- No bats test changes needed (modifying markdown files, not scripts)

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
- Added `## Transcription Divergence Check` section to `skill-dev-recheck.md` immediately after `## Retrospective Guard`, matching the existing naming style (no step number prefix, consistent with other cross-step concerns)
- Added step 2.6 in `SKILL.md` Step 10.2 between step 2.5 and step 3, gated on `scripts/validate-skill-syntax.py` existence to preserve the skill-dev-only conditional loading pattern
- Section uses SHOULD severity for divergence findings, consistent with the documentation quality classification (not a correctness bug)

### Deferred Items
- None — scope is narrow (markdown-only change) and fully implemented

### Notes for Next Phase
- Both Pre-merge ACs verified PASS: `file_contains "transcription"` and `grep "spike|aspirational|N-vote"` both match
- Changed files: `skills/review/skill-dev-recheck.md` and `skills/review/SKILL.md` only; no docs/ updates needed per Spec Notes
- validate-skill-syntax.py passed on all 10 skills; bats 700 tests all passed
