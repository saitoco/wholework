---
name: verify
description: Acceptance test. Automatically verifies post-merge acceptance conditions and updates Issue checkboxes (`/verify 123`). Use after `/merge`. Reopens Issue on FAIL to return to the fix cycle.
context: fork
model: sonnet
allowed-tools: Bash(git checkout:*, git pull:*, git status:*, git stash:*, git add:*, git commit:*, git push:*, git merge:*, git worktree:*, git branch:*, gh issue view:*, gh issue edit:*, gh issue list:*, gh issue close:*, gh issue reopen:*, gh issue create:*, gh pr list:*, gh label list:*, gh label create:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-verify.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-extract-issue-from-pr.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-verify-iteration.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh:*, wc:*, diff:*, test:*, git log:*, git diff:*, npm:*, node:*, make:*, gh pr view:*, gh api:*), Read, Write, Edit, Glob, Grep, ToolSearch, EnterWorktree, ExitWorktree, mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_close
---

# Acceptance Test

Receive an Issue number and automatically verify post-merge acceptance conditions.

If ARGUMENTS contains `--help`, Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and follow the "Processing Steps" section to output help, then stop.

## Autonomous Mode (--auto)

If ARGUMENTS contains the `--auto` flag, delegate as follows:

> **Note**: This mode only works when invoked via `/auto` (direct `run-verify.sh` call). Running `/verify 123 --auto` directly from an interactive session spawns a fork sub-agent via `context: fork`, making it appear unresponsive because output is not streamed. In interactive sessions, run `/verify 123` without `--auto`.

1. Extract the Issue number from ARGUMENTS (numeric part)
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/run-verify.sh $NUMBER` via Bash
3. Exit after the script completes (do not execute subsequent steps)

If `--auto` is not present, proceed with mode detection below.

## Mode Detection

<!-- Flag role separation:
  --auto: Used when the user runs `/verify 123 --auto`. Delegates to run-verify.sh and exits.
  --non-interactive: Automatically added when run-verify.sh calls the verify SKILL internally.
                     Indicates autonomous execution mode in `--dangerously-skip-permissions` environment.
  This two-layer design separates --auto as a user delegation flag and --non-interactive as an
  internal execution flag.
-->

If ARGUMENTS contains the `--non-interactive` flag, operate in **non-interactive mode** (set when invoked autonomously via `run-verify.sh`).

- **Non-interactive mode**: autonomous execution in `--dangerously-skip-permissions` environment. Follow the "Non-interactive mode" column in the error handling table below
- **Interactive mode** (no flag): run normal steps

## Error Handling in Non-Interactive Mode

When invoked via `run-verify.sh` (`--dangerously-skip-permissions` environment), apply **auto-resolve + log** at each decision point instead of aborting (except hard-error cases).

Read `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md` and follow the "Non-Interactive Mode Handling" section. Per-step behavior:

| Location | Interactive mode | Non-interactive mode |
|------|-----------|---------------------|
| Step 1: uncommitted changes check | Output error and abort if uncommitted changes exist | Same (hard-error: uncommitted changes cannot be auto-resolved) |
| Step 5 (verify each condition) Step 2 (conditions with verify commands): `command` hint permission | Execute after user approval | `--dangerously-skip-permissions` removes confirmation requirement. Execute directly (auto-resolve) |
| Step 10: create improvement proposal Issue | Auto-create Issue | Same (auto-resolve) |
| Any other AskUserQuestion during verification | Ask user | Auto-resolve: adopt the safest interpretation (treat ambiguous conditions as UNCERTAIN rather than PASS); record decision in the Spec's `## Autonomous Auto-Resolve Log` subsection |

## Steps

**Do not use compound commands (`&&`, `|`).**

### Step 1: Check Working Directory Safety

```bash
git status
```

- **Uncommitted changes present** → output error message and abort:
  Output the `VERIFY_FAILED` marker at the start of the error message (`run-verify.sh` detects this marker to propagate the error):
  "VERIFY_FAILED"
  Then output the error message:
  "Error: Cannot run verify because there are uncommitted changes. Run `git stash` or `git commit`, then re-run `/verify $NUMBER`."
- **Clean** → continue

Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` and display the start banner with ENTITY_TYPE="issue", ENTITY_NUMBER=$NUMBER, SKILL_NAME="verify".

**pre-check: all-checked, no-implementation pattern**

After the banner, detect the false-ready state: all acceptance conditions are pre-checked (`[x]`) but no implementation commit or merged PR exists for this issue. If detected, output a warning and continue (do not abort).

1. Fetch Issue body: `gh issue view "$NUMBER" --json body`
2. **Metadata-only implementation-type check**: If the Issue body contains the `<!-- implementation-type: metadata-only -->` marker, skip the false-ready detection below and continue with the normal verify flow. Metadata-only routes (e.g., issues whose implementation is purely `gh issue edit` or other GitHub-metadata changes that intentionally produce no file commits or PRs) have no implementation commit or merged PR by design, so the commit/PR check would always fire as a false positive.
3. Count total checkboxes and checked (`[x]`) items in the Acceptance Criteria section
4. If all conditions are checked:
   - Check for merged PR: `gh pr list --search "closes #$NUMBER" --state merged --json number --jq 'length'`
   - Check for direct commits: `git log --oneline --grep="#$NUMBER" -20`
   - If no implementation commit or merged PR is found (both return 0 results), output the following warning and continue:
     ```
     Warning: All acceptance conditions are pre-checked but no implementation commit or PR was found for issue #$NUMBER. This may be a false-ready state.
     ```
5. Continue with normal verify flow

### Step 2: Detect and Update Base Branch

If ARGUMENTS contains `--base {branch}`, use that as `BASE_BRANCH`. Otherwise, search for a merged PR linked to the Issue and fetch `baseRefName`:

```bash
PR_NUMBER=$(gh pr list --search "closes #$ISSUE_NUMBER" --state merged --json number --jq ".[0].number")
```

If PR number is found:

```bash
EXTRACT_RESULT=$(${CLAUDE_PLUGIN_ROOT}/scripts/gh-extract-issue-from-pr.sh "$PR_NUMBER")
BASE_BRANCH=$(echo "$EXTRACT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('base_ref','main'))")
```

Default to `BASE_BRANCH=main` if no PR is found or base branch cannot be fetched.

If `--base` is not specified and `PR_NUMBER` is empty, search for an OPEN PR before checking out:

```bash
OPEN_PR=$(gh pr list --search "closes #$ISSUE_NUMBER" --state open --json number,title --jq ".[0].number")
```

If `OPEN_PR` is not empty, output `VERIFY_FAILED` and abort:

```
VERIFY_FAILED
Warning: PR #$OPEN_PR is open but not yet merged.
/verify is designed to run after merge. Please merge PR #$OPEN_PR first, then re-run `/verify $ISSUE_NUMBER`.
```

```bash
git checkout "${BASE_BRANCH}"
```

```bash
git pull origin "${BASE_BRANCH}"
```

### Step 3: Worktree Entry

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Entry section" to create a worktree.

**Worktree naming convention:** `verify/issue-$NUMBER`

Record the `ENTERED_WORKTREE` variable for use in subsequent steps.

### Step 4: Fetch Issue Acceptance Conditions

```bash
gh issue view "$NUMBER" --json body
```

Parse acceptance condition checkboxes:

**Resolving configuration values**: Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section to fetch configuration values from `.wholework.yml`. Retain `SPEC_PATH`, `STEERING_DOCS_PATH`, `PRODUCTION_URL`, and `VERIFY_MAX_ITERATIONS` for use in subsequent steps.

Read `${CLAUDE_PLUGIN_ROOT}/modules/domain-loader.md` and follow the "Processing Steps" section with `SKILL_NAME=verify`. Domain file content provides Skill infrastructure improvement classification criteria for Step 13.

**Resolving `{{base_url}}` to production URL**: If verify commands contain `{{base_url}}`, replace `{{base_url}}` with `PRODUCTION_URL` before passing to verify-executor.

- If `PRODUCTION_URL` is found: run browser verification with the replaced URL
- If `PRODUCTION_URL` is empty (not configured): treat verify commands containing `{{base_url}}` as UNCERTAIN, noting "`production-url` is not configured in `.wholework.yml`" in the remarks column

- If there are no section divisions, target all unchecked items
- If sections are divided into "Pre-merge (auto verify)" and "Post-merge":
  - **Pre-merge**: treat all conditions as auto-verification targets (with or without hints)
  - **Post-merge + with hints** (`<!-- verify: ... -->`): treat as auto-verification targets
  - **Post-merge + without hints**: not an auto-verification target. Present as user verification guide only; do not update checkboxes

### Step 5: Verify Each Condition

**Patch route detection (run before verification):**

If PR_NUMBER (from Step 2) is empty and any acceptance condition contains `github_check "gh pr checks"`, treat those conditions as UNCERTAIN with the following guidance:

> PR does not exist (patch route). Use `github_check "gh run list"` form instead. See `${CLAUDE_PLUGIN_ROOT}/modules/verify-classifier.md`.

Example replacement:
```
# Before (patch route incompatible)
github_check "gh pr checks" "Run bats tests"

# After (patch route compatible)
github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success"
```

Do not attempt to run `github_check "gh pr checks"` conditions in patch route Issues — mark as UNCERTAIN immediately and skip execution.

Verification priority:

#### Step 1: CI Infrastructure Failure Detection (only when referencing CI results)

When referencing CI job results, determine whether the failure is infrastructure-caused (not from test code). The following patterns are considered **CI infrastructure failures**:

| Pattern | Reasoning |
|---------|---------|
| steps is empty (`steps: []`) | Job terminated abnormally before starting. Test code was not executed |
| Timeout (`cancelled` + execution time exceeded) | Forced termination due to infrastructure response delay |
| Runner error (e.g., `The runner has received a shutdown signal`) | GitHub Actions runner anomaly |
| Network error (e.g., `Unable to download`, `ECONNREFUSED`) | Dependency download failure |

**Fall back to local tests** (when infrastructure failure is determined):

1. Ignore CI results; fetch local test commands from `command` verify commands and run them
2. For acceptance conditions without `command` verify commands, fall back with AI judgment
3. If local tests pass: **treat as PASS via alternative verification** (note "CI infrastructure failure; verified via local tests" in details)
4. If local tests fail: treat as FAIL (problem with the test code itself)

**Note**: The infrastructure failure determination errs on the safe side. If not detected, it remains UNCERTAIN/FAIL rather than becoming an incorrect PASS.

#### Step 2: Conditions with Verify Commands

For conditions with `<!-- verify: ... -->`, Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md` and follow the "Processing Steps" section's translation table to translate and execute verify commands. Mode: **full** (`command` hints are also treated as execution targets; however, actual execution is only after user approval).

**Security note for `command` hints**: In full mode, "execute `command` hints" means:
- **Interactive mode**: present the command to the user and execute only after approval. Treat suspicious commands as UNCERTAIN.
- **Non-interactive mode** (`--dangerously-skip-permissions` environment): no approval required. Execute commands directly. `command` hints are written in Issue bodies managed by repository maintainers and are treated as trusted commands. Do not use in repositories where external contributors have write access.

**`rubric` commands**: Processed via the same verify-executor translation table. Runs in both safe and full modes (`always_allow` — no side effects); the grader receives the Issue body, git diff, and any files explicitly named in the rubric text as input. Returns PASS, FAIL, or UNCERTAIN; FAIL includes a natural-language gap description.

**Syntax errors** (unknown commands, missing arguments, etc.) → treat as UNCERTAIN and fall back to AI judgment. Record error details in the remarks column of the results table.

**Browser verification command (`browser_check`, `browser_screenshot`) processing flow:**

First check `HAS_BROWSER_CAPABILITY` (fetched via `detect-config-markers.md` in Step 4). Reuse the value. Only if `HAS_BROWSER_CAPABILITY=true`, Read `skills/verify/browser-verify-phase.md` and follow the "Inside Step 2: Browser Verification Command Processing Flow" section. If `HAS_BROWSER_CAPABILITY` is unset or false, treat browser verification commands as UNCERTAIN.

#### Step 3: No Hints → Attempt Verification with AI Judgment

**Responsibility boundary with `rubric`**: Step 3 is an implicit fallback for conditions that lack a `<!-- verify: ... -->` hint — it applies best-effort AI judgment opportunistically. `rubric` is an explicit opt-in declared at Issue creation time, processed in Step 2 via the verify-executor translation table. The two paths coexist: `rubric` for declared semantic judgment, Step 3 for hint-less fallback.

If the condition follows the pattern "command X works" or "tests pass", Read `${CLAUDE_PLUGIN_ROOT}/modules/test-runner.md` and follow the "Processing Steps" section to run tests.

For other patterns, verify using the translation table below:

**Condition text patterns (examples):**

| Condition text pattern | Verification method |
|----------------|---------|
| "X has been created" / "X has been deleted" | `test -f` / `test ! -f` |
| "X section exists" / "X is documented" | Read file content and analyze |
| "X has been updated" | Check for changes with `git diff` + analyze content validity with Read |
| "X is supported" | Read entire file, AI judgment on feature/structure presence |
| "X is configured" | Check environment |

#### Step 4: Cannot Auto-Verify → Defer to User Verification

The following cannot be auto-verified:
- Things that can only be confirmed in external services or production environments
- Subjective UI/UX evaluations
- Conditions starting with "The user..." (requires user action)

**Prerequisite check before browser-verifiable case exclusion**: Before making this determination, confirm that `HAS_BROWSER_CAPABILITY` has been fetched (via `detect-config-markers.md` in Step 4).

**Browser-verifiable case exclusion**: Only if `HAS_BROWSER_CAPABILITY=true` is confirmed via the above steps, Read `skills/verify/browser-verify-phase.md` and follow the "Inside Step 4: Browser-Verifiable Case Exclusion" section for classification. If `HAS_BROWSER_CAPABILITY` is unset or false, treat conditions with browser verification commands as UNCERTAIN.

### Step 6: Update Checkboxes

Identify the checkbox indices (1-based) of conditions that PASSed and pass to the script:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh "$NUMBER" --checkbox <pass-indices> --check
# Example: if 1st and 3rd acceptance conditions PASS
# ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh "$NUMBER" --checkbox 1,3 --check
```

**Checkbox mode** (when updating only checkboxes by index):

Identify PASS condition indices (1-based) and update individually:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh "$NUMBER" --checkbox 1,3 --check
```

Comma-separated multiple indices are supported. Use `--uncheck` to uncheck.

**Handling partial PASS:**
- PASS conditions → immediately update to `- [x]`
- FAIL conditions → leave as `- [ ]`
- SKIPPED conditions → leave as `- [ ]` (not executed due to unmet environment conditions)
- Cannot auto-verify → leave as `- [ ]` (deferred to user verification)
- **Post-merge + no hints conditions** → do not update checkboxes (maintain `- [ ]`)
- **Re-runs**: re-verify all conditions (idempotent). Re-verify even if already checked; report via comment if result changes

### Step 7: Post Comment on Issue

**Comment body format:**

Do not include checkbox format in the comment body. Do not duplicate Issue body checkboxes in the comment — the Issue body is the SSoT; checkboxes added to comments are not persisted when the comment is updated.

Use the following format for the comment body:

```
## Acceptance Test Results

### Auto Verification
| Condition | Result | Details |
|-----------|--------|---------|
| Condition 1 | PASS | Summary of verification method |
| Condition 2 | FAIL | Reason for failure |
| Condition 3 | UNCERTAIN | Reason auto-determination is not possible |
| Condition 4 | PENDING | CI is in_progress; re-run after CI completes |
| Condition 5 | SKIPPED | Not executed due to unmet environment conditions |

### Items Requiring User Verification

**1. Condition content**

Verification steps:
1. What to do (specific action: run command, access URL, etc.)
2. Where (terminal, browser, specific directory)
3. What to look for (output/state to verify)

Verification command: `specific command`
Success criteria: what output/state indicates success
On failure: what to do if different from expected
```

Write body to `.tmp/issue-comment-$NUMBER.md` with Write tool, then pass to script:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh "$NUMBER" ".tmp/issue-comment-$NUMBER.md"
rm -f .tmp/issue-comment-$NUMBER.md
```

### Step 8: Output Summary to Terminal

Output in the following format to terminal:

```markdown
## Acceptance Test Results

### Auto Verification
| Condition | Result | Details |
|-----------|--------|---------|
| Condition 1 | ✅ PASS | Summary of verification method |
| Condition 2 | ❌ FAIL | Reason for failure |
| Condition 3 | ⚠️ UNCERTAIN | Reason auto-determination is not possible |
| Condition 4 | ⏳ PENDING | CI is in_progress; re-run after CI completes |
| Condition 5 | ⏭️ SKIPPED | Not executed due to unmet environment conditions |

### Items Requiring User Verification

Present post-merge section conditions without hints and conditions that cannot be auto-verified as a user verification guide in the following format.

**1. Condition content**

Verification steps:
1. What to do (specific action: run command, access URL, etc.)
2. Where (terminal, browser, specific directory)
3. What to look for (output/state to verify)

Verification command: `specific command`
Success criteria: what output/state indicates success
On failure: what to do if different from expected
```

### Step 9: Apply Verification Results

First, detect the current Issue state:

```bash
gh issue view "$NUMBER" --json state --jq '.state'
```

**Conditions subject to reopen judgment**:
- All pre-merge conditions (with or without hints)
- Post-merge conditions with hints (`<!-- verify: ... -->`)
- **Post-merge conditions without hints are excluded** (user verification items)

Branch on Issue state:

- `OPEN` → Issue OPEN path (auto-close disabled; see below)
- `CLOSED` → Issue CLOSED path (standard flow; see below)

#### When Issue is CLOSED (standard flow via `closes #N`)

Judgment:

- **All auto-verification target conditions are PASS or SKIPPED (0 FAIL/UNCERTAIN among auto-verification targets; SKIPPED is ignored as environment conditions were unmet)**:
  - Check if any unchecked (`- [ ]`) `<!-- verify-type: opportunistic -->` or `<!-- verify-type: manual -->` conditions remain in the post-merge section of the Issue body
  - **If unchecked opportunistic or manual conditions remain**: assign `phase/verify` (Issue remains CLOSED; do not reopen):
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify
    ```
    Inform the user: "Manually check the remaining opportunistic/manual conditions, then re-run `/verify $NUMBER` to complete."
  - **If all conditions are checked**: assign `phase/done`. Confirm the Issue is closed. If not closed, close with `gh issue close "$NUMBER"` (handles cases like XL parent Issues not auto-closed by PR's `closes #N`):
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" done
    ```
  - **Even if post-merge conditions without hints are unchecked, do not reopen the Issue** (present user verification guide only)
- **Auto-verification targets include FAIL**:
  - Check iteration counter before reopening:
    ```bash
    CURRENT_ITERATION=$(${CLAUDE_PLUGIN_ROOT}/scripts/get-verify-iteration.sh "$NUMBER")
    NEXT_ITERATION=$((CURRENT_ITERATION + 1))
    ```
  - If `NEXT_ITERATION < VERIFY_MAX_ITERATIONS` (limit not yet reached):
    - Post a comment with the updated counter marker:
      ```
      <!-- verify-iteration: ${NEXT_ITERATION} -->
      Verification FAIL (iteration ${NEXT_ITERATION}/${VERIFY_MAX_ITERATIONS}). Reopening Issue for fix cycle.
      ```
    - Reopen Issue and remove all `phase/*` labels:
      ```bash
      gh issue reopen "$NUMBER"
      ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER"
      ```
    - Output guidance for the user:
      ```
      Issue #N を再オープンしました。以下のいずれかで修正してください:
      - `/code --patch N` — Size を変えずに main 直コミットで修正（小さな修正）
      - `/code --pr N` — 新規ブランチ + PR で修正（Size L の大きな修正）
      - `/spec N` — Spec から見直し（根本的な設計変更が必要な場合）
      ```
  - If `NEXT_ITERATION >= VERIFY_MAX_ITERATIONS` (limit reached):
    - Post a comment with the max-iterations notice:
      ```
      <!-- verify-iteration: ${NEXT_ITERATION} -->
      max iterations reached (${NEXT_ITERATION}/${VERIFY_MAX_ITERATIONS}). Stopping verify-reopen loop. Issue stays in phase/verify for human judgment.
      ```
    - Assign `phase/verify` label without reopening (Issue remains CLOSED):
      ```bash
      ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify
      ```
    - Output `MAX_ITERATIONS_REACHED` to terminal followed by guidance:
      ```
      MAX_ITERATIONS_REACHED
      verify-reopen ループが上限（${VERIFY_MAX_ITERATIONS}回）に達しました。Issue #N は phase/verify に留まります。手動で調査・修正してください。
      ```
- **PENDING のみ（FAIL なし、PENDING ≥1）**:
  - Assign `phase/verify` label without reopening the Issue:
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify
    ```
  - Notify user: "CI が実行中のため一部の条件が PENDING です。CI 完了後に `/verify $NUMBER` を再実行してください。"
- **UNCERTAIN のみ（FAIL なし、UNCERTAIN ≥1）**:
  - Assign `phase/verify` label without reopening the Issue:
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify
    ```
  - Notify user: "Auto-verification contains UNCERTAIN items. Please manually re-verify the flagged conditions, then re-run `/verify $NUMBER` to complete."

#### When Issue is OPEN (auto-close disabled)

When the repository has GitHub's "Auto-close issues with merged linked pull requests" setting disabled, Issues remain OPEN after merge even when the PR body contains `closes #N`.

Judgment:

- **All auto-verification target conditions are PASS or SKIPPED**:
  - Check if any unchecked (`- [ ]`) `<!-- verify-type: opportunistic -->` or `<!-- verify-type: manual -->` conditions remain in the post-merge section of the Issue body
  - **If unchecked opportunistic or manual conditions remain**: assign `phase/verify` (Issue remains OPEN; do not close):
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify
    ```
    Inform the user: "Manually check the remaining opportunistic/manual conditions, then re-run `/verify $NUMBER` to complete."
  - **If all conditions are checked**: assign `phase/done` and close:
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" done
    gh issue close "$NUMBER"
    ```
  - **Even if post-merge conditions without hints are unchecked, do not close the Issue** (present user verification guide only)
- **Auto-verification targets include FAIL**:
  - Check iteration counter before processing:
    ```bash
    CURRENT_ITERATION=$(${CLAUDE_PLUGIN_ROOT}/scripts/get-verify-iteration.sh "$NUMBER")
    NEXT_ITERATION=$((CURRENT_ITERATION + 1))
    ```
  - If `NEXT_ITERATION < VERIFY_MAX_ITERATIONS` (limit not yet reached):
    - Post a comment with the updated counter marker:
      ```
      <!-- verify-iteration: ${NEXT_ITERATION} -->
      Verification FAIL (iteration ${NEXT_ITERATION}/${VERIFY_MAX_ITERATIONS}). Issue stays open for fix cycle.
      ```
    - Remove all `phase/*` labels (Issue is already OPEN; no reopen needed):
      ```bash
      ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER"
      ```
    - User selects the next action (`/code`, `/spec`, or `/issue`) to return to the fix cycle
  - If `NEXT_ITERATION >= VERIFY_MAX_ITERATIONS` (limit reached):
    - Post a comment with the max-iterations notice:
      ```
      <!-- verify-iteration: ${NEXT_ITERATION} -->
      max iterations reached (${NEXT_ITERATION}/${VERIFY_MAX_ITERATIONS}). Stopping verify-reopen loop. Issue stays in phase/verify for human judgment.
      ```
    - Assign `phase/verify` label (Issue remains OPEN):
      ```bash
      ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify
      ```
    - Output `MAX_ITERATIONS_REACHED` to terminal followed by guidance:
      ```
      MAX_ITERATIONS_REACHED
      verify-reopen ループが上限（${VERIFY_MAX_ITERATIONS}回）に達しました。Issue #N は phase/verify に留まります。手動で調査・修正してください。
      ```
- **PENDING のみ（FAIL なし、PENDING ≥1）**:
  - Assign `phase/verify` label (Issue remains OPEN):
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify
    ```
  - Notify user: "CI が実行中のため一部の条件が PENDING です。CI 完了後に `/verify $NUMBER` を再実行してください。"
- **UNCERTAIN のみ（FAIL なし、UNCERTAIN ≥1）**:
  - Assign `phase/verify` label (Issue remains OPEN):
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify
    ```
  - Notify user: "Auto-verification contains UNCERTAIN items. Please manually re-verify the flagged conditions, then re-run `/verify $NUMBER` to complete."

### Step 10: Retrospective (Full Workflow Review)

As the final step of the workflow, verify conducts a retrospective of the entire Issue lifecycle.

**Retrospective scope**: All phases (spec → design → code → review → merge → verify)
**Information sources**: verification results, git log, Issue/PR comments, Spec, PR diff

**Retrospective dimensions:**

| Phase | Retrospective dimension | Information source | Detection method |
|---------|-------------|--------|---------|
| issue | Acceptance condition quality (ambiguity, verifiability, gaps), ambiguity resolution history, decision validity | `## Issue Retrospective` section in Spec (also search `## Spec Retrospective` for backward compatibility) | Check issue retrospective section when reading Spec |
| spec | Design validity (deviations from implementation, oversights), design decision validity, use of minor observations | Spec, `## Spec Retrospective` section in Spec (also search `## Design Retrospective` for backward compatibility), PR diff | Compare `$SPEC_PATH/issue-$NUMBER-*.md` with diff; check spec retrospective (or design retrospective) section when reading Spec |
| code | Implementation rework (fixup/amend patterns in commit history, number of review comment incorporations), design deviation patterns, rework cause analysis | git log, `## Code Retrospective` section in Spec | Detect fixup/amend patterns with `git log --oneline`; check code retrospective section when reading Spec |
| review | Review effectiveness (were comments accurate, anything missed), review comment trends, oversight patterns | PR review comments, `## Review Retrospective` section in Spec, verification results | Check whether FAIL items were detected in review; check review retrospective section when reading Spec |
| merge | Merge process issues (conflicts, CI failures, etc.) | git log, PR status | Check merge commit messages for conflict resolution traces |
| verify | FAIL root causes, verify command inconsistencies | Verification results | Analyze Step 5 results |

> **Note: Obligation to verify factual claims**: When writing factual claims such as "fixed" or "resolved", confirm the corresponding commit exists with `git log --oneline` before recording. Factual claims without commit verification can lead to incorrect PASS judgments.

**Steps:**

1. Collect information:
   - Confirm Issue body with `gh issue view "$NUMBER" --json body` (reuse if already fetched in Step 3)
   - Read Spec (if `$SPEC_PATH/issue-$NUMBER-*.md` exists)
     - Extract `## Issue Retrospective` section (result of `/issue` retrospective; also search `## Spec Retrospective` for backward compatibility)
     - Extract `## Spec Retrospective` section (result of `/spec` retrospective; also search `## Design Retrospective` for backward compatibility)
     - Extract `## Code Retrospective` section (result of `/code` retrospective)
     - Extract `## Review Retrospective` section (result of `/review` retrospective)
     - Extract `## Auto Retrospective` section (present when orchestration anomalies were detected on any route; skip if not present)
   - Identify related PR and review commit history with `git log --oneline`
2. Detect improvements across the 6 phases above:
   - Integrate content from each phase's retrospective
   - Cross-reference information sources in the retrospective dimensions table with collected retrospective information to detect improvement patterns across the entire workflow
3. **Persist retrospective results to Spec**:
   - If Spec (`$SPEC_PATH/issue-$NUMBER-*.md`) does not exist: skip persistence and output to terminal only
   - If Spec exists, add `## Verify Retrospective` section at the end
   - Include improvement proposals if any, or "N/A" if none
   - Use the following template:
     ```markdown
     ## Verify Retrospective

     ### Phase-by-Phase Review

     #### spec
     - (observations on acceptance condition quality, spec ambiguities, etc.)

     #### design
     - (observations on design validity, design decision validity, etc.)

     #### code
     - (observations on implementation rework, design deviation patterns, etc.)

     #### review
     - (observations on review effectiveness, comment trends, etc.)

     #### merge
     - (observations on merge process issues, etc.)

     #### verify
     - (observations on FAIL root causes, verify command inconsistencies, etc.)

     ### Improvement Proposals
     - (list improvement proposals here, or "N/A" if none)
     ```
   - Append section at end of Spec with Edit tool
   - Commit (push is done in Step 11 Worktree Exit):
     ```bash
     git add $SPEC_PATH/issue-"$NUMBER"-*.md
     git commit -s -m "Add verify retrospective for issue #$NUMBER

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
     ```
     ```bash
     git log -1 --format='%B' | grep -q "^Signed-off-by:" || { echo "ERROR: missing sign-off"; exit 1; }
     ```

### Step 11: Worktree Exit (merge-to-main)

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Exit: merge-to-main section" to exit the worktree.

Behavior differs based on `ENTERED_WORKTREE`:
- `ENTERED_WORKTREE=true`: ExitWorktree("keep") → merge → push → cleanup
- `ENTERED_WORKTREE=false`: run `git push origin main` normally

### Step 12: Opportunistic Verification

Only if `.wholework.yml` in the project has `opportunistic-verify: true`, Read `${CLAUDE_PLUGIN_ROOT}/modules/opportunistic-verify.md` and follow the "Processing Steps" section to run opportunistic verification. The skill name is `/verify`. Skip this step if not configured.

### Step 13: Collect Improvement Proposals and Create Issues

Read `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` and follow the "Processing Steps" section to normalize titles (used for Issue title normalization when creating Issues). Reuse `HAS_SKILL_PROPOSALS` already fetched via `detect-config-markers.md` in Step 4 (if `opportunistic-verify.md` in Step 12 fetched it again, reuse that result).

Extract text from `### Improvement Proposals` sections in each Spec retrospective section (spec, design, code, review, verify, auto). Note: `## Auto Retrospective` is generated by `/auto` for XL routes (always) and for M/L/patch routes when orchestration anomalies were detected (see `/auto` Step 4a); it is not generated for anomaly-free M/L/patch executions.

**Judgment criteria**: If the `### Improvement Proposals` section text contains only "N/A" or "None", treat as no improvement proposals. Any other text is treated as having improvement proposals. Make this determination mechanically based on text presence alone, without judging duplication with existing guidelines or validity.

Integrate improvement proposals collected from multiple phases, removing only exact duplicates.

**If no improvement proposals**: proceed to completion report.

**If improvement proposals exist**:

**Early gate — if `HAS_SKILL_PROPOSALS=false`**: skip classification. Treat all proposals as Code improvements and proceed directly to the Code improvement handler (duplicate check → freshness check → create Issues). No skill-infra classification, no skip-count log.

**If `HAS_SKILL_PROPOSALS=true`**: classify each improvement proposal using the criteria from the Domain file loaded in Step 4 (`.wholework/domains/verify/`). If no Domain file was loaded, treat all proposals as Code improvements.

- **Code improvement**: improvement proposals not falling into the Skill infrastructure improvement criteria above (proposals for code, configuration, tests, CI, etc. in the current repository)

After classifying collected improvement proposals, create Issues per the following rules (auto-execute without confirmation):

- **Code improvement**: always create Issue
- **Skill infrastructure improvement**: create Issue (reached only when `HAS_SKILL_PROPOSALS=true`)

For proposals to be Issue-ized:

**Duplicate check against existing Issues (always run before creating Issues):**

```bash
gh issue list --state open --limit 200 --json number,title
```

Fetch the list of open Issues. Semantically compare each improvement proposal's title (after normalization) against existing Issue titles. If the same or substantially identical improvement proposal is already Issue-ized, skip creating a new Issue. Output skipped proposals to terminal (e.g., "Skipping Issue creation due to duplicate: {title} (existing: #{number})"). Criteria for duplicate: title or content is identical/similar, or an existing Issue's background/purpose targets substantially the same improvement.

For non-duplicate proposals, process in order:

**Pre-resolution check (freshness verification)**:

Extract 1–3 keywords from the improvement proposal content, then grep related files in the current main branch to check if the issue is already resolved (infer implementation target files from proposal content):

```bash
grep -r "{keyword}" {target file or directory}
```

- **If judged as resolved**: skip Issue creation and output to terminal (e.g., "Skipping due to freshness check: {title} (may already be resolved in main)")
- **If unresolved or cannot determine**: proceed to the next step (Issue creation)

**Create Issue and add verify commands**:

- Normalize title following `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` processing steps, then create Issues in standard format (background, purpose, acceptance conditions) with `gh issue create --label "retro/verify"` for each improvement proposal. Do not add the `triaged` label; the `triaged` label is assigned by the `/triage` skill after triage is actually executed.
- **Add verify commands to acceptance conditions**: add verify commands like `<!-- verify: grep "{keyword}" "{target file}" -->` to the created Issue's acceptance conditions. Extract keywords from acceptance condition text and infer target files from proposal content (improves automation accuracy for `/auto --batch`). Create Issue without verify commands if they cannot be determined
- If Issue creation fails, output error log to stderr, skip, and continue verify (does not affect exit code)
- Output created Issue number to terminal

**Completion report (always use this format):**

- All conditions PASS: "Acceptance test complete. Issue #$NUMBER is closed."
- Partial PASS: "Acceptance test found unchecked conditions. Issue #$NUMBER has been reopened."

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=verify`
- `ISSUE_NUMBER=$NUMBER`
- `RESULT={success if PASS, fail if partial PASS}`

---

## Notes

- Verification commands are read-only in principle (do not modify the environment)
- Always wrap variables (`$NUMBER`, etc.) in double quotes
- Always create and write temp files with the Write tool. Creating or writing temp files via Bash `cat`/`echo`/redirect (`>`) is prohibited (causes confirmation prompts)
