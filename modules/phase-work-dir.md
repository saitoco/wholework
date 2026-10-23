# phase-work-dir

Shared rules for where a phase puts large verification work files, when it removes them, and how it handles the leftovers of an interrupted run.

## Purpose

A phase sometimes needs large work files to verify something: a copy of the repository, installed dependencies (`node_modules`), build output, or a browser-automation profile (for example a Chrome user-data directory). These are called **large work files** in this module. Examples: building the candidate versions of a framework upgrade side by side, or running a browser check against a built copy.

Placing them carelessly breaks the next run, not only the current one:

- On many Linux hosts `/tmp` is tmpfs, so every file there uses memory. A repository copy with `node_modules` and a build is about 1 GB each.
- A phase that stops midway (watchdog stop, OOM killer, crash) never removes what it created. Leftovers accumulate across re-runs until memory and swap are exhausted and the next run is killed too (the keio #347 incident: three consecutive `/spec` runs stopped, with `/tmp` at 89% and the OOM killer firing).
- A copy placed inside the repository tree can be picked up by the build, test, or lint of the repository under work (TypeScript `include`, test-runner discovery, formatter globs).

This rule is common to **every phase**: whichever phase creates large work files for verification follows the same placement, cleanup, and sweep rules. `/spec`, `/code`, and `/verify` call it from their own steps (see Callers).

Out of scope: small temporary files that skill and module procedures create, and the private scratch files of bundled scripts. They follow `modules/filesystem-scope.md` § Temporary Files.

## Input

- `ISSUE_NUMBER`: the Issue number the phase is processing
- `PHASE_NAME`: the phase name (for example `spec`, `code`, `verify`)

## Processing Steps

All path resolution, creation, and deletion go through `${CLAUDE_PLUGIN_ROOT}/scripts/phase-work-dir.sh`. Do not build the path by hand and do not run `rm -rf` on it yourself.

### 1. Placement

Put every large work file under the directory printed by `${CLAUDE_PLUGIN_ROOT}/scripts/phase-work-dir.sh create $ISSUE_NUMBER $PHASE_NAME`. That directory satisfies three requirements:

1. **On disk, not in memory.** Do not use a location that uses memory: `/tmp`, `$TMPDIR`, `/dev/shm`, `/run`, or any tmpfs. The script resolves the location under `${XDG_CACHE_HOME:-$HOME/.cache}/wholework/work/` and refuses (exit 1) when that location is on tmpfs or ramfs.
2. **Outside the scan scope of the repository under work.** Do not place it inside the repository tree: not in the main checkout, not in a worktree, and not in the gitignored `.tmp/`. TypeScript `include`, test-runner discovery, and lint or formatter globs can pick up a copy there, depending on the tool and its configuration.
3. **Named by Issue number and phase.** The directory is `issue-<N>-<phase>` (for example `issue-347-spec`), under a per-repository key (`<repo-key>`, built from the path of the main checkout), so the name alone shows which Issue and phase created it and which repository it belongs to.

The phase may create any subdirectories it needs under the printed directory (for example `repo-copy`, `browser-profile`). A tool that places its own scratch under `$TMPDIR` (for example a Chrome launch started by an audit tool) is run with `TMPDIR=<work directory>/tmp` for that command only; create that `tmp` subdirectory first.

If the verification can run inside the phase's own worktree without creating large work files, do not create them.

### 2. Cleanup timing

1. **When the phase ends, remove what it created, whether it ended in success or in failure.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/phase-work-dir.sh clean $ISSUE_NUMBER $PHASE_NAME`. Removing early, as soon as the files are no longer needed, is also fine. A path that stops the phase with an error runs the same cleanup.
2. **What could not be removed is removed by the next run, at its start.** A forced termination (watchdog stop, OOM killer, crash) skips the cleanup in item 1, so the phase-start sweep in section 3 is the guarantee that leftovers do not accumulate.

### 3. Phase-start sweep

At the start of the phase, before creating anything, run `${CLAUDE_PLUGIN_ROOT}/scripts/phase-work-dir.sh sweep $ISSUE_NUMBER $PHASE_NAME`. The script looks for work directories left by earlier runs and treats them differently:

1. **The same repository, the same Issue, and the same phase: remove it, then start.** The same Issue and phase never run in parallel, so a directory with this name is a leftover. The script reports what it removed, with path and size.
2. **Any other Issue, other phase, or other repository: do not remove it; warn with its location and size.** It may belong to a session running in parallel. The script prints one warning line per directory, up to 20, then one summary line for the rest ("N more directories not shown").

Relay the warnings to the user. Do not delete a warned directory on your own judgment, even if it looks old; the user decides.

### 4. When the directory cannot be used

If the script exits non-zero (the location cannot be resolved, the location is on tmpfs, a permission or sandbox restriction applies, or the disk is full), do not fall back to `/tmp`, `$TMPDIR`, or `.tmp/`. Do the verification that can run inside the worktree there, and record the verification that needs a copy as UNCERTAIN (not verified) in the Spec's Notes or the phase retrospective, with the reason.

## Output

- `create`: the absolute path of the work directory on stdout (exit 0)
- `sweep`: one stderr line for a removed leftover, and one warning line for each directory it left in place
- Exit codes: `0` success, `1` usage error or an unsafe environment (nothing was touched), `2` part of a removal failed (the next run's sweep retries it)

## Notes

- **Why not `.tmp/` in the repository.** `.tmp/` is right for small files that skill procedures create (`modules/filesystem-scope.md` § Temporary Files), but a repository copy placed inside the tree can be scanned by the tool under test. Moving the copy outside the tree guarantees requirement 2 without depending on each tool's configuration. The XDG cache directory is the standard place for non-essential, regenerable user data, which matches the meaning of these files.
- **Forced termination skips cleanup.** A hard kill runs no exit handler, so the sweep at the next start is the only way back for a leftover. The rule therefore has two halves: remove at the end, sweep at the start.
- **No exclusion for the same Issue and phase.** The sweep assumes the same Issue and phase are not running in parallel. It does not take a lock.
- **Owner-only permissions.** The directory is created with mode 700 because a repository copy can include files such as `.env`.
- **Why a script.** Removing what an earlier run left behind is the kind of deletion an automatic permission classifier can block when an LLM runs `rm -rf` directly. The script validates its inputs, rebuilds the target path from validated parts, never follows symbolic links, never removes anything outside the one matching directory, and is covered by `tests/phase-work-dir.bats`.
- **Other phases.** `/review` and other phases follow the same rules whenever they create large work files. Wiring `sweep` and `clean` into those phases is done separately.
- **Changing the location.** Set `XDG_CACHE_HOME` (an absolute path) to move the base directory. There is no dedicated variable or `.wholework.yml` key.

## Callers (auto-maintained)

All callers that read this module. Update this table when a new Skill starts reading `modules/phase-work-dir.md`.

### Direct Callers (SKILL.md)

| Skill | Path | Call points |
|-------|------|-------------|
| spec | `skills/spec/SKILL.md` | Step 2 (sweep), Step 6 (create), Step 14 (clean) |
| code | `skills/code/SKILL.md` | Step 2 (sweep), Step 6 (create), Step 14 (clean) |
| verify | `skills/verify/SKILL.md` | Step 3 (sweep, create), Step 13 (clean) |
