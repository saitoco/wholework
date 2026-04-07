# External Review Step

## Step 7 Prerequisites: External Review Tool Settings

Read `modules/detect-config-markers.md` and follow the "Processing Steps" section to detect setting values from `.wholework.yml`.

Retain the detection results (`HAS_COPILOT_REVIEW`, `HAS_CLAUDE_CODE_REVIEW`) and use them for the following determination:

- If both tools are `false`: skip all of Step 7 (7.1–7.4) and proceed to Step 8

---

## Step 7: Wait for External Review and Apply Fixes

Wait for external reviews immediately after PR creation and apply any issues found. Process enabled external review tools in sequence.

### 7.1. Wait for Copilot Review

Skip this step if `HAS_COPILOT_REVIEW=false`.

```bash
~/.claude/scripts/wait-external-review.sh "$NUMBER" copilot
```

The script:
- Waits until the Copilot review is complete (max timeout: 5 minutes)
- Outputs issue content when review is complete
- Returns exit code 1 on timeout (waiting logs and timeout messages are printed to stderr)

**On timeout**: do not treat as an error; proceed to the next step.

### 7.2. Apply Copilot Issues

Skip this step if `HAS_COPILOT_REVIEW=false` or if the Copilot review timed out.

**With `--review-only` mode**: skip 7.2 and proceed to 7.3.

After review completion, if issues exist:

1. **Assess each issue automatically**:
   - **Issues requiring a fix**: make code changes → commit → push
   - **Issues not requiring a fix** (matters of preference, false positives, etc.): skip

2. **Fix work**: manage tasks with TaskCreate/TaskUpdate
   - Edit files with Edit tool
   - Stage with `git add`
   - Commit with `git commit -m "Address Copilot review: {fix summary}"`
   - Push with `git push`

3. **Record results** (used in Step 14 summary posting):

```markdown
## Copilot Review Response

### Fixed Issues
- filename:line — issue summary → fix content

### Skipped Issues
- filename:line — issue summary (skip reason)
```

**If no issues**: skip this section and proceed to the next step.

### 7.3. Wait for Claude Code Review

Skip this step if `HAS_CLAUDE_CODE_REVIEW=false`.

```bash
~/.claude/scripts/wait-external-review.sh "$NUMBER" claude-code-review
```

The script:
- Waits until Claude Code Review is complete (max timeout: 5 minutes)
- Outputs issue content when review is complete
- Returns exit code 1 on timeout

**On timeout**: do not treat as an error; proceed to the next step.

### 7.4. Apply Claude Code Review Issues

Skip this step if `HAS_CLAUDE_CODE_REVIEW=false` or if Claude Code Review timed out.

**With `--review-only` mode**: skip 7.4 and proceed to Step 8.

After review completion, if issues exist, apply them using the same procedure as 6.2:

1. **Assess each issue** (requires fix / does not require fix)
2. **Fix work**: Edit → git add → git commit → git push
   - Commit message: `"Address Claude Code Review: {fix summary}"`
3. **Record results**:

```markdown
## Claude Code Review Response

### Fixed Issues
- filename:line — issue summary → fix content

### Skipped Issues
- filename:line — issue summary (skip reason)
```

**If no issues**: skip this section and proceed to Step 8.

---

## Step 14: External Review Response Results Section

Use the following template when generating the Step 14.1 summary body. Generate a section per enabled external tool.

```markdown
### Copilot Review Response

| Filename | Line | Issue | Response | Fix/Skip reason |
|---------|------|-------|----------|----------------|
| example.py | 42 | Variable name unclear | Resolved | Renamed `x` → `result` |
| test.sh | 15 | Shell injection | Skipped | Internal script that does not accept user input |

### Claude Code Review Response

| Filename | Line | Issue | Response | Fix/Skip reason |
|---------|------|-------|----------|----------------|
| config.py | 28 | Missing type hint | Resolved | Added return type hint |
```

**If no external tool response (when Step 7 was skipped or settings are disabled)**: omit the corresponding external tool section.
