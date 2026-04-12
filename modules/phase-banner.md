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
   /SKILL_NAME #N
   TITLE
   URL
   ```
3. If `gh` command fails, output banner without title/URL (skip silently)

## Output
Phase identification banner displayed to terminal.

## Notes

Both SKILL.md (LLM-executed) skills and `run-*.sh` shell scripts use the same `/SKILL_NAME #N` format.

For `run-*.sh` shell scripts, `scripts/phase-banner.sh` provides `print_start_banner` / `print_end_banner` functions that accept `skill_name` as a third argument and output the same unified format:
```
/skill_name #N
TITLE
URL
```
