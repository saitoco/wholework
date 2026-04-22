# Issue #338: spec/doc: Make skill-dev-checks.md Call Gate Conditions Explicit in SKILL.md (Phase 2 Sub 2F)

## Overview

Phase 2 (#293) foundation work. Both `skills/spec/SKILL.md` and `skills/doc/SKILL.md` already contain gate conditions for reading `modules/skill-dev-checks.md`, but the conditions are expressed as inline prose, making them implicit and hard to align with the frontmatter-driven Domain registration schema established in Sub 2A/2B. This issue makes these conditions explicit using the Phase 1 gate format: state the skip condition first (negative case), then state the action (positive case).

No new Domain file is created; this is a call-site gate clarification only.

## Changed Files

- `skills/spec/SKILL.md`: rewrite line 225 gate condition — from mixed inline prose (`If SPEC_DEPTH=full and ... exists, read ... Skip if ...`) to explicit gate format (skip conditions listed first, Read instruction separated) — bash 3.2+ compatible (no shell scripts)
- `skills/doc/SKILL.md`: rewrite line 508 gate condition — from `If ... exists, Read ...` inline to explicit gate format (skip condition first, Read instruction separated) — bash 3.2+ compatible (no shell scripts)

## Implementation Steps

1. In `skills/spec/SKILL.md` Step 10, replace the single inline sentence at line 225:
   > "If SPEC_DEPTH=full and `scripts/validate-skill-syntax.py` exists, read `${CLAUDE_PLUGIN_ROOT}/modules/skill-dev-checks.md` and follow it at the relevant point in Step 10. Skip if SPEC_DEPTH=light or the file does not exist."

   with the explicit gate format (skip conditions first):
   > "If `scripts/validate-skill-syntax.py` does not exist, skip this step. Skip also if SPEC_DEPTH=light.
   >
   > Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-dev-checks.md` and follow it at the relevant point in Step 10."

   (→ acceptance criteria 1, 3)

2. In `skills/doc/SKILL.md` "Cross-skill consistency check" block at line 508, replace:
   > "If `scripts/validate-skill-syntax.py` exists, Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-dev-checks.md` and follow the "Cross-Skill Consistency Check" section to run cross-cutting checks. Include detected inconsistencies in the drift report in Step 7 (normalization proposals)."

   with the explicit gate format (skip condition first):
   > "If `scripts/validate-skill-syntax.py` does not exist, skip this step entirely.
   >
   > Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-dev-checks.md` and follow the "Cross-Skill Consistency Check" section to run cross-cutting checks. Include detected inconsistencies in the drift report in Step 7 (normalization proposals)."

   (→ acceptance criteria 2, 4)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md explicitly gates the Read instruction for modules/skill-dev-checks.md with both scripts/validate-skill-syntax.py existence AND SPEC_DEPTH=full" --> /spec の gate 条件が SKILL.md 側に明示化されている
- <!-- verify: rubric "skills/doc/SKILL.md explicitly gates the Read instruction for modules/skill-dev-checks.md with scripts/validate-skill-syntax.py existence" --> /doc sync の gate 条件が SKILL.md 側に明示化されている
- <!-- verify: file_contains "skills/spec/SKILL.md" "skill-dev-checks.md" --> /spec の Read instruction が残存している
- <!-- verify: file_contains "skills/doc/SKILL.md" "skill-dev-checks.md" --> /doc の Read instruction が残存している

### Post-merge

- 非 skill-dev プロジェクトで `/spec --full` 実行時に skill-dev-checks が読まれないことを手動確認

## Notes

**Gate format reference**: Follows the Phase 1 (#292) pattern established in `skills/code/SKILL.md`:
- Negative case first: "If X does not exist, skip this step entirely."
- Positive case (action) separated by blank line: "Read `...` and follow ..."

This mirrors the `load_when` frontmatter schema's explicit condition declaration (Sub 2A), but expressed in SKILL.md prose rather than machine-readable YAML.

**Content unchanged**: Both gate conditions already had the correct logic. Only the format changes:
- spec/SKILL.md: SPEC_DEPTH=full AND validate-skill-syntax.py exists (both conditions already present)
- doc/SKILL.md: validate-skill-syntax.py exists (already present)
