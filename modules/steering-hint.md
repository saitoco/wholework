# steering-hint

Shared module for displaying a dynamic hint recommending `/doc init` when steering docs are absent.

## Purpose

At skill completion, check whether Steering Documents are missing and whether the project has accumulated enough closed Issues via wholework. If conditions are met, display a one-line hint prompting the user to run `/doc init`.

The hint is opt-out: it displays every time conditions are met unless `steering-hint: false` is set in `.wholework.yml`.

## Input

Information provided by the calling skill:

- None (this module reads `.wholework.yml` and project state directly)

## Processing Steps

Skills that Read this file should execute the following steps.

### 1. Check `steering-hint` Flag

Read `.wholework.yml` from the project root.

- If `.wholework.yml` does not exist: treat `steering-hint` as `true` (default) and proceed
- If `steering-hint: false` is set: skip all subsequent steps (output nothing)
- Otherwise: proceed

### 2. Check Steering Docs Existence

Use `STEERING_DOCS_PATH` if the calling skill has already resolved it; otherwise default to `docs`.

Use Glob to search for `*.md` files under `$STEERING_DOCS_PATH`. For each file found, check whether its frontmatter contains `type: steering`.

- If one or more files with `type: steering` are found: steering docs exist — skip all subsequent steps (output nothing)
- If no such file is found: proceed

### 3. Count Closed Issues with `phase/done` Label

```bash
gh issue list --state closed --label "phase/done" --json number | jq length
```

- If the result is less than 5: threshold not reached — skip all subsequent steps (output nothing)
- If the result is 5 or more: proceed

### 4. Output Hint

Output the following one-line hint:

```
/doc init を実行すると今後の skill の精度が上がる可能性があります
```

## Output

- One-line hint to terminal (only when all conditions are met)
- No GitHub updates, no file writes
