---
type: domain
skill: code
load_when:
  file_exists_any: [scripts/check-language-convention.py]
---

# Language Convention Check (/code supplement)

This file is loaded only in repositories where `scripts/check-language-convention.py` exists. In a repository without that script (for example, another project that uses Wholework as a plugin), skip this entire check and continue.

## Processing Steps

Run the language convention check locally before committing. It mirrors the CI `language-convention` job (`.github/workflows/test.yml`), which feeds the diff of the English-designated paths to `scripts/check-language-convention.py`. Editing an existing line puts the whole line into the diff as a `+` line, so Japanese prose that was already on that line is reported too — catching it here avoids a round trip through CI and `/review`.

Keep the target paths and the diff form below in sync with the CI job.

1. **Determine the base**: run the following as its own step, where `BASE_BRANCH` is the value resolved in Step 0 (default `main`):

   ```bash
   git merge-base "origin/$BASE_BRANCH" HEAD
   ```

   Substitute the printed SHA literally for `<base>` in the later steps. Do not use inline command substitution for this: the worktree isolation guard rejects it, and if the inline command failed the diff would silently lose its base and check a different range. Diffing from the merge base (rather than from the tip of the base branch) uses the same fork point as the CI `origin/<base>...HEAD` form, so changes that landed on the base branch while you were working are not mistaken for your own. If the command fails, use `HEAD` as `<base>` and continue, and report that only uncommitted changes were checked.

2. **Register untracked files**: `git diff <base>` does not list untracked files, so a new file would silently escape the check. List them and register each one with intent-to-add (the content is not staged):

   ```bash
   git status --porcelain --untracked-files=all -- skills/ modules/ scripts/
   ```

   For every line starting with `??`, run `git add -N -- <path>`. If there are none, do nothing. This does not interfere with Step 11, which stages the changed files individually with `git add`.

3. **Check**: run the CI-equivalent diff against the working tree:

   ```bash
   git diff -U100000 <base> -- skills/ modules/ scripts/ | python3 scripts/check-language-convention.py
   ```

   This compares the merge base with the working tree, so committed changes and uncommitted changes are checked together in a single pass. `-U100000` is required: the script follows fenced-code-block state through the context lines. Pass the diff to the script as is, without reformatting it through `sed`, `tr`, or similar.

4. **Handle the result**:
   - No output and exit 0 (including an empty diff): no violations — continue.
   - Violations are printed one per line as `<path>:<line content>` and the script exits 1. Fix every reported line before committing, then re-run step 3 until it exits 0. On the patch route, make any fix commit with `git commit -s` before the Step 11 commit; on the pr route, make it before the Step 11 push.
   - Fixing guidance:
     - Editing an existing line puts the whole line into the diff, so Japanese prose that was already there is reported. Translate the whole line into English.
     - Keep intentional Japanese (data keywords, output messages) inside a form the script excludes: a fenced code block, inline code, or a quoted string. Do not loosen the script to make a violation disappear.
     - If a fix touches wording that a test asserts on, re-run the affected tests.
   - If one round of fixes does not clear the violations, treat it like an unresolved test failure (Step 9 `Test FAIL handling`): abort on the patch route in non-interactive mode, ask via AskUserQuestion on the patch route in interactive mode, and on the pr route continue and list the remaining violations in the completion message.

## Failure Handling

This check is a local preview of CI, and CI remains the final gate, so a broken local tool must not block the commit:

- `git merge-base` fails: use `HEAD` as `<base>` and continue (fail-open), as described in step 1.
- The script or `python3` cannot run or crashes (non-zero exit with no `<path>:<line content>` output): record "language convention check not run" in the completion message and continue (fail-open).
- Only a reported violation (`<path>:<line content>` output present) stops progress until it is fixed (fail-closed).
