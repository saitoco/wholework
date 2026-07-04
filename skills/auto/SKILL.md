---
name: auto
description: Autonomous execution (`/auto 123`). Runs spec (when needed)→code→review→merge→verify in sequence. XL Issues use sub-issue dependency graph with parallel execution. Size auto-detection with `--patch`/`--pr` and `--review=light`/`--review=full` overrides. Issues without `phase/*` labels start from issue triage. `--batch N` processes N backlog XS/S Issues; `--batch N1 N2 ...` processes the explicitly listed Issues in order (assigns a BATCH_ID for parallel-safe checkpointing). `--resume N` resumes a single Issue (restores verify counter from checkpoint); `--batch --resume` resumes an interrupted batch using `list_active_batches` to identify the target session.
loop-paths-used: [A, E]
loop-paths-fallback: [A]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*, gh issue view:*, gh issue list:*, gh issue close:*, gh issue comment:*, gh issue create:*, gh pr list:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-review.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-merge.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-sub-issue-graph.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-spec.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-issue.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/detect-wrapper-anomaly.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/validate-recovery-plan.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-auto-session-report.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/check-session-findings-disposition.sh:*), Read, Edit, Glob, Grep, Write, Skill, Task, TaskCreate, TaskUpdate, TaskList, TaskGet
---

# Autonomous Execution

Receive an Issue number and run spec (when needed)→code→review→merge→verify in sequence using Size-based routing. code/review/merge phases run via `run-*.sh` using `claude -p --dangerously-skip-permissions` for a fresh context with full permission bypass. verify runs as a Skill invocation in the parent session (enabling AskUserQuestion for manual AC confirmation).

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

**AUTO_SESSION_ID generation (run before all route detection):**

Generate a session identifier and record it in a PGID-specific pointer file so sub-processes spawned by `run-auto-sub.sh` can read it:

**Session boundary isolation design**: Each `/auto` session uses its process group ID (PGID) as part of the pointer file name (`.tmp/auto-session-${PGID}`). This prevents parallel `/auto` sessions from overwriting each other's pointer file — each session's sub-processes (run-auto-sub.sh, run-code.sh, run-review.sh, run-merge.sh) share the same PGID as their parent, so they naturally read the correct session_id without cross-session contamination.

1. Generate `SESSION_ID` and create the PGID-specific pointer file:
   ```bash
   mkdir -p .tmp
   SESSION_ID="$$-$(date +%s)"
   PGID=$(ps -o pgid= -p $$ | tr -d ' ')
   printf '%s\n' "$SESSION_ID" > ".tmp/auto-session-${PGID}"
   ```
2. Collect skill commit hashes for 8 major skills before writing the session metadata file (bash 3.2+ compatible; empty string on failure):
   ```bash
   SKILL_AUTO_HASH=$(git log -1 --format=%H -- skills/auto/SKILL.md 2>/dev/null || echo "")
   SKILL_CODE_HASH=$(git log -1 --format=%H -- skills/code/SKILL.md 2>/dev/null || echo "")
   SKILL_SPEC_HASH=$(git log -1 --format=%H -- skills/spec/SKILL.md 2>/dev/null || echo "")
   SKILL_VERIFY_HASH=$(git log -1 --format=%H -- skills/verify/SKILL.md 2>/dev/null || echo "")
   SKILL_REVIEW_HASH=$(git log -1 --format=%H -- skills/review/SKILL.md 2>/dev/null || echo "")
   SKILL_MERGE_HASH=$(git log -1 --format=%H -- skills/merge/SKILL.md 2>/dev/null || echo "")
   SKILL_ISSUE_HASH=$(git log -1 --format=%H -- skills/issue/SKILL.md 2>/dev/null || echo "")
   SKILL_AUDIT_HASH=$(git log -1 --format=%H -- skills/audit/SKILL.md 2>/dev/null || echo "")
   ```
3. Write `.tmp/auto-session-${SESSION_ID}.json` using the Write tool with session metadata including `skill_versions`:
   ```json
   {
     "session_id": "<SESSION_ID>",
     "session_start": "<current UTC timestamp in ISO8601>",
     "skill_versions": {
       "skills/auto/SKILL.md": "<SKILL_AUTO_HASH>",
       "skills/code/SKILL.md": "<SKILL_CODE_HASH>",
       "skills/spec/SKILL.md": "<SKILL_SPEC_HASH>",
       "skills/verify/SKILL.md": "<SKILL_VERIFY_HASH>",
       "skills/review/SKILL.md": "<SKILL_REVIEW_HASH>",
       "skills/merge/SKILL.md": "<SKILL_MERGE_HASH>",
       "skills/issue/SKILL.md": "<SKILL_ISSUE_HASH>",
       "skills/audit/SKILL.md": "<SKILL_AUDIT_HASH>"
     }
   }
   ```
   Substitute the actual `SESSION_ID`, current UTC timestamp, and skill hash values before writing.
4. Set `AUTO_SESSION_ID="$SESSION_ID"` in the current Bash context (does not persist across separate Bash tool calls; sub-processes read from the pointer file instead):
   ```bash
   export AUTO_SESSION_ID="$SESSION_ID"
   ```

**Pointer file regeneration required before every `run-*.sh` / `run-auto-sub.sh` call**: Each Bash tool call spawns a brand-new process group, so its PGID differs from the PGID used when the pointer file was first written in step 1 above. The pointer file at `.tmp/auto-session-${PGID}` is therefore valid only for the Bash tool call that created it — it is **not** a one-time setup step. Because `SESSION_ID` does not persist as a shell variable across separate Bash tool calls (see step 4 above), the literal `SESSION_ID` string recorded in step 1 must be substituted directly into the command. Immediately before every subsequent Bash tool call that invokes `run-code.sh`, `run-review.sh`, `run-merge.sh`, or `run-auto-sub.sh`, recompute the current PGID and rewrite (再生成) the pointer file in that same Bash call, e.g.:
```bash
mkdir -p .tmp
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
printf '%s\n' "<literal SESSION_ID value from step 1>" > ".tmp/auto-session-${PGID}"
${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh $NUMBER --patch
```
Skipping this pointer file re-generation (再生成) means the sub-process reads an empty `AUTO_SESSION_ID`, and the emitted event's `session_id` field is dropped — degrading event aggregation and L3 session-retrospective boundary detection.

**`--resume` detection (single-Issue resume):**

If ARGUMENTS contains `--resume` but NOT `--batch`: record `RESUME_MODE=true` and extract the numeric token following `--resume` as `NUMBER`. Output a log line: "Resume mode: restoring checkpoint for issue #$NUMBER". Proceed to Step 2 as normal (checkpoint restoration happens in Step 4 before the verify loop).

**`--batch` detection:**

If `--batch` flag is present:

- If `--resume` is present AND no numeric tokens follow `--batch` (i.e., `ARGUMENTS = "--batch --resume"` or similar with no numbers after `--batch`): record `RESUME_BATCH=true` and branch to `### Resume mode (--batch --resume)` in the "Batch Mode (--batch)" section (**skip Steps 2–6**)
- Else: collect all consecutive numeric tokens following `--batch`, stopping at any non-numeric token or ARGUMENTS end.
  - If exactly 1 numeric token collected (e.g., `ARGUMENTS = "--batch 5"`): record `BATCH_SIZE = 5` (Count mode) and branch to `### Count mode (--batch N)` in the "Batch Mode (--batch)" section (**skip Steps 2–6**)
  - If 2 or more numeric tokens collected (e.g., `ARGUMENTS = "--batch 123 124 125"`): record `BATCH_LIST = [123, 124, 125]` (List mode) and branch to `### List mode (--batch N1 N2 ...)` in the "Batch Mode (--batch)" section (**skip Steps 2–6**)

No Issue number needed for batch mode.

Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` and display the start banner with ENTITY_TYPE="issue", ENTITY_NUMBER=$NUMBER, SKILL_NAME="auto".

### Step 2: Route Detection and Base Branch

**Load project config and stop-at settings (run before flag detection):**

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `AUTO_STOP_AT` and `ALWAYS_PR` for use in route detection and phase execution below.

Parse the `--stop-at=<phase>` flag from ARGUMENTS (per-invocation override):
- If `--stop-at=<phase>` is present, extract the phase value (valid values: `spec`, `code`, `review`, `merge`, `verify`)
- `EFFECTIVE_STOP_AT` priority: `--stop-at` flag > `AUTO_STOP_AT` config > default `"verify"`
- If the extracted phase is not one of the valid values, ignore the flag and use the next priority value
- Record `EFFECTIVE_STOP_AT` for use in Step 4 stop-at checks

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

**ALWAYS_PR promotion (apply after flag detection and before Size auto-detection):**

If `ALWAYS_PR=true`:
- If ROUTE was set to `patch` (via `--patch` flag or Size XS/S auto-detect): output "Warning: always-pr: true is set in .wholework.yml. Promoting to pr route." and set ROUTE to `pr`
- If ROUTE was set to `pr` (via `--pr` flag): no change

If no flags, fetch Size to auto-detect route:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh "$NUMBER" 2>/dev/null
```

Set `REVIEW_DEPTH` from flags or Size (used unchanged in Step 4 unless Step 3a refreshes it):

| Condition | REVIEW_DEPTH |
|---|---|
| `--review=full` flag present | `--full` |
| `--review=light` flag present | `--light` |
| `--patch` flag present | (not applicable — patch route) |
| Auto-detect or `--pr` without `--review=...`: Size M | `--light` |
| Auto-detect or `--pr` without `--review=...`: Size L | `--full` |
| Auto-detect or `--pr` without `--review=...`: other/unset | `--light` (safe fallback) |

### Step 2a: Fix-cycle Detection

Before checking the phase label in Step 3, detect whether the Issue is in a **fix-cycle state** — a condition where `/verify` has already run and flagged a FAIL (or the Issue was reopened after merge), phase labels were cleared by `/verify`, and a Spec already exists. In this state, re-running issue/spec phases is unnecessary and risks overwriting the existing Spec.

**Detection criteria (all three must hold):**

1. **verify-fail marker exists OR Issue has been reopened after the most recent merge**:
   - **verify-fail marker check**: At least one Issue comment contains `<!-- wholework-event: type=verify-fail` in its body.
     ```bash
     gh issue view "$NUMBER" --json comments \
       --jq '[.comments[] | select(.body | contains("<!-- wholework-event: type=verify-fail"))] | length > 0'
     ```
     Use the most recent such comment (`createdAt` descending) as the FAIL event reference.
   - **OR reopened check**: `gh-graphql.sh --query get-last-reopen -F "num=$NUMBER"` returns a non-null timestamp AND that timestamp is after the last merge commit timestamp (`reopen_ts > last_merge_ts`).
     ```bash
     reopen_ts=$("${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh" --query get-last-reopen \
       -F "num=$NUMBER" \
       --jq '.data.repository.issue.timelineItems.nodes[0].createdAt' 2>/dev/null \
       | tr -d '"' || true)
     # Cross-check: only count as "reopened after merge" if a merge commit exists before the reopen
     if [[ -n "$reopen_ts" && "$reopen_ts" != "null" ]]; then
       last_merge_ts=$(git log -1 --format=%cI --grep="closes #${NUMBER}" origin/main 2>/dev/null \
         | tr -d '"' || true)
       if [[ -z "$last_merge_ts" || ! "$reopen_ts" > "$last_merge_ts" ]]; then
         reopen_ts=""
       fi
     fi
     ```
     `reopen_ts > last_merge_ts` の場合のみ criterion 1 (reopened) を満たす。
     merge commit が存在しない場合 (`last_merge_ts` が空) や reopen が merge より前の場合は criterion 1 不満足。
   - Either condition satisfying is sufficient for criterion 1.

2. **No `phase/code`, `phase/review`, or `phase/spec` labels present**: The Issue has no label matching `phase/code`, `phase/review`, or `phase/spec`. (`phase/verify` is permitted — it may be left over from a previous verify run on a reopened Issue.)
   ```bash
   gh issue view "$NUMBER" --json labels \
     --jq '[.labels[].name | select(. == "phase/code" or . == "phase/review" or . == "phase/spec")] | length == 0'
   ```

3. **Spec file exists**: At least one Spec file matches `$SPEC_PATH/issue-$NUMBER-*.md`.
   Use `Glob("$SPEC_PATH/issue-$NUMBER-*.md")` or `ls $SPEC_PATH/issue-$NUMBER-*.md 2>/dev/null`.

**If all three criteria are met (fix-cycle state detected):**

Output: "Fix-cycle detected for issue #$NUMBER — skipping issue/spec phases, running code directly."

**phase/verify label reset (reopened-only path)**: If criterion 1 was satisfied via the reopened check only (no verify-fail marker), the `phase/verify` label may still be present from the previous verify run. Reset it before running code:

```bash
if gh issue view "$NUMBER" --json labels -q '.labels[].name' | grep -q '^phase/verify$'; then
  "${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh" "$NUMBER" ready
fi
```

Skip Step 3 and Step 3a entirely. Select the code phase run based on ROUTE (determined in Step 2 from flags or Size):

| ROUTE / condition | Action |
|---|---|
| `patch` (Size XS/S or `--patch` flag) | Proceed to Step 4 patch route |
| `pr` (Size M/L or `--pr` flag) | Proceed to Step 4 pr route |
| Size `XL` | Output: "Fix-cycle fast-path is not supported for XL Issues. Run `/code $NUMBER` or split sub-issues manually." and go to Step 6 (error report) |
| Size unset, no explicit flag | Use `pr` route as safe fallback; proceed to Step 4 pr route |

Step 4 handles code → (review → merge →) verify in the normal way for the chosen route. No additional `COMMENT_SCOPE` flag is needed for `run-code.sh` — the verify-fail marker exception in `modules/l0-surfaces.md` Step 2 ensures the FAIL marker comment is consumed by the code phase regardless of cutoff.

**If any criterion is not met**: proceed normally to Step 3.

### Step 3: `phase/ready` Label Check

Fetch labels with `gh issue view $NUMBER --json labels -q '.labels[].name'` and branch based on label state:

- **`phase/ready` label present**: proceed to the next step
- **`phase/issue` label present (no `phase/ready`)**:
  - **Size is XS**: Spec not needed — skip spec and proceed to Step 4
  - Size is `L`: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-spec.sh $NUMBER --opus` (run spec with Opus model)
  - Size is neither XS nor L: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-spec.sh $NUMBER`
  - On spec success:
    - **stop-at check**: if `EFFECTIVE_STOP_AT == "spec"`: output "Stopped at phase: spec (auto-stop-at=spec)" and proceed to Step 5 (Completion Report) with `STOPPED_AT="spec"`
    - Otherwise, proceed to Step 4
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
    - On spec success:
      - **stop-at check**: if `EFFECTIVE_STOP_AT == "spec"`: output "Stopped at phase: spec (auto-stop-at=spec)" and proceed to Step 5 (Completion Report) with `STOPPED_AT="spec"`
      - Otherwise, proceed to Step 4
    - On spec failure, go to Step 6 (error report)
  - If expected `phase/*` label state is not reached after re-fetch, go to Step 6 (error report)
  - On issue failure, go to Step 6 (error report)

### Step 3a: Post-Spec Size Refresh

**Run only when** `run-spec.sh` was called and succeeded in Step 3 (i.e., spec was executed — not when `phase/ready` was already set at Step 3 entry, and not when Size was XS which skips spec). Also skip if `--patch`, `--pr`, or `--review=...` flag is present in ARGUMENTS (preserve explicit-flag priority behavior).

Re-fetch Size to detect updates made by the spec phase:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh --no-cache "$NUMBER" 2>/dev/null
```

Update ROUTE and REVIEW_DEPTH based on the refreshed Size:

| Refreshed Size | Route | Review depth |
|---|---|---|
| XS or S | patch | — |
| M | pr | `--light` |
| L | pr | `--full` |
| XL | sub_issue | — |
| unset | pr | (safe fallback) |

If route changed from Step 2, output a log line: "Post-spec Size refresh: Size updated to {NEW_SIZE}, route re-determined as {NEW_ROUTE}."

**Route demotion (pr → patch only):**

If `ALWAYS_PR=true` and the refreshed Size would set ROUTE to `patch`: suppress the demotion, keep ROUTE as `pr`, and output: "ALWAYS_PR=true: suppressing pr → patch demotion in Step 3a. Route stays pr." Then proceed to Step 4 with ROUTE unchanged (only REVIEW_DEPTH is updated per the table above).

If ROUTE changed from `pr` to `patch` (i.e., the prior ROUTE was `pr` and the refreshed ROUTE is `patch`, and `ALWAYS_PR=false`):

1. Output: "Post-spec route demotion: pr → patch, remaining phases re-planned"
2. In Step 4, use the patch route sequence instead of the pr route sequence: run `code --patch` then `verify` (skip `review` and `merge`)

Proceed to Step 4 using the updated ROUTE and REVIEW_DEPTH.

### Step 4: Autonomous Execution (run-*.sh)

Select the route section below based on the current ROUTE value (set in Step 2 and potentially overridden by Step 3a's route demotion logic).

Run each phase via `run-*.sh`. Each script launches an independent process with `claude -p --dangerously-skip-permissions` for a fresh context and full permission bypass.

**Execution pattern:**
- Each `run-*.sh` runs via Bash with `run_in_background: true` and **no explicit `timeout` parameter**, in sequence. Do not wrap the call in an external Bash timeout — a legitimately long-running phase (e.g., Size L/XL code phases) must not be killed by the harness before it finishes.
- `run-*.sh` scripts already own a silent-window watchdog internally (`scripts/claude-watchdog.sh`, default 1800s, tunable via `watchdog-timeout-{phase}-seconds` in `.wholework.yml`; see `modules/detect-config-markers.md`) that kills a genuinely hung invocation. An external Bash-tool timeout duplicates and conflicts with this mechanism — it can fire mid-flight on a phase that is silently-but-correctly still working, well before the internal watchdog would. Backgrounding + relying on the internal watchdog avoids that conflict.
- After starting a phase with `run_in_background: true`, wait for the harness completion notification rather than polling; do not add a manual wait/sleep loop.
- PR number extraction is run by the parent session with `gh pr list` (included in `allowed-tools`)

**VERIFY_ITERATION_COUNT initialization (single-Issue routes only — skip for batch modes):**

Before running any phase, initialize `VERIFY_ITERATION_COUNT`:
- If `RESUME_MODE=true`: call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh read_single $NUMBER` and set `VERIFY_ITERATION_COUNT` to the returned value. Output: "Restored verify_iteration_count=$VERIFY_ITERATION_COUNT from checkpoint."
  - After restoring, also perform a label conflict check: fetch live labels with `gh issue view $NUMBER --json labels -q '.labels[].name'`. If the issue is already at `phase/done` (label `phase/done` present), the checkpoint is stale — call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh delete_single $NUMBER`, set `VERIFY_ITERATION_COUNT=0`, and output: "Checkpoint discarded: live labels show phase/done."
  - For pr route (M/L), `run-auto-sub.sh` automatically handles code phase resume via the `code_phase_milestone` checkpoint: at the start of the code phase, it probes observable git/GitHub state (`_observe_code_milestone`), writes the milestone, and dispatches to the appropriate action (`skip-to-review` / `create-pr` / `push-and-pr` / `run-code`). The `/auto` skill does not need to orchestrate this — it is handled transparently inside `run-auto-sub.sh`.
- If `RESUME_MODE` is not set (normal mode): set `VERIFY_ITERATION_COUNT=0`

---

**XL route: sub-issue dependency graph with parallel execution (`run-auto-sub.sh` checks each sub-issue's `phase/ready` and auto-runs spec if not set):**

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `AUTO_MAX_CONCURRENT` (maximum concurrent sub-issue executions; default: 5).

1. **Fetch dependency graph**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/get-sub-issue-graph.sh $NUMBER
   ```
   Parse the result JSON and extract `execution_order` (array of sub-issue numbers per level).

2. **Run levels in order, in parallel**: Process each level in `execution_order` sequentially.

   Run each level's sub-issues in parallel via Bash background (`&`) with concurrency capped at `AUTO_MAX_CONCURRENT`, then wait for all to complete:
   ```
   # For each level (in execution_order order):
   Skip sub-issues that depend on failed issues,
   then run non-skipped sub-issues with concurrency cap using AUTO_MAX_CONCURRENT:
     RUNNING=0
     PIDS=()
     for each SUB in non-skipped sub-issues:
       ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $SUB_NUMBER &
       PIDS+=($!)
       RUNNING=$((RUNNING + 1))
       if [ $RUNNING -ge $AUTO_MAX_CONCURRENT ]; then
         # bash 4.3+: wait -n waits for any one child to finish
         # bash 3.2 fallback (macOS): kill -0 polling
         if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
           wait -n
         else
           while true; do
             for pid in "${PIDS[@]}"; do
               if ! kill -0 "$pid" 2>/dev/null; then break 2; fi
             done
             sleep 1
           done
         fi
         RUNNING=$((RUNNING - 1))
       fi
     done
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
2. code phase: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh $NUMBER --patch [--base {branch}]` via Bash with `run_in_background: true` (no external timeout — see Step 4 "Execution pattern")
3. Unconditional completion check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-patch $NUMBER --check-completion` — runs unconditionally regardless of exit code; if `matches_expected: false` (including exit 0), go to Step 6; if code exited non-zero but `matches_expected: true`, override to success
   - **stop-at check**: if `EFFECTIVE_STOP_AT == "code"`: output "Stopped at phase: code (auto-stop-at=code)" and proceed to Step 5 (Completion Report) with `STOPPED_AT="code"`
4. **XS only**: transcribe issue retrospective to Spec (see Step 4b)
5. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh verify $NUMBER --check-precondition --warn-only`
6. Increment counter: `VERIFY_ITERATION_COUNT=$((VERIFY_ITERATION_COUNT + 1))`
7. Save checkpoint: `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh write_single $NUMBER $VERIFY_ITERATION_COUNT`
8. verify phase: invoke `Skill(skill="wholework:verify", args="$NUMBER")` in the parent session (enables AskUserQuestion for manual AC confirmation)
9. Based on verify result, proceed to Step 5 or Step 6
   - If verify output contains `MAX_ITERATIONS_REACHED`: max iterations has been reached; delete checkpoint (`${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh delete_single $NUMBER`); stop chained execution and proceed to Step 5 (human judgment required — do not re-run verify automatically)
   - On verify success: delete checkpoint (`${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh delete_single $NUMBER`), and proceed to Step 5

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
2. Output `[1/4] code`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh $NUMBER --pr [--base {branch}]` via Bash with `run_in_background: true` (no external timeout — see Step 4 "Execution pattern")
3. Unconditional completion check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh code-pr $NUMBER --check-completion` — runs unconditionally regardless of exit code; if `matches_expected: false` (including exit 0), go to Step 6; if `matches_expected: true`, output `[1/4] code → done (PR #N)`, and continue
4. Extract PR number via exact-match filter (matches SSoT branch name worktree-code+issue-N established by #310): `gh pr list --json number,headRefName | jq -r ".[] | select(.headRefName == \"worktree-code+issue-$NUMBER\") | .number" | head -1`
5. If PR number cannot be fetched: report error and go to Step 6
   - **stop-at check**: if `EFFECTIVE_STOP_AT == "code"`: output "Stopped at phase: code (auto-stop-at=code)" and proceed to Step 5 (Completion Report) with `STOPPED_AT="code"` (at this point `$PR_NUMBER` is known)
6. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh review $NUMBER --pr $PR_NUMBER --check-precondition --warn-only`
7. Output `[2/4] review`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/run-review.sh $PR_NUMBER $REVIEW_DEPTH` via Bash with `run_in_background: true` (no external timeout — see Step 4 "Execution pattern") (REVIEW_DEPTH set in Step 2, refreshed by Step 3a if applicable); on success output `[2/4] review → done`
   - **stop-at check**: if `EFFECTIVE_STOP_AT == "review"`: output "Stopped at phase: review (auto-stop-at=review)" and proceed to Step 5 (Completion Report) with `STOPPED_AT="review"`
8. If review fails: completion check `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh review $NUMBER --pr $PR_NUMBER --check-completion` — if `matches_expected: true`, override to success; otherwise go to Step 6
9. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh merge $NUMBER --pr $PR_NUMBER --check-precondition --warn-only`
10. Output `[3/4] merge`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/run-merge.sh $PR_NUMBER` via Bash with `run_in_background: true` (no external timeout — see Step 4 "Execution pattern"); on success output `[3/4] merge → done`
    - **stop-at check**: if `EFFECTIVE_STOP_AT == "merge"`: output "Stopped at phase: merge (auto-stop-at=merge)" and proceed to Step 5 (Completion Report) with `STOPPED_AT="merge"`
11. If merge fails: completion check `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh merge $NUMBER --pr $PR_NUMBER --check-completion` — if `matches_expected: true`, override to success; otherwise go to Step 6
12. Precondition check: `${CLAUDE_PLUGIN_ROOT}/scripts/reconcile-phase-state.sh verify $NUMBER --check-precondition --warn-only`
13. Increment counter: `VERIFY_ITERATION_COUNT=$((VERIFY_ITERATION_COUNT + 1))`
14. Save checkpoint: `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh write_single $NUMBER $VERIFY_ITERATION_COUNT`
15. Output `[4/4] verify`, then invoke `Skill(skill="wholework:verify", args="$NUMBER")` in the parent session (enables AskUserQuestion for manual AC confirmation); on success output `[4/4] verify → done`
16. Based on verify result, proceed to Step 5 or Step 6
    - If verify output contains `MAX_ITERATIONS_REACHED`: max iterations has been reached; delete checkpoint (`${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh delete_single $NUMBER`); stop chained execution and proceed to Step 5 (human judgment required — do not re-run verify automatically)
    - On verify success: delete checkpoint (`${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh delete_single $NUMBER`), and proceed to Step 5

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

4. **Append recovery events to orchestration-recoveries.md** (before Spec retrospective commit):

   Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` to confirm `SPEC_PATH` (already retained from step 1 of this section).

   Determine whether any of the following sources contributed recovery events during this run:

   | Source | When to append | Dependency |
   |--------|---------------|------------|
   | Source 1: `fallback-catalog` | A catalog entry in `orchestration-fallbacks.md` was applied during Tier 2 recovery | Available (#315 shipped) |
   | Source 2: `recovery-sub-agent` | The `orchestration-recovery` sub-agent produced a successful recovery plan during Tier 3 recovery | Available (#617 shipped) |
   | Source 3: `wrapper-anomaly-detector` | `detect-wrapper-anomaly.sh` detected a known failure pattern during Tier 2 recovery | Available (#313 shipped) |

   **Source 1 note — XL route only**: For XL routes, `run-auto-sub.sh` Tier 2 bash path writes the sub-issue's Spec Auto Retrospective directly at recovery time (when `apply-fallback.sh` succeeds) via `_write_tier2_recovery_to_spec()`. Similarly, the Tier 3 bash path writes the sub-issue's Spec Auto Retrospective directly at recovery time (when `spawn-recovery-subagent.sh` succeeds) via `_write_tier3_recovery_to_spec()`. When Step 4a processes XL sub-issue results, the sub-issue Spec Auto Retrospective entries from Tier 2 and Tier 3 recovery are already present — Step 4a does not need to add them again. `orchestration-recoveries.md` should still be updated as the session-level SSoT.

   **Source 2 detection — single-Issue parent session only**: Check if `TIER3_RECOVERY_PHASE` is set (retained in Step 6 after Tier 3 succeeds). If set, use retained `TIER3_RECOVERY_*` variables to build the entry and prepend it. For batch/XL routes, `spawn-recovery-subagent.sh` writes directly to `orchestration-recoveries.md`, so Source 2 here covers only single-Issue parent sessions (M/L/patch). `run-auto-sub.sh` commits and pushes `docs/reports/orchestration-recoveries.md` immediately after Tier 3 success to prevent dirty-file conflicts at `/verify` invocation (see #677).

   For each applicable source, prepend a new entry block to `docs/reports/orchestration-recoveries.md` (after the header comment line `<!-- Log entries appear below, newest first. -->`). Use the Write/Edit tool. Entry format:

   ```markdown
   ## YYYY-MM-DD HH:MM UTC: <symptom-short>

   ### Context
   - Issue #N, phase: <phase>
   - Source: <fallback-catalog|recovery-sub-agent|wrapper-anomaly-detector>
   - Wrapper: <run-*.sh name>, exit code: <N>
   - Log tail: "<last relevant log line>"

   ### Diagnosis
   - <observed state and root cause>

   ### Recovery Applied
   - <catalog anchor or sub-agent plan excerpt or manual steps>

   ### Outcome
   - <success|partial|failed>

   ### Improvement Candidate
   - <未起票|起票済み #NNN|N/A (resolved by known catalog)>
   ```

   If no sources contributed recovery events, skip the append (do not create an empty entry).

   Add `docs/reports/orchestration-recoveries.md` to the same `git add` in the next step.

5. **Commit and push**:
   ```bash
   git add $SPEC_PATH/issue-$NUMBER-*.md docs/reports/orchestration-recoveries.md
   git commit -s -m "Add auto retrospective for issue #$NUMBER

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
   git push origin main
   ```

   If no recovery events were appended, omit `docs/reports/orchestration-recoveries.md` from `git add` (only add it when it was actually modified).

6. **Collect and create Improvement Proposal Issues**: Read `${CLAUDE_PLUGIN_ROOT}/modules/retro-proposals.md` and follow the "Processing Steps" section. Use `SPEC_PATH` and `HAS_SKILL_PROPOSALS` already retained from this step's `detect-config-markers.md` call. If the shared module returns no proposals, skip silently.

### Step 4d: XL Sub-issue Verify (XL route only)

**Skip this step for all routes other than XL.**

Run after all sub-issue levels complete (after Step 4a Auto Retrospective) and before Step 4c close flow.

Collect all sub-issue numbers from `get-sub-issue-graph.sh` output (all sub-issues that reached `phase/done` or `phase/verify`), then append the parent issue number: `[sub_issue_1, sub_issue_2, ..., $NUMBER]`.

For each issue number in this list, **serially** in the parent session:

```
Skill(skill="wholework:verify", args="$N")
```

This runs verify in the parent context, enabling AskUserQuestion for manual AC confirmation on each issue.

**Skip any sub-issue that**:
- was skipped due to a dependency failure (in the failure set from Step 4 execution)
- already has `phase/done` label (already verified and closed in a prior run)

Continue to the next issue even if one verify invocation ends in FAIL or MAX_ITERATIONS_REACHED — the close flow in Step 4c will assess the final state.

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

**Stop-at stopped banner (emit before the normal completion report when `STOPPED_AT` is set):**

If `STOPPED_AT` is set (pipeline stopped early due to `auto-stop-at` or `--stop-at=<phase>`):

1. Output the stopped-at banner:
   ```
   /auto #N stopped at STOPPED_AT
   TITLE
   URL
   ```
2. Output a result table showing phases executed vs. not executed.
3. Output the next-action message based on the stopped phase:

   | `STOPPED_AT` | next-action message |
   |---|---|
   | `spec` | "Next: run `/code $NUMBER` to proceed with implementation." |
   | `code` | "Next: run `/review $PR_NUMBER` to proceed with code review." |
   | `review` | "Next: review PR #$PR_NUMBER and run `/merge $NUMBER` when ready." |
   | `merge` | "Next: run `/verify $NUMBER` to proceed with post-merge verification." |

4. Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with `SKILL_NAME=auto`, `ISSUE_NUMBER=$NUMBER`, `RESULT=success`.
5. Run the event-based observation scan and daily rollup (same as normal completion).
6. Return (do not execute normal completion flow below).

---

If all phases succeeded:

1. **Check for opportunistic pending state**: Run `gh issue view $NUMBER --json labels --jq '.labels[].name'`

2. **CI FAIL/recovery scan (build Notes before result table):**

   Scan the run-*.sh output captured in the LLM context during Step 4 for CI check failures and auto-recovery events in each phase:

   - **CI check failure**: `gh pr checks`-style output lines containing `fail` or `FAILED` (e.g., `Run bats / bats (push) fail`)
   - **Review auto-fix**: phrases such as `MUST issue resolved` / `MUST issue auto-resolved`, or commit messages beginning with `Fix:` added as follow-up commits in the review phase

   For each phase where a CI failure or auto-fix is detected, record a concise one-line Notes value for the result table:
   - Example: `1 CI fail → fixed in abc1234`
   - Example: `1 MUST issue auto-resolved`
   - Example: `2 CI fails → fixed; 1 MUST issue resolved` (multiple events in one phase)

   If nothing is detected for a phase, leave Notes as `—`.

3. **If output from step 1 contains `phase/verify` (opportunistic pending)**: output the partial success — opportunistic pending banner:
   ```
   /auto #N partial success — opportunistic pending
   TITLE
   URL
   ```
   Followed by a result table (one row per phase with status, Notes from step 2).

   Then enumerate unchecked post-merge conditions from the Issue body:
   1. Fetch Issue body: `gh issue view $NUMBER --json body -q '.body'`
   2. Locate the post-merge section (lines after `### Post-merge` or `## Post-merge` heading, up to the next `##` heading or end of file)
   3. Extract all lines matching `- [ ]` within that section
   4. For each extracted line, strip the `- [ ]` prefix and remove any `<!-- verify: ... -->` HTML comment substrings, then trim whitespace to produce human-readable condition text
   5. Display the conditions:
      - If 1–5 conditions: list each on its own line, prefixed with `  - `
      - If 6 or more: list the first 5 with `  - ` prefix, then output `  ... and N more` (where N is the total count minus 5)
      - If 0 conditions: omit the list (output nothing after the result table)

   After the list (or result table if no conditions), output: "Run \`/verify $NUMBER\` after confirming them manually."

4. **If output from step 1 does not contain `phase/verify`**: output the completion banner:
   ```
   /auto #N complete
   TITLE
   URL
   ```
   Followed by a result table (one row per phase with status, Notes from step 2).

**If an Auto Retrospective was recorded in the Spec (XL routes: always; M/L/patch routes: when orchestration anomalies were detected), also output "Auto retrospective recorded in Spec".**

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=auto`
- `ISSUE_NUMBER=$NUMBER`
- `RESULT=success`

**Event-based observation scan (auto-run event, runs after Completion Report regardless of success/failure):**

Run `${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh --event auto-run` and capture stdout as `OBSERVATION_MATCHES` (newline-separated Issue numbers; may be empty).

If `OBSERVATION_MATCHES` is non-empty, read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section to load `AUTONOMY_TIER`, then apply tier-aware dispatch:
- **L1**: skip dispatch (advisory-only — the comment already posted by `observation-trigger.sh` is the only action)
- **L2 / L3**: for each number in `OBSERVATION_MATCHES` other than `$NUMBER` (the Issue this `/auto` run just processed), dispatch `Skill(skill="wholework:verify", args="$N")` sequentially

**L3 auto-retrospective (batch/XL routes only, runs after observation scan regardless of success/failure):**

1. **Route guard**: If `ROUTE` is neither `batch` nor `sub_issue` (XL route), output "L3 retrospective skipped: no notable orchestration content" and skip the remaining L3 steps.

2. **Create session dir and extract session events** (always for batch/XL routes, before notable judgment):
   ```bash
   DATE=$(date -u +%Y-%m-%d)
   SESSION_DIR="docs/sessions/${AUTO_SESSION_ID}-${DATE}"
   mkdir -p "$SESSION_DIR"
   ```
   - Extract session events:
     ```bash
     jq -c 'select(.session_id == "'"$AUTO_SESSION_ID"'")' .tmp/auto-events.jsonl > "$SESSION_DIR/events.jsonl" 2>/dev/null || true
     ```
   - **Empty-dir guard** (防止策): After all file writes above complete, remove the session dir if it is still empty. This prevents orphaned empty directories when the process aborts before writing any files (e.g., DATE-cross retry creates a new dir but writes nothing to it):
     ```bash
     if [ -d "$SESSION_DIR" ] && [ -z "$(ls -A "$SESSION_DIR")" ]; then
       rmdir "$SESSION_DIR"
       echo "Warning: No session data was written to $SESSION_DIR — removed empty session dir"
     fi
     ```

3. **Notable judgment** (using events from `.tmp/auto-events.jsonl` and in-context variables):
   - Extract events for this session:
     ```bash
     jq -c 'select(.session_id == "'"$AUTO_SESSION_ID"'")' .tmp/auto-events.jsonl 2>/dev/null
     ```
   - **batch route** (`ROUTE="batch"`) — notable if ANY of:
     - Tier 2/3 recovery fired (`TIER3_RECOVERY_PHASE` is set, OR recovery event detected in events)
     - Verify FAIL (any Issue label `phase/verify` with unchecked `- [ ]` at batch end)
     - Commit count for this session >= 3 (`commit` events in filtered events; if the events log does not emit `commit` events, use `git log --oneline --since="$session_start"` line count as a fallback)
     - Watchdog kill detected (`watchdog_timeout` event in filtered events)
   - **XL route** (`ROUTE="sub_issue"`) — notable if ANY of:
     - Parallel race detected (conflicting commit event or explicit race event in filtered events)
     - Cross-cutting AC mismatch (any `FAIL` from Step 4's cross-cutting pre-verification)
     - At least 1 sub-issue failure in the execution summary
   - If NOT notable: commit `events.jsonl` for this session and stop:
     ```bash
     git add "$SESSION_DIR"
     git commit -s -m "Add L3 session data for session ${AUTO_SESSION_ID}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
     git push origin main
     ```
     Output "L3 session events committed (not notable — session.md skipped)." and skip the remaining L3 steps.

4. **Fetch the Metrics section** (--no-github; retry-once on failure; log stderr to auto-metrics-stderr.log), capturing stdout to a scratch file:
   ```bash
   if ! "${CLAUDE_PLUGIN_ROOT}/scripts/get-auto-session-report.sh" "$AUTO_SESSION_ID" --metrics-only --no-github > ".tmp/auto-metrics-${AUTO_SESSION_ID}.md" 2>".tmp/auto-metrics-${AUTO_SESSION_ID}-stderr.log"; then
     if ! "${CLAUDE_PLUGIN_ROOT}/scripts/get-auto-session-report.sh" "$AUTO_SESSION_ID" --metrics-only --no-github > ".tmp/auto-metrics-${AUTO_SESSION_ID}.md" 2>>".tmp/auto-metrics-${AUTO_SESSION_ID}-stderr.log"; then
       echo "Warning: Metrics section generation failed — session.md will note the fallback"
       echo "## Metrics" > ".tmp/auto-metrics-${AUTO_SESSION_ID}.md"
       echo "" >> ".tmp/auto-metrics-${AUTO_SESSION_ID}.md"
       echo "(unavailable — generation failed; re-run \`scripts/get-auto-session-report.sh ${AUTO_SESSION_ID} --metrics-only\` manually)" >> ".tmp/auto-metrics-${AUTO_SESSION_ID}.md"
     else
       rm -f ".tmp/auto-metrics-${AUTO_SESSION_ID}-stderr.log"
     fi
   else
     rm -f ".tmp/auto-metrics-${AUTO_SESSION_ID}-stderr.log"
   fi
   ```
   Read the scratch file's contents for use in the next step.

5. **Write `$SESSION_DIR/session.md`** using the Write tool — insert the fetched `## Metrics` section between the title and `## What worked`, format:
   ```markdown
   # L3 Session Retrospective: {AUTO_SESSION_ID}

   {contents of .tmp/auto-metrics-${AUTO_SESSION_ID}.md}

   ## What worked
   (successful phases, recovery patterns used)

   ## Findings
   (single list covering cross-cutting conflicts, concurrent commit issues, AC mismatches,
   tier gaps, and structural improvement candidates. Each top-level bullet MUST end with
   exactly one of the following disposition tags — exhaustive:
   - `[Filed: pending]` — a new Issue should be filed for this finding. Use the `pending`
     placeholder at authoring time only (the Issue number is not yet known — retro-proposals
     in sub-step 6 below files it, and the Backlink sub-step backfills the real `#N` before
     commit). `check-session-findings-disposition.sh` treats `[Filed: pending]` as
     non-canonical and flags it if left unresolved — this placeholder must not survive to commit.
   - `[No action: <reason>]` — accepted as-is, no Issue needed. `<reason>` is required
     (e.g., "already covered by #100").
   - `[Resolved directly: <what was done>]` — resolved within this session (e.g., a
     follow-up comment was posted). `<what was done>` is required.
   )

   ## Auto Retrospective
   ### Improvement Proposals
   (mechanically transcribed from `## Findings`: every bullet tagged `[Filed: ...]` above,
   listed here verbatim. `modules/retro-proposals.md` reads this section — its read logic
   is unchanged.)
   ```
   After writing `session.md`, delete the scratch file: `rm -f ".tmp/auto-metrics-${AUTO_SESSION_ID}.md"`

6. **Call `modules/retro-proposals.md`** — improvement Issue creation:
   - Create a bridge file for retro-proposals.md interface compatibility:
     - XL route (`ROUTE="sub_issue"`): `BRIDGE_NUMBER=$NUMBER`; write bridge file at `$SESSION_DIR/issue-${BRIDGE_NUMBER}-l3session.md` containing the `## Auto Retrospective > ### Improvement Proposals` section from `session.md`
     - batch route (`ROUTE="batch"`): `BRIDGE_NUMBER="batch-${AUTO_SESSION_ID}"`; write bridge file at `$SESSION_DIR/issue-${BRIDGE_NUMBER}-l3session.md`
   - Read `${CLAUDE_PLUGIN_ROOT}/modules/retro-proposals.md` and follow "Processing Steps" with `SPEC_PATH=$SESSION_DIR`, `NUMBER=$BRIDGE_NUMBER`, `HAS_SKILL_PROPOSALS` (already retained from `.wholework.yml` detection).
   - Collect filed Issue numbers from retro-proposals output.

7. **Backlink**: If any Issues were filed, append a `## Filed Issues` section to `$SESSION_DIR/session.md` listing each filed Issue number as `- #N`.

   **`## Findings` disposition backfill**: For each `[Filed: pending]` bullet in `## Findings`,
   replace it with `[Filed: #N]` using the Issue number retro-proposals filed for the
   corresponding proposal. If retro-proposals skipped a proposal (dedup against an existing
   Issue, or considered already resolved), replace its `[Filed: pending]` with
   `[No action: <reason retro-proposals gave, e.g. duplicate of #M>]` instead. Complete this
   backfill in this sub-step, before the check in sub-step 9 and the commit in sub-step 10.

8. **Skill Self-Update Propagation check** (batch/XL routes only; runs after Backlink, before commit):
   - Load `skill_versions` from `.tmp/auto-session-${AUTO_SESSION_ID}.json`:
     ```bash
     SKILL_VERSIONS=$(jq -r '.skill_versions // empty' ".tmp/auto-session-${AUTO_SESSION_ID}.json" 2>/dev/null)
     ```
     If the file is absent or `jq` fails (empty output), skip this sub-step entirely.
   - For each of the 8 skills (auto/code/spec/verify/review/merge/issue/audit), compare the saved hash against the current `HEAD` hash:
     ```bash
     for skill in auto code spec verify review merge issue audit; do
       START_HASH=$(echo "$SKILL_VERSIONS" | jq -r ".\"skills/${skill}/SKILL.md\" // \"\"" 2>/dev/null || echo "")
       CURRENT_HASH=$(git log -1 --format=%H -- "skills/${skill}/SKILL.md" 2>/dev/null || echo "")
       if [ -n "$START_HASH" ] && [ -n "$CURRENT_HASH" ] && [ "$START_HASH" != "$CURRENT_HASH" ]; then
         CHANGED_SKILLS="${CHANGED_SKILLS:+$CHANGED_SKILLS }${skill}:${START_HASH}:${CURRENT_HASH}"
       fi
     done
     ```
   - If at least one skill has changed hashes, append a `## Skill Self-Update Propagation Note` section to `$SESSION_DIR/session.md`:
     ```markdown
     ## Skill Self-Update Propagation Note

     Session 中に以下の skill が更新されました (本 session には未適用、次 session から反映):
     - skills/auto/SKILL.md: <start-hash> → <current-hash>  (or "(no change)" when unchanged)
     - skills/code/SKILL.md: (no change)
     ...
     ```
     List all 8 skills — show `<start-hash> → <current-hash>` for changed ones and `(no change)` for unchanged ones.
   - If no skills changed, skip the append (do not add the section).

9. **Findings disposition tag check (warn-only)**: Run
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-session-findings-disposition.sh "$SESSION_DIR/session.md"`.
   This is warn-only — a non-zero exit prints a warning (including the untagged lines from
   the script's output) but does not abort the commit. Aborting here would leave
   `session.md` itself uncommitted, losing the retrospective entirely, which is worse than
   committing with a tagging gap that can be caught on the next cross-audit pass.

10. **Commit and push**:
    ```bash
    git add "$SESSION_DIR"
    git commit -s -m "Add L3 session retrospective for session ${AUTO_SESSION_ID}

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
    git push origin main
    ```

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
- **`mid-run-api-error` pattern**: run `reconcile-phase-state.sh <phase> $NUMBER --check-completion`;
  if `matches_expected: true` override to success; if `matches_expected: false` inspect
  `hint_*` fields in `actual` JSON to restore the phase label, then retry the failed phase
  once via the corresponding `run-*.sh` script
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

5. **Act on recovery plan**:
   - `action=retry`: re-run the failed phase once (same `run-*.sh` call with same arguments); if it fails again, fall back to stop-and-report
   - `action=skip`: treat the phase as complete and continue to the next phase
   - `action=recover`: execute `steps` sequentially; if all steps succeed, continue to the next phase; if any step fails, fall back to stop-and-report
   - `action=abort`: fall back to stop-and-report immediately

5b. **Retain recovery state** (on successful recovery — action is not `abort`):
   Retain the following as in-context variables for use in Step 4a Source 2:
   - `TIER3_RECOVERY_PHASE=$PHASE`
   - `TIER3_RECOVERY_ACTION=$action` (the action that succeeded)
   - `TIER3_RECOVERY_RATIONALE`: `rationale` field from the recovery plan JSON
   - `TIER3_RECOVERY_STEPS_COUNT`: number of steps in the plan (0 for retry/skip)
   - `TIER3_RECOVERY_EXIT_CODE=$EXIT_CODE`
   - `TIER3_RECOVERY_LOG_TAIL`: last line of `.tmp/wrapper-out-$NUMBER-$PHASE.log`

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

**Manual recovery hand-off**: If the parent session manually recovers and continues to subsequent phases instead of stopping here, complete the remaining phases via manual recovery first, then call `bash ${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh --write-manual-recovery ISSUE PHASE RECOVERY_TYPE` to automatically write the recovery record to the sub-issue Spec's `## Auto Retrospective` section (where RECOVERY_TYPE describes the action taken, e.g., `push-only`, `pr-create`, `review-rerun`). Skip this call if the Tier 2 anomaly detector already appended a recovery entry for this event to avoid duplicate entries. Then proceed to Step 5.

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

**Batch checkpoint initialization (List mode only):**

At the start of List mode, generate a BATCH_ID and write the full batch state:
```
BATCH_ID="${PPID}-$(date +%s)"
${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh write_batch "$BATCH_ID" "N1 N2 N3" "" ""
```
(`BATCH_ID` is used for all subsequent checkpoint calls in this batch session; first list arg: space-separated full list in double quotes — quoting is required when the list contains spaces; remaining args: empty strings for completed and failed)

Process each Issue in `BATCH_LIST` in order:

1. Check Issue labels: `gh issue view $NUMBER --json labels -q '.labels[].name'`
2. **If no `phase/*` labels**: run `${CLAUDE_PLUGIN_ROOT}/scripts/run-issue.sh $NUMBER` (issue triage → Size setting → `phase/ready` assignment)
   - On failure: output a warning; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER fail`; skip to the next Issue (do not abort the entire batch)
3. Re-check Size: call `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER`; if Size is XL: output a warning; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER fail`; skip to the next Issue (do not abort the entire batch)
4. **Blocked-by check**: Extract blocker numbers from the Issue body:
   ```
   gh issue view $NUMBER --json body -q '.body' | grep -ioE "blocked by #[0-9]+" | grep -oE "[0-9]+"
   ```
   - If no blockers found: skip to step 5
   - For each blocker `$BLOCKER`:
     ```
     gh issue view $BLOCKER --json state,labels -q '{state: .state, phases: [.labels[].name | select(startswith("phase/"))]}'
     ```
     - If `state` is `"CLOSED"` or `phases` contains `"phase/done"`: gate released — continue to next blocker
     - Otherwise: extract `$BLOCKER_PHASE` (first `phase/*` label of blocker, or `"OPEN"` if no `phase/*` label); output warning and skip `$NUMBER` (do NOT call `update_batch` — keeps `$NUMBER` in `remaining` for `/auto --batch --resume`):
       ```
       Warning: #$NUMBER blocked by #$BLOCKER which is $BLOCKER_PHASE (manual post-merge pending). Skipping #$NUMBER. After completing #$BLOCKER manually, resume with /auto --batch --resume.
       ```
5. Run `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh $NUMBER` (all phases spec→code→review→merge→verify, auto-starting from the current `phase/*` state)
   - On success: proceed to step 6
   - On failure: output a warning; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER fail`; skip to the next Issue (do not abort the entire batch)
6. **Verify orchestration** (after run-auto-sub.sh success):
   - Re-fetch current labels: `gh issue view $NUMBER --json labels -q '.labels[].name'`
   - If `phase/verify` is present in labels:
     - If `--non-interactive` is NOT in ARGUMENTS: invoke `Skill(skill="wholework:verify", args="$NUMBER")` in the parent session
       - On success: call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`
       - On failure or output contains `MAX_ITERATIONS_REACHED`: output a warning; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER fail`; skip to the next Issue
     - If `--non-interactive` IS in ARGUMENTS: output "Skipping verify for #$NUMBER (non-interactive mode); phase/verify remains"; call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`
   - If `phase/verify` is NOT in labels: call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh update_batch "$BATCH_ID" $NUMBER complete`

After all Issues are processed, delete the batch checkpoint:
```
${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh delete_batch "$BATCH_ID"
```

### Resume mode (--batch --resume)

Entered from Step 1 when `--batch --resume` is detected with no numeric tokens after `--batch`.

1. Call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh list_active_batches` and capture the output as `ACTIVE_BATCH_IDS` (newline-separated list).
   - If `ACTIVE_BATCH_IDS` is non-empty:
     - In interactive mode: present candidates to user via AskUserQuestion to select a BATCH_ID
     - In non-interactive mode: use the last line (most recent entry) as `BATCH_ID`
   - If `ACTIVE_BATCH_IDS` is empty: fall back to `BATCH_ID="default"` (handles pre-BATCH_ID migration case where `.tmp/auto-batch-state.json` may exist from an older run)
2. Call `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh read_batch "$BATCH_ID"` and capture the output as `REMAINING`.
3. If `REMAINING` is empty: output "No resume target found. Run `/auto --batch N1 N2 ...` to start a new batch." and exit.
4. Output a log line: "Resuming batch: batch_id=$BATCH_ID, remaining issues = $REMAINING"
5. Treat `REMAINING` as `BATCH_LIST` and process each Issue following the same steps as `### List mode (--batch N1 N2 ...)`.
   - Note: do NOT call `write_batch` again at the start (the existing batch state file is the live state); only call `update_batch "$BATCH_ID"` and `delete_batch "$BATCH_ID"` as per List mode.

### Batch Completion Report

After all Issues are processed, report results (success/skip/failure) for each Issue.

**Pending manual confirmation (best-effort):**

1. For each issue in BATCH_LIST, run `gh issue view $NUMBER --json labels -q '.labels[].name'` and check whether the output contains `phase/verify`. Collect matching issues into `PENDING_LIST`.
2. If `PENDING_LIST` is empty: output "No issues pending manual confirmation." and continue to the next step.
3. For each issue in `PENDING_LIST`, run `gh issue view $NUMBER --json body -q '.body'` and count:
   - Unchecked checkbox lines (containing `- [ ]`) that also contain `<!-- verify-type: manual` → `MANUAL_N`
   - Unchecked checkbox lines (containing `- [ ]`) that also contain `<!-- verify-type: observation` → `OBS_N`
   - Unchecked checkbox lines (containing `- [ ]`) that also contain `<!-- verify-type: opportunistic` → `OPP_N`
4. Accumulate `TOTAL_MANUAL`, `TOTAL_OBS`, `TOTAL_OPP` across all issues in `PENDING_LIST`.
5. Output the aggregation in the following format:
   ```
   Pending manual confirmation (N issues in phase/verify):
   - #NUMBER: MANUAL_N manual AC, OBS_N observation AC, OPP_N opportunistic AC
   ...
   verify-type breakdown: manual=TOTAL_MANUAL, observation=TOTAL_OBS, opportunistic=TOTAL_OPP
   Recommended next action:
   - For observation/opportunistic: wait for event fire (auto-checked next /verify run)
   - For manual: review and confirm or run /verify $NUMBER
   ```

If any `gh issue view` call fails, skip that issue and continue (best-effort — do not block the batch report).

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=auto`
- `RESULT=success`
- (omit `ISSUE_NUMBER` — batch run with multiple issues, guide will be omitted per module logic)

**Event-based observation scan (batch, best-effort):**

Run `${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh --event auto-run` and capture stdout as `OBSERVATION_MATCHES` (newline-separated Issue numbers; may be empty).

If `OBSERVATION_MATCHES` is non-empty, read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section to load `AUTONOMY_TIER`, then apply tier-aware dispatch:
- **L1**: skip dispatch (advisory-only — the comment already posted by `observation-trigger.sh` is the only action)
- **L2 / L3**: for each number in `OBSERVATION_MATCHES` not already included in `BATCH_LIST` (Issues already processed by this batch), dispatch `Skill(skill="wholework:verify", args="$N")` sequentially

**Next-cycle seed (batch, best-effort):**

1. Load `AUTONOMY_TIER` and `NEXT_CYCLE_SEED_ENABLED` from `.wholework.yml` via `modules/detect-config-markers.md`.
2. Tier check: if `AUTONOMY_TIER=L1` or `NEXT_CYCLE_SEED_ENABLED=false`, use path A only — print `Recommend: run /audit drift to identify next-cycle candidates` and skip to the next block.
3. Otherwise (path E), read `session_start` from `.tmp/auto-session-${AUTO_SESSION_ID}.json` using `jq -r .session_start`. If the file is absent or jq fails, print "Warning: session start time unavailable, skipping next-cycle seed." and skip to the next block.
4. Fetch `audit/drift` candidates:
   ```bash
   gh issue list --label "audit/drift" --state open --json number,createdAt \
     --jq "[.[] | select(.createdAt > \"$SESSION_START\") | {issue: .number, source: \"audit/drift\"}]"
   ```
   Fetch `audit/fragility` candidates the same way (separate query; `--label` is AND-only). Merge the two arrays, deduplicating by issue number.
5. For each candidate, run `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER` (best-effort); add `size_hint` field if the output is non-empty.
6. Write `.tmp/next-cycle.json` using the Write tool with the following structure:
   ```json
   {
     "schema_version": "v1",
     "seeded_at": "<current UTC ISO8601>",
     "seeded_by_session": "<AUTO_SESSION_ID>",
     "candidates": [
       {"issue": 712, "source": "audit/drift", "size_hint": "S"},
       {"issue": 715, "source": "audit/fragility", "size_hint": "M"}
     ]
   }
   ```
7. Emit `next_cycle_seeded` event via `source ${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh && emit_event "next_cycle_seeded" "candidate_count=$CANDIDATE_COUNT" "source_breakdown=audit/drift:$DRIFT_N,audit/fragility:$FRAGILITY_N" "batch_session_id=$AUTO_SESSION_ID"` (best-effort; wrap in subshell to prevent failure propagation).

If any step in path E fails, print "Warning: next-cycle seed step N failed. Skipping." and continue (best-effort — never block the parent report).

**L3 auto-retrospective (batch route):**

Set `ROUTE="batch"`, then follow the **L3 auto-retrospective** steps in Step 5 (route guard, notable judgment, session file creation, retro-proposals call, backlink, commit and push).

## Notes

- Run after `/issue` is complete (spec is auto-run if not yet complete)
- Detailed logic for each phase (review comment handling, conflict resolution, etc.) is delegated to each skill
- `auto` itself does not post Issue comments (posted individually within each phase)
- Skills are installed via the plugin marketplace and referenced through `${CLAUDE_PLUGIN_ROOT}` at runtime

## Checkpoint Design

### reconciler-first / checkpoint-as-hint

`/auto --resume N` resumes a single Issue after interruption. The authority for the current phase is **GitHub labels + `reconcile-phase-state.sh`** — the checkpoint is a hint only.

| Information | Authority source (SSoT) | Checkpoint role |
|-------------|------------------------|-----------------|
| Current phase | GitHub labels (`phase/*`) + `reconcile-phase-state.sh` | Not consulted (labels take priority) |
| PR number | `gh pr list` (live query) | Not stored |
| Route (patch/pr/XL) | Derived from Size | Not stored |
| **verify iteration_count** | None (in-run variable only) | **Persisted** (cross-run limit management) |
| **Batch remaining list** | None | **Persisted** (incomplete Issue list) |
| **code phase milestone** | Observable git+GitHub state (worktree/branch/PR) | **Persisted** (hint; resume time observe-reconcile) |

When checkpoint and labels conflict, labels win and the checkpoint is discarded (stale). The `code_phase_milestone` hint is reconciled from live state at resume time — it is never treated as the sole authority.

### Checkpoint file schemas (JSON v1)

```json
// .tmp/auto-state-NUMBER.json  (single Issue)
{
  "schema_version": "v1",
  "issue_number": 317,
  "verify_iteration_count": 2,
  "code_phase_milestone": "post-commit",
  "last_update": "2026-04-22T16:10:05Z"
}
```

```json
// .tmp/auto-batch-state-${BATCH_ID}.json  (batch, per-session)
// BATCH_ID="default" -> .tmp/auto-batch-state.json (backward compat)
// BATCH_ID="12345-1718336400" -> .tmp/auto-batch-state-12345-1718336400.json
{
  "schema_version": "v1",
  "mode": "list",
  "remaining": [104, 105],
  "completed": [101, 102],
  "failed": [103],
  "last_update": "2026-04-22T16:10:05Z"
}
```

```json
// .tmp/auto-batch-active.json  (active batch index)
{
  "schema_version": "v1",
  "active_batch_ids": ["12345-1718336400", "67890-1718336500"],
  "last_update": "2026-04-22T16:10:05Z"
}
```

- `BATCH_ID` format: `${PPID}-$(date +%s)` (parent PID + Unix timestamp; bash 3.2+ compatible)
- `"default"` BATCH_ID maps to `.tmp/auto-batch-state.json` and is not tracked in the active index
- Parallel `/auto --batch` sessions each use a distinct BATCH_ID, so their state files do not collide

Writes are **atomic**: write to `*.json.tmp` then `mv` to the target path to prevent corrupt reads on interruption.

### Stale checkpoint detection

A checkpoint is considered stale and must be discarded when either of the following holds:

1. **issue_number mismatch**: the `issue_number` field in `.tmp/auto-state-NUMBER.json` does not match `NUMBER` (handled by `auto-checkpoint.sh read_single` — returns 0 and exits 0)
2. **Label conflict**: live GitHub labels show `phase/done` for the issue while a checkpoint exists (handled by `/auto` Step 4 initialization — calls `delete_single` and resets count to 0)

In both cases, the label + reconciler state is the authority and the checkpoint is dropped.

### Checkpoint cleanup triggers

| Event | Cleanup action |
|-------|---------------|
| Verify loop succeeds | `delete_single $NUMBER` |
| `MAX_ITERATIONS_REACHED` | `delete_single $NUMBER` |
| Issue CLOSED / `phase/done` detected at resume | `delete_single $NUMBER` (stale label conflict path) |
| Batch fully processed | `delete_batch "$BATCH_ID"` (also removes from active index) |

`.tmp/` files are gitignored and are not committed.

### code_phase_milestone: 6-stage resume hint (pr route only)

`run-auto-sub.sh` writes a coarse milestone to the checkpoint when starting or completing the code phase (pr route: Size M/L). At resume time, `_observe_code_milestone` probes observable git/GitHub state to determine the fine milestone, which is then used to dispatch the recovery action.

**6-stage milestone values:**

| Milestone | Meaning | resume_action |
|-----------|---------|---------------|
| `initial` | Code phase not yet started (default) | `run-code` (run `/code` normally) |
| `pre-commit` | Worktree has uncommitted changes; commit not done | `run-code` (re-run; uncommitted changes discarded) |
| `post-commit` | All commits done in worktree; push not done | `push-and-pr` (push then create PR) |
| `post-push` | Branch pushed to origin; PR not created | `create-pr` (create PR then proceed to review) |
| `pre-PR-create` | In the middle of PR creation | `create-pr` (re-attempt PR creation) |
| `post-PR-create` | PR number obtained; review not started | `skip-to-review` (skip code phase, proceed to review) |

**Write semantics (run-auto-sub.sh):**
- `write_milestone $NUMBER initial` — written before `run_phase_with_recovery "code-pr"` call (best-effort `|| true`)
- `write_milestone $NUMBER post-PR-create` — written after code-pr succeeds (best-effort `|| true`)
- Fine milestones (`pre-commit`, `post-commit`, `post-push`, `pre-PR-create`) are not written by `run-auto-sub.sh` — they are observed from git/GitHub state at resume time via `_observe_code_milestone`

**Resume preamble (at sub-issue start for pr route):**

Before calling `run_phase_with_recovery "code-pr"`, `run-auto-sub.sh` checks for residual artifacts:
- **Gate**: local branch `worktree-code+issue-N` exists OR worktree directory `.claude/worktrees/code+issue-N` exists
- If gate fires: call `_observe_code_milestone` → `write_milestone` (persist) → `resume_action` → dispatch
- If gate does not fire (first run): proceed normally with `write_milestone initial` + `run_phase_with_recovery "code-pr"`

`auto-checkpoint.sh resume_action <MILESTONE>` is a pure function mapping milestone → action, testable independently of the git/GitHub observation step.

### Scope

XL route checkpoint (sub-issue dependency graph + parallel worktree state) is out of scope for this implementation. XL sub-issues can each be individually resumed with `/auto --resume N` on their sub-issue numbers.

The `code_phase_milestone` resume preamble applies to pr route (Size M/L) only. patch route (Size XS/S) uses the existing `reconcile-phase-state.sh code-patch` completion check.
