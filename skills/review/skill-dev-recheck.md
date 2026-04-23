---
type: domain
skill: review
domain: skill-dev
load_when:
  file_exists_any: [scripts/validate-skill-syntax.py]
applies_to_proposals:
  file_patterns:
    - skills/review/SKILL.md
    - scripts/validate-skill-syntax.py
  content_keywords:
    - SKILL.md
    - validate-skill-syntax
    - skill-dev
    - review
    - ${CLAUDE_PLUGIN_ROOT}
  rewrite_target:
    - from: skills/review/SKILL.md
      to: skills/review/skill-dev-recheck.md
---

# Skill Development Re-check (/review supplement)

This file is loaded only in skill development repositories where `scripts/validate-skill-syntax.py` exists.
Follow the additional steps below for each relevant step.

## Step 8: Additional Suggestions on CI Failure

When a CI job is FAILURE, suggest the following job-specific fixes:

- `validate-skill-syntax` FAIL → run `python3 scripts/validate-skill-syntax.py skills/` locally and fix errors

## Step 12.3: Re-run validate-skill-syntax

During the lightweight re-check, run:

```bash
python3 scripts/validate-skill-syntax.py skills/
```

Verify that all SKILL.md files pass syntax validation.
