# opportunistic-verify

Shared module for running opportunistic verification of verification-pending Issues at skill completion.

## Purpose

At each skill execution completion, extract `verify-type: opportunistic` conditions from Issues with the `phase/verify` label that are relevant to the current skill, and automatically check them via AI retrospective. This creates a structure where normal workflow operations become the throughput rate for consuming the verification backlog.

## Input

Information provided by the calling skill:

- **Skill name**: Hardcoded by the calling skill in its SKILL.md (e.g., `/spec`, `/review`, `/verify`, `/issue`, `/code`)

## Processing Steps

Skills that Read this file should execute opportunistic verification following the steps below.

### 1. Fetch Verification-Pending Issues and Extract Conditions

First check for the existence of `${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh` using a `-x` test. If the script does not exist (or is not executable), output "Warning: ${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh not found. Skipping opportunistic verification." and skip all subsequent processing.

If the script exists:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh <skill-name>
```

- The script fetches closed Issues with the `phase/verify` label and filters by `verify-type: opportunistic` tag, skill name, and unchecked conditions
- Output is JSON: `[{"number": N, "condition": "condition text"}]` (empty: `[]`)
- **If output is `[]`**: Output "Opportunistic verification: 0 conditions found, skipping" and exit

### 2. Cross-Reference with Current Execution Results (AI Retrospective)

For each extracted condition, reflect on this skill's execution memory (output results, operations performed, observed facts) and judge by PASS/FAIL/SKIP criteria:

- **PASS**: Confirmed during this execution that the condition is met
- **FAIL**: Confirmed during this execution that the condition is not met
- **SKIP**: Insufficient information for judgment (not the specific pattern of input, etc.)

No additional log retention mechanism is needed. The AI retrospects on its memory of skill execution to make judgments.

### 3. Update Checkboxes

For Issues with PASS conditions, execute the following:

**Update Issue body:**

1. Get current Issue body with `gh issue view $N --json body -q .body`
2. Rewrite `- [ ]` to `- [x]` for PASS conditions
3. Create directory with `mkdir -p .tmp`, then write updated body to `.tmp/issue-body-$N.md` using the Write tool
4. Update Issue body with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh $N .tmp/issue-body-$N.md`
5. Delete temp file with `rm -f .tmp/issue-body-$N.md`

**Post comment:**

1. Write comment body to `.tmp/issue-comment-$N.md` using the Write tool (template below)
2. Post comment with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $N .tmp/issue-comment-$N.md`
3. Delete temp file with `rm -f .tmp/issue-comment-$N.md`

**Comment template:**
```markdown
## Opportunistic Verification (during /skill-name execution)

| Condition | Result |
|-----------|--------|
| condition text 1 | PASS |
| condition text 2 | SKIP |
```

For FAIL: only report via comment (do not reopen; FAIL reopening is determined during explicit `/verify`)

### 4. All Conditions PASS → Label Transition

After updating checkboxes, confirm whether all post-merge conditions for the Issue (all conditions regardless of `verify-type` tag) are now checked (`- [x]`).

Re-fetch the updated Issue body and check whether any unchecked (`- [ ]`) conditions remain in the post-merge section.

If all conditions are checked:

```bash
gh issue edit $N --remove-label "phase/verify" --add-label "phase/done"
```

## Output

- Terminal output: Opportunistic verification summary (number of target Issues, judgment result for each condition)
- GitHub Issue updates: Checkbox updates for PASS conditions + verification record comment + label transition (only when all conditions PASS)
