---
type: domain
skill: doc
domain: skill-dev
load_when:
  file_exists_any: [scripts/validate-skill-syntax.py, skills/]
applies_to_proposals:
  file_patterns:
    - skills/doc/SKILL.md
    - skills/*/SKILL.md
  content_keywords:
    - SKILL.md
    - modules/*.md
    - agents/*.md
    - skill-dev
    - sync
  rewrite_target:
    - from: skills/doc/SKILL.md
      to: skills/doc/skill-dev-sync.md
---

# Skill Development Sync (/doc supplement)

This file is loaded in skill development repositories where `scripts/validate-skill-syntax.py` exists or the `skills/` directory exists.

## Processing Steps

### Scan implementation code

Also load the following files with Glob:
- `skills/*/SKILL.md`
- `modules/*.md`
- `agents/*.md`
- `scripts/*.sh`

### Cross-skill consistency check

Run only when `scripts/validate-skill-syntax.py` exists. If it does not exist, skip this sub-step.

Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-dev-checks.md` and follow the "Cross-Skill Consistency Check" section to run cross-cutting checks. Include detected inconsistencies in the drift report in Step 7 (normalization proposals).

### Terms consistency check

Run only when the `--deep` flag is enabled. If the `--deep` flag is not enabled, skip this sub-step entirely.

**Step 1 — Deprecated term detection:**

Scan the Terms table in Steering Documents that carry `ssot_for: terminology` in their frontmatter (typically `docs/product.md`). Extract all entries that have a "Formerly called" annotation, collecting the deprecated alias for each term. For each deprecated alias, Grep implementation files (`skills/*/SKILL.md`, `modules/*.md`, `agents/*.md`) for occurrences. Exclude matches within the Terms table itself and within `$SPEC_PATH/` files (disposable specs). Add each match to the drift report as "Deprecated term in use" — each finding should include: Steering Document name, section name ("Terms"), drift category, deprecated alias and its replacement term, and file/line locations.

**Step 2 — Missing term detection:**

Retrieve the list of terms already registered in the Terms table from the Steering Documents identified above. Using AI judgment, extract domain-specific nouns and concepts from implementation files (`skills/*/SKILL.md`, `modules/*.md`, `agents/*.md`) that appear in 3 or more distinct files. Exclude generic programming terms (e.g., "step", "file", "skill", "PR", "Issue", "commit"). Cross-reference candidates against the existing Terms table entries and add unregistered candidates to the drift report as "Missing term" — each finding should include: the unregistered term, number of files it appears in, example locations, and a suggested addition direction.

**Output:**

Accumulate all Terms consistency check findings in the drift report alongside the narrative drift findings above, and pass them to Step 7 (normalization proposals). Do not auto-fix any Terms consistency drift.
