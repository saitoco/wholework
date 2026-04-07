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
