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

## Transcription Divergence Check

Trigger: any changed Domain file or SKILL.md references a spike report (e.g., `docs/reports/*-spike.md`).

If no spike reference is found in changed files, skip this section.

Steps:

1. **Identify spike references**: scan changed Domain files and SKILL.md for references to spike reports (file paths matching `docs/reports/*-spike.md` or `reports/*-spike.md`).
2. **Read spike chapter**: for each spike reference found, read the referenced spike report and extract aspirational expressions. Examples of aspirational expressions to look for:
   - "N-vote" (e.g., "3-vote adversarial verify", "N-vote")
   - "adversarial verify" with multiple votes or rounds
   - Loop counts (e.g., "ループ until dry", "loop until dry", "最大 N 件", "up to N items")
   - Parallelism counts (e.g., "N agents in parallel", "parallel fan-out of N")
   - "複数回", "multiple rounds", "retry N times"
3. **Grep implementation files**: for each aspirational expression found in step 2, search the changed implementation files (Domain files, SKILL.md, scripts) to verify whether the expressed behavior matches the actual implementation.
4. **Compare expressed vs. actual behavior**: if a Domain file or SKILL.md describes "N-vote adversarial verify" but the actual implementation spawns only 1 refutation agent per finding, that is a transcription divergence.

Output: when transcription divergence is detected, report a SHOULD-level finding:

```
**[Transcription Divergence] {file}:{approx-line}**
- path: {file}
- line: {approx-line}
- body: The expression "{aspirational text}" in this file was transcribed from the spike report but the actual implementation is {actual behavior}. Update the documentation to reflect the real implementation.
- severity: SHOULD
```

Note: transcription divergence is a documentation quality issue, not a correctness bug. Use SHOULD severity.

## Retrospective Guard

Before committing the review retrospective to the Spec:

1. Run forbidden expressions check to detect any deprecated terms introduced by the retrospective content:
   ```bash
   bash scripts/check-forbidden-expressions.sh
   ```
2. If violations are detected: fix the retrospective text before committing
   - Use descriptive language instead of quoting deprecated terms directly (e.g., write `旧称: <term>` or describe without quoting the term)
3. If no violations: proceed with commit
