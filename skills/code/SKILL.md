---
name: code
description: Local implementation (`/code 123`). Size auto-detection routes XS/S→patch (direct commit to main), M/L→branch+PR. Override with `--patch`/`--pr`.
context: fork
allowed-tools: Bash(gh issue view:*, gh issue edit:*, gh issue list:*, git checkout:*, git pull:*, git add:*, git status:*, git diff:*, git commit:*, git push:*, git merge:*, git worktree:*, git branch:*, gh pr create:*, gh pr comment:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-type.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*, python3:*, bats:*), Glob, Grep, Read, Write, Edit, TaskCreate, TaskUpdate, TaskList, TaskGet, EnterWorktree, ExitWorktree
---

# Local Implementation

Receive an Issue number and implement based on the Spec.

If ARGUMENTS contains `--help`, Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and follow the "Processing Steps" section to output help, then stop.

## Autonomous Mode (--auto)

If ARGUMENTS contains the `--auto` flag, delegate as follows:

1. Extract the Issue number from ARGUMENTS (numeric part)
2. If `--patch` is present, run `${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh $NUMBER --patch [--base {branch}]` via Bash; otherwise run `${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh $NUMBER [--base {branch}]` (add `--base {branch}` if `--base` flag is present)
3. Exit after the script completes (do not execute subsequent steps)

If `--auto` is not present, proceed with mode detection below.

> **Note**: Running `/code 123` from an interactive session spawns a fork sub-agent via `context: fork`. Output is not streamed, but a summary is returned upon completion.

## Mode Detection

<!-- Flag role separation:
  --auto: Used when the user runs `/code 123 --auto`. Delegates to run-code.sh and exits.
  --non-interactive: Automatically added when run-code.sh calls the code SKILL internally.
                     Indicates autonomous execution mode where AskUserQuestion cannot be used.
  This two-layer design separates --auto as a user delegation flag and --non-interactive as an
  internal execution flag.
-->

If ARGUMENTS contains the `--non-interactive` flag, operate in **non-interactive mode** (set when invoked autonomously via `run-code.sh`). In this mode, AskUserQuestion cannot be used — see `## Error Handling in Non-Interactive Mode` below for the complete policy.

In interactive mode (no flag), use AskUserQuestion to follow the normal steps.

## Error Handling in Non-Interactive Mode

In `--non-interactive` mode (invoked via `run-code.sh` with `claude -p`), AskUserQuestion is not available (the process would hang).

**Policy**: At any step that would call AskUserQuestion, apply **auto-resolve + log** instead of aborting.

Read `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md` and follow the "Non-Interactive Mode Handling" section. In summary:
- **auto-resolve**: adopt the most reasonable default choice using model judgment, then record the decision in the Spec's `## Autonomous Auto-Resolve Log` subsection
- **skip**: for High-Stakes Decisions (see module for exhaustive list), output a warning and continue without executing the risky action
- **hard-error abort** (exceptions — these still exit with non-zero):
  - Size label is not set (cannot determine patch vs. pr route; guide to set Size label, then abort)
  - Size is `XL` (requires sub-issue splitting before coding; guide to split the Issue, then abort)

## Steps

### Step 0: Route Detection

Determine the route based on Size (Project field preferred → label fallback) and option flags.

Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` and display the start banner with ENTITY_TYPE="issue", ENTITY_NUMBER=$NUMBER, SKILL_NAME="code".

First, fetch Size (run before route detection):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh "$NUMBER" 2>/dev/null
```

`get-issue-size.sh` fetches Size in two stages: Project field preferred → `size/*` label fallback. Use the output value (e.g., `S`, `M`; empty means Size not set) in subsequent steps (e.g., XS/S detection in Step 2).

**Fetch base branch (run before route detection)**:

If ARGUMENTS contains `--base {branch}`, use that value as `BASE_BRANCH`. If `--base` is not specified, default to `BASE_BRANCH=main` (backward compatibility).

**Flag precedence (explicit flag > Size auto-detection)**:
- ARGUMENTS contains `--patch` → **patch route** (direct commit to BASE_BRANCH, no PR). Even if Size is `XL`, `--patch` takes precedence — skip the XL check and run as patch route
- ARGUMENTS contains `--pr` → **pr route** (branch + PR flow)

**Size auto-detection** (when no flags are present):

Follow the Size→workflow mapping table in `${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md`:
- `XS` or `S` → **patch route**
- `M` or `L` → **pr route** (branch + PR flow)
- `XL` → exit with error ("XL requires sub-issue splitting. Split the Issue and run `/code` on each sub-issue.")
- Size not set (empty output) and interactive mode → use AskUserQuestion to let the user choose the route (patch / pr)
- Size not set (empty output) and `--non-interactive` mode → output error message, guide "Set Size via the Project field or `size/*` label, then run `/code $NUMBER` interactively", and abort

Record the result (patch / pr) for use in subsequent steps.

### Step 1: Fetch Issue Info

```bash
gh issue view $NUMBER --json title,body
```

Generate a short description from the title (e.g., "add-implement-skill").

### Step 2: Worktree Entry

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Entry section" to create a worktree.

**Worktree naming convention (by route):**
- **patch route**: `patch/issue-$NUMBER`
- **pr route**: `issue-$NUMBER-<short-description>` (same as branch name)

Record the `ENTERED_WORKTREE` variable for use in subsequent steps.

**Edit/Write path conventions inside worktree (CWD-relative):**

After entering the worktree, CWD switches to the worktree directory. When editing or creating files with Edit/Write tools, **verify CWD first** (check with `pwd`), and **use CWD-relative paths rather than absolute paths** (e.g., `~/.claude/` or `/Users/.../src/...`). Using absolute paths would edit the main repository, causing missed commits and conflicts.

### Step 3: `phase/ready` Label Check

**Skip this check if Size is XS** (XS does not require Spec — skip this entire step and proceed to Step 4).

For sizes other than XS: run `gh issue view $NUMBER --json labels -q '.labels[].name'` to get labels, then check if `phase/ready` is present.

- `phase/ready` label present: proceed to the next step
- `phase/ready` label absent:
  - Confirm via AskUserQuestion (non-interactive mode: auto-resolve — proceed without Spec; read requirements from Issue body directly and continue; record the decision in the Spec's `## Autonomous Auto-Resolve Log` subsection)
    - "Continue": proceed with execution
    - "Abort": stop processing and guide "run `/spec $NUMBER`", then exit

### Step 4: Create Branch & Label Transition

**For pr route**:

The branch was already created by Worktree Entry (EnterWorktree) in Step 2 — no need to run `git checkout -b`.

**For patch route (direct commit to BASE_BRANCH)**:

The worktree was already created by Worktree Entry (EnterWorktree) in Step 2 — no explicit branch work needed.

Both routes:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER code
```

### Step 5: Load Spec

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `SPEC_PATH` and `STEERING_DOCS_PATH` for use in subsequent steps.

Search for `$SPEC_PATH/issue-$NUMBER-*.md` and read the Spec to review the implementation plan.

If no Spec exists, read the requirements from the Issue body and implement accordingly.

**Review notes section (only if present in Spec):**

If the Spec has a "Notes" section, cross-reference each item against the implementation steps and recognize them as constraints/specifications to consider during implementation. Skip this step if there is no "Notes" section.

### Step 6: Verify Uncertainties (only if present in Spec)

If the Spec has an "Uncertainties" section, before implementing:

1. Verify each uncertainty using the confirmation method described
2. If official documentation URLs are listed, review the spec information recorded there; use AskUserQuestion for any unclear points (non-interactive mode: auto-resolve — proceed with best-effort interpretation; record the unclear details and chosen interpretation in the Spec's `## Autonomous Auto-Resolve Log` subsection)
3. If operational verification is needed, confirm with a simple verification script or bats test
4. If implementation approach is problematic based on verification results, report to user via AskUserQuestion (non-interactive mode: auto-resolve — proceed with the most conservative approach; record the problem details and chosen approach in the Spec's `## Autonomous Auto-Resolve Log` subsection)

**If uncertainties cannot be verified, or the design premise turns out to be incorrect:**
- In interactive mode: abort implementation and propose Spec revision
- In non-interactive mode: auto-resolve by proceeding with best-effort implementation; note the unresolved uncertainty in the Spec's `## Autonomous Auto-Resolve Log` subsection

### Step 7: Reference Steering Documents (if present)

Use Glob to check whether the following steering documents exist, then Read only those that exist:

- `$STEERING_DOCS_PATH/tech.md` — Coding conventions, Architecture Decisions (check for convention compliance), Forbidden Expressions (avoid prohibited expressions)
- `$STEERING_DOCS_PATH/structure.md` — Directory structure, Key Files (check file placement)

**If not present, skip this step and proceed to the next.**

Use information from steering documents for coding convention compliance, file placement, and naming consistency during implementation. If `$STEERING_DOCS_PATH/tech.md` is Read, reference the `## Forbidden Expressions` section and avoid using prohibited expressions in code comments, variable names, commit messages, and new documents.

**Project-local Domain files (if present):**

Read `${CLAUDE_PLUGIN_ROOT}/modules/domain-loader.md` and follow the "Processing Steps" section with `SKILL_NAME=code`. Domain file content provides additional implementation guidelines and constraints.

### Step 8: Implement

Implement the code following the "Implementation Steps" in the Spec.

- Use TaskCreate/TaskUpdate to manage tasks while working
- Commit after each step completes

### Step 9: Run Tests

Read `${CLAUDE_PLUGIN_ROOT}/modules/test-runner.md` and follow the "Processing Steps" section to run tests.

**Additional validation (run after tests):**

After tests complete, run skill syntax validation locally:

```bash
python3 scripts/validate-skill-syntax.py skills/
```

This is equivalent to the CI `validate-syntax` job and detects invalid `allowed-tools` patterns or YAML frontmatter syntax errors before reaching CI. If validation fails, fix the issues before continuing (same as test failures).

**Documentation consistency check (run after validation):**

Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-checker.md` and follow the "Impact assessment criteria" section to determine whether documentation sync updates are needed for files changed during implementation.

If sync is required, update the target documents (`README.md`, `docs/workflow.md`, etc.) before committing.

### Step 10: Verify Command Consistency

**Patch route verify command check:**

If patch route (Size is `XS`/`S` or `--patch` flag), before running verify-executor, scan the Issue body's `## Acceptance Criteria > Pre-merge` for `github_check "gh pr checks"` entries.
- If found: output "Warning: patch route — `github_check "gh pr checks"` is incompatible. Auto-fixing to `github_check "gh run list"` form." and replace each with `github_check "gh run list"` form (add `--workflow=<filename>` if there are multiple workflow files under `.github/workflows/`). Update Issue body via `gh-issue-edit.sh`. Also update Spec verify commands (`$SPEC_PATH/issue-$NUMBER-*.md`) with the same fix.

**Resolving `{{base_url}}` to localhost**: If verify commands contain `{{base_url}}`, resolve it before passing to verify-executor:

1. If environment variable `LOCAL_BASE_URL` is set, use that value
2. If `LOCAL_BASE_URL` is not set, default to `http://localhost:3000`
3. Replace `{{base_url}}` in verify commands with the resolved URL before passing to verify-executor

Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md` and follow the "Processing Steps" section to run verify command consistency verification in **full mode**. Target: pre-merge verify commands for Issue #$NUMBER. Skip if no hints exist.

Handle results as follows:
1. If all PASS, complete this step and update checkboxes:
   - Pre-create directory with `mkdir -p .tmp`
   - Fetch current Issue body with `gh issue view $NUMBER --json body`
   - For each pre-merge condition line with verify command, replace leading `- [ ]` with `- [x]` (preserve the rest of the line, verify command comments `<!-- verify: ... -->`, etc.)
   - Write updated body to `.tmp/issue-body-$NUMBER.md` with Write tool
   - Update Issue body with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh $NUMBER .tmp/issue-body-$NUMBER.md`
   - After update, delete temp file with `rm -f .tmp/issue-body-$NUMBER.md`
2. If any hints FAIL:
   - **Determine the FAIL cause** for each failing `section_contains`/`file_contains` hint:
     - **"Spec-derived literal string absent"** — The Spec mandates a keyword that the implementation file should literally contain, but it is missing from the file:
       - **First choice: Add the literal string to the implementation file.** The verify command is correct — update the implementation to include the required text.
       - Example: `section_contains "skills/verify/SKILL.md" "Step 9" "Issue OPEN"` FAILs because "Issue OPEN" is absent from the implementation → add that text to the appropriate section in `skills/verify/SKILL.md`.
     - **"Miscalibrated hint"** — The keyword was incorrectly specified (wrong file path, wrong string that was never intended to be in the file, etc.):
       - **Rewrite the hint with the correct one** rather than removing it.
       - Example: `file_contains "settings.json" "gh project"` FAILs → check actual file content and rewrite to `file_contains "settings.json" "Skill(triage)"`
   - For any hints that were rewritten (miscalibrated hint case):
     - Pre-create directory with `mkdir -p .tmp`
     - Write updated Issue body to `.tmp/issue-body-$NUMBER.md` with Write tool
     - Update with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh $NUMBER .tmp/issue-body-$NUMBER.md`
     - After update, delete temp file with `rm -f .tmp/issue-body-$NUMBER.md`
3. If any hints are UNCERTAIN (syntax errors, etc.):
   - Display a warning and continue
   - Do not fix UNCERTAIN hints — they will be re-verified in the `/verify` phase after merge

**Spec sync (when verify commands are modified):** If Issue body verify commands (`<!-- verify: ... -->`) are modified, also apply the same fix to the "Verification > Pre-merge" section in the Spec (`$SPEC_PATH/issue-$NUMBER-*.md`). Updating only the Issue body without updating the Spec will cause discrepancies flagged in the review retrospective.

### Step 11: Commit, Push, or Create PR

**For patch route (commit to BASE_BRANCH)**:

**Type → prefix mapping (exhaustive):**

| Type | prefix |
|------|--------|
| Bug | `fix:` |
| Feature | `feat:` |
| Task | `chore:` |
| Not set | `patch:` |

**Determine commit prefix (fetch Type → map to prefix):**

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-type.sh $NUMBER` and get the returned Type name (`Bug`/`Feature`/`Task`)
2. If none are set (empty string): use `patch:` prefix

Include `closes #N` only when the base branch is `main` (GitHub auto-close via `closes #N` only works when merging to the default branch).

```bash
git add <changed files>
# If BASE_BRANCH is main: "{prefix} <summary> (closes #$NUMBER)"
# If BASE_BRANCH is not main: "{prefix} <summary>"
git commit -s -m "{prefix} <summary>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

Push is done in Step 13 Worktree Exit (merge-to-main pattern). Label transition happens after push completes (after Step 13).

**For pr route (branch + PR)**:

```bash
gh pr create --title "Issue #$NUMBER: {summary of changes}" --base "${BASE_BRANCH}" --body "..."
```

Include `closes #N` in PR body only when BASE_BRANCH is `main`. If BASE_BRANCH is not main, omit `closes #N` and instead note: "Since the base branch is `{BASE_BRANCH}`, please close the Issue manually at final merge."

**PR title format:**
- Use the format `Issue #N: {summary of changes}` (concise English summary)
- Example: `Issue #48: Fix Mermaid diagram parse error`

PR body should include:
- Summary: overview of changes
- Verification (pre-merge) — bullet list without checkboxes (`- ` only). Informational only; checkbox management is done on the Issue side
- Verification (post-merge) — same as above
- `closes #$NUMBER`

**PR body template example:**

```markdown
## Summary
{overview of changes}

## Verification (pre-merge)
- {item 1}
- {item 2}

## Verification (post-merge)
- {item 1}

closes #$NUMBER
```

**Auto-append acceptance conditions to Issue:**

When creating a PR, compare the Spec verification methods against the Issue acceptance conditions. If the Issue acceptance conditions are missing verification items, fetch the current Issue body with `gh issue view $NUMBER --json body`, build the updated body with the missing items appended, pre-create the directory with `mkdir -p .tmp`, write the updated body to `.tmp/issue-body-$NUMBER.md` with Write tool, update with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh $NUMBER .tmp/issue-body-$NUMBER.md`. After update, delete the temp file with `rm -f .tmp/issue-body-$NUMBER.md`.

**Change tracking comment (post-PR):**

After creating the PR, if any of the following changes occurred during Step 10 or Step 11, post a change tracking comment to the Issue:

- Step 10 case 2: verify command was rewritten (FAIL → corrected hint)
- Step 10 Spec sync: Spec verify commands were updated to match Issue body
- Step 11 auto-append: acceptance conditions were appended to the Issue body

If none of the above changes occurred, skip this step.

When changes occurred, write the comment body to `.tmp/change-tracking-$NUMBER.md` with the Write tool, then post:

```bash
mkdir -p .tmp
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $NUMBER .tmp/change-tracking-$NUMBER.md
rm -f .tmp/change-tracking-$NUMBER.md
```

Comment format:

```markdown
## Change Tracking (by /code)

### Changes Made
- {change summary 1 — what was changed and why}
- {change summary 2}
```

### Step 12: Code Retrospective

Append retrospective information to the Spec and commit.

**Content to append:**
- Deviations from the design (what deviated and why)
- Design gaps/ambiguities (problems found during implementation)
- Rework (where rework occurred and the cause)

**Template:**
```markdown
## Code Retrospective

### Deviations from Design
- (deviation and reason)

### Design Gaps/Ambiguities
- (problems found during implementation)

### Rework
- (where rework occurred and the cause)
```

**Sync Spec implementation steps (when deviations exist):**

If there are items under "Deviations from Design" (reordering of implementation steps, omission/consolidation of steps, adoption of a different approach due to design changes, etc.), in addition to recording in the retrospective, also update the Spec "Implementation Steps" section itself to match the actual implementation. This allows the subsequent `/verify` phase to verify based on the latest implementation.

- No deviations: no need to update Spec implementation steps
- Deviations exist: revise Spec implementation steps to match actual implementation and include in the same commit

**Steps:**
1. If no retrospective information, write "N/A"
2. Append `## Code Retrospective` section after `## Spec Retrospective` in the Spec (`$SPEC_PATH/issue-$NUMBER-*.md`) using the Edit tool
3. If "Deviations from Design" exist, also update the "Implementation Steps" section in the Spec to match the actual implementation
4. Commit (push is done in Step 13 Worktree Exit):
   ```bash
   git add $SPEC_PATH/issue-$NUMBER-*.md
   git commit -s -m "Add code retrospective for issue #$NUMBER

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
   ```
   - **For pr route**: also push from within the worktree:
     ```bash
     git push origin HEAD
     ```

### Step 13: Worktree Exit

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the Exit section appropriate for the route.

**patch route (merge-to-main pattern):**
Follow "Exit: merge-to-main section". After push completes, transition the label (patch route skips `/merge`, so label transition happens here).

**patch route (XS/S common)**: After push completes, transition to `phase/verify`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER verify
```

patch route completes here. Follow the completion report section to inform the user.

**pr route (push-and-remove pattern):**
Follow "Exit: push-and-remove section" (push was done in Step 12, so only delete the worktree).

### Step 14: Opportunistic Verification

Only if `.wholework.yml` in the project has `opportunistic-verify: true`, Read `${CLAUDE_PLUGIN_ROOT}/modules/opportunistic-verify.md` and follow the "Processing Steps" section to run opportunistic verification. The skill name is `/code`. Skip this step if not configured.

## Completion Report

Output the route-specific prefix, then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section.

- **patch route prefix**: "Direct commit and push to main complete."
- **pr route prefix**: "PR creation complete."

Parameters to pass to next-action-guide:
- `SKILL_NAME=code`
- `ISSUE_NUMBER=$NUMBER`
- `PR_NUMBER={PR number if pr route}`
- `ROUTE={patch|pr}`
- `RESULT=success`

## Notes

- Direct work on the main branch is only allowed for the patch route (size/XS·S or `--patch` flag). For the pr route, always create a branch
- Prioritize the Spec for reference
- If tests fail, fix them before continuing
- Always create and write temp files with the Write tool. Creating or writing temp files via Bash `cat`/`echo`/redirect (`>`) is prohibited (causes confirmation prompts)
- bats test `@test` names must be in English (ASCII). Multibyte characters (Japanese, etc.) cause test name parse failures and result in 0 tests executed. See: #226
- **Brace expansion (`{1,2,3}`) is prohibited**. Use globs for deleting multiple files: `rm -f .tmp/issue-*.md` (brace expansion triggers Claude Code security warnings)
- Files under `.claude/` are treated as **sensitive files** by Claude Code — Edit and Write tools are rejected for these paths. When implementation requires editing `.claude/` files (e.g., `settings.json.template`), use Bash (e.g., `python3 -c "..."` or `sed -i`) instead
