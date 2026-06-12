# Issue #562: Spec-as-memory Enhancement (Retrospective Discipline and /code・/spec Guidance)

## Overview

Strengthen the Spec-as-memory pattern by:
1. Adding guidance to read existing retrospective sections before implementation (`skills/code/SKILL.md` Step 5) and before design (`skills/spec/SKILL.md` Step 6)
2. Adding explicit retrospective writing discipline to `skills/spec/SKILL.md` Step 13 and `skills/code/SKILL.md` Step 12

The writing discipline follows Fable 5 memory-surface guidance: one learning per entry, record corrections and confirmed approaches, avoid duplicating git history, update/delete entries found to be incorrect.

## Changed Files

- `skills/code/SKILL.md`: Step 5 — add retrospective reading guidance; Step 12 — add writing discipline rules
- `skills/spec/SKILL.md`: Step 6 — add retrospective reading guidance; Step 13 — add writing discipline rules

## Implementation Steps

1. `skills/code/SKILL.md` Step 5 (Load Spec): After the existing "Phase Handoff read" block, add a **Read existing retrospective sections** paragraph instructing `/code` to read any retrospective sections present in the Spec (e.g., `## spec retrospective`, `## code retrospective`) before starting implementation (→ AC#1)

2. `skills/spec/SKILL.md` Step 6 (Codebase Investigation): At the very start of Step 6, before `Read ${CLAUDE_PLUGIN_ROOT}/modules/measurement-scope.md`, add a **Read existing retrospective sections** paragraph instructing `/spec` to read any retrospective sections already present in the Spec file for this Issue before proceeding with codebase investigation (→ AC#2)

3. `skills/spec/SKILL.md` Step 13 (Spec Retrospective): Before the existing retrospective template block, add a **Retrospective writing discipline** paragraph with the 5 rules: one entry per learning; record both corrections and confirmed approaches; link related entries; do not duplicate what the repository or git history already records; update or delete entries found to be incorrect (→ AC#3)

4. `skills/code/SKILL.md` Step 12 (Code Retrospective): Before the existing retrospective template block, add the same **Retrospective writing discipline** paragraph as Step 3 (→ AC#4)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md Step 5 (Load Spec) includes guidance to read existing retrospective sections in the Spec (such as ## Code Retrospective or ## Spec Retrospective) before starting implementation" --> <!-- verify: section_contains "skills/code/SKILL.md" "Step 5" "retrospective" --> `skills/code/SKILL.md` の Step 5 (Load Spec) またはそれに準じる位置に、実装開始前に Spec 内の既存 retrospective セクションを参照する誘導が追加されている
- <!-- verify: rubric "skills/spec/SKILL.md Step 6 (Codebase Investigation) or equivalent early step includes guidance to read existing retrospective sections in the Spec file from prior phases before designing the implementation plan" --> <!-- verify: section_contains "skills/spec/SKILL.md" "Step 6" "retrospective" --> `skills/spec/SKILL.md` の早期ステップ（コードベース調査等）に、設計前に既存フェーズの retrospective を参照する誘導が追加されている
- <!-- verify: rubric "skills/spec/SKILL.md Step 13 (Spec Retrospective) explicitly states retrospective writing guidelines: one learning per entry, record both corrections and confirmed approaches, avoid duplicating what the repository or git history already records, and update or delete entries found to be incorrect" --> `skills/spec/SKILL.md` Step 13 に retrospective 記述規律（1 エントリ 1 学び、訂正も確認済みアプローチも記録、git history 重複排除、誤り修正）が明示されている
- <!-- verify: rubric "skills/code/SKILL.md Step 12 (Code Retrospective) explicitly states retrospective writing guidelines: one learning per entry, record both corrections and confirmed approaches, avoid duplicating what the repository or git history already records, and update or delete entries found to be incorrect" --> `skills/code/SKILL.md` Step 12 に retrospective 記述規律（1 エントリ 1 学び、訂正も確認済みアプローチも記録、git history 重複排除、誤り修正）が明示されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 既存 bats テストが CI で PASS している

### Post-merge

- 実 `/auto` で Spec retrospective が後続フェーズに参照され、重複/矛盾記述が減っていること（観測） <!-- verify-type: manual -->

## Notes

- No bats test changes required — changes are SKILL.md text additions only
- No docs/ translation sync required — changed files are under `skills/`, not `docs/`
- No doc update (README.md, workflow.md) required — no new skills or phases added; internal step-level behavior change only
- Auto-resolved ambiguity points from Issue body are carried over verbatim (see Issue body § Auto-Resolved Ambiguity Points)
- Step 13 and Step 12 note: the writing discipline rules should be placed as a named block (e.g., `**Retrospective writing discipline:**`) before the template block so they are clearly visible as authoring guidelines, not part of the template itself

## Code Retrospective

### Deviations from Design
- None — implementation followed the 4-step plan exactly

### Design Gaps/Ambiguities
- The Spec called for "linking related entries" as a discipline rule; this was included in both Step 12 and Step 13 additions, but the Issue AC rubric did not check for it. It is present in the implementation and adds value beyond the minimum rubric requirement.

### Rework
- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Added "retrospective reading guidance" to Step 5 of `/code` (after Phase Handoff read block) and Step 6 of `/spec` (before measurement-scope.md line) — these are the first natural points where the Spec is loaded, making the guidance immediately actionable.
- Used `**Retrospective writing discipline:**` named block (as specified in Spec Notes) before each template block in Step 12 and Step 13, so the rules are visually distinct from the template itself.
- Writing discipline includes 5 rules: one-entry-per-learning, record corrections AND confirmed approaches, link related entries, no-git-history-duplication, update/delete stale entries.

### Deferred Items
- Behavioral observation of whether `/auto` actually reduces duplicate/conflicting retrospective entries is a post-merge manual verification item (AC post-merge, verify-type: manual).
- No follow-up Issues created — the implementation is complete and self-contained.

### Notes for Next Phase
- All 5 pre-merge ACs verified PASS (section_contains, rubric ×4, github_check CI).
- Changes are purely additive text insertions in two SKILL.md files — no logic, no scripts, no tests modified. Low regression risk.
- The `link related entries` discipline rule is present in both additions even though the rubric did not check for it — verify should confirm the full discipline list matches the AC intent.
