# phase-banner

Standardized phase identification banner for skill start.

## Purpose
Display Issue/PR title and URL at skill start for identification.
Right after the banner, also warn when the plugin directory the Skill was loaded from (`${CLAUDE_PLUGIN_ROOT}`) is a git checkout that is behind its upstream, because a stale checkout silently runs old Skills, modules, and scripts.

## Input
- ENTITY_TYPE: "issue" or "pr"
- ENTITY_NUMBER: Issue or PR number (extracted by calling skill)
- SKILL_NAME: name of the skill (e.g., "issue", "spec", "review")

## Processing Steps
1. Fetch title and URL:
   - Issue: `gh issue view $N --json title,url`
   - PR: `gh pr view $N --json title,url`
2. Output banner format (at skill start, after number extraction):
   ```
   /SKILL_NAME #N
   TITLE
   URL
   ```
3. If `gh` command fails, output banner without title/URL (skip silently)
4. Warn when the plugin directory is behind its upstream, right after the banner. Skip this step when the same warning was already shown earlier in this conversation (for example when this Skill runs inside another Skill's flow). Run the helper as a single command; it never changes the checkout and always exits 0:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/check-plugin-staleness.sh
   ```
   - **No output**: the plugin directory is not a git checkout (for example a marketplace install), HEAD is detached, no upstream is configured, it is not behind, or counting the lag failed. Output nothing and continue with the calling Skill.
   - **One line `behind=N upstream=U root=R`**: the upstream is N commits ahead of HEAD. Output this warning as one line, with {N}, {U}, and {R} substituted ({R} is already shell-quoted; use it as is):
     ```
     wholework の読み込み元が最後に fetch した {U} より {N} コミット遅れています。`git -C {R} pull --ff-only` を検討してください
     ```
   - **The command itself cannot run** (script missing, not executable, non-zero exit): treat it as no output. Never stop the Skill, retry, or report an error because of this step.
   - Never run `git pull`, `git fetch`, `git merge`, or any other command that changes the checkout, including the suggested one. Whether and when to update is the user's decision (see Notes).

## Output
Phase identification banner displayed to terminal, followed by a one-line staleness warning only when the plugin directory is behind its upstream.

## Notes

Both SKILL.md (LLM-executed) skills and `run-*.sh` shell scripts use the same `/SKILL_NAME #N` format.

For `run-*.sh` shell scripts, `scripts/phase-banner.sh` provides `print_start_banner` / `print_end_banner` functions that accept `skill_name` as a third argument and output the same unified format:
```
/skill_name #N
TITLE
URL
```

### Plugin directory staleness warning (Issue #1519)

- **Scope**: `${CLAUDE_PLUGIN_ROOT}` is checked only when it is itself the top level of a git work tree whose current branch has an upstream, which is the `claude --plugin-dir <checkout>` setup. A marketplace install (not a git checkout), a plain directory (including one nested inside an unrelated repository), a detached HEAD, a branch without an upstream, or any failure while counting produces no output, so the Skill continues without a warning.
- **Measurement**: `git rev-list --count HEAD..@{u}`, the number of upstream commits that HEAD does not contain. The helper makes no network access, so the count is relative to the remote-tracking ref as of the last fetch: a checkout that nobody has fetched can look up to date. Keeping that ref fresh (for example a scheduled `git fetch` in the checkout) is left to the user; see `docs/guide/troubleshooting.md`.
- **Never updates the checkout**: this step only reports. It never runs `git pull`, `git fetch`, or `git merge`, because another session may be executing scripts from the same checkout and a pull would change them mid-run. The suggested `git -C <root> pull --ff-only` is for the user to run.
- **Why `scripts/phase-banner.sh` does not call the helper**: it serves the `run-*.sh` wrappers, which run headless and repeat for every phase (in `--output-format json` runs the wrapper keeps only the final `.result`, so a line the session prints mid-run does not reach the wrapper log anyway). An interactive `/auto` shows this warning once at its own banner; calling the helper from `print_start_banner` too would repeat the line for every phase of every Issue.
- **Not covered**: Skills that show no start banner (`/audit`, `/doc`) and runs that are headless from the start.
