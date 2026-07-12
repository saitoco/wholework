# next-action-guide module

## Purpose

Generates a unified next action guide at the completion of each skill. Provides users with context-aware guidance — a recommended action and an alternative — so they know what to do next without having to re-learn the workflow for each skill.

Called by: `issue`, `spec`, `code`, `review`, `merge`, `verify`, `triage`, `auto`

## Input

Variables passed by the calling skill:

- `SKILL_NAME` (string, required): Name of the completed skill. One of: `issue` / `spec` / `code` / `review` / `merge` / `verify` / `triage` / `auto`
- `RESULT` (string, optional, default `success`): Outcome of the skill. One of: `success` / `fail` / `blocked`
- `ISSUE_NUMBER` (int, optional): Issue number. Pass when available
- `PR_NUMBER` (int, optional): PR number. Pass when available (primarily for `code`, `review`, `merge`)
- `SIZE` (string, optional): Issue size. One of: `XS` / `S` / `M` / `L` / `XL` / empty string
- `ROUTE` (string, optional): Workflow route. One of: `patch` / `pr` / `sub_issue` / `operate`. When omitted, derived from SIZE using `modules/size-workflow-table.md`. `operate` cannot be derived from SIZE (it is an orthogonal diff-less-axis value — see `modules/size-workflow-table.md` § "Diff-less Axis (operate route)") and must always be passed explicitly by the caller
- `BLOCKED_BY_OPEN` (bool, optional, default `false`): Whether open blocked-by relationships exist

## Processing Steps

Use contextual understanding to determine the appropriate guidance. This is a judgment task — do not mechanically apply rules, but interpret the situation and select the most helpful recommendation.

### Step 1: Check RESULT

- `blocked` → Skip Steps 2–3 and go to Step 4 (blocker guidance)
- `fail` → Proceed to Step 3, selecting the fail row for the skill
- `success` → Proceed to Step 2

### Step 2: Derive ROUTE from SIZE (when ROUTE is not provided)

If the caller passed `ROUTE` explicitly, skip this derivation step entirely — do not overwrite it from SIZE. This matters in particular for `operate`, which cannot be derived from SIZE (see Input above).

Read `${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md` to derive ROUTE from SIZE:
- `XS` or `S` → `patch`
- `M` or `L` → `pr`
- `XL` → `sub_issue`
- SIZE empty → treat as unknown; omit route-specific reasoning

### Step 3: Select recommendation using judgment table

Use the table below as guidance. Contextual factors (e.g., whether acceptance criteria are clearly defined, whether blockers exist) may shift the recommendation — apply LLM judgment rather than strict pattern matching.

| SKILL_NAME | RESULT  | Situation                           | Recommended              | Alternative                    |
|------------|---------|-------------------------------------|--------------------------|--------------------------------|
| `triage`   | success | any                                 | `/issue {ISSUE_NUMBER}`  | `/auto {ISSUE_NUMBER}`         |
| `issue`    | success | XS/S and acceptance criteria clear  | `/auto {ISSUE_NUMBER}`   | `/spec {ISSUE_NUMBER}`         |
| `issue`    | success | M/L                                 | `/spec {ISSUE_NUMBER}`   | `/auto {ISSUE_NUMBER}`         |
| `issue`    | success | XL (sub-issue split recommended)    | `/issue {ISSUE_NUMBER}` (split) | —                         |
| `spec`     | success | patch (XS/S)                        | `/auto {ISSUE_NUMBER}`   | `/code {ISSUE_NUMBER}`         |
| `spec`     | success | pr (M/L)                            | `/auto {ISSUE_NUMBER}`   | `/code {ISSUE_NUMBER}`         |
| `spec`     | success | sub_issue (XL)                      | `/issue {ISSUE_NUMBER}` (split) | —                         |
| `code`     | success | patch                               | `/verify {ISSUE_NUMBER}` | `/auto {ISSUE_NUMBER}`         |
| `code`     | success | pr                                  | `/review {PR_NUMBER}`    | `/auto {ISSUE_NUMBER}`         |
| `code`     | success | operate                             | `/verify {ISSUE_NUMBER}` | `/auto {ISSUE_NUMBER}`         |
| `review`   | success | any                                 | `/merge {PR_NUMBER}`     | `/auto {ISSUE_NUMBER}`         |
| `merge`    | success | any                                 | `/verify {ISSUE_NUMBER}` | `/auto {ISSUE_NUMBER}`         |
| `verify`   | success (PASS) | any                          | (no guidance)            | —                              |
| `verify`   | fail    | any                                 | `/code {ISSUE_NUMBER}`   | `/auto {ISSUE_NUMBER}`         |
| `auto`     | success | any                                 | (no guidance)            | —                              |
| `auto`     | fail    | any                                 | `/code {ISSUE_NUMBER}`   | manual investigation           |

**Batch/bulk completion (ISSUE_NUMBER not provided)**: When `SKILL_NAME` is `triage`, `auto`, or similar and `ISSUE_NUMBER` is not passed (multi-issue batch run), omit the next action guide entirely.

### Step 4: Blocker guidance (when BLOCKED_BY_OPEN=true or RESULT=blocked)

Do not show a recommended next action. Instead, inform the user to wait for the blocker to be resolved:

```
次のアクション:
- ブロッカー Issue を解消してから `/code {ISSUE_NUMBER}` または `/auto {ISSUE_NUMBER}` を実行してください
```

## Output

Output to terminal in Japanese. Follow CLAUDE.md convention: "Skill output (terminal): Japanese".

**Pattern 1 — Recommendation available:**

```
次のアクション:
- **`{recommended command}`** （推奨） — {one-line reason}
- `{alternative command}` — {one-line purpose}
```

**Pattern 2 — No guidance (verify PASS, auto success, batch completion):**

Output nothing. The calling skill's completion message is sufficient.

**Pattern 3 — Blocked:**

```
次のアクション:
- ブロッカー Issue を解消してから `/code {ISSUE_NUMBER}` または `/auto {ISSUE_NUMBER}` を実行してください
```
