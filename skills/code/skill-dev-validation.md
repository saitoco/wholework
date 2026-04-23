---
type: domain
skill: code
domain: skill-dev
load_when:
  file_exists_any: [scripts/validate-skill-syntax.py]
applies_to_proposals:
  file_patterns:
    - skills/code/SKILL.md
    - scripts/validate-skill-syntax.py
  content_keywords:
    - SKILL.md
    - validate-skill-syntax
    - skill-dev
    - ${CLAUDE_PLUGIN_ROOT}
  rewrite_target:
    - from: skills/code/SKILL.md
      to: skills/code/skill-dev-validation.md
---

# Skill Development Validation (/code supplement)

This file is loaded only in skill development repositories where `scripts/validate-skill-syntax.py` exists.

## Processing Steps

Run skill syntax validation locally:

```bash
python3 scripts/validate-skill-syntax.py skills/
```

This is equivalent to the CI `validate-syntax` job and detects invalid `allowed-tools` patterns or YAML frontmatter syntax errors before reaching CI. If validation fails, fix the issues before continuing (same as test failures).
