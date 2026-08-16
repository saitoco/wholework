# verify-classifier

Classification criteria and logic for determining the verifiability type of post-merge conditions. The `manual` tag value this criteria produces is also assigned to pre-merge conditions via a separate path — see Purpose.

## Purpose

This file provides classification criteria for assigning `<!-- verify-type: auto|opportunistic|manual -->` tags to each condition in the post-merge acceptance criteria section. Caller: `/issue`. Expected to also be referenced by `/verify` in the future.

Separately, `/issue` Step 4's pre-merge-preview tier (`ac-tier: preview`, gated on `HAS_PR_PREVIEW_CAPABILITY`) assigns `verify-type: manual` to **pre-merge** conditions that require human confirmation against the PR preview environment — a distinct assignment path from this module's own priority-ordered classification below, which evaluates post-merge conditions only. `verify-type: manual` is therefore not exclusively post-merge: consumers that scan for it to mean "awaiting human confirmation post-merge" (e.g., a Manual Waiting Count) must exclude AC lines that also carry `ac-tier: preview`, since those were already confirmed pre-merge by `/review` against the preview URL, not left pending post-merge.

## Input

Information provided by the calling skill:

- Each acceptance condition from the post-merge section. (Pre-merge `ac-tier: preview` conditions are classified by `/issue` Step 4 directly, not through this module's criteria — see Purpose.)

## Processing Steps

Skills that Read this file should evaluate each post-merge condition against the classification criteria **in order from top to bottom**, assigning the `<!-- verify-type: TYPE -->` tag of the first matching type. This ordered evaluation applies to post-merge conditions only; the pre-merge `ac-tier: preview` manual assignment (see Purpose) is decided by `/issue` Step 4's own preview-environment axis, not by this priority order.

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
keys with two or more dots are not supported. The plain `config=<key>` form (no `:`) compares
boolean-only (`true`/`false`). For enum-valued keys (e.g. `auto-stop-at`), use the
`config=<key>:<value>` form instead:

```
<!-- verify-type: observation event=auto-run config=auto-stop-at:verify -->
```

which matches when `<key>`'s resolved value case-insensitively equals `<value>` — see
`modules/observation-trigger.md` § Condition Check Gate (`config=`) for the split, sanitization,
and fail-closed rules.

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

### observation Type: Population Definition for Numeric Conditions

When an observation condition's evidence is a count or aggregate (e.g., "the number of X has decreased since a baseline of N"), state the population the count is measured against directly in the condition text — the scan scope (label filter, date range, open/closed state) the number was computed from. Without an explicit population, a later re-measurement under a different scope can produce a materially different number, and even invert the PASS/FAIL verdict for the same underlying change (observed in Issues #1164/#1165/#1158: a baseline of 79 measured within a 90-day window read as an increase to 123 when re-measured all-time, but as a decrease to 18 within that same 90-day window).

**Trade-off — aggregate count vs. individual entity state**: an aggregate count is compact but re-scopable, so its PASS/FAIL verdict depends on a population definition living outside the condition unless the condition states one explicitly. An individual-entity condition (e.g., "confirm Issue #1066 and #1060 are no longer counted; Issues #1059/#709/#548/#442/#441 remain intentionally and are not counted toward the decrease") has nothing to re-scope — it is verifiable as written, with no population definition needed (Issue #1167). **Prefer the individual-entity form** when the set of relevant entities is small and enumerable.

**When an aggregate count cannot be avoided**: state the population explicitly in the condition text itself (label filter, date range, open/closed state) — do not rely on a value recorded elsewhere (e.g., a linked report's own baseline note) to supply it implicitly.

### observation Type: Firing Likelihood Check (before assignment)

Before assigning `verify-type: observation`, confirm the condition text can state two things: which `event=<name>` firing is expected to supply evidence, and what evidence — once that event fires — is sufficient to judge PASS or FAIL. Write both directly into the condition text; do not leave them implicit.

If the condition cannot state the second part — there is no describable evidence a firing of the chosen event would produce, only a hope that a relevant firing eventually occurs — do not assign `observation`. A condition that cannot state its own resolution path either accumulates SKIPPED notifications indefinitely (the event never fires in a way relevant to the condition) or, worse, is judged against evidence the verifier cannot actually observe.

**Alternatives, in order of preference:**
1. **Resolve now**: if the underlying fact is already knowable at merge time, verify it directly (a pre-merge condition, or an `auto`-type post-merge condition with its own verify command) instead of deferring it to a future event.
2. **Fall back to `auto`**: if a concrete, mechanically-checkable verify command exists for the condition once the relevant state exists, attach it and classify as `verify-type: auto` instead of `observation`.
3. **Drop the condition**: if the condition does not correspond to a resolvable gate at all, remove it from the Issue rather than leaving an unresolvable placeholder in `phase/verify`.

**Examples that fail the firing likelihood check** (cannot state evidence-on-fire): a condition assuming a specific downstream skill runs on a particular future `/auto` invocation (no guarantee it does), a condition awaiting "the next PR of a specific shape" (no guarantee the observation window sees one before it closes), a condition awaiting "the next Spec that touches a certain topic" (a Spec's subject matter is not itself an event `opportunistic-search.sh` can dispatch on).

### observation Type: Evidence Collection Patterns

Once an observation condition passes the Firing Likelihood Check above, the following four patterns are proven-effective evidence sources for actually resolving it — extracted from `/verify` Step 8c runs during the 2026-08-10〜11 `phase/verify` backlog batch (40 Issues, #1349). They are not exhaustive, and `/verify` Step 8c's own evidence collection list is not replaced by this table — treat these as concrete techniques to try first, alongside that list.

| Pattern | When to use | How |
|---------|-------------|-----|
| `git blame` + post-fix `session.md` cross-search | `session=next` conditions ("confirm the feature works correctly in the next session") | `git blame` the changed skill/module to confirm the fix landed, then `grep` `docs/sessions/*/session.md` reports generated after the fix for evidence the feature actually ran and behaved correctly (effective in #1304, #1300, #1289) |
| bats subset execution matching the condition's scenario | The condition text names a specific behavior with an existing or addable test case | Identify the bats test case whose name/scenario matches the condition wording and run it directly with `bats tests/foo.bats -f "test name"` (effective in #1307, #1318) |
| Direct grep against operational log files | The condition's evidence is a real-world occurrence pattern already recorded in an operational log | `grep` directly against `docs/reports/orchestration-recoveries.md`, `.tmp/auto-events.jsonl`, or similar operational logs to confirm the pattern actually occurred (effective in #984, #318) |
| On-the-fly lightweight live test construction | No natural occurrence can be waited for, but a minimal live test can be constructed on demand | Place a test handler at `.wholework/verify-commands/{name}.md` (or equivalent) to actually exercise the dispatch path being verified, rather than waiting for it to occur naturally (effective in #124) |

All four patterns remain best-effort: if no evidence surfaces via any of them, do not force a PASS verdict — keep the existing conservative judgment policy (UNCERTAIN or SKIPPED, per `/verify` Step 8c) rather than resolving on partial or absent evidence.

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

For Issues implemented via the patch route (direct commit to main, no PR) or the operate route (diff-less, external-tool operations only — see `modules/size-workflow-table.md` § "Diff-less Axis (operate route)"), `github_check "gh pr checks"` **cannot be used** — neither route produces a PR.

This note applies only when the Issue actually takes the patch or operate route. When `.wholework.yml` sets `always-pr: true`, Size XS/S is promoted to pr route (see `modules/size-workflow-table.md` § "ALWAYS_PR Override"), a PR does exist, and `github_check "gh pr checks"` is the correct form. Derive the route from `ALWAYS_PR` first, not from Size alone. The `always-pr: true` override does not apply to operate route — a Spec that meets the Diff-less Axis determination criteria resolves to operate route regardless of `always-pr`.

Use the `github_check "gh run list"` form instead:

```
github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"
```

When `/verify` detects `github_check "gh pr checks"` in an acceptance condition for a patch-route or operate-route Issue (PR_NUMBER is empty), it treats the condition as UNCERTAIN and recommends switching to the `gh run list` form.

**Note:** When converting from `github_check "gh pr checks" "JOB_NAME"`, also replace the `expected_value` from the job name to `"success"`. `gh run list` outputs a run-level table (STATUS / conclusion / TITLE / WORKFLOW / ...) and does not include job names — specifying a job name as `expected_value` will never match and will always FAIL even when CI is green.

**Why `--commit` is not used (run/commit correspondence via `head_sha`):** GitHub Actions creates a workflow run only for the commit at the *head* of a push (the run's `head_sha`) — not for every commit included in that push. Patch route sends `[implementation commit, retrospective commit]` in a single push, so the retrospective commit is always the push head and the only one with a `head_sha`-matched run; the implementation commit itself never has a run of its own. A form pinned to a literal fixed implementation-commit SHA (`--commit=<implementation commit SHA>`) therefore always returns an empty result and cannot be judged PASS/FAIL. The prior canonical form, which resolved `--commit=` via `git rev-parse HEAD`, is a distinct failure mode: it is evaluated at `/verify` execution time and resolves to whatever the base branch's HEAD is at that moment — typically the retrospective commit (the push head), which *does* have a `head_sha`-matched run — so it returns a non-empty but potentially unrelated commit's run, not an empty result. Neither form can verify this Issue's own implementation. Because the retrospective commit only touches the Spec file, the tree its run built is equivalent to the implementation's tree — referencing "the most recent run on the target branch" (`--branch=main --limit=1`, omitting `--commit`) is a valid substitute.

**Worktree HEAD pitfall (a further failure mode of the prior `--commit=` form):** `/verify` itself executes inside its own worktree (`verify/issue-$NUMBER`, see `modules/worktree-lifecycle.md`), not directly on `origin/<base>`. Because of this, `git rev-parse HEAD` evaluated during `/verify` resolves to the **worktree's own local HEAD** — which can be a commit that was never pushed at all (e.g., the local commit `append-consumed-comments-section.sh` creates in `/verify` Step 4, before that phase's own push) — not merely "whatever `origin/<base>`'s HEAD happens to be" as the paragraph above frames it. Such a commit has no CI run whatsoever, so a `--commit=` scoped via `git rev-parse HEAD` can return an empty result for a reason distinct from the head_sha mismatch already described. If a `--commit=`-scoped check is ever needed again, resolve the actual **pushed** HEAD SHA first — e.g. `git rev-parse origin/main` (or the equivalent for another base branch), not the worktree-local `git rev-parse HEAD` — and pass that literal SHA to `--commit=`. The simpler and recommended fix remains switching to the `--branch=main --limit=1` form above, which avoids commit resolution (and this worktree pitfall) entirely.

**Residual risk (defect A is not fully eliminated):** Even with `--branch=main --limit=1`, there is no guarantee that "the most recent run on the branch at the time `/verify` executes" is the run produced by this Issue's own push — this repository runs concurrent sessions as a matter of course, and another session's push to `main` after this Issue's push would become the new "most recent" run. When the referenced run's result looks inconsistent with this Issue's own change (e.g., `cancelled`, or a `failure` on a job unrelated to the Issue's Changed Files), treat the condition as UNCERTAIN rather than a mechanical PASS/FAIL and recommend re-running `/verify` — the same operational stance as the CI Reference Fallback (#1126), applied here as guidance rather than an automated check.

## Output

Assign the `<!-- verify-type: auto|opportunistic|manual -->` tag to the end of each post-merge condition. Place the tag one half-width space before the line break at the end of the condition text.
