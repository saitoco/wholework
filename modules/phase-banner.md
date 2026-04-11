# phase-banner

Standardized phase identification banner for skill start.

## Purpose
Display Issue/PR title and URL at skill start for identification.

## Input
- ENTITY_TYPE: "issue" or "pr"
- ENTITY_NUMBER: Issue or PR number (extracted by calling skill)
- SKILL_NAME: name of the skill (e.g., "issue", "spec", "review")

## Processing Steps
1. Fetch title and URL:
   - Issue: `gh issue view $N --json title,url`
   - PR: `gh pr view $N --json title,url`
2. Output banner format (at skill start, after number extraction):
   ```
   --- /SKILL_NAME #N ---
   TITLE
   URL
   ---
   ```
3. If `gh` command fails, output banner without title/URL (skip silently)

## Output
Phase identification banner displayed to terminal.

## Notes

The banner format above applies to **SKILL.md (LLM-executed)** skills only.

For `run-*.sh` shell scripts, a separate helper `scripts/phase-banner.sh` is used instead.
Its `print_start_banner` function outputs a different format:
```
Issue: #N TITLE
URL: URL
```

This is an intentional 2-layer design: SKILL.md module defines the LLM-executed banner format,
while `scripts/phase-banner.sh` defines the shell-executed banner format for `run-*.sh`.
