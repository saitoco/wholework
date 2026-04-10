---
name: verify
description: Acceptance test. Automatically verifies post-merge acceptance conditions and updates Issue checkboxes (`/verify 123`). Use after `/merge`. Reopens Issue on FAIL to return to the fix cycle.
context: fork
allowed-tools: Bash(git checkout:*, git pull:*, git status:*, git stash:*, git add:*, git commit:*, git push:*, git merge:*, git worktree:*, git branch:*, gh issue view:*, gh issue edit:*, gh issue list:*, gh issue close:*, gh issue reopen:*, gh issue create:*, gh pr list:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-verify.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-extract-issue-from-pr.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*, wc:*, diff:*, test:*, git log:*, git diff:*, npm:*, node:*, make:*, gh pr view:*, gh api:*), Read, Write, Edit, Glob, Grep, ToolSearch, EnterWorktree, ExitWorktree, mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_close
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

When invoked via `run-verify.sh` (`--dangerously-skip-permissions` environment), take the following alternative actions at each step:

| Location | Interactive mode | Non-interactive mode |
|------|-----------|---------------------|
| Step 1: uncommitted changes check | Output error and abort if uncommitted changes exist | Same |
| Step 5 (verify each condition) Step 2 (conditions with acceptance checks): `command` hint permission | Execute after user approval | `--dangerously-skip-permissions` removes confirmation requirement. Execute directly |
| Step 10: create improvement proposal Issue | Auto-create Issue | Same |

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

### Step 2: Detect and Update Base Branch

If ARGUMENTS contains `--base {branch}`, use that as `BASE_BRANCH`. Otherwise, search for a merged PR linked to the Issue and fetch `baseRefName`:

```bash
PR_NUMBER=$(gh pr list --search "$ISSUE_NUMBER" --state merged --json number --jq ".[0].number")
```

If PR number is found:

```bash
EXTRACT_RESULT=$(${CLAUDE_PLUGIN_ROOT}/scripts/gh-extract-issue-from-pr.sh "$PR_NUMBER")
BASE_BRANCH=$(echo "$EXTRACT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('base_ref','main'))")
```

Default to `BASE_BRANCH=main` if no PR is found or base branch cannot be fetched.

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

**Resolving `{{base_url}}` to production URL**: If acceptance checks contain `{{base_url}}`, Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section to fetch `PRODUCTION_URL` from `.wholework.yml` (key: `production-url: "https://example.com"`). Then replace `{{base_url}}` with `PRODUCTION_URL` before passing to verify-executor.

- If `PRODUCTION_URL` is found: run browser verification with the replaced URL
- If `PRODUCTION_URL` is empty (not configured): treat acceptance checks containing `{{base_url}}` as UNCERTAIN, noting "`production-url` is not configured in `.wholework.yml`" in the remarks column

- If there are no section divisions, target all unchecked items
- If sections are divided into "Pre-merge (auto verify)" and "Post-merge":
  - **Pre-merge**: treat all conditions as auto-verification targets (with or without hints)
  - **Post-merge + with hints** (`<!-- verify: ... -->`): treat as auto-verification targets
  - **Post-merge + without hints**: not an auto-verification target. Present as user verification guide only; do not update checkboxes

### Step 5: Verify Each Condition

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

1. Ignore CI results; fetch local test commands from `command` acceptance checks and run them
2. For acceptance conditions without `command` acceptance checks, fall back with AI judgment
3. If local tests pass: **treat as PASS via alternative verification** (note "CI infrastructure failure; verified via local tests" in details)
4. If local tests fail: treat as FAIL (problem with the test code itself)

**Note**: The infrastructure failure determination errs on the safe side. If not detected, it remains UNCERTAIN/FAIL rather than becoming an incorrect PASS.

#### Step 2: Conditions with Acceptance Checks

For conditions with `<!-- verify: ... -->`, Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md` and follow the "Processing Steps" section's translation table to translate and execute acceptance checks. Mode: **full** (`command` hints are also treated as execution targets; however, actual execution is only after user approval).

**Security note for `command` hints**: In full mode, "execute `command` hints" means:
- **Interactive mode**: present the command to the user and execute only after approval. Treat suspicious commands as UNCERTAIN.
- **Non-interactive mode** (`--dangerously-skip-permissions` environment): no approval required. Execute commands directly. `command` hints are written in Issue bodies managed by repository maintainers and are treated as trusted commands. Do not use in repositories where external contributors have write access.

**Syntax errors** (unknown commands, missing arguments, etc.) → treat as UNCERTAIN and fall back to AI judgment. Record error details in the remarks column of the results table.

**Browser verification command (`browser_check`, `browser_screenshot`) processing flow:**

First check `HAS_BROWSER_CAPABILITY`. If not yet fetched, Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` at this point to fetch it. Reuse the value if already fetched. Only if `HAS_BROWSER_CAPABILITY=true`, Read `skills/verify/browser-verify-phase.md` and follow the "Inside Step 2: Browser Verification Command Processing Flow" section. If `HAS_BROWSER_CAPABILITY` is unset or false, treat browser verification commands as UNCERTAIN.

#### Step 3: No Hints → Attempt Verification with AI Judgment

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

**Prerequisite check before browser-verifiable case exclusion**: Before making this determination, confirm that `HAS_BROWSER_CAPABILITY` has been fetched within the same `/verify` execution flow. If not yet fetched, Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` at this point to fetch it.

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
| Condition 4 | ⏭️ SKIPPED | Not executed due to unmet environment conditions |

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

Assuming Issues are auto-closed via `closes #N` in PR body on merge, take the following actions based on verification results.

**Conditions subject to reopen judgment**:
- All pre-merge conditions (with or without hints)
- Post-merge conditions with hints (`<!-- verify: ... -->`)
- **Post-merge conditions without hints are excluded** (user verification items)

Judgment:

- **All auto-verification target conditions are PASS or SKIPPED (0 FAIL/UNCERTAIN among auto-verification targets; SKIPPED is ignored as environment conditions were unmet)**:
  - Check if any unchecked (`- [ ]`) `<!-- verify-type: opportunistic -->` or `<!-- verify-type: manual -->` conditions remain in the post-merge section of the Issue body
  - **If unchecked opportunistic or manual conditions remain**: assign `phase/verify` label and remove all other `phase/*` labels:
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" verify
    ```
  - **If no unchecked opportunistic or manual conditions remain**: remove all `phase/*` labels and assign `phase/done` (also handles cases where `phase/code` persists in patch route):
    ```bash
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER" done
    ```
  - Confirm the Issue is closed. If not closed, close with `gh issue close "$NUMBER"` (handles cases like XL parent Issues not auto-closed by PR's `closes #N`)
  - **Even if post-merge conditions without hints are unchecked, do not reopen the Issue** (present user verification guide only)
- **Auto-verification targets include FAIL or UNCERTAIN**:
  - Reopen Issue and remove all `phase/*` labels:
    ```bash
    gh issue reopen "$NUMBER"
    ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$NUMBER"
    ```
  - User selects the next action (`/code`, `/spec`, or `/issue`) to return to the fix cycle

### Step 10: Retrospective (Full Workflow Review)

As the final step of the workflow, verify conducts a retrospective of the entire Issue lifecycle.

**Retrospective scope**: All phases (spec → design → code → review → merge → verify)
**Information sources**: verification results, git log, Issue/PR comments, Spec, PR diff

**Retrospective dimensions:**

| Phase | Retrospective dimension | Information source | Detection method |
|---------|-------------|--------|---------|
| issue | Acceptance condition quality (ambiguity, verifiability, gaps), ambiguity resolution history, decision validity | `## Issue Retrospective` section in Spec (also search `## Spec Retrospective` for backward compatibility) | Check issue retrospective section when reading Spec |
| spec | Design validity (deviations from implementation, oversights), design decision validity, use of minor observations | Spec, `## Spec Retrospective` section in Spec (also search `## Design Retrospective` for backward compatibility), PR diff | Compare `docs/spec/issue-$NUMBER-*.md` with diff; check spec retrospective (or design retrospective) section when reading Spec |
| code | Implementation rework (fixup/amend patterns in commit history, number of review comment incorporations), design deviation patterns, rework cause analysis | git log, `## Code Retrospective` section in Spec | Detect fixup/amend patterns with `git log --oneline`; check code retrospective section when reading Spec |
| review | Review effectiveness (were comments accurate, anything missed), review comment trends, oversight patterns | PR review comments, `## Review Retrospective` section in Spec, verification results | Check whether FAIL items were detected in review; check review retrospective section when reading Spec |
| merge | Merge process issues (conflicts, CI failures, etc.) | git log, PR status | Check merge commit messages for conflict resolution traces |
| verify | FAIL root causes, acceptance check inconsistencies | Verification results | Analyze Step 5 results |

> **Note: Obligation to verify factual claims**: When writing factual claims such as "fixed" or "resolved", confirm the corresponding commit exists with `git log --oneline` before recording. Factual claims without commit verification can lead to incorrect PASS judgments.

**Steps:**

1. Collect information:
   - Confirm Issue body with `gh issue view "$NUMBER" --json body` (reuse if already fetched in Step 3)
   - Read Spec (if `docs/spec/issue-$NUMBER-*.md` exists)
     - Extract `## Issue Retrospective` section (result of `/issue` retrospective; also search `## Spec Retrospective` for backward compatibility)
     - Extract `## Spec Retrospective` section (result of `/spec` retrospective; also search `## Design Retrospective` for backward compatibility)
     - Extract `## Code Retrospective` section (result of `/code` retrospective)
     - Extract `## Review Retrospective` section (result of `/review` retrospective)
     - Extract `## Auto Retrospective` section (result of `/auto` XL route retrospective; skip if not present)
   - Identify related PR and review commit history with `git log --oneline`
2. Detect improvements across the 6 phases above:
   - Integrate content from each phase's retrospective
   - Cross-reference information sources in the retrospective dimensions table with collected retrospective information to detect improvement patterns across the entire workflow
3. **Persist retrospective results to Spec**:
   - If Spec (`docs/spec/issue-$NUMBER-*.md`) does not exist: skip persistence and output to terminal only
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
     - (observations on FAIL root causes, acceptance check inconsistencies, etc.)

     ### Improvement Proposals
     - (list improvement proposals here, or "N/A" if none)
     ```
   - Append section at end of Spec with Edit tool
   - Commit (push is done in Step 11 Worktree Exit):
     ```bash
     git add docs/spec/issue-"$NUMBER"-*.md
     git commit -m "Add verify retrospective for issue #$NUMBER

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
     ```

### Step 11: Worktree Exit (merge-to-main)

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Exit: merge-to-main section" to exit the worktree.

Behavior differs based on `ENTERED_WORKTREE`:
- `ENTERED_WORKTREE=true`: ExitWorktree("keep") → merge → push → cleanup
- `ENTERED_WORKTREE=false`: run `git push origin main` normally

### Step 12: Opportunistic Verification

Only if `.wholework.yml` in the project has `opportunistic-verify: true`, Read `${CLAUDE_PLUGIN_ROOT}/modules/opportunistic-verify.md` and follow the "Processing Steps" section to run opportunistic verification. The skill name is `/verify`. Skip this step if not configured.

### Step 13: Collect Improvement Proposals and Create Issues

Read `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` and follow the "Processing Steps" section to normalize titles (used for Issue title normalization when creating Issues). Also Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section to detect `.wholework.yml` settings and fetch `HAS_SKILL_PROPOSALS` (if already fetched and detected in Step 12's `opportunistic-verify.md` processing, reuse the result).

Extract text from `### Improvement Proposals` sections in each Spec retrospective section (spec, design, code, review, verify, auto).

**Judgment criteria**: If the `### Improvement Proposals` section text contains only "N/A" or "None", treat as no improvement proposals. Any other text is treated as having improvement proposals. Make this determination mechanically based on text presence alone, without judging duplication with existing guidelines or validity.

Integrate improvement proposals collected from multiple phases, removing only exact duplicates.

**If no improvement proposals**: proceed to completion report.

**If improvement proposals exist**: classify each improvement proposal by the following criteria.

- **Skill infrastructure improvement**: improvement proposals matching any of the following (examples):
  - Proposals for changes to skill commands themselves (`/spec`, `/verify`, `/review`, etc.) (e.g., "Should add a step to `/spec`")
  - References to files under `~/.claude/` (e.g., "Should improve `${CLAUDE_PLUGIN_ROOT}/modules/xxx.md`")
  - References to skill-specific filenames like `SKILL.md`, `modules/*.md`, `agents/*.md`
  - **Classification note**: Generic path names like `scripts/`, `docs/` are classified as skill infrastructure improvement only when referenced in the context of the skill infrastructure (behavior of `/verify`, `modules/` files). Improvement proposals for `scripts/` or `docs/` in external repositories are treated as code improvements
- **Code improvement**: improvement proposals not falling into the above (proposals for code, configuration, tests, CI, etc. in the current repository)

After classifying collected improvement proposals, create Issues per the following rules (auto-execute without confirmation):

- **Code improvement**: always create Issue
- **Skill infrastructure improvement**: only create Issue if `HAS_SKILL_PROPOSALS=true`. If `false`, skip Issue creation and output the count of skipped proposals to terminal (e.g., "Detected N skill infrastructure improvement proposals, but skipping Issue creation because `skill-proposals` marker is disabled.")

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

**Create Issue and add verify hints**:

- Normalize title following `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` processing steps, then create Issues in standard format (background, purpose, acceptance conditions) with `gh issue create` for each improvement proposal
- **Add verify hints to acceptance conditions**: add acceptance checks like `<!-- verify: grep "{keyword}" "{target file}" -->` to the created Issue's acceptance conditions. Extract keywords from acceptance condition text and infer target files from proposal content (improves automation accuracy for `/auto --batch`). Create Issue without verify hints if they cannot be determined
- If Issue creation fails, output error log to stderr, skip, and continue verify (does not affect exit code)
- Output created Issue number to terminal

**Assign `retro/verify` label (best-effort):**

After each Issue is created successfully, assign the `retro/verify` label. This applies to both Code improvement and Skill infrastructure improvement categories.

1. Ensure the `retro/verify` label exists (run once before assigning to Issues):
   ```bash
   gh label list --limit 100 | grep -q "retro/verify" || gh label create "retro/verify" --color "#c5def5" --description "Auto-created from /verify retrospective improvement proposal"
   ```
   If `gh label create` fails, output a warning and continue (does not affect Issue creation).

2. Assign the label to the created Issue:
   ```bash
   gh issue edit {issue_number} --add-label "retro/verify"
   ```
   If `gh issue edit` fails, output a warning and continue (does not affect the exit code).

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
