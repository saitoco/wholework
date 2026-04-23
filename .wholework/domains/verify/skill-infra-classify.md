---
type: domain
skill: verify
load_when:
  marker: skill-proposals
---

# Skill Infrastructure Improvement Classification

## Skill infrastructure improvement

Classify improvement proposals as **Skill infrastructure improvement** when they match any of the following:

- Proposals for changes to skill commands themselves (`/spec`, `/verify`, `/review`, etc.) (e.g., "Should add a step to `/spec`")
- References to files under `~/.claude/` (e.g., "Should improve `${CLAUDE_PLUGIN_ROOT}/modules/xxx.md`")
- References to skill-specific filenames like `SKILL.md`, `modules/*.md`, `agents/*.md`
- **Classification note**: Generic path names like `scripts/`, `docs/` are classified as skill infrastructure improvement only when referenced in the context of the skill infrastructure (behavior of `/verify`, `modules/` files). Improvement proposals for `scripts/` or `docs/` in external repositories are treated as code improvements
