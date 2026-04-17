---
name: merge
description: Squash-merge a PR and delete the remote branch (`/merge 88`). Use when merging review-approved, CI-passing PRs. Automatically attempts conflict resolution when conflicts occur.
context: fork
model: sonnet
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

## Non-Interactive Mode Behavior

If ARGUMENTS contains `--non-interactive` (set automatically by `run-merge.sh`), operate in **non-interactive mode**. In this mode, `AskUserQuestion` cannot be used.

Read `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md` and follow the "Non-Interactive Mode Handling" section for the three-tier policy (auto-resolve / skip / hard-error). Apply **auto-resolve + log** at each step instead of aborting.

Key per-step behavior in non-interactive mode:
- **Step 1: mergeable=false, reason=review_pending** (or other non-conflict reason): auto-resolve by proceeding with the merge attempt anyway; record the decision in the Auto-Resolve Log as an issue comment. If the merge ultimately fails, exit with non-zero so the caller can detect it
- **Step 3 (Resolve Conflicts) — multiple conflicting files**: auto-resolve by attempting sequential resolution of each file; record the decisions in the Auto-Resolve Log. If resolution fails for any file, run `git rebase --abort` and exit with non-zero
- **Step 3 (Resolve Conflicts) — complex conflict**: auto-resolve using the conservative merging strategy (include both sides where possible); record the decision in the Auto-Resolve Log
- **Step 3 — test failures after conflict resolution**: auto-resolve by outputting test failure details and exiting with non-zero (test failures are not safe to ignore)
- **Step 3 — push rejected**: auto-resolve by exiting with non-zero (remote branch updates require human intervention)

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
- **Other (e.g., reason=review_pending)**: Report the error and reason, then use AskUserQuestion to ask the user how to proceed (non-interactive mode: auto-resolve — see "Non-Interactive Mode Behavior" section)
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
- Report the error via AskUserQuestion and abort (non-interactive mode: output the error details and exit with non-zero — checkout failure cannot be auto-resolved)

#### Step 2: Run Rebase

```bash
git rebase origin/"${BASE_BRANCH}"
```

After running rebase:
- **Conflicts detected**: Proceed to Step 3
- **No conflicts (completed successfully)**: Proceed to Step 6 (Run Tests)
- **Other errors** (network error, permission error, etc.): Run `git rebase --abort`, report to user via AskUserQuestion and abort (non-interactive mode: run `git rebase --abort`, output the error details, and exit with non-zero — rebase errors cannot be auto-resolved)

#### Step 3: Assess Conflicting Files

```bash
git diff --name-only --diff-filter=U
```

- **Single file**: Attempt automatic resolution (proceed to Step 4)
- **Multiple files**: Confirm with user via AskUserQuestion (non-interactive mode: auto-resolve — see "Non-Interactive Mode Behavior" section; attempt sequential resolution)
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
   - Confirm resolution approach via AskUserQuestion (non-interactive mode: auto-resolve — see "Non-Interactive Mode Behavior" section; use conservative merge strategy and record decision in Auto-Resolve Log)
   - User declines: Abort rebase with `git rebase --abort` and exit
5. If no appropriate resolution can be found:
   - Request manual resolution via AskUserQuestion (non-interactive mode: run `git rebase --abort` and exit with non-zero — unresolvable conflicts cannot be auto-resolved)
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
   - **Failure**: Report to user via AskUserQuestion and confirm whether to continue (non-interactive mode: output test failure details and exit with non-zero — test failures after conflict resolution cannot be safely ignored)
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
3. Report via AskUserQuestion: "Remote branch has new commits; push was rejected" (non-interactive mode: output push rejection details and exit with non-zero — remote branch updates require human intervention)
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
