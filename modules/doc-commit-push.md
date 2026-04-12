# doc-commit-push

## Purpose

Confirm with the user and execute commit/push for file changes written out by `/doc` subcommands.
Runs `git status --porcelain` first; if there are no changes, exits silently without prompting.

## Input

- `SUMMARY`: Summary string for the commit message body (set by the caller, e.g., `"sync (reverse-generation)"`). Placeholders (`{doc}`, `{path}`, `{name}`) are expanded by the caller at the point of invocation.

## Processing Steps

1. Run `git status --porcelain`. If the output is empty (no changes), exit silently (no AskUserQuestion prompt).
2. Display the change summary with `git status --short` to show what will be committed.
3. Ask with AskUserQuestion:
   ```
   Commit and push these changes?
   - Yes, commit and push
   - No, skip
   ```
4. If "No, skip" is selected: display "Changes left uncommitted. Run `git status` to review, or re-run the /doc command later." and exit.
5. If "Yes, commit and push" is selected:
   ```bash
   git add -A
   git commit -s -m "docs: ${SUMMARY}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
   git push origin HEAD
   ```
6. Display the commit hash and push result to confirm completion.

## Output

Side effects only (commit and push). No return value.
