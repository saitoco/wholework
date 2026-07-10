# worktree-lifecycle module

## Purpose

Provides a shared worktree Entry/Exit lifecycle common to all skills (/spec, /code, /verify, /review, /merge). Transparently manages EnterWorktree/ExitWorktree to structurally eliminate commit contamination risk and synchronization overhead.

## Input

- `WORKTREE_NAME`: Worktree name (e.g., `spec/issue-123`). Specified by each skill following naming conventions
- `EXIT_MODE`: `merge-to-main` | `push-and-remove`. Select based on the skill's commit destination

## Processing Steps

### Entry Section (execute at skill start)

The calling skill enters the worktree with the following steps:

1. **Determine worktree context**: Run `${CLAUDE_PLUGIN_ROOT}/scripts/detect-foreign-worktree.sh "$WORKTREE_NAME"` (pass the same value used for `EnterWorktree`'s `name` parameter in step 3):
   - **Output `none`** (not inside any worktree): Record `ENTERED_WORKTREE=true` and proceed to the next step
   - **Output `own`** (already inside the worktree matching `WORKTREE_NAME`): Record `ENTERED_WORKTREE=false` and skip EnterWorktree, proceeding to the next step
   - **Output `foreign <path>`** (inside a *different* worktree — e.g. inherited via a nested `Skill()` dispatch from a parent phase's Opportunistic Verification / Event-based observation scan, or a leftover worktree from a prior phase that was never exited): run `cd <path>` to return to the main repository root, then record `ENTERED_WORKTREE=true` and proceed to the next step exactly as in the `none` case (this creates the skill's own properly isolated worktree instead of silently operating — and potentially committing — inside the foreign one)

2. **Stale worktree check** (when step 1 recorded `ENTERED_WORKTREE=true`; run before calling `EnterWorktree(name: WORKTREE_NAME)` in step 3): `detect-foreign-worktree.sh` only inspects the *current* branch, so it cannot see a worktree directory left behind by a previous session that crashed or exited without calling `ExitWorktree` — from the main repo root, such a worktree is invisible to step 1 and would otherwise conflict with a fresh `EnterWorktree(name: ...)` call. Check whether `.claude/worktrees/$WORKTREE_NAME` already exists on disk:
   - **Does not exist**: no stale worktree — proceed to step 3 as normal.
   - **Exists** (candidate stale worktree): treat it as a live conflict — not stale — unless there is positive evidence the owning process has actually ended (e.g., no concurrent session or `/auto` run is known to hold it); when in doubt, stop and surface the conflict instead of acting automatically. Once confirmed stale, decide **reuse vs. discard**:
     - Inspect residual content: `git -C ".claude/worktrees/$WORKTREE_NAME" status --porcelain` (and `git diff` for detail).
     - **No uncommitted changes**, or changes **consistent with this phase's intended work** (e.g., for `/code`, matching the Spec's Implementation Steps at `docs/spec/issue-N-*.md`) → **reuse**: call `EnterWorktree(path: ".claude/worktrees/$WORKTREE_NAME")` instead of step 3's `name` form.
     - Changes that **contradict or only partially match** the intended work, or nothing to compare against → **discard**: remove the stale worktree and branch (`git worktree remove --force ".claude/worktrees/$WORKTREE_NAME"`; `git branch -D "worktree-${WORKTREE_NAME//\//+}"`), then proceed to step 3 to create a fresh worktree.

3. Only when `ENTERED_WORKTREE=true`: Call `EnterWorktree(name: WORKTREE_NAME)`

4. **Run worktree initialization hook**: Run only if `.claude/hooks/worktree-init.sh` exists:
   ```bash
   test -x .claude/hooks/worktree-init.sh && bash .claude/hooks/worktree-init.sh
   ```
   Do nothing if hook does not exist (skip).

5. **`node_modules` symlink from parent repo (optional, for Node.js projects)**: When `command` verify types depend on binaries such as `pnpm exec` or `npx`, those binaries are not found inside the worktree because `node_modules/` only exists in the parent repository. If the parent repo has `node_modules/`, adding the following snippet to `.claude/hooks/worktree-init.sh` creates a symlink to share it:
   ```bash
   PARENT_ROOT="$(git worktree list | awk 'NR==1{print $1}')"
   if [ -d "$PARENT_ROOT/node_modules" ] && [ ! -e "node_modules" ]; then
     ln -s "$PARENT_ROOT/node_modules" node_modules
   fi
   ```
   **Note**: The symlink is safe only when the lockfile in the worktree branch matches the parent. If the branch has a different lockfile, run `pnpm install --frozen-lockfile` instead of creating the symlink.

### Exit: merge-to-main Section (used by /spec, /code patch, /verify)

The calling skill exits the worktree with the following steps after completing commits:

**When `ENTERED_WORKTREE=false`**: Skip this section and run the merge-push script without `--from` (lock+push only):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh [--base "$BASE_BRANCH"]
```

**When `ENTERED_WORKTREE=true`**:

1. Call `ExitWorktree(action: "keep")` to return to the original directory (do not delete the worktree branch)

2. Retain `WORKTREE_BRANCH` with the branch name worked on in the worktree (confirmable after calling EnterWorktree)

3. Run the new script which acquires a short-lived lock, merges the worktree branch into the base branch, performs the conflict marker check, and pushes — all as a single atomic unit:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh --from "$WORKTREE_BRANCH" [--base "$BASE_BRANCH"]
   ```

   The script handles: lock acquisition (PID stamping, stale detection, configurable timeout via `patch-lock-timeout` in `.wholework.yml`, default 300s), `git merge --ff-only` (with `git pull --rebase` retry on FF failure, and worktree-branch rebase fallback when base has advanced while the worktree was running — see `modules/orchestration-fallbacks.md#ff-only-merge-fallback`), conflict marker check, `git push origin <base>`, and lock release via EXIT trap. On script failure (non-zero exit), abort and skip cleanup.

4. **Cleanup** (output warning and continue if any command fails):
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

## Notes

### Editing `.claude/` files inside worktrees

Files under `.claude/` are treated as **sensitive files** by Claude Code — Edit and Write tools are automatically rejected for these paths. When implementation requires editing `.claude/` files (e.g., `settings.json.template`, hook scripts), use Bash commands instead:

```bash
# Example: modify a .claude/ file via Python
python3 -c "
content = open('.claude/settings.json.template').read()
content = content.replace('OLD_VALUE', 'NEW_VALUE')
open('.claude/settings.json.template', 'w').write(content)
"

# Example: modify via sed
sed -i 's/OLD_VALUE/NEW_VALUE/g' .claude/settings.json.template
```

This constraint applies to all files under `.claude/`, including `settings.json.template`, `settings.json`, and hook scripts under `.claude/hooks/`.

### Edit/Write path conventions in worktree sessions

After calling `EnterWorktree` (`ENTERED_WORKTREE=true`), when editing files inside the
worktree, **always use the worktree-local path** with the Edit or Write tool:

- ✅ Absolute worktree path: `Edit .claude/worktrees/{NAME}/docs/spec/issue-N-foo.md`
- ✅ CWD-relative path (when CWD is inside the worktree): `Edit docs/spec/issue-N-foo.md`
- ❌ Absolute parent-repo path during a worktree session: `Edit /path/to/repo/docs/spec/issue-N-foo.md`

**Why**: Using an absolute parent-repo path calls Edit on the parent repo's file instead
of the worktree copy. In parallel-session environments, other sessions observing the
resulting dirty state of the parent repo file may fail unexpectedly.

**How to verify CWD**: Run `pwd` to confirm you are inside the worktree, or confirm that
the return value from `EnterWorktree` points to the worktree path before calling Edit.

**Enforcement**: This convention is mechanically enforced by `scripts/hook-worktree-path-guard.sh` (registered as a PreToolUse hook in `hooks/hooks.json`), which blocks Edit/Write calls whose `file_path` is an absolute parent-repo path while the session is inside a worktree. **Scope limit**: the hook matches only the Edit/Write/NotebookEdit tools — Bash-based edits, including the `.claude/` file workaround above, are not covered, so the worktree-local-path discipline must still be applied manually there.

## Callers (auto-maintained)

All callers that read this module. Update this table when a new Skill starts reading `modules/worktree-lifecycle.md`.

### Direct Callers (SKILL.md)

| Skill | Path | Runner script |
|-------|------|---------------|
| spec | `skills/spec/SKILL.md` | `scripts/run-spec.sh` |
| code | `skills/code/SKILL.md` | `scripts/run-code.sh` |
| review | `skills/review/SKILL.md` | `scripts/run-review.sh` |
| merge | `skills/merge/SKILL.md` | `scripts/run-merge.sh` |
| verify | `skills/verify/SKILL.md` | (in-session only — no run-verify.sh) |

### Orchestrator

| Script | Role |
|--------|------|
| `scripts/run-auto-sub.sh` | Calls run-spec.sh / run-code.sh / run-review.sh / run-merge.sh in sequence for sub-issue execution |

### Update Protocol

When a new Skill reads this module, add a row to the Direct Callers table above (and its runner script if one exists). This keeps the caller list as SSoT for impact-range visibility when modifying entry/exit logic, lock ordering, or rebase fallback behavior.
