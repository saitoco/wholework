# worktree-lifecycle module

## Purpose

Provides a shared worktree Entry/Exit lifecycle common to all skills (/spec, /code, /verify, /review, /merge). Transparently manages EnterWorktree/ExitWorktree to structurally eliminate commit contamination risk and synchronization overhead.

## Input

- `WORKTREE_NAME`: Worktree name (e.g., `spec/issue-123`). Specified by each skill following naming conventions
- `EXIT_MODE`: `merge-to-main` | `push-and-remove`. Select based on the skill's commit destination

## Processing Steps

### Entry Section (execute at skill start)

The calling skill enters the worktree with the following steps:

1. **Determine if already in a worktree**: Run `test -f .git`
   - **If file (inside worktree)**: Already running inside a worktree. Record `ENTERED_WORKTREE=false` and skip EnterWorktree, proceeding to the next step
   - **If directory (normal repository)**: Record `ENTERED_WORKTREE=true` and proceed to the next step

2. Only when `ENTERED_WORKTREE=true`: Call `EnterWorktree(name: WORKTREE_NAME)`

3. **Run worktree initialization hook**: Run only if `.claude/hooks/worktree-init.sh` exists:
   ```bash
   test -x .claude/hooks/worktree-init.sh && bash .claude/hooks/worktree-init.sh
   ```
   Do nothing if hook does not exist (skip).

### Exit: merge-to-main Section (used by /spec, /code patch, /verify)

The calling skill exits the worktree with the following steps after completing commits:

**When `ENTERED_WORKTREE=false`**: Skip this section and run normal `git push origin main` (or `git push origin $BASE_BRANCH`).

**When `ENTERED_WORKTREE=true`**:

1. Call `ExitWorktree(action: "keep")` to return to the original directory (do not delete the worktree branch)

2. Retain `WORKTREE_BRANCH` with the branch name worked on in the worktree (confirmable after calling EnterWorktree)

3. Merge the worktree branch into main (or `BASE_BRANCH`):
   ```bash
   git merge $WORKTREE_BRANCH --ff-only
   ```
   - If FF merge fails: Run `git pull --rebase origin main` (or `git pull --rebase origin $BASE_BRANCH`) then retry

4. **Conflict marker residue check**: After merging, confirm no conflict markers remain:
   ```bash
   grep -rn '<<<<<<' .
   ```
   - If markers detected: Output the following error message, skip push, and abort (do not cleanup either — retain branch so user can resolve conflicts manually):
     ```
     Error: Conflict markers remain. Please resolve conflicts manually then push.
     ```
   - If no markers detected: Proceed to next step (push)

5. Push to remote:
   ```bash
   git push origin main
   ```
   (If BASE_BRANCH is not main: `git push origin $BASE_BRANCH`)

6. **Cleanup** (output warning and continue if any command fails):
   ```bash
   git worktree remove ".claude/worktrees/$WORKTREE_NAME" 2>/dev/null || echo "Warning: Failed to remove worktree directory. Please remove manually: .claude/worktrees/$WORKTREE_NAME"
   git branch -d "$WORKTREE_BRANCH" 2>/dev/null || echo "Warning: Failed to delete branch. Please delete manually: $WORKTREE_BRANCH"
   ```

### Exit: push-and-remove Section (used by /code PR, /review, /merge)

The calling skill exits the worktree with the following steps after completing push:

**When `ENTERED_WORKTREE=false`**: Skip this section (push is assumed to be already completed by the calling skill in the normal flow).

**When `ENTERED_WORKTREE=true`**:

1. Confirm push is complete inside the worktree (push is assumed completed by calling skill)

2. Call `ExitWorktree(action: "remove", discard_changes: true)` to delete the worktree and return to the original directory
   - **If deletion fails**: Output warning message and guide manual deletion; skill continues normally:
     ```
     Warning: Failed to remove worktree. Please remove manually.
     ```

## Output

- `ENTERED_WORKTREE`: `true` (EnterWorktree was executed) or `false` (skipped)
- After executing the Entry section, the worktree's filesystem becomes accessible
