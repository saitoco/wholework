# verify-classifier

Classification criteria and logic for determining the verifiability type of post-merge conditions.

## Purpose

This file provides classification criteria for assigning `<!-- verify-type: auto|opportunistic|manual -->` tags to each condition in the post-merge acceptance criteria section. Caller: `/issue`. Expected to also be referenced by `/verify` in the future.

## Input

Information provided by the calling skill:

- Each acceptance condition from the post-merge section

## Processing Steps

Skills that Read this file should evaluate each post-merge condition against the classification criteria **in order from top to bottom**, assigning the `<!-- verify-type: TYPE -->` tag of the first matching type.

### Classification Criteria (Priority: auto > opportunistic > observation > manual)

| Type | Criteria | Examples |
|------|---------|---------|
| `auto` | A verify command (`<!-- verify: ... -->`) is actually attached | File existence check, grep pattern match, test execution |
| `opportunistic` | Condition text matches the pattern "verify X when `/skill-name` is run" | "Confirm doc impact check runs when `/spec` is executed" |
| `observation` | Condition is an event-driven observation that requires a specific trigger to fire | "Observe that the next `/review --full` auto-checks the condition" |
| `manual` | Does not match any of the above | "Confirm no dialog appears", "Visual browser verification" |

### observation Type: Event Values and Syntax

`<!-- verify-type: observation event=<event-name> -->` marks a condition as an event-driven observation.
The condition is **not** verified during a normal `/verify` run **while the specified event has not yet fired**; instead, it is re-evaluated once the event fires. After the event fires, the condition is evaluated (not skipped) during the next normal `/verify` run per `skills/verify/SKILL.md` Step 8c.

**Valid `event-name` values (restricted by convention):**

| Event name | When it fires | Emitter |
|------------|---------------|---------|
| `pr-review-full` | Next `/review --full` completion | `/review` skill (Step runs `opportunistic-search.sh --event pr-review-full`) |
| `pr-review-light` | Next `/review --light` completion | `/review` skill (Step runs `opportunistic-search.sh --event pr-review-light`) |
| `auto-run` | Next `/auto` completion (success or failure) | `/auto` skill (post-completion step runs `opportunistic-search.sh --event auto-run`) |
| `watchdog-kill` | When watchdog kill fires | `scripts/claude-watchdog.sh` (kill handler runs `opportunistic-search.sh --event watchdog-kill`) |
| `fix-cycle` | When a verify FAIL → reopen → fix cycle activates | Not yet implemented — emitter is a follow-up (#650 child Issue) |

**Unknown event fallback**: if an unknown `event=` value is encountered, emit a warning to stderr:
```
Warning: unknown event '<name>', falling back to opportunistic treatment
```
Then treat the condition as `verify-type: opportunistic` (backward-compatible).

**Syntax note**: The `event=` parameter is a required attribute of `verify-type: observation`. Omitting `event=` is treated as an unknown event and triggers the fallback above.

**`config=<key>` for setting-dependent observation conditions**: when the observation condition's
text depends on a specific `.wholework.yml` setting (e.g., "observe X under `always-pr: true`"),
append a `config=<key>` attribute to the tag:

```
<!-- verify-type: observation event=auto-run config=always-pr -->
```

If `config=` is omitted for a setting-dependent condition, the AC matches unconditionally on every
`event=` dispatch — including in repositories where the referenced setting is unset or `false`, so
the condition can never actually resolve. The result is notification comments accumulating on the
Issue indefinitely with no path to PASS. See `modules/observation-trigger.md` § Condition Check
Gate (`config=`) for the resolution mechanics.

`<key>` must be a flat kebab-case key or a single-level nested key in block format (e.g.
`capabilities.workflow`), matching `get-config-value.sh`'s own constraint — inline hash format and
keys with two or more dots are not supported, and the comparison is boolean-only (`true`/`false`);
enum-valued keys (e.g. `auto-stop-at`) are out of scope for `config=`.

**`when=<axis>:<value>` for context-dependent observation conditions**: when the observation
condition's text depends on the `/auto` run context that fires the event (route / mode / recovery
tier), or on the firing skill's own execution context (main / fork — e.g. an AC that only makes
sense when `/review` ran as a direct interactive invocation rather than via `run-review.sh`),
append one or more comma-separated `when=<axis>:<value>` clauses (combined with AND) to the tag:

```
<!-- verify-type: observation event=auto-run when=route:operate -->
<!-- verify-type: observation event=pr-review-full when=execution-context:main -->
```

If `when=` is omitted for a context-dependent condition, the AC matches unconditionally on every
`event=` dispatch — including runs whose context does not satisfy the condition, so it resolves
SKIPPED every time instead of ever reaching a real evaluation. Declarable axes, per-axis fact JSON
fields, and fail-open semantics are documented in `modules/observation-trigger.md` § Condition
Check Gate (`when=`).

**`session=next` for skill self-update propagation**: wholework is self-hosted — the harness caches
skill content per conversation session, not per `/auto` execution. When an Issue changes
`skills/*/SKILL.md`, a post-merge observation condition that observes the changed skill's own
behavior cannot be evaluated in the conversation session that processed that Issue, because the
change lands on the base branch only after that session's skill content was already loaded. The
condition only becomes evaluable once a conversation session that starts after the change has
landed loads the updated skill. Append `session=next` to the tag to declare this:

```
<!-- verify-type: observation event=auto-run session=next -->
```

`session=next` is a declaration only — it does not gate `opportunistic-search.sh` dispatch (see
`modules/observation-trigger.md` § Notes). Consumers (exhaustive):

| Consumer | Role |
|----------|------|
| `/issue` Step 4 | Detects missing `session=next` on Issues that change `skills/*/SKILL.md` and warns (via `scripts/check-skill-change-observation-ac.sh`) |
| `/verify` Step 8c | Resolves a fired `session=next` condition to `SKIPPED` (not `UNCERTAIN`) when there is no evidence the changed skill step actually ran in the observed `/auto` execution |
| `scripts/opportunistic-search.sh` | Matches `event=` by substring — `session=next` does not change dispatch behavior |

Background: `docs/sessions/73536-1785868487-2026-08-04/session.md` § Skill Self-Update Propagation
Note documents a measured instance of this non-propagation (Issue #1157, condition 7).

### Tag Assignment Example

```markdown
### Post-Merge
- [ ] <!-- verify: github_check "gh pr checks" "Run bats tests" --> All bats tests PASS <!-- verify-type: auto -->
- [ ] Confirm test file search is included when `/spec` runs <!-- verify-type: opportunistic -->
- [ ] User visually confirms no confirmation dialog appears <!-- verify-type: manual -->
```

### Constraint: Required Rule When Using auto Type

When assigning `<!-- verify-type: auto -->` to a condition, a `<!-- verify: ... -->` verify command **must be present**.

- `verify-type: auto` is assigned only to conditions that have a verify command (a `auto` without a verify command is equivalent to skipping verification, which contradicts user expectations)
- If a verify command cannot be provided, classify as `opportunistic` or `manual` instead

### Translation File Condition Verification

Conditions that require verifying a translate update (e.g., "Update `docs/ja/tech.md`
to reflect changes") can be automatically verified using `file_contains` or `grep`.
Do not default to `verify-type: manual` for translation conditions — attach a verify
command and classify as `auto`.

**Pattern: `file_contains "docs/ja/xxx.md" "keyword"`**

Pick a keyword that must appear in the translated file after the update:

```markdown
- [ ] Update `docs/ja/tech.md` with the new section
  <!-- verify: file_contains "docs/ja/tech.md" "翻訳後のキーワード" -->
  <!-- verify-type: auto -->
```

Keyword selection tips:
- Use a term that is unique to the added/changed content (a section heading or a key concept)
- Prefer Japanese terms that are unlikely to appear elsewhere in the file

When a keyword cannot be identified, fall back to `grep` with a broader pattern:

```markdown
<!-- verify: grep "translate" docs/ja/tech.md -->
```

### Patch Route CI Verification Note

For Issues implemented via the patch route (direct commit to main, no PR), `github_check "gh pr checks"` **cannot be used** — no PR exists in the patch route.

This note applies only when the Issue actually takes the patch route. When `.wholework.yml` sets `always-pr: true`, Size XS/S is promoted to pr route (see `modules/size-workflow-table.md` § "ALWAYS_PR Override"), a PR does exist, and `github_check "gh pr checks"` is the correct form. Derive the route from `ALWAYS_PR` first, not from Size alone.

Use the `github_check "gh run list"` form instead:

```
github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"
```

When `/verify` detects `github_check "gh pr checks"` in an acceptance condition for a patch-route Issue (PR_NUMBER is empty), it treats the condition as UNCERTAIN and recommends switching to the `gh run list` form.

**Note:** When converting from `github_check "gh pr checks" "JOB_NAME"`, also replace the `expected_value` from the job name to `"success"`. `gh run list` outputs a run-level table (STATUS / conclusion / TITLE / WORKFLOW / ...) and does not include job names — specifying a job name as `expected_value` will never match and will always FAIL even when CI is green.

**Why `--commit` is not used (run/commit correspondence via `head_sha`):** GitHub Actions creates a workflow run only for the commit at the *head* of a push (the run's `head_sha`) — not for every commit included in that push. Patch route sends `[implementation commit, retrospective commit]` in a single push, so the retrospective commit is always the push head and the only one with a `head_sha`-matched run; the implementation commit itself never has a run of its own. A form pinned to a literal fixed implementation-commit SHA (`--commit=<implementation commit SHA>`) therefore always returns an empty result and cannot be judged PASS/FAIL. The prior canonical form, which resolved `--commit=` via `git rev-parse HEAD`, is a distinct failure mode: it is evaluated at `/verify` execution time and resolves to whatever the base branch's HEAD is at that moment — typically the retrospective commit (the push head), which *does* have a `head_sha`-matched run — so it returns a non-empty but potentially unrelated commit's run, not an empty result. Neither form can verify this Issue's own implementation. Because the retrospective commit only touches the Spec file, the tree its run built is equivalent to the implementation's tree — referencing "the most recent run on the target branch" (`--branch=main --limit=1`, omitting `--commit`) is a valid substitute.

**Residual risk (defect A is not fully eliminated):** Even with `--branch=main --limit=1`, there is no guarantee that "the most recent run on the branch at the time `/verify` executes" is the run produced by this Issue's own push — this repository runs concurrent sessions as a matter of course, and another session's push to `main` after this Issue's push would become the new "most recent" run. When the referenced run's result looks inconsistent with this Issue's own change (e.g., `cancelled`, or a `failure` on a job unrelated to the Issue's Changed Files), treat the condition as UNCERTAIN rather than a mechanical PASS/FAIL and recommend re-running `/verify` — the same operational stance as the CI Reference Fallback (#1126), applied here as guidance rather than an automated check.

## Output

Assign the `<!-- verify-type: auto|opportunistic|manual -->` tag to the end of each post-merge condition. Place the tag one half-width space before the line break at the end of the condition text.
