---
name: auto
description: Autonomous execution (`/auto 123`). Runs spec (when needed)→code→review→merge→verify in sequence. XL Issues use sub-issue dependency graph with parallel execution. Size auto-detection with `--patch`/`--pr` and `--review=light`/`--review=full` overrides. Issues without `phase/*` labels start from issue triage. `--batch N` processes N backlog XS/S Issues; `--batch N1 N2 ...` processes the explicitly listed Issues in order.
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*, gh issue view:*, gh issue list:*, gh issue close:*, gh issue comment:*, gh pr list:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-review.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-merge.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-verify.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-sub-issue-graph.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-spec.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-issue.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/detect-wrapper-anomaly.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/validate-recovery-plan.sh:*), Read, Grep, Write, Task, TaskCreate, TaskUpdate, TaskList, TaskGet
---

# Autonomous Execution

Receive an Issue number and run spec (when needed)→code→review→merge→verify in sequence using Size-based routing. Each phase runs via `run-*.sh` using `claude -p --dangerously-skip-permissions` for a fresh context with full permission bypass.

If ARGUMENTS contains `--help`, Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and follow the "Processing Steps" section to output help, then stop.

## Route-Phase Matrix

| Route | Target Size | Phase sequence |
|--------|----------|-------------|
| patch (XS/S) | XS, S | `spec (when needed) → code(--patch) → verify` |
| pr (M) | M | `spec (when needed) → code → review(--light) → merge → verify` |
| pr (L) | L | `spec (when needed) → code → review(--full) → merge → verify` |
| XL | XL | Sub-issue dependency graph with parallel execution (spec auto-runs per sub-issue) |

- **Size not set**: default to pr route (safe fallback since AskUserQuestion is unavailable in non-interactive mode)

## Steps

### Step 1: Extract Issue Number

Extract the Issue number from ARGUMENTS. Examples: `ARGUMENTS = "279"` → `NUMBER = 279`; `ARGUMENTS = "279 --patch"` → `NUMBER = 279, ROUTE_FLAG = --patch`

If `--batch` flag is present: collect all consecutive numeric tokens following `--batch`, stopping at any non-numeric token or ARGUMENTS end.

- If exactly 1 numeric token collected (e.g., `ARGUMENTS = "--batch 5"`): record `BATCH_SIZE = 5` (Count mode) and branch to `### Count mode (--batch N)` in the "Batch Mode (--batch)" section (**skip Steps 2–6**)
- If 2 or more numeric tokens collected (e.g., `ARGUMENTS = "--batch 123 124 125"`): record `BATCH_LIST = [123, 124, 125]` (List mode) and branch to `### List mode (--batch N1 N2 ...)` in the "Batch Mode (--batch)" section (**skip Steps 2–6**)

No Issue number needed for batch mode.

Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` and display the start banner with ENTITY_TYPE="issue", ENTITY_NUMBER=$NUMBER, SKILL_NAME="auto".

### Step 2: Route Detection and Base Branch

Detect `--patch`/`--pr`, `--review=full`/`--review=light`, and `--base {branch}` flags from ARGUMENTS.

If `--base {branch}` is present, record as `BASE_BRANCH`. If `--base` is not specified, default to `BASE_BRANCH=main`.

| Flag | Route | Phase sequence |
|--------|--------|-------------|
| `--patch` | patch | `code(--patch) → verify` |
| `--pr` | pr | `code → review → merge → verify` |
| `--pr --review=full` | pr | `code → review(--full) → merge → verify` |
| `--pr --review=light` | pr | `code → review(--light) → merge → verify` |
| `--base {branch}` | (no route change) | Specify base branch; propagates to all phases |
| none | auto-detect | Determine route from Size label |

If no flags, fetch Size to auto-detect route:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh "$NUMBER" 2>/dev/null
```

### Step 3: `phase/ready` Label Check

Fetch labels with `gh issue view $NUMBER --json labels -q '.labels[].name'` and branch based on label state:

- **`phase/ready` label present**: proceed to the next step
- **`phase/issue` label present (no `phase/ready`)**:
  - **Size is XS**: Spec not needed — skip spec and proceed to Step 4
  - Size is `L`: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-spec.sh $NUMBER --opus` (run spec with Opus model)
  - Size is neither XS nor L: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-spec.sh $NUMBER`
  - On spec success, proceed to Step 4
  - On spec failure, go to Step 6 (error report)
- **No `phase/*` labels** (issue triage not done):
  - Run `${CLAUDE_PLUGIN_ROOT}/scripts/run-issue.sh $NUMBER` (issue triage → Size setting/requirement shaping)
  - After success, re-fetch Size (`${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`). Update route if Size is now set.
  - Re-fetch labels: `gh issue view $NUMBER --json labels -q '.labels[].name'`
  - If re-fetched labels have **`phase/ready`**: proceed to Step 4
  - If re-fetched labels have **`phase/issue` (no `phase/ready`)**:
    - **Size is XS**: skip spec, proceed to Step 4
    - Size is `L`: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-spec.sh $NUMBER --opus`
    - Size is neither XS nor L: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-spec.sh $NUMBER`
    - On spec success, proceed to Step 4
    - On spec failure, go to Step 6 (error report)
  - If expected `phase/*` label state is not reached after re-fetch, go to Step 6 (error report)
  - On issue failure, go to Step 6 (error report)

### Step 4: Autonomous Execution (run-*.sh)

Run each phase via `run-*.sh`. Each script launches an independent process with `claude -p --dangerously-skip-permissions` for a fresh context and full permission bypass.

**Execution pattern:**
- Each `run-*.sh` runs as a blocking call (`timeout: 600000`) in sequence
- PR number extraction is run by the parent session with `gh pr list` (included in `allowed-tools`)

---

**XL route: sub-issue dependency graph with parallel execution (`run-auto-sub.sh` checks each sub-issue's `phase/ready` and auto-runs spec if not set):**

1. **Fetch dependency graph**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/get-sub-issue-graph.sh $NUMBER
   ```
   Parse the result JSON and extract `execution_order` (array of sub-issue numbers per level).

2. **Run levels in order, in parallel**: Process each level in `execution_order` sequentially.

   Run each level's sub-issues in parallel via Bash background (`&`), then wait for all to complete:
   ```
   # For each level (in execution_order order):
   Skip sub-issues that depend on failed issues,
   then run non-skipped sub-issues in background:
     ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $SUB_NUMBER &
   Wait for all processes with `wait`, check each process exit code
   ```

   **After `wait` completes, aggregate-update parent phase** (run after each level completes):
   1. Fetch each sub-issue's current phase label with `gh issue view $SUB_NUMBER --json labels`
   2. Determine parent phase based on aggregation rules:
      - 1+ children at `phase/code` or later (code/review/verify/done) → parent becomes `phase/code`
      - All children at `phase/verify` or later (verify/done) → parent becomes `phase/verify`
      - All children at `phase/done` → handled by close flow judgment (Step 4c); do not aggregate-update here
   3. Update parent with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER <aggregated phase>`

   **After aggregate-update, cross-cutting condition pre-verification (best-effort)**:
   When a level completes, proactively check the parent XL Issue's cross-cutting Acceptance Criteria:
   1. Fetch parent Issue body: `gh issue view $NUMBER --json body -q '.body'`
   2. Extract `<!-- verify: ... -->` commands from the Acceptance Criteria sections (pre-merge and post-merge)
   3. Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md` and execute each verify command in full mode
   4. For each FAIL result: output a warning and continue (best-effort cross-cutting condition detection)
      Format: "Warning: cross-cutting condition failed: [condition text]. Run `/verify $NUMBER` to confirm."
   5. Continue to the next level regardless of results (authoritative verification is done by `/verify $NUMBER`)

3. **On failure**:
   - Add failed sub-issue numbers to the failure set
   - In subsequent levels, skip sub-issues that depend on (have `blocked_by` containing) a number in the failure set
   - Continue processing sub-issues that do not depend on failed issues
   - To determine skip: check `blocked_by` in `get-sub-issue-graph.sh` output and mark any sub-issue containing a failed Issue number as skip target

4. **Completion report**: After all levels complete, report results (success/failure/skip) for each sub-issue.

5. **Auto retrospective**: See "Step 4a: Auto Retrospective" section.

---

**patch route XS/S (2 phases):**

Each phase follows the Observe → Diagnose → Act pattern (same as pr route; see above).

1. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-patch $NUMBER --check-precondition --warn-only`
2. code phase: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh $NUMBER --patch [--base {branch}]` via Bash (timeout: 600000)
3. If code fails: completion check `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-patch $NUMBER --check-completion` — if `matches_expected: true`, override to success; otherwise go to Step 6
4. **XS only**: transcribe issue retrospective to Spec (see Step 4b)
5. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh verify $NUMBER --check-precondition --warn-only`
6. verify phase: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-verify.sh $NUMBER [--base ${BASE_BRANCH}]` via Bash (timeout: 600000)
7. Based on verify result, proceed to Step 5 or Step 6
   - If verify output contains `MAX_ITERATIONS_REACHED`: max iterations has been reached; stop chained execution and proceed to Step 5 (human judgment required — do not re-run verify automatically)

**pr route (4 phases):**

Phase transition output format: output `[N/M] phase_name` before each phase, and `[N/M] phase_name → done (details)` after success. Example:
```
[1/4] code
(run-code.sh output)
[1/4] code → done (PR #125)
[2/4] review
...
```

Each phase follows the Observe → Diagnose → Act pattern:
1. **Observe (precondition)**: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh <phase> <issue> --check-precondition --warn-only` — mismatch outputs a stderr warning but does not block execution (stage-1 gradual rollout)
2. **Act**: run `<run-*.sh>`
3. **Diagnose (completion)**: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh <phase> <issue> --check-completion`; parse JSON output — if `matches_expected: true`, continue; if `matches_expected: false`, treat as mismatch and go to Step 6

Full phase sequence:

1. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-pr $NUMBER --check-precondition --warn-only`
2. Output `[1/4] code`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh $NUMBER --pr [--base {branch}]` via Bash (timeout: 600000); on success output `[1/4] code → done (PR #N)`
3. If code fails: completion check `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-pr $NUMBER --check-completion` — if `matches_expected: true`, override to success and continue; otherwise go to Step 6
4. Extract PR number via exact-match filter (matches SSoT branch name worktree-code+issue-N established by #310): `gh pr list --json number,headRefName | jq -r ".[] | select(.headRefName == \"worktree-code+issue-$NUMBER\") | .number" | head -1`
5. If PR number cannot be fetched: report error and go to Step 6
6. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh review $NUMBER --pr $PR_NUMBER --check-precondition --warn-only`
7. Output `[2/4] review`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/run-review.sh $PR_NUMBER [--light|--full]` via Bash (timeout: 600000) (M→`--light`, L→`--full`); on success output `[2/4] review → done`
8. If review fails: completion check `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh review $NUMBER --pr $PR_NUMBER --check-completion` — if `matches_expected: true`, override to success; otherwise go to Step 6
9. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh merge $NUMBER --pr $PR_NUMBER --check-precondition --warn-only`
10. Output `[3/4] merge`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/run-merge.sh $PR_NUMBER` via Bash (timeout: 600000); on success output `[3/4] merge → done`
11. If merge fails: completion check `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh merge $NUMBER --pr $PR_NUMBER --check-completion` — if `matches_expected: true`, override to success; otherwise go to Step 6
12. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh verify $NUMBER --check-precondition --warn-only`
13. Output `[4/4] verify`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/run-verify.sh $NUMBER [--base ${BASE_BRANCH}]` via Bash (timeout: 600000); on success output `[4/4] verify → done`
14. Based on verify result, proceed to Step 5 or Step 6
    - If verify output contains `MAX_ITERATIONS_REACHED`: max iterations has been reached; stop chained execution and proceed to Step 5 (human judgment required — do not re-run verify automatically)

### Step 4b: Issue Retrospective Transcription (XS patch route only)

**Skip this step for all routes other than XS patch.**

The XS patch route does not go through the `/spec` phase, so no Spec file exists. To allow the `/verify` improvement proposal pipeline to collect the issue retrospective, create a Spec file and transcribe it using the following steps.

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `SPEC_PATH` for use in subsequent steps.

1. **Check for issue retrospective in Issue comments**:
   - Fetch all Issue comments: `gh issue view "$NUMBER" --json comments -q '.comments[].body'`
   - Search for comments containing a `## Issue Retrospective` section
   - If not found: skip this entire step (no transcription needed if no issue retrospective)

2. **Determine Spec file path**: `$SPEC_PATH/issue-$NUMBER-<short-title>.md`
   - Generate `short-title` as English kebab-case from Issue title (e.g., `xs-patch-retro`)
   - If an existing Spec file is found, use it

3. **Create (or update) Spec file and append issue retrospective**:
   - For new files: include a `# Issue #$NUMBER: $TITLE` heading at the top
   - Append `## Issue Retrospective` section at the end of the Spec file (naturally referenced by `/verify`'s Spec reading)

4. **Commit and push**:
   ```bash
   git add $SPEC_PATH/issue-$NUMBER-*.md
   git commit -s -m "Add issue retrospective for issue #$NUMBER

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
   git push origin main
   ```

### Step 4a: Auto Retrospective

**Conditions to run this step:**

- **XL route**: always run — record orchestration results for all sub-issues
- **M/L/patch route**: run only when the parent session detects **any** of the following orchestration anomalies; skip if no anomalies are detected:
  - (a) A shell wrapper (`run-code.sh`, `run-auto-sub.sh`, etc.) exited non-zero, but subsequent state was manually recovered
  - (b) A phase that should have transitioned automatically was manually invoked by the parent session
  - (c) `/auto` completed with behavior that differs from the original spec

If no anomalies are detected (M/L/patch route), skip this step — do not record an empty section.

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `SPEC_PATH` for use in subsequent steps.

1. **Determine Spec file path**: `$SPEC_PATH/issue-$NUMBER-<short-title>.md`
   - Generate `short-title` as English kebab-case from Issue title (e.g., `xl-orchestration-retrospective`)
   - If an existing Spec file is found, use it and append `## Auto Retrospective` section
   - **If Spec file does not exist** (e.g., XS patch route without spec phase): create a new Spec file with `# Issue #$NUMBER: $TITLE` header, then append `## Auto Retrospective` section

2. **Create (or update) Spec file**:

   **XL route** — record full sub-issue summary:
   ```markdown
   # Issue #$NUMBER: $TITLE

   ## Auto Retrospective

   ### Execution Summary
   | # | Title | Route | Result | Notes |
   |---|-------|--------|--------|-------|
   (list result for each sub-issue)

   ### Parallel Execution Issues
   - (conflicts, race conditions, recovery history. "None" if no issues)

   ### Improvement Proposals
   - (structural issues and fixes. "N/A" if no proposals)
   ```
   - **Result column criteria**: exit code 0 → `SUCCESS`, non-zero exit code → `FAILED (exit code N)`, dependency skip → `SKIPPED (blocked by #X)`
   - **Improvement proposal guidance**: document structural issues from parallel execution (conflicts, PR extraction failures, verify chain FAILs, etc.) and their fixes. `/verify`'s Step 13 reads `### Improvement Proposals` and creates Issues from them

   **M/L/patch route** — append orchestration anomaly record (append to existing Spec; create new Spec with header if none exists):
   ```markdown
   ## Auto Retrospective

   ### Execution Summary
   | Phase | Route | Result | Notes |
   |-------|-------|--------|-------|
   | code  | pr    | SUCCESS (manual PR extract fallback) | run-auto-sub.sh exit 1 but PR #N already created |
   | review | pr   | SUCCESS | manual invocation after wrapper failure |
   | merge | pr    | SUCCESS | manual invocation |
   | verify | -    | SUCCESS | |

   ### Orchestration Anomalies
   - (describe each anomaly: which script, what exit code, what state, how manually recovered)

   ### Improvement Proposals
   - (list structural improvements to prevent recurrence. "N/A" if none)
   ```

3. **Fetch issue retrospective from Issue comments and transcribe to Spec** (XL route only):
   - Fetch all Issue comments: `gh issue view "$NUMBER" --json comments -q '.comments[].body'`
   - Search for comments containing `## Issue Retrospective`
   - If found: append `## Issue Retrospective` section at end of Spec file (naturally referenced by `/verify`'s Spec reading)
   - If not found: skip (XL Issues not going through `/issue` may not have this)

4. **Commit and push**:
   ```bash
   git add $SPEC_PATH/issue-$NUMBER-*.md
   git commit -s -m "Add auto retrospective for issue #$NUMBER

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
   git push origin main
   ```

### Step 4c: XL Parent Issue Close Flow (XL route only)

**Skip this step for all routes other than XL.**

Determine the close flow for the parent Issue based on all sub-issue execution results.

1. **Confirm all sub-issues succeeded (`phase/done`)**:
   - If any sub-issue failed or was skipped: skip close flow and leave parent phase as-is (do not close)

2. **If all children are `phase/done`**: check for unchecked (`- [ ]`) conditions in the post-merge section of the parent Issue body:
   - Fetch post-merge section with `gh issue view $NUMBER --json body`
   - Check if any unchecked `- [ ]` conditions remain

3. **No unchecked cross-cutting conditions**: auto-close the parent:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER done
   gh issue close $NUMBER
   ```

4. **Unchecked cross-cutting conditions remain**: transition to `phase/verify` and post a notification comment:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER verify
   gh issue comment $NUMBER --body "All sub-issues are complete. The parent Issue has remaining manual acceptance conditions. Run \`/verify $NUMBER\` after reviewing."
   ```
   Leave the parent Issue open. The user runs `/verify $NUMBER` for final confirmation before closing.

### Step 5: Completion Report

If all phases succeeded, output the completion banner:
```
/auto #N complete
TITLE
URL
```
Followed by a result table (one row per phase with status).

**For XL routes, also output "Auto retrospective recorded in Spec".**

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=auto`
- `ISSUE_NUMBER=$NUMBER`
- `RESULT=success`

### Step 6: On Failure: 3-Tier Recovery

If any phase exits with a non-zero exit code, apply the following 3-tier recovery hierarchy before stopping.

**Always first**: Write the failed phase's output to `.tmp/wrapper-out-$NUMBER-$PHASE.log` using the Write tool (needed by Tier 2 anomaly detector).

---

#### Tier 1 (Observe): State Reconciliation

Run the completion check for the failed phase:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh <phase> $NUMBER --check-completion
```

Parse the JSON output. If `matches_expected: true`: the phase actually succeeded despite wrapper exit non-zero — override to success and continue to the next phase (skip Tier 2 and Tier 3).

If `matches_expected: false`: proceed to Tier 2.

---

#### Tier 2 (Known pattern): Anomaly Detector + Fallback Catalog

Run the anomaly detector:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/detect-wrapper-anomaly.sh --log .tmp/wrapper-out-$NUMBER-$PHASE.log --exit-code $EXIT_CODE --issue $NUMBER --phase $PHASE
```

If detector output is non-empty (known pattern matched):
- Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` to get `SPEC_PATH`
- Append the detector output to the Spec file (`$SPEC_PATH/issue-$NUMBER-*.md`) under `## Auto Retrospective`, and commit and push
- Read `${CLAUDE_PLUGIN_ROOT}/modules/orchestration-fallbacks.md` and follow the catalog entry matching the detected pattern to apply the recovery steps
- If the catalog's recovery succeeds, continue to the next phase (skip Tier 3)
- If the catalog's recovery fails, proceed to Tier 3

If detector output is empty (unknown pattern): proceed to Tier 3.

---

#### Tier 3 (Unknown): Recovery Sub-Agent

Spawn the orchestration-recovery sub-agent via Task to diagnose the unknown failure and produce a recovery plan:

1. Collect inputs:
   - `phase`: the failed phase name (e.g., `code-pr`, `review`, `merge`, `verify`)
   - `exit_code`: wrapper exit code
   - `log_tail`: last 200 lines of `.tmp/wrapper-out-$NUMBER-$PHASE.log`
   - `reconcile_snapshot`: JSON output from the Tier 1 `reconcile-phase-state.sh --check-completion` call
   - `issue_number`: `$NUMBER`
   - `issue_labels`: output of `gh issue view $NUMBER --json labels -q '.labels[].name'`
   - `pr_number`: `$PR_NUMBER` if available, otherwise empty string
   - `branch`: current worktree branch if available

2. Spawn the sub-agent:
   ```
   Task: agents/orchestration-recovery.md
   Prompt: (pass all inputs from step 1)
   ```

3. Write the sub-agent's output (the raw JSON) to `.tmp/recovery-plan-$NUMBER-$PHASE.json` using the Write tool.

4. **Safety guard** — validate the recovery plan:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/validate-recovery-plan.sh .tmp/recovery-plan-$NUMBER-$PHASE.json
   ```
   - Validation checks: JSON parseable, required keys (`action`, `rationale`, `steps`) present, `action` in `{retry, skip, recover, abort}`, `steps` length ≤ 5, no forbidden ops (`force_push`, `reset_hard`, `close_issue`, `merge_pr`, `direct_push_main`)
   - If validation fails (exit non-zero): fall back to stop-and-report (see below)

5. **Dispatch on action**:
   - `action=retry`: re-run the failed phase once (same `run-*.sh` call with same arguments); if it fails again, fall back to stop-and-report
   - `action=skip`: treat the phase as complete and continue to the next phase
   - `action=recover`: execute `steps` sequentially; if all steps succeed, continue to the next phase; if any step fails, fall back to stop-and-report
   - `action=abort`: fall back to stop-and-report immediately

6. Clean up: `rm -f .tmp/recovery-plan-$NUMBER-$PHASE.json .tmp/wrapper-out-$NUMBER-$PHASE.log`

---

#### Stop-and-Report Fallback

If all tiers are exhausted without recovery, stop processing and output the stopped banner:
```
/auto #N stopped at PHASE
TITLE
URL
```
Followed by a result table (one row per phase; use `-` for unexecuted phases).

Do not invoke subsequent phases.

- code phase failure: error in branch creation, implementation, tests, or PR creation
- review phase failure: review wait timeout, fix failure, retry limit reached
- merge phase failure: invalid PR state (not approved, CI failure), conflict resolution failure
- verify phase failure: acceptance condition FAIL, Issue reopened

**Manual recovery hand-off**: If the parent session manually recovers and continues to subsequent phases instead of stopping here, complete the remaining phases via manual recovery first, then follow Step 4a (after all phases are done) to append anomaly details and improvement proposals to the Spec's `## Auto Retrospective > ### Orchestration Anomalies` and `### Improvement Proposals` sections, then proceed to Step 5. Note: if the Tier 2 anomaly detector already appended a known pattern, skip the `### Orchestration Anomalies` / `### Improvement Proposals` append in Step 4a to avoid duplicate entries.

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=auto`
- `ISSUE_NUMBER=$NUMBER`
- `RESULT=fail`

## Batch Mode (--batch)

When `--batch` is detected in Step 1, process Issues sequentially (skip Steps 2–6).

Two modes:
- **Count mode** (`--batch N`): selects the N most recent XS/S Issues from the backlog
- **List mode** (`--batch N1 N2 ...`): processes the explicitly listed Issues in the user-specified order (任意の Issue 番号を空白区切りで指定)

### Count mode (--batch N)

既存の `--batch N` の挙動は変更せず後方互換で維持する。

#### Fetch Batch Candidates

```bash
gh issue list --state open --label triaged --json number,title,labels,createdAt --limit 200
```

#### Filtering criteria

For each candidate, call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`;
exclude Issues where Size is M, L, or XL (Projects V2 field first, label fallback).

Sort by `createdAt` descending (newest first) and select the top N. Targets: Issues with no Size set, XS, or S.

#### Process Each Issue

Process the selected N Issues **sequentially** (serially):

1. Check Issue labels: `gh issue view $NUMBER --json labels -q '.labels[].name'`
2. **If no `phase/*` labels**: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-issue.sh $NUMBER` (issue triage → Size setting → `phase/ready` assignment)
   - On failure: output a warning and skip to the next Issue (do not abort the entire batch)
3. Re-check Size: call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`; if Size is M, L, or XL: output a warning and skip to the next Issue (do not abort the entire batch)
4. Run `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $NUMBER` (all phases spec→code→review→merge→verify, auto-starting from the current `phase/*` state)
   - On failure: output a warning and skip to the next Issue (do not abort the entire batch)

### List mode (--batch N1 N2 ...)

`BATCH_LIST` に記録された Issue 番号を、ユーザが渡した順序（指定順）で順次処理する（並び替えなし）。

候補取得（Fetch Batch Candidates）および `createdAt` ソートは List mode では行わない。

許容 Size: XS/S/M/L。ユーザが明示指定した以上、その意思は heuristic より強いシグナルのため Size 制限を緩和する。XL のみ例外で、警告を出して当該 Issue を skip し、残りの Issue は継続処理する（XL はサブ Issue 依存グラフによる並列実行経路を持ち、batch の直列処理と噛み合わないため）。

Process each Issue in `BATCH_LIST` in order:

1. Check Issue labels: `gh issue view $NUMBER --json labels -q '.labels[].name'`
2. **If no `phase/*` labels**: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-issue.sh $NUMBER` (issue triage → Size setting → `phase/ready` assignment)
   - On failure: output a warning and skip to the next Issue (do not abort the entire batch)
3. Re-check Size: call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`; if Size is XL: output a warning and skip to the next Issue (do not abort the entire batch)
4. Run `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $NUMBER` (all phases spec→code→review→merge→verify, auto-starting from the current `phase/*` state)
   - On failure: output a warning and skip to the next Issue (do not abort the entire batch)

### Batch Completion Report

After all Issues are processed, report results (success/skip/failure) for each Issue.

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=auto`
- `RESULT=success`
- (omit `ISSUE_NUMBER` — batch run with multiple issues, guide will be omitted per module logic)

## Notes

- Run after `/issue` is complete (spec is auto-run if not yet complete)
- Detailed logic for each phase (review comment handling, conflict resolution, etc.) is delegated to each skill
- `auto` itself does not post Issue comments (posted individually within each phase)
- Skills are installed via the plugin marketplace and referenced through `${CLAUDE_PLUGIN_ROOT}` at runtime
