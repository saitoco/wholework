---
name: review
description: PR review (`/review 88`). Automatically runs acceptance criteria verification, multi-perspective code review, issue resolution, and summary posting. Use after `/code` creates a PR and before `/merge` (`--light`/`--full` to adjust depth).
context: fork
allowed-tools: Bash(gh pr view:*, gh pr diff:*, gh pr comment:*, gh issue view:*, gh issue edit:*, gh issue create:*, gh issue list:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-review.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/wait-external-review.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/run-review.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-type.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-extract-issue-from-pr.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*, wc:*, diff:*, git log:*, git diff:*, git show:*, git add:*, git commit:*, git push:*, git fetch:*, git checkout:*, git worktree:*, git branch:*, python3:*), Read, Write, Edit, Glob, Grep, Task, TaskCreate, TaskUpdate, TaskList, TaskGet, EnterWorktree, ExitWorktree
---

# PR Review

Accepts a PR number as ARGUMENTS. If an Issue number is provided, searches for the related PR.

If ARGUMENTS contains `--help`, read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and output help following the "Processing Steps" section. Do not execute further steps.

## Autonomous Mode (--auto)

If ARGUMENTS contains `--auto`:

> **Note**: This mode only works when invoked via `/auto` (direct `run-review.sh` call). Running `/review 88 --auto` from an interactive session spawns a fork sub-agent via `context: fork`, causing no visible output. In interactive sessions, use `/review 88` without `--auto`.

**Note**: `--auto` mode only accepts a **PR number**. If an Issue number is provided, do not use `--auto`; instead, search for the related PR in normal mode before running `/review`.

1. Extract the PR number from ARGUMENTS
2. Check for `--review-only`, `--light`, `--full` flags and include them as arguments
3. Run `${CLAUDE_PLUGIN_ROOT}/scripts/run-review.sh $NUMBER [--review-only] [--light | --full]` via Bash
4. After the script completes, stop (do not execute further steps)

If `--auto` is absent, run the normal steps below.

## Review-only Mode (--review-only)

If ARGUMENTS contains `--review-only` (and `--auto` is absent), set `REVIEW_ONLY=true` for reference in subsequent processing.

- With `--review-only`: skip Steps 7.2 (Copilot issue resolution), 7.4 (Claude Code Review issue resolution), 7.6 (CodeRabbit issue resolution), 12, 13, 14, and retrospective
- Status label transitions are not made after Step 11 completes (maintain `phase/review`)
- When combining `--auto` and `--review-only`, the `--auto` section passes `--review-only` to `run-review.sh` as an argument, which passes it through to ARGUMENTS for branching control in SKILL.md

## Steps

**Execute immediately without confirmation. Do not use compound commands (`&&`, `|`).**

### Step 1: Fetch PR Information

```bash
gh pr view "$NUMBER" --json number,title,body,headRefName,baseRefName
```

- **If PR not found**: treat as Issue, search for related PR in `gh issue view "$NUMBER" --json body` (look for `#XX` links, etc.). If no PR found, display error message and exit.

Extract the linked Issue number and base branch using `gh-extract-issue-from-pr.sh`:

```bash
EXTRACT_RESULT=$(${CLAUDE_PLUGIN_ROOT}/scripts/gh-extract-issue-from-pr.sh "$NUMBER")
ISSUE_NUMBER=$(echo "$EXTRACT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('issue_number',''))")
BASE_REF=$(echo "$EXTRACT_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('base_ref','main'))")
```

- **If Issue number cannot be extracted**: skip Step 8 and run only Step 10.

**Fetch Type (only when Issue number is extracted):**

Run `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-type.sh $ISSUE_NUMBER` and store the result in `$TYPE`:
- Value (`Bug`/`Feature`/`Task`) stored as-is
- Empty string: `TYPE=` (empty; the "unset" row in each agent applies, maintaining current behavior)

If Issue number cannot be extracted, set `TYPE=` (empty string).

### Step 2: Worktree Entry

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Entry" section.

**Worktree name convention:** `review/pr-$NUMBER`

Record `ENTERED_WORKTREE`. After entry, switch to the PR branch:

```bash
git fetch origin "$headRefName"
git checkout "$headRefName"
```

(`headRefName` is the PR's headRefName from Step 1)

### Step 3: Review Mode Detection

Determine the review mode using ARGUMENTS and the linked Issue's Size, and store as `REVIEW_DEPTH`.

**Exclusivity check:** if both `--light` and `--full` are specified, display error and exit.

**Detection priority:**

1. `--light` in ARGUMENTS → `REVIEW_DEPTH=light`
2. `--full` in ARGUMENTS → `REVIEW_DEPTH=full`
3. Get Size from linked Issue → map as follows:

| Size | REVIEW_DEPTH | Behavior |
|------|-------------|----------|
| `XS` | skip | Early exit (patch route) |
| `S`  | skip | Early exit (patch route) |
| `M`  | light | Run Step 9 as lightweight integrated review (1 agent) |
| `L`  | full | Run all steps |
| `XL` | full | Run all steps |

4. Size unset (or Issue number not extractable) → `REVIEW_DEPTH=full` (safe fallback)

**XS/S (patch route) early exit:**

If `REVIEW_DEPTH=skip`, skip Steps 7/8/9/10/11/12/13/14 and output this message:

```
Patch route — review is not needed. Proceed with `/merge $PR_NUMBER`.
If you need to run a review explicitly (e.g., main branch protection required PR route), run `/review $PR_NUMBER --light`.
```

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with `SKILL_NAME=review, PR_NUMBER=$NUMBER, ISSUE_NUMBER=$ISSUE_NUMBER, RESULT=success`.

Get Size (Project field first, label fallback):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh "$ISSUE_NUMBER" 2>/dev/null
```

### Step 4: Label Transition (review start)

If Issue number was extracted:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh "$ISSUE_NUMBER" review
```

### Step 5: Fetch Issue Information

```bash
gh issue view "$ISSUE_NUMBER" --json body
```

Parse acceptance criteria checkboxes.

- Prioritize "Pre-merge (auto-verified)" section if present
- If no sections, target all conditions
- **If no checkboxes**: skip Step 8

### Step 6: Fetch PR Diff

```bash
gh pr diff "$NUMBER"
```

If large (over 500 lines), fetch the file list and prioritize files with large changes:

```bash
gh pr view "$NUMBER" --json files
```

---

## Step 7: External Review Integration

Detect external review tool settings and handle waiting/issue resolution for enabled tools. Also detect the `review-bug` independent control marker.

### 7.0. External Review Tool Detection

Read `skills/review/external-review-phase.md` and follow the "Step 7 Prerequisites" section (which internally reads `modules/detect-config-markers.md` to detect `.wholework.yml` settings).

`review-bug` is also included in `detect-config-markers.md` detection targets.

Store detection results:

```
HAS_COPILOT_REVIEW: true if copilot-review: true is set (default: false)
HAS_CLAUDE_CODE_REVIEW: true if claude-code-review: true is set (default: false)
HAS_CODERABBIT_REVIEW: true if coderabbit-review: true is set (default: false)
SKIP_REVIEW_BUG: true if review-bug: false is set (default: false)
```

After detection, follow `external-review-phase.md`'s Step 7 procedure for external review waiting/issue resolution. All three reviewer types use the same "wait → resolve" flow (switch reviewer type via the second argument to `wait-external-review.sh`).

- If all three (`HAS_COPILOT_REVIEW`, `HAS_CLAUDE_CODE_REVIEW`, `HAS_CODERABBIT_REVIEW`) are `false`: skip all of Step 7 and proceed to Step 8
- With `--review-only` mode: skip issue resolution (Steps 7.2, 7.4, 7.6)

---

## Step 8: Static Acceptance Criteria Verification

### 8.0. Preview URL Resolution (if verify commands contain `{{base_url}}`)

If any verify command contains `{{base_url}}`, resolve the Preview URL before passing to verify-executor:

1. Get the PR branch name:
   ```bash
   gh pr view "$NUMBER" --json headRefName -q '.headRefName'
   ```

2. Get the latest deployment ID for the branch via GitHub Deployments API:
   ```bash
   gh api "repos/:owner/:repo/deployments?ref=<branch-name>&per_page=10" -q '.[0].id'
   ```
   If output is empty or `null`, treat `{{base_url}}`-containing browser checks as UNCERTAIN (note "Deployment not found via Deployments API").

3. Get `state` and `environment_url` from the latest deployment status:
   ```bash
   gh api "repos/:owner/:repo/deployments/<deployment-id>/statuses?per_page=1" -q '.[0] | {state: .state, environment_url: .environment_url}'
   ```

4. Based on the result:
   - `state` is `success` and `environment_url` is obtained → replace `{{base_url}}` with `PREVIEW_URL`; run static checks first, then browser checks last
   - `state` is `pending`/`in_progress` etc. → treat `{{base_url}}` checks as UNCERTAIN (note "Preview deployment not complete")
   - Empty statuses → treat as UNCERTAIN (note "Cannot retrieve deployment status")

5. When Preview URL is obtained, run static checks (file existence, etc.) first, then run `{{base_url}}`-containing browser checks last. Since the Preview URL comes from GitHub Deployments API (trusted source), run `browser_check`/`browser_screenshot` in full mode when browser tools are available (still applying security checks from `${CLAUDE_PLUGIN_ROOT}/modules/browser-verify-security.md`).

Skip this step if no `{{base_url}}`-containing checks exist.

Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-executor.md` and follow the "Processing Steps" translation table. Mode: **safe**, PR number: `$NUMBER`. For `command` hints, do not run directly — attempt CI reference fallback (`gh pr view "$NUMBER" --json statusCheckRollup` to check related job status). If CI cannot determine the result, treat as UNCERTAIN (note reason such as "corresponding CI job not identified").

Verify each condition:

1. **With verify command (`<!-- verify: ... -->`)**:
   - Valid syntax: run the specified command's corresponding processing
   - **Invalid syntax** (unknown command name, missing args, etc.) → treat as UNCERTAIN, fall back to AI judgment. Note error details.

2. **No hint**: attempt AI judgment (check if diff adds a file, if text is present, etc.)

3. Classify each condition:
   - PASS — condition met
   - FAIL — condition not met
   - UNCERTAIN — cannot auto-determine
   - POST-MERGE — condition to verify after merge

### Checkbox Updates

For "Pre-merge (auto-verified)" conditions that PASS in Step 7 verification, update Issue checkboxes:

Write to `.tmp/issue-body-$ISSUE_NUMBER.md` using the Write tool, then run:
```bash
mkdir -p .tmp
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh "$ISSUE_NUMBER" .tmp/issue-body-$ISSUE_NUMBER.md
```

- PASS → update to `- [x]`
- FAIL/UNCERTAIN → leave as `- [ ]`
- POST-MERGE → leave as `- [ ]`

---

## Step 9: CI Status Check

After Step 7, check the PR's overall CI status:

```bash
gh pr view "$NUMBER" --json statusCheckRollup
```

- **All jobs SUCCESS (or SKIPPED)**: note CI is successful and proceed
- **PENDING/IN_PROGRESS jobs**: note CI is running and proceed
- **FAILURE jobs**: list failed job names and statuses; suggest fixes where possible. If `scripts/validate-skill-syntax.py` exists, also read `skills/review/skill-dev-recheck.md` and follow the "Step 8: Additional Suggestions on CI Failure" section.

---

## Step 10: Multi-perspective Code Review (parallel execution)

**In light mode**: if `REVIEW_DEPTH=light` and Issue number was extracted (Step 7 ran), run 1-agent lightweight integrated review instead of 2-agent parallel (see 10.0). If Issue number was not extracted and Step 7 was skipped, run full mode (10.1–10.3) regardless of `REVIEW_DEPTH`.

### 10.0. Lightweight Integrated Review (REVIEW_DEPTH=light only)

Run only when `REVIEW_DEPTH=light` and Issue number is extractable.

If `SKIP_REVIEW_BUG=true`, specify in the prompt to run only review-light's spec divergence (aspect 1) and documentation consistency (aspect 4). If `SKIP_REVIEW_BUG=false`, run all 4 aspects.

1. **Save PR diff to file**:
   - `mkdir -p .tmp`
   - Write `gh pr diff "$NUMBER"` result to `.tmp/pr-diff-$NUMBER.txt`
   - Write `gh pr view "$NUMBER" --json files` result to `.tmp/pr-files-$NUMBER.json`

2. **Get Spec path**:
   - Glob for `docs/spec/issue-$ISSUE_NUMBER-*.md`
   - Record path if found; empty string if not

3. **Get steering doc paths**:
   - Glob for `docs/product.md`, `docs/tech.md`, `docs/structure.md`
   - Record existing paths comma-separated as `STEERING_DOCS_PATHS`

4. **Launch 1 `review-light` agent**:

   ```text
   Task(
     subagent_type="review-light",
     description="Lightweight integrated review (all 4 aspects)",
     prompt="Run review: PR=$NUMBER, Issue=$ISSUE_NUMBER, Type=$TYPE, Spec=$DESIGN_FILE_PATH, Steering Documents=$STEERING_DOCS_PATHS, PR diff=.tmp/pr-diff-$NUMBER.txt, changed files=.tmp/pr-files-$NUMBER.json"
   )
   ```

5. **Pass results to Step 10**:
   - Extract `path`, `line`, `body`, `severity` from `review-light` output; generate line comments JSON and Review body (same processing as full mode 10.2)
   - Write to `.tmp/review-comments-$NUMBER.json` and `.tmp/review-body-$NUMBER.md`

6. **Proceed to Step 10** (skip 10.1–10.3)

Split into 2 groups and run in parallel using Task tool (`REVIEW_DEPTH=full` or fallback).

### 10.1. Group Definitions

| Group | Aspects | Model | Agent file |
|-------|---------|-------|-----------|
| **Spec: spec/documentation** | Spec divergence, documentation consistency, steering document alignment | **opus** | `~/.claude/agents/review-spec.md` |
| **Bug: bug/logic error detection** | HIGH SIGNAL bugs, logic errors, security issues | **opus** | `~/.claude/agents/review-bug.md` (×2 parallel) |

### 10.2. Parallel Execution Steps

1. **Save PR diff to file**:
   - `mkdir -p .tmp`
   - Write `gh pr diff "$NUMBER"` result to `.tmp/pr-diff-$NUMBER.txt`
   - Write `gh pr view "$NUMBER" --json files` result to `.tmp/pr-files-$NUMBER.json`

2. **Get Spec path**:
   - If Issue number extracted: Glob for `docs/spec/issue-$ISSUE_NUMBER-*.md`
   - Record path if found; empty string if not

2.5. **Get steering doc paths**:
   - Glob for `docs/product.md`, `docs/tech.md`, `docs/structure.md`
   - Record comma-separated as `STEERING_DOCS_PATHS` (empty string if none exist)

3. **Launch agents in parallel**:
   - `SKIP_REVIEW_BUG=true`: launch **review-spec only** (skip review-bug)
   - `SKIP_REVIEW_BUG=false`: launch **review-spec + review-bug×2 in parallel**
     - review-bug agent 1 (diff bug scan): focus on diff and detect clear bugs
     - review-bug agent 2 (security scan): detect security issues and invalid logic in changed code

   ```text
   Task(
     subagent_type="review-spec",
     description="Spec review",
     prompt="Run review: PR=$NUMBER, Issue=$ISSUE_NUMBER, Type=$TYPE, Spec=$DESIGN_FILE_PATH, Steering Documents=$STEERING_DOCS_PATHS, PR diff=.tmp/pr-diff-$NUMBER.txt, changed files=.tmp/pr-files-$NUMBER.json"
   )

   Task(
     subagent_type="review-bug",
     description="Bug review (diff bug scan)",
     prompt="Run review: PR=$NUMBER, Type=$TYPE, PR diff=.tmp/pr-diff-$NUMBER.txt, changed files=.tmp/pr-files-$NUMBER.json. Focus on + lines in the diff; detect clear bugs and logic errors using HIGH SIGNAL principles."
   )

   Task(
     subagent_type="review-bug",
     description="Bug review (security scan)",
     prompt="Run review: PR=$NUMBER, Type=$TYPE, PR diff=.tmp/pr-diff-$NUMBER.txt, changed files=.tmp/pr-files-$NUMBER.json. Detect security issues and invalid logic in changed code using HIGH SIGNAL principles."
   )
   ```

4. **Integrate 2 groups' results and generate line comments JSON and Review body**:
   - Collect outputs from each group (successful groups only)
   - Record failed groups as "review unavailable"
   - Extract `path`, `line`, `body`, `severity` from each issue:
     - Detect issue start with `**[aspect name] filename:line-approx**` line
     - Read values from subsequent `- path: ...` / `- line: ...` lines (raw values without backticks)
     - Determine severity from `Issue. Severity: MUST / SHOULD / CONSIDER`
     - Issues where `path` is not `null` → add to line comments array (with `side: "RIGHT"`)
     - Issues where `path` is `null` → merge into "General Comments" section of Review body (**MUST issues MUST be included in General Comments** — even with `path: null`, MUST is the basis for `event=REQUEST_CHANGES`, so not including in Review body leaves it unclear what the problem is)
   - `mkdir -p .tmp`
   - Write line comments array to `.tmp/review-comments-$NUMBER.json` (JSON array format)
   - Write Review body (acceptance criteria table + CI status + General Comments + issue count summary) to `.tmp/review-body-$NUMBER.md`

5. **Pass integrated results to Step 10.3**:
   - Run 2-stage verification on issues collected from review-bug×2 via verification sub-agents (see 10.3)
   - review-spec results are passed directly to Step 10 (no verification needed)

### 10.3. Verification Sub-agents (2-stage Bug Issue Verification)

Run only when `SKIP_REVIEW_BUG=false` (skip if review-bug was skipped).

Launch verification sub-agents (Opus) in parallel for each issue collected from review-bug×2 to filter false positives. Issue limit: **10**; excess issues are passed to Step 10 without verification.

1. **Collect issues**: list review-bug issues from 10.2 results
2. **Launch verification sub-agents in parallel** (one inline prompt per issue):

   ```text
   Task(
     subagent_type="general-purpose",
     description="Bug issue verification #{n}",
     prompt="""Verify the following bug issue.

PR title: {PR_TITLE}
PR body (author's intent): {PR_BODY}
Issue: {full issue text including path/line/severity}

Verification criteria:
- Is the problem actually confirmed in the diff's + lines?
- Is it HIGH SIGNAL (compile error, clear logic error, quoted CLAUDE.md violation, security issue)?
- Is it a misunderstanding of the author's intent?

Output your conclusion as "PASS (problem confirmed)" or "REJECT (false positive)" and explain in 1-2 sentences.
Format: VERDICT: PASS|REJECT
Reason: {explanation}"""
   )
   ```

3. **Process verification results**:
   - `VERDICT: PASS` → include issue in Step 10 integrated results
   - `VERDICT: REJECT` → filter out issue and record in rejection log; remove from `.tmp/review-comments-$NUMBER.json`

4. **Append rejection log to Review body** (if any issues were rejected):

   ```markdown
   ### Issues Rejected by Verification (false positive filtering results)

   - Rejected: {issue summary} → Reason: {REJECT reason}
   ```

5. **Pass integrated results to Step 11**: use `.tmp/review-body-$NUMBER.md` and `.tmp/review-comments-$NUMBER.json` in Step 11

---

## Step 11: Post Review Results

Integrate Steps 7 (acceptance criteria verification), 8 (CI status), and 10 (parallel review) and post as a GitHub Pull Request Review.

1. `mkdir -p .tmp`
2. **When Step 9 was run (both full and light mode)**: `.tmp/review-body-$NUMBER.md` already generated in Step 9 (no Write needed). **When Step 9 was entirely skipped** (only when Issue number was not extractable and Step 7 was also skipped): write Review body (acceptance criteria table + CI status) to `.tmp/review-body-$NUMBER.md`
3. Post review to PR via script:

When Step 9 was run (with line comments):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-review.sh "$NUMBER" ".tmp/review-body-$NUMBER.md" ".tmp/review-comments-$NUMBER.json"
```

When Step 9 was skipped (no line comments):
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-review.sh "$NUMBER" ".tmp/review-body-$NUMBER.md"
```

- Script automatically posts with `REQUEST_CHANGES` event if MUST issues exist
- Script automatically posts with `COMMENT` event if no MUST issues

```bash
rm -f .tmp/review-body-$NUMBER.md .tmp/review-comments-$NUMBER.json
```

**If `gh-pr-review.sh` fails**: output review content to terminal (fallback).

**Review body output format:**

```markdown
## Acceptance Criteria Verification Results

| Condition | Result | Notes |
|-----------|--------|-------|
| Condition summary | PASS | — |
| Condition summary | FAIL | Missing content |
| Condition summary | UNCERTAIN | Why auto-determination failed |
| Condition summary | POST-MERGE | Verify after merge |

## CI Status

| Job name | Status | Notes |
|---------|--------|-------|
| job-name | SUCCESS | — |
| job-name | FAILURE | Fix suggestion: {specific fix} |
| job-name | PENDING | CI running |

## Code Review

### General Comments (issues where path/line cannot be identified)

Issues at design or architecture level that cannot be attributed to a specific file/line.

**[aspect name] description**
Issue content. Severity: MUST / SHOULD / CONSIDER

Recommended fix:
(specific fix suggestion)

### Issue Count Summary

- Posted as line comments: {N} (MUST: {M}, SHOULD: {S}, CONSIDER: {C})
- General Comments (in body): {N}

---
Next: run `/merge $NUMBER`.
```

(When Step 9 was entirely skipped, replace Code Review section with:)
```markdown
## Code Review

Step 9 skipped (Issue number not extractable, Step 7 also skipped).
```

(When MUST issues exist, change the footer to:)
```
---
MUST issues found. After fixing in Step 11 and posting response summary in Step 13, run `/merge $NUMBER`.
```

### review-only mode: Branch after Step 10 completes

If `REVIEW_ONLY=true`, skip Steps 11/12/13/retrospective and output the following completion report. No status label transition (maintain `phase/review`).

```
## Review Complete (review-only mode)

- Acceptance criteria verification: {PASS} PASS / {FAIL} FAIL / {UNCERTAIN} UNCERTAIN / {SKIPPED} SKIPPED
- Code review issues: {MUST} MUST / {SHOULD} SHOULD / {CONSIDER} CONSIDER

Issue resolution was not performed.
Fixes should be handled by the user or Copilot.
```

---

## Step 12: Issue Resolution and Fixes

**With `--review-only` mode**: skip Step 11 and output review-only completion report.

After posting Step 10 review results, if Claude review issues exist:

### 12.1. Issue Priority Assessment

Classify each issue:
- **MUST**: must fix (spec divergence, security, bugs, unverified uncertainty, etc.)
- **SHOULD**: strongly recommended fix (maintainability, consistency, robustness, etc.)
- **CONSIDER**: items to consider (style, optimization, future extensibility, etc.)

### 12.2. Fix Work

Fix all MUST issues. Claude decides whether to fix SHOULD/CONSIDER issues.

1. **Task management with TaskCreate/TaskUpdate**: create a task per issue to fix
2. **Edit files using Edit tool**
3. **Stage with git add**
4. **Commit with `git commit -m "Address review feedback: {fix summary}"`**
5. **Push with git push**

### 12.3. Lightweight Re-check

If `scripts/validate-skill-syntax.py` exists, read `skills/review/skill-dev-recheck.md` and follow "Step 12.3: Re-run validate-skill-syntax".

After fixes, run a lightweight re-check focused on changed areas:
- Light re-check (not full Step 7+9 re-run) focused on changed areas
- Check for new issues
- Re-run tests/validation
- If new MUST issues found in re-check, return to Step 12.2
- **Retry limit**: 3 times total (initial review + 2 re-checks)

### 12.4. Record Fix Results

```markdown
## Claude Review Response

### Fixed Issues
- [aspect name] filename:line — issue summary → fix content

### Skipped Issues
- [aspect name] filename:line — issue summary (skip reason)
```

**If no issues**: skip Step 11 and proceed to Step 13.

---

## Step 13: Acceptance Criteria Consistency Check

**With `--review-only` mode**: skip Step 12 and output review-only completion report.

After Step 11 issue resolution (including when Step 11 was skipped), check consistency between changes and acceptance criteria.

### 13.1. Policy Change Detection

Analyze the following implementation changes for policy changes:
- All implementation changes made in Step 7 (Copilot review; including 7.2)
- All implementation changes made in Step 12

Policy change detection patterns:

| Detection pattern | Example |
|------------------|---------|
| Design approach change due to security issue | "run in safe mode" → "return UNCERTAIN" |
| Implementation approach change due to Copilot issue | Direct API call → via wrapper |
| Scope reduction/expansion | Split part of feature into another Issue |
| Behavioral spec change | Default value change, error handling policy change |

Assess whether any changes contradict the acceptance criteria (verify command text or condition descriptions).

**If no policy changes** (or no implementation changes in Step 7/12): skip this step and proceed to Step 13.

### 13.2. Update Issue Body (only on policy change detection)

1. `gh issue view "$ISSUE_NUMBER" --json body -q .body` to get current Issue body
2. Identify acceptance conditions invalidated by policy changes
3. Update condition text and `<!-- verify: ... -->` hints to reflect post-change content
4. Write to `.tmp/issue-body-$ISSUE_NUMBER.md`
5. `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh "$ISSUE_NUMBER" .tmp/issue-body-$ISSUE_NUMBER.md`

### 13.3. Post Change Reason Comment (only on policy change detection)

Format:
```markdown
## Acceptance Criteria Update

### Change Reason
- Review issue ({Copilot/Claude}) led to {change summary}

### Updated Conditions
| Condition | Before | After |
|-----------|--------|-------|
| Condition summary | old text | new text |

### Updated Verify Commands
| Hint | Before | After |
|------|--------|-------|
| command name | old syntax | new syntax |
```

Post comment:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh "$ISSUE_NUMBER" .tmp/issue-acceptance-update-$ISSUE_NUMBER.md
rm -f .tmp/issue-acceptance-update-$ISSUE_NUMBER.md
```

---

## Step 14: Post Response Summary

**With `--review-only` mode**: skip Step 14 and output review-only completion report.

Compile Steps 7 (Copilot response) and 12 (Claude response) and post as a second PR comment.

### 14.1. Generate Summary Body

Refer to `skills/review/external-review-phase.md`'s "Step 14: External Review Response Results Section" and include external review response results in the summary.

Template:
```markdown
## Review Response Summary

### Claude Review Response

| Aspect | Filename | Line | Issue | Response | Fix/Skip reason |
|--------|---------|------|-------|----------|----------------|
| Spec divergence | config.json | 10 | Out-of-scope config added | Resolved | Removed unnecessary config |
| Bug detection | utils.py | 88 | Missing boundary check | Resolved | Added range check |

### Lightweight Re-check Results

- Tests/validation: PASS (`validate-skill-syntax.py` included if the file exists per skill-dev-recheck.md)
- Fix diff check: PASS
- New issues: none

### Acceptance Criteria Updates (only if policy changes occurred)

(If Step 13 updated acceptance criteria, append:)
- Change reason: {review issue summary}
- Updated condition: {before} → {after}
- Issue comment: posted
```

**If no Claude response (Step 11 skipped)**: omit Claude section.

**If Step 10 was entirely skipped**: replace Claude review section with "Step 10 skipped (Issue number not extractable)". **In light mode (`REVIEW_DEPTH=light`)**: include `review-light` agent results in the Claude review section showing all 4 aspects.

**If no acceptance criteria updates (Step 12 skipped)**: omit that section.

### 14.2. Post PR Comment

```bash
mkdir -p .tmp
gh pr comment "$NUMBER" --body-file .tmp/review-summary-$NUMBER.md
rm -f .tmp/review-summary-$NUMBER.md .tmp/pr-diff-$NUMBER.txt .tmp/pr-files-$NUMBER.json .tmp/issue-body-$ISSUE_NUMBER.md
```

**On failure**: output summary to terminal (fallback).

---

## Retrospective

**With `--review-only` mode**: skip retrospective and output review-only completion report.

Reflect on the review phase; record improvement proposals in the Spec only. Issue proposals are aggregated in `/verify`.

**Retrospective scope**: this step (review)
**Sources**: PR diff, Issue acceptance criteria, Spec

**Retrospective aspects (examples):**

| Aspect | Check |
|--------|-------|
| Spec vs. implementation divergence patterns | Are there structural divergences between Spec and PR diff? |
| Recurring issues | Are there multiple issues of the same kind (room for workflow improvement)? |
| Acceptance criteria verification difficulty | Are there many UNCERTAINs, missing or inaccurate verify commands? |

**Steps:**

1. Identify improvements from Steps 8 and 10 results
2. **Write review retrospective to Spec**:
   - Append `## review retrospective` section to the end of `docs/spec/issue-$ISSUE_NUMBER-*.md` using Edit tool
   - Create subsections for each of the 3 aspects; write "Nothing to note" for aspects with nothing to record
   - Commit and push:
     ```bash
     git add docs/spec/issue-$ISSUE_NUMBER-*.md
     git commit -m "Add review retrospective for issue #$ISSUE_NUMBER

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
     git push origin HEAD
     ```
3. **If improvement proposals exist**: record in review retrospective only (do not create issues; proposals are aggregated in `/verify`)

## Worktree Exit (push-and-remove)

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Exit: push-and-remove" section.

Since the retrospective push (`git push origin HEAD`) is complete, call ExitWorktree("remove", discard_changes: true) to delete the worktree and return to the original directory.

## Opportunistic Verification

If `opportunistic-verify: true` is set in `.wholework.yml`, read `${CLAUDE_PLUGIN_ROOT}/modules/opportunistic-verify.md` and follow "Processing Steps". Skill name: `/review`. Skip if not set.

## Completion Report

**Completion report (always use this format):**

After posting the Step 14 summary, output a review response summary to the terminal in the following format (do not abbreviate or modify):

```
## Review Complete

- Copilot review response: {response count} resolved, {skip count} skipped
- Claude review response: {response count} resolved, {skip count} skipped
- Lightweight re-check: {result}
```

**If Copilot/Claude response was skipped (including Step 7 skip due to settings)**: omit the corresponding line.

**When Step 10 was entirely skipped**: replace "Claude review response" line with "Step 10: skipped (Issue number not extractable)".

**In light mode (`REVIEW_DEPTH=light`)**: replace "Claude review response" line with "Step 10 (lightweight integrated review): review-light agent ran all 4 aspects".

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=review`
- `PR_NUMBER=$NUMBER`
- `ISSUE_NUMBER=$ISSUE_NUMBER`
- `RESULT=success`

---

## Review Aspects

Documentation consistency check (review-spec aspect 2, review-light aspect 4) verifies:

- No missing updates in README/CLAUDE.md/workflow.md etc.
- Paths and command examples match implementation
- When adding/modifying documentation, body descriptions and tables/lists are consistent

For Python script changes, additionally verify:

- Newly added/moved function calls are inside try-except blocks (leaking outside try-except means exceptions propagate without being silenced, but can represent unintended exception boundary changes)
- When existing try-except boundaries are changed, verify the caught exceptions haven't changed

---

## Notes

- `/review` posts review results (Step 11), then resolves issues (Step 12), then posts response summary (Step 14)
- Copilot review (Step 7) and Claude review (Step 10) are complementary: Copilot handles local code quality checks (auto-fix level), Claude handles project context and acceptance criteria alignment (design review level)
- Always wrap variables (`$NUMBER`, `$ISSUE_NUMBER`, etc.) in double quotes
- Always use the Write tool for temp files. Shell redirects trigger confirmation prompts
- MUST issues must always be fixed in Step 12. After fixing, proceed with `/merge` (do not re-run `/review`)
