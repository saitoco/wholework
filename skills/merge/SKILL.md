---
name: merge
description: Squash-merge a PR and delete the remote branch (`/merge 88`). Use when merging review-approved, CI-passing PRs. Automatically attempts conflict resolution when conflicts occur.
context: fork
allowed-tools: Bash(gh pr merge:*, gh pr view:*, gh pr ready:*, gh issue edit:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-merge.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-merge-status.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*, git fetch:*, git checkout:*, git rebase:*, git add:*, git push:*, git branch:*, git diff:*, git pull:*, git reset:*, git merge:*, git worktree:*), Read, Edit, Grep, EnterWorktree, ExitWorktree
---

# Squash Merge

If ARGUMENTS contains `--help`, Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and follow the "Processing Steps" section to output help, then stop.

## Autonomous Mode (--auto)

If ARGUMENTS contains the `--auto` flag, delegate as follows:

**Note**: `--auto` mode accepts **PR numbers only**.

1. Extract the PR number from ARGUMENTS (numeric part)
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/run-merge.sh $NUMBER` via Bash
3. Exit after the script completes (do not execute subsequent steps)

If `--auto` is not present, proceed with the normal steps below.

> **Note**: Running `/merge 88` from an interactive session spawns a fork sub-agent via `context: fork`. Output is not streamed, but a summary is returned upon completion.

## Error Handling in Non-Interactive Mode

In `--auto` mode (invoked via `run-merge.sh` with `claude -p`), AskUserQuestion is not available (the process would hang).

**Policy**: At any step that would call AskUserQuestion, output a clear error message and exit with a non-zero exit code instead.

- Output the error details clearly
- Include the choices/intent that would have been presented via AskUserQuestion as reference for manual handling
- Guide the user to resume interactively (e.g., run `/merge {PR number}` interactively)
- Explicitly state "Aborting" and do not execute any further steps
- **Exit the process with a non-zero exit code (e.g., `exit 1`) via Bash** so that `run-merge.sh` / Agent tool via `/auto` can detect the failure

## Steps

**Execute immediately without confirmation. Do not use compound commands (`&&`, `|`).**

### Step 1: Check PR State

1. Fetch PR metadata:
   ```bash
   gh pr view "$NUMBER" --json headRefName,baseRefName,isDraft
   ```
   Record `baseRefName` as `BASE_BRANCH`. If `BASE_BRANCH` is not `main` (e.g., `release/v2.0`), the Issue will not be auto-closed on merge — inform the user after Step 3 completes.

2. Determine mergeability:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-merge-status.sh "$NUMBER"
   ```
   Based on `mergeable` / `reason` in the output JSON, proceed as follows.

Note: Always wrap `$NUMBER` in double quotes.

- **isDraft is true**: Run `gh pr ready "$NUMBER"` to un-draft, then continue
- **mergeable=true**: Proceed directly to Step 4 (Execute Squash Merge)
- **mergeable=false, reason=conflicts**: Proceed to Step 3 (Resolve Conflicts)
- **Other (e.g., reason=review_pending)**: Report the error and reason, then use AskUserQuestion to ask the user how to proceed (non-interactive mode: output PR state details and reason, guide to run `/merge {PR number}` interactively, then abort)
  - User selects "Abort": Stop processing (do not proceed to subsequent steps)
  - User selects "Treat as conflict": Proceed to Step 2 (Resolve Conflicts)

Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` and display the start banner with ENTITY_TYPE="pr", ENTITY_NUMBER=$NUMBER, SKILL_NAME="merge".

### Step 2: Worktree Entry

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Entry section" to create a worktree.

**Worktree naming convention:** `merge/pr-$NUMBER`

Record the `ENTERED_WORKTREE` variable for use in subsequent steps.

### Step 3: Resolve Conflicts (CONFLICTING only)

#### Step 1: Checkout Branch

```bash
git fetch origin
git checkout "${headRefName}"
```

Note: Always wrap `headRefName` in double quotes to prevent shell injection.

If checkout fails (branch not found, etc.):
- Report the error via AskUserQuestion and abort (non-interactive mode: output the error details, guide to run `/merge {PR number}` interactively, then abort)

#### Step 2: Run Rebase

```bash
git rebase origin/"${BASE_BRANCH}"
```

After running rebase:
- **Conflicts detected**: Proceed to Step 3
- **No conflicts (completed successfully)**: Proceed to Step 6 (Run Tests)
- **Other errors** (network error, permission error, etc.): Run `git rebase --abort`, report to user via AskUserQuestion and abort (non-interactive mode: run `git rebase --abort`, output the error details, guide to run `/merge {PR number}` interactively, then abort)

#### Step 3: Assess Conflicting Files

```bash
git diff --name-only --diff-filter=U
```

- **Single file**: Attempt automatic resolution (proceed to Step 4)
- **Multiple files**: Confirm with user via AskUserQuestion (non-interactive mode: output list of conflicting files, run `git rebase --abort`, guide to run `/merge {PR number}` interactively, then abort)
  - User approves: Resolve each file in sequence
  - User declines: Abort rebase with `git rebase --abort` and exit

#### Step 4: Resolve Conflicts

Read the conflicting file with Read, analyze both sides of the conflict:

1. Locate sections containing `<<<<<<<`, `=======`, `>>>>>>>` markers
2. Understand the changes on both sides (HEAD and branch)
3. Determine the best resolution that respects the intent of both changes:

   **Resolution approaches (examples):**
   - Include both (merge)
   - Choose one side
   - Create new integrated code
4. If deemed complex (e.g., different parts of the same function, conflicting logic changes):
   - Confirm resolution approach via AskUserQuestion (non-interactive mode: output conflict details, run `git rebase --abort`, guide to run `/merge {PR number}` interactively, then abort)
   - User declines: Abort rebase with `git rebase --abort` and exit
5. If no appropriate resolution can be found:
   - Request manual resolution via AskUserQuestion (non-interactive mode: output conflict details, run `git rebase --abort`, guide to run `/merge {PR number}` interactively, then abort)
   - Abort with `git rebase --abort` and exit

Update the file with Edit to remove conflict markers.

#### Step 5: Continue Rebase

```bash
git add <resolved-file>
git rebase --continue
```

After `git rebase --continue`:
- **Conflict message appears**: Additional conflicts exist — return to Step 3
- **Rebase completed successfully**: All conflicts resolved — proceed to Step 6

#### Step 6: Run Tests (after conflict resolution only)

**Note**: This step runs only after conflict resolution. For PRs with no conflicts, tests have already passed in CI — skip this step.

To identify the test command:

1. Check in this order:
   - If `package.json` exists: adopt `npm test` if `scripts.test` is defined
   - If `Makefile` exists: adopt `make test` if a `test` target is defined
   - If test scripts exist under `./scripts/`: adopt them (e.g., `./scripts/test-skills.sh`)
2. If a test command is found, run it
3. Check test results:
   - **Success**: Proceed to Step 7
   - **Failure**: Report to user via AskUserQuestion and confirm whether to continue (non-interactive mode: output test failure details, guide that "the local branch is preserved in the post-rebase state; run `/merge {PR number}` interactively to handle", then abort)
     - User declines: Stop automated processing. Inform user: "The local branch is preserved in the post-rebase state. Handle manually as needed."
4. If no test command is found, skip and continue

#### Step 7: Push

```bash
git push --force-with-lease origin "${headRefName}"
```

Note: Always wrap `headRefName` in double quotes to prevent shell injection.

**If push fails** (e.g., `--force-with-lease` detects remote branch updates):

1. Do not automatically switch to `--force`
2. Run `git fetch origin "${headRefName}"` to fetch the latest state
3. Report via AskUserQuestion: "Remote branch has new commits; push was rejected" (non-interactive mode: output push rejection details, guide that "the local branch is preserved in the post-rebase state; run `/merge {PR number}` interactively to handle", then abort)
4. Ask the user for next steps:
   - Rebase again → return to Step 2 (Run Rebase)
   - Abort → guide: "The local branch is preserved in the post-rebase state. You can reset to the remote state with `git reset --hard "origin/${headRefName}"` or handle manually." then exit
5. Do not take any further automated action until the user provides explicit instructions

### Step 4: Execute Squash Merge

```bash
gh pr merge "$NUMBER" --squash --delete-branch
```

If the PR body contains `closes #N` and `BASE_BRANCH` is `main`, the Issue will be auto-closed on merge (no manual close needed).

If `BASE_BRANCH` is not `main`, inform the user after merge:
"Since the base branch is `{BASE_BRANCH}`, `closes #N` will not auto-close the Issue. The Issue will be closed when `{BASE_BRANCH}` is merged to main. You may manually run `gh issue close {ISSUE_NUMBER}` if needed."

### Step 5: Label Transition (after successful merge)

Extract the related Issue number from the PR body (`closes #N`, `Related to #N`, `Issue #N:` in PR title, etc.):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$ISSUE_NUMBER" verify
```

### Step 6: Worktree Exit (push-and-remove)

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Exit: push-and-remove section" to exit the worktree.

`gh pr merge --squash --delete-branch` in Step 4 has already merged and deleted the remote branch, so call ExitWorktree("remove", discard_changes: true) to delete the worktree and return to the original directory.

## Completion Report

Extract the related Issue number from the PR body.

**Issue number extraction steps:**
1. Run `gh pr view "$NUMBER" --json title,body` to get PR info
2. Search the PR body for `closes #N`, `Related to #N`, or `Issue #N`
3. If not found, search the PR title for `Issue #N`

Output "Merge complete." as a fixed prefix, then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=merge`
- `ISSUE_NUMBER=$ISSUE_NUMBER`
- `RESULT=success`

## Notes

- **No compound commands**: Run one command at a time to avoid confirmation dialogs
- **Shell injection prevention**: Always wrap `headRefName`, `$NUMBER`, etc. in double quotes
- **Use force-with-lease**: Avoid overwriting others' changes
- **Rebase loop**: If conflicts remain after `git rebase --continue`, always return to Step 3 (Assess Conflicting Files)
- **Abort rebase**: If the user declines conflict resolution, abort with `git rebase --abort`
- **Draft PRs**: Check `isDraft` in Step 1; if draft, un-draft with `gh pr ready`
- **Test before push**: Run tests before pushing, then push only after tests pass
