---
type: domain
domain: skill-dev
load_when:
  file_exists_any: [scripts/validate-skill-syntax.py]
applies_to_proposals:
  file_patterns:
    - modules/doc-checker.md
    - skills/*/SKILL.md
  content_keywords:
    - doc-checker
    - SKILL.md
    - skill-dev
    - doc-impact
    - ${CLAUDE_PLUGIN_ROOT}
  rewrite_target:
    - from: modules/doc-checker.md
      to: modules/skill-dev-doc-impact.md
---

# Skill Development Doc Impact

This file is loaded only in skill development repositories where `scripts/validate-skill-syntax.py` exists.

## Change Types

**Change Types (exhaustive):**

| Change Type | Affected Documents |
|------------|-------------------|
| Skill addition, change, or deletion | `README.md` (skill list), `docs/workflow.md` (skill list, phase descriptions), `CLAUDE.md` (skill list, dev flow) |
| Agent/shared module addition, change, or deletion | `docs/workflow.md` (modules/agents list table), `README.md` (if applicable) |
| Script addition, change, or deletion | `README.md` (setup instructions, script descriptions), `docs/workflow.md` (if applicable) |
