---
name: issue
description: Issue creation and refinement (`/issue "title"` or `/issue 123`). Creates new issues or refines/reformats existing ones. Use when creating issues, defining requirements, or standardizing issue content.
allowed-tools: Bash(gh issue create:*, gh issue view:*, gh issue edit:*, gh issue close:*, gh issue list:*, gh label create:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/set-blocked-by.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*), Glob, Grep, Write, Read, WebFetch, ToolSearch, Task, TaskCreate, TaskUpdate, TaskList, TaskGet
---

# Issue Creation and Refinement

If ARGUMENTS is a number, refine an existing issue; if a string, create a new one.

If ARGUMENTS contains `--help`, read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and output help following the "Processing Steps" section. Do not execute further steps.

## Non-Interactive Mode Behavior

If ARGUMENTS contains `--non-interactive` (set automatically by `run-issue.sh`), operate in **non-interactive mode**. In this mode, `AskUserQuestion` cannot be used.

Read `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md` and follow the "Non-Interactive Mode Handling" section for the three-tier policy (auto-resolve / skip / hard-error). The specific branching at each step is noted inline below.

Key per-step behavior in non-interactive mode:
- **New Issue Creation Step 5 / Existing Issue Step 8** (Clarification Questions): auto-resolve each ambiguity point using model judgment; record decisions in the Auto-Resolve Log posted as an issue retrospective comment
- **Existing Issue Step 12** (Scope Assessment / sub-issue splitting): **skip** (High-Stakes Decision — sub-issue splitting is irreversible); output warning and continue without splitting

---

## New Issue Creation

### Step 1: Collect Basic Information

Use AskUserQuestion to collect:
1. Background (why is this needed)
2. Purpose (what to achieve)
3. Acceptance criteria (completion conditions, multiple allowed)

### Step 2: Reference Steering Documents (if present)

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `SPEC_PATH`, `STEERING_DOCS_PATH`, and `HAS_PR_PREVIEW_CAPABILITY` for use in subsequent steps.

Check whether the following steering documents exist using Glob, then read only those that exist:

- `$STEERING_DOCS_PATH/product.md` — project vision, Non-Goals, Terms (terminology consistency)
- `$STEERING_DOCS_PATH/tech.md` — Forbidden Expressions (to avoid prohibited terms)

**If none exist, skip this step and proceed to the next.**

Use the referenced documents in subsequent steps for vision alignment, terminology consistency, and forbidden expression avoidance.

### Step 3: Ambiguity Detection

Read `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md` and check acceptance criteria against the pattern table.

New issue creation flow has no Size yet (treat as unset). Follow the "size routing table" in `modules/ambiguity-detector.md` — extract **at most 3** ambiguity points.

### Step 4: Classify Acceptance Criteria and Assign Verify Commands

**Existing adapter pattern survey (only when proposing a new verify command type):**

If a requirement cannot be expressed using any command from the supported commands table below, before proposing a new custom handler mechanism, follow `docs/environment-adaptation.md` Extension Guide Step 0:
- Enumerate all rows in `modules/verify-executor.md` translation table that delegate via `adapter-resolver.md` (e.g., `browser_check`, `lighthouse_check`)
- List all bundled adapters under `modules/{capability}-adapter.md`
- Confirm that the new requirement cannot be expressed by adding a new capability following the existing `adapter-resolver` pattern before proposing a new mechanism

If expressible via existing `adapter-resolver` patterns, prefer that approach over proposing a new mechanism.

Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-patterns.md` and follow the "Processing Steps" section guidelines to design verify command patterns.

After ambiguity detection, classify each acceptance criterion as "pre-merge" or "post-merge" and assign verify commands.

**pre-merge-preview tier (URL/UX AC classification):**

When `HAS_PR_PREVIEW_CAPABILITY` is `true` (i.e., `.wholework.yml` has `capabilities.pr-preview: true`), classify URL/UX-based verify commands into the **pre-merge-preview** tier instead of post-merge.

URL/UX verify command set (exhaustive): `http_status`, `html_check`, `api_check`, `http_header`, `http_redirect`, `browser_check`, `browser_screenshot`, `lighthouse_check`.

For each AC whose verify command belongs to the above set and `HAS_PR_PREVIEW_CAPABILITY=true`:
- Place the AC in the `### Pre-merge (auto-verified)` section (not in Post-merge)
- Append `<!-- ac-tier: preview -->` to the AC line (after the checkbox text, before any `<!-- verify-type: ... -->` tag)
- Auto-append `--when="test -n \"$PREVIEW_URL\""` to the verify command so the check is SKIPPED when the `PREVIEW_URL` env variable is not set (see `--when` modifier table entry "Preview URL required")
- `/review` will execute these ACs against the preview URL when `PREVIEW_URL` is exported; `/verify` will skip them post-merge to prevent double verification

When `HAS_PR_PREVIEW_CAPABILITY` is `false` or unset: classify URL/UX-based ACs as post-merge as before (existing behavior unchanged).

**Classification guidance (examples):**

| Pre-merge (auto-verified) | Post-merge |
|--------------------------|-----------|
| File existence/content | Environment reflection (symlinks, etc.) |
| Documentation updates | Command execution verification |
| Code quality/structure | Production environment behavior |
| Test results | User experience verification |

**Verify command (`<!-- verify: ... -->`) assignment:**

- **Always assign**: file existence/absence, specific text presence (mechanically verifiable)
- **Conditionally assign**: command execution results (may omit if CI covers it)
- **Do not assign**: subjective judgment, external environment dependency, user experience

**Translation document exclusion:**

Do not create verify command items for translation output files. These are auto-generated by `/doc translate` and are not implementation targets:
- `docs/{lang}/` subdirectories (e.g., `docs/ja/`, `docs/zh/`)
- `README.{lang}.md` files (e.g., `README.ja.md`, `README.zh.md`)

Assign hints on a best-effort basis. Inaccuracies are handled by `/verify`'s AI fallback.

**Test file existence check (for verify commands referencing test files):**

When generating an AC whose verify command references a test file path (e.g., `tests/*.bats`, `tests/*.py`), confirm whether the referenced file exists before writing the verify command:

1. Run `ls tests/<filename>` or use Glob to check file presence
2. **File exists**: proceed with the verify command as normal
3. **File does not exist**: the file is a new creation target in this Issue — note this explicitly in the AC or alongside it (e.g., "test file `tests/<filename>.bats` will be created as part of implementation"). Avoid referencing a non-existent file in verify commands that presuppose its existence (e.g., `file_contains`, `section_contains`); prefer `command "bats tests/<filename>.bats"` which validates execution rather than static content.

This check shifts conflict detection from the `/spec` phase (codebase investigation) to the `/issue` phase, reducing rework.

**Table cell value vs. compound key string mismatch:**

When using `file_contains` or `section_contains` with a compound string like `"key: value"`, be aware that markdown table cells often contain only the cell value (e.g., `steering`) and not the full compound string (e.g., `type: steering`). If the target file uses a markdown table to represent structured data, the compound key string will not match the table cell content. In such cases, search for the standalone value (`"steering"`) or add prose text that contains the compound string to make verification reliable.

**Prefer dedicated commands over `command` hints:**

`command` hints run generic shell commands and become UNCERTAIN in `/review` safe mode. Use dedicated commands when possible:

- **Use dedicated commands for**: file/directory existence, text containment, JSON field values, symlink checks
- **Use `command` hints for**: bats test runs, CI integration, compound condition verification

**Supported commands (exhaustive):**

| Command | Syntax | Purpose |
|---------|--------|---------|
| `file_exists` | `file_exists "path"` | File existence |
| `file_not_exists` | `file_not_exists "path"` | File absence |
| `dir_exists` | `dir_exists "path"` | Directory existence |
| `dir_not_exists` | `dir_not_exists "path"` | Directory absence |
| `file_contains` | `file_contains "path" "text"` | Text containment |
| `file_not_contains` | `file_not_contains "path" "text"` | Text absence |
| `grep` | `grep "pattern" "path"` | Regex match |
| `command` | `command "cmd"` | Command execution (exit 0 = success). **Note: runs with user confirmation in `/verify`. Only specify safe test/verification commands** |
| `json_field` | `json_field "path" ".key" "value"` | JSON field value |
| `section_contains` | `section_contains "path" "heading" "text"` | Text within a markdown section (heading to next same-or-higher-level heading) |
| `section_not_contains` | `section_not_contains "path" "heading" "text"` | Text absence within a markdown section |
| `symlink` | `symlink "path" "target"` | Symlink verification |
| `http_status` | `http_status "URL" "CODE"` / `http_status "URL" "CODE" --allow-localhost` | HTTP response code. Safe mode blocks private IPs (including localhost). Add `--allow-localhost` to opt-in to localhost access in safe mode (other private IPs remain blocked) |
| `html_check` | `html_check "URL" "selector" "--exists"` / `html_check "URL" "selector" "--count=N"` / (with `--allow-localhost`) | HTML structure verification using CSS selectors. Add `--allow-localhost` to opt-in to localhost access in safe mode |
| `api_check` | `api_check "URL" "jq_expression" "expected_value"` / (with `--allow-localhost`) | JSON API response verification (GET only). Add `--allow-localhost` to opt-in to localhost access in safe mode |
| `http_header` | `http_header "URL" "Header-Name" "expected_value"` | HTTP response header value |
| `http_redirect` | `http_redirect "source_URL" "expected_destination" "expected_status"` | HTTP redirect verification |
| `build_success` | `build_success "CMD"` | Build command success. **Note: only in `/verify` (full) mode. Use only safe build/validation commands** |
| `lighthouse_check` | `lighthouse_check "URL" "category" "min_score"` | Lighthouse score. **Note: only in `/verify` (full) mode. Requires Lighthouse CLI** |
| `browser_check` | `browser_check "url" "selector" ["expected_text"]` | Browser element existence/text. **Note: only in `/verify` (full) mode. Requires MCP Playwright** |
| `browser_screenshot` | `browser_screenshot "url" "description"` | Browser screenshot with AI visual judgment. **Note: only in `/verify` (full) mode** |
| `mcp_call` | `mcp_call "tool_name" "description"` | MCP tool call with AI judgment. Use `server_name__tool_name` format. **Note: only in `/verify` (full) mode** |
| `github_check` | `github_check "gh_command" "expected_value"` | GitHub state verification. Safe mode: read-only operations only |
| `rubric` | `rubric "text"` | Semantic-level natural-language judgment via LLM grader. Runs in both safe and full modes (`always_allow` — no side effects); grader is invoked at both `/review` pre-merge and `/verify` post-merge. See `modules/verify-patterns.md` §9 for selection criteria. |

**rubric + supplementary file_contains / section_contains:**

When using `rubric` and the target file and section are predictable in advance, add `file_contains` or `section_contains` alongside it to increase verification accuracy. The supplementary check provides a mechanical safety net for cases where `rubric` may PASS despite content being in the wrong location.

Example:

```
<!-- verify: rubric "modules/example.md §3 includes guidance on the new pattern" -->
<!-- verify: section_contains "modules/example.md" "### 3." "new_pattern_keyword" -->
```

See `modules/verify-patterns.md` §9 for the full guideline and applicability conditions.

In particular, when the rubric's grader description contains a numeric literal, constant name, or threshold value (e.g., `BREAKEVEN_THRESHOLD_PCT = 10.0`), add a `file_contains` hint for the corresponding constant alongside the `rubric` to enable deterministic verification of the value.

When MCP tools are available, use ToolSearch with `select:<tool_name>` to confirm existence and read-only nature before proposing `mcp_call` hints.

**Custom verify command handlers (project-local):**

Projects can extend the built-in command set by placing handler Markdown files at `.wholework/verify-commands/{name}.md`. Once placed, the custom command is available as `<!-- verify: {name} "arg" -->` in Issue acceptance criteria — no capability declaration is required.

- To add a custom command, place `.wholework/verify-commands/{name}.md` following the handler contract in `docs/environment-adaptation.md` Layer 4
- Use `<!-- verify: {name} "arg" --> condition description` in acceptance criteria the same way as built-in commands
- For full handler contract details and the safe-mode self-declaration spec, see the "Custom Verify Command Handlers" section in `docs/environment-adaptation.md`

**`--when` modifier (conditional verification):**

Append `--when="shell_condition"` to any check to skip it when the condition is not met (returns SKIPPED):

| Pattern | `--when` condition |
|---------|--------------------|
| Browser required | `--when="command -v browser-use \|\| test -n \"$PLAYWRIGHT_MCP\""` |
| Preview URL required | `--when="test -n \"$PREVIEW_URL\""` |
| MCP tool required | `--when="test -n \"$MCP_TOOLS\""` |
| Specific CLI required | `--when="command -v lighthouse"` |
| CI only | `--when="test -n \"$CI\""` |

**MCP tool detection and mcp_call proposal (conditional):**

Reuse `MCP_TOOLS` already fetched via `detect-config-markers.md` in Step 2. If non-empty, read `skills/issue/mcp-call-guidelines.md` and follow the "Declaration Priority" section. If empty, skip `mcp_call` hints.

**Assign verify-type tags to post-merge conditions:**

Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-classifier.md` and assign `<!-- verify-type: auto|opportunistic|manual -->` tags to each post-merge condition.

**BRE metacharacter detection in verify commands:**

After assigning verify-type tags, scan all `<!-- verify: grep "PATTERN" ... -->` commands in the Issue body. For each `grep` verify command, extract the PATTERN string (the first quoted argument after `grep`) and check whether it contains BRE metacharacters: `\|`, `\(`, `\)`, `\+`, `\?`.

If any BRE metacharacter is detected:
- Output a warning to terminal listing the affected verify command
- Present the ERE rewrite candidate: replace `\|` → `|`, `\(` → `(`, `\)` → `)`, `\+` → `+`, `\?` → `?`
- Note that `grep` verify commands in Wholework use ripgrep (ERE by default); BRE metacharacters like `\|` are interpreted as literal `|` in ERE and do not function as OR alternation
- If the intended behavior is BRE alternation, suggest switching to ERE form or using `command "grep -G ..."` to force BRE mode

Example warning format:
```
Warning: BRE metacharacter detected in verify command:
  grep "PATTERN_WITH_\|" "path/to/file"
Suggested ERE rewrite: grep "PATTERN_WITH_|" "path/to/file"
Note: verify-executor uses ripgrep (ERE); \| in BRE means OR but is a literal | in ERE.
```

### Step 5: Clarification Questions

If ambiguity points were found, process them as follows.

**削除系 Issue の事前スキャン (Deletion-type issue pre-scan):**

Before processing ambiguity points, check if the Issue body or purpose contains deletion-type keywords (「削除」「撤去」「remove」「delete」「clean up」). If detected:
1. Extract the target keyword or pattern from the Issue content
2. Run `grep -rl 'pattern' .` from the repository root to enumerate all files containing the pattern
3. Add a `## Scope` section to the Issue body listing all enumerated files (create if absent, supplement with newly found files if already present)

**Priority sort:**

Sort ambiguity points from Step 3 in descending order of impact (scope of effect on acceptance criteria text, degree of propagation to implementation approach).

**Auto-resolution (for L/XL or all sizes in new issue flow):**

After priority sorting, check auto-resolution conditions from lowest-priority items upward. Conditions:
- Uniquely inferrable from existing codebase patterns
- Same judgment made in past similar issues (in retrospectives)
- Acceptance criteria text is unaffected regardless of which option is chosen

Items not meeting any condition are presented to the user.

**Pre-investigation (for each unresolved ambiguity point):**

Refer to `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md`'s "Sources to investigate" column and investigate sequentially (no sub-agents):

| Aspect | Content | Source |
|--------|---------|--------|
| Existing patterns | Similar implementations/conventions | Project source code (Grep/Read) |
| Past knowledge | Retrospectives from similar issues/specs | `$SPEC_PATH/*.md`. Skip if absent |
| Trade-offs | Pros and cons of each option | Codebase + Steering Docs |

Format with investigation results + recommended option + alternative + confirmation question, or with "no related patterns" note as fallback.

### Step 6: Create Issue

Read `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` and normalize the title. Create the issue:

1. `mkdir -p .tmp`
2. Write body to `.tmp/new-issue-body.md`
3. `gh issue create --title "$TITLE" --body-file .tmp/new-issue-body.md`
4. `rm -f .tmp/new-issue-body.md`

### Step 7: Apply Labels

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER issue
```

After applying labels, set blocked-by relationships from `Blocked by #N` patterns in the issue body:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh $NUMBER
```

(Exit code 2 means open blockers were detected and relationships were set — this is normal.)

### Step 8: Triage Auto-chain (if `triaged` label is absent)

If `triaged` is absent from labels: read `skills/triage/SKILL.md` and run the "Single Execution" section starting from Step 2 (title normalization). Output an intermediate triage results table after completion.

If `triaged` is present: skip this step.

### Step 9: Scope Assessment (sub-issue splitting)

**(non-interactive mode: skip this entire step — sub-issue splitting is a High-Stakes Decision. Output: "[non-interactive mode] Skipping high-stakes action: sub-issue splitting. To perform this action, run `/issue {number}` interactively." then proceed to Step 10.)**

Read `${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md` and use its XL definition (11+ files or multiple independent features) as the split threshold.

Analyze the issue background and acceptance criteria to determine whether sub-issue splitting is needed.

**Split criteria (examples, Claude judgment):**
- Changes span multiple independent features
- Staged release is preferable
- Scope exceeds a single PR
- **Risk profile differences**: high-risk vs. low-risk changes benefit from separation
- **Sequential validation**: A can be merged/validated before B
- **Independent testability**: each part testable independently

**When splitting is not needed (skip):** small changes (single feature, few files) or clear single-scope acceptance criteria.

**Size change rules (both directions):**
- **No split needed**: If Size is `XL` but splitting is not needed, read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and update Size XL → L (steps 1→2→3→4). Use label fallback (step 5) only if GraphQL fails. When GitHub Projects is not configured, step 1 returns empty `projectsV2.nodes` and automatically falls through to step 5.
- **Split executed**: After completing the split procedure below, if the current Size is not `XL`, read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and update parent Size → XL (steps 1→2→3→4). Use label fallback (step 5) only if GraphQL fails. This ensures routing consistency: downstream skills (`/auto`, etc.) use Size=XL to select the sub-issue route for parent issues.

**Procedure:**
1. Propose split plan via AskUserQuestion (sub-issue count, scope of each, dependencies)
2. After approval, create sub-issues with `gh issue create`
3. Redistribute acceptance criteria; retain only cross-cutting conditions in the parent
3a. Run lightweight refinement loop per sub-issue (steering doc alignment, verify command assignment, lightweight ambiguity detection, auto-resolution, record unresolved points, update body)
4. Set parent-child relationships via `addSubIssue` GraphQL mutation
5. Set sub-issue dependencies with `addBlockedBy` if applicable
6. Apply `phase/issue` label to each sub-issue
7. Run lightweight triage for each sub-issue (skip Steps 1, 1.5, 7; inherit Type/Priority from parent; determine Size individually per sub-issue scope)
8. Parent phase management: auto-close when all sub-issues done (no cross-cutting conditions); phase/verify + notify when cross-cutting conditions remain
9. **Upgrade parent Size to XL**: If the current parent Size is not already `XL`, read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and update parent Size → XL (steps 1→2→3→4). Use label fallback (step 5) only if GraphQL fails.

**GraphQL commands (examples):**
```bash
# Get issue ID
mapfile -t _id_arr < <(${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --cache --query get-issue-id -F num=$NUM --jq '.data.repository.issue.id')
ID="${_id_arr[0]}"

# Set parent-child
${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query add-sub-issue -F parentId="$PARENT_ID" -F childId="$CHILD_ID"

# Set dependency
${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query add-blocked-by -F issueId="$FRONTEND_ID" -F blockingId="$BACKEND_ID"
```

### Step 10: Issue Retrospective

**Skip condition**: Skip posting this retrospective comment if ALL of the following hold:
- Zero ambiguity auto-resolutions were made
- Zero acceptance criteria changes were made
- No surprising policy decisions were made

When skipping: output `retrospective skipped: no notable content` to terminal and proceed to the next step without posting a comment.

When NOT skipping: post a retrospective comment covering: judgment rationale for ambiguity resolution, key policy decisions from Q&A, and reasons for acceptance criteria changes.

The comment body must use `## Issue Retrospective` as the top-level heading (canonical key used by `/auto` Step 4b and `/verify`).

```bash
mkdir -p .tmp
# write to .tmp/issue-comment-$NUMBER.md with heading: ## Issue Retrospective
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $NUMBER .tmp/issue-comment-$NUMBER.md
rm -f .tmp/issue-comment-$NUMBER.md
```

### Step 11: Opportunistic Verification

If `opportunistic-verify: true` is set in `.wholework.yml`, read `${CLAUDE_PLUGIN_ROOT}/modules/opportunistic-verify.md` and follow "Processing Steps". Skill name: `/issue`. Skip if not set.

---

## Existing Issue Refinement

### Step 1: Fetch Issue Information

```bash
gh issue view $NUMBER --json body,title,labels
gh issue view $NUMBER --json comments
```

Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` and display the start banner with ENTITY_TYPE="issue", ENTITY_NUMBER=$NUMBER, SKILL_NAME="issue".

Detect embedded links in body and comments; fetch GitHub-hosted attachments via WebFetch or Read. Use attachment content and all comments as context for subsequent steps.

### Step 2: Auto-chain to triage (if `triaged` label is absent)

If `triaged` is absent from `labels`: read `skills/triage/SKILL.md` and run the "Single Execution" section starting from Step 2 (title normalization). Output an intermediate triage results table after completion.

If `triaged` is present: skip this step.

### Step 3: Label Transition

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER issue
```

### Step 4: Reference Steering Documents (if present)

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `SPEC_PATH`, `STEERING_DOCS_PATH`, and `HAS_PR_PREVIEW_CAPABILITY` for use in subsequent steps.

Check whether the following steering documents exist using Glob, then read only those that exist:

- `$STEERING_DOCS_PATH/product.md` — project vision, Non-Goals, Terms (terminology consistency)
- `$STEERING_DOCS_PATH/tech.md` — Forbidden Expressions (to avoid prohibited terms)

**If none exist, skip this step and proceed to the next.**

Use the referenced documents in subsequent steps for vision alignment, terminology consistency, and forbidden expression avoidance.

### Step 5: Background Factual Claim Verification (advisory)

Scan the `## Background` (or `## 背景`) section of the Issue body for factual claims about how the codebase works. Target patterns:

- **Generation/creation**: "X は Y で生成される", "X is generated by Y", "X creates Y"
- **Call/invocation**: "X は Y を呼ぶ", "X calls Y", "X invokes Y"
- **Dependency**: "X uses Y", "X depends on Y", "X は Y を使う"

For each identified factual claim, extract the code artifact name(s) (script filenames, function names, command names) and run:

```bash
grep -rl '<artifact_name>' . 2>/dev/null | head -5
```

**Advisory behavior (do not block)**:
- Results found: claim is likely accurate — continue silently
- No results: output a warning and continue:
  ```
  Warning [background-fact-check]: No codebase match for "<artifact_name>"
    Claim: "<claim text>"
    Advisory: verify this factual claim before proceeding to /spec
  ```

**Skip condition**: If the Background section contains no code-referencing factual claims, skip this step silently.

### Step 6: Ambiguity Detection

Read `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md`. Get Size with `get-issue-size.sh $NUMBER`. Detection limit: XS/S/M or unset → **at most 3**; L/XL → **at most 5**.

### Step 7: Classify Acceptance Criteria and Assign Verify Commands

Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-patterns.md` and follow the "Processing Steps" section guidelines to design verify command patterns.

Follow the full procedure defined in "New Issue Creation → Step 4: Classify Acceptance Criteria and Assign Verify Commands" above: classify each acceptance criterion as "pre-merge" or "post-merge", assign verify commands using the supported command table, apply translation document exclusions, prefer dedicated commands over `command` hints, apply `--when` modifiers, perform MCP tool detection, and assign verify-type tags to post-merge conditions.

Propose "Pre-merge" / "Post-merge" section split for existing issues lacking sections.

### Step 8: Clarification Questions

Collect ambiguity points and missing information. Process as follows:

**削除系 Issue の事前スキャン (Deletion-type issue pre-scan):**

Before processing ambiguity points, check if the Issue body or purpose contains deletion-type keywords (「削除」「撤去」「remove」「delete」「clean up」). If detected:
1. Extract the target keyword or pattern from the Issue content
2. Run `grep -rl 'pattern' .` from the repository root to enumerate all files containing the pattern
3. Add a `## Scope` section to the Issue body listing all enumerated files (create if absent, supplement with newly found files if already present)

**Priority sort:** Sort ambiguity points from Step 6 in descending order of impact (scope of effect on acceptance criteria text, degree of propagation to implementation approach).

**Auto-resolution:** After priority sorting, check auto-resolution conditions from lowest-priority items upward. Auto-resolve when all of the following hold: uniquely inferrable from existing codebase patterns; same judgment made in past similar issues (in retrospectives); acceptance criteria text is unaffected regardless of which option is chosen. Present items not meeting any condition to the user.

**Pre-investigation (for each unresolved ambiguity point):** Refer to `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md`'s "Sources to investigate" column and investigate sequentially (no sub-agents). Format with investigation results + recommended option + alternative + confirmation question, or with "no related patterns" note as fallback.

After confirming auto-resolved items, record them in an "Auto-Resolved Ambiguity Points" section appended to the issue body (combined with Step 9 body update). Skip the record if no items were auto-resolved.

### Step 9: Update Issue Body

`mkdir -p .tmp`, write to `.tmp/issue-body-$NUMBER.md`, update with `gh-issue-edit.sh $NUMBER .tmp/issue-body-$NUMBER.md`, delete with `rm -f .tmp/issue-body-$NUMBER.md`.

> **Note**: Always use the Write tool for temp files. Shell redirects trigger confirmation prompts.

### Step 10: Title Drift Check

Read `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` and follow the "Title Drift Check" section. Detect semantic drift between the current title and the updated Issue body, and update the title if drift is found.

### Step 11: Set Blocked-by Dependencies

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh $NUMBER
```

Exit code 0: no open blockers. Exit code 2: open blockers (relationship set, continue). Exit code 1: error (warn and continue).

### Step 12: Scope Assessment (sub-issue splitting)

**(non-interactive mode: skip this entire step — sub-issue splitting is a High-Stakes Decision. Output: "[non-interactive mode] Skipping high-stakes action: sub-issue splitting. To perform this action, run `/issue {number}` interactively." then proceed to Step 13.)**

Read `${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md`.

**For L/XL issues: run parallel investigation (Step 12a → 12b → 12c).**

#### Step 12a: Parallel Investigation (Scope / Risk / Precedent Agents)

Get steering doc paths with Glob. Launch these 3 subagents in a single message to ensure parallel fan-out (single-message fan-out prevents serialization regardless of model generation):

```text
Task(subagent_type="issue-scope", description="Scope investigation",
  prompt="Issue=$NUMBER, Steering Documents=$STEERING_DOCS_FILES, Issue body=<full text>")

Task(subagent_type="issue-risk", description="Risk investigation",
  prompt="Issue=$NUMBER, Issue body=<full text>")

Task(subagent_type="issue-precedent", description="Precedent investigation",
  prompt="Issue=$NUMBER, Issue body=<full text>")
```

On failure: fall back to standard scope assessment.

#### Step 12b: Split Proposal (integrate results)

Integrate outputs into a structured split proposal: sub-issue boundaries (from scope + risk data), size estimates, parallelization groups, key design decisions (from precedent data). Present via AskUserQuestion.

#### Step 12c: Create sub-issues (after approval)

Run the standard sub-issue creation flow (New Issue Creation Step 9, procedures 2–8):
2. Create sub-issues with `gh issue create`
3. Redistribute acceptance criteria; retain only cross-cutting conditions in the parent
3a. Run lightweight refinement loop per sub-issue (steering doc alignment, verify command assignment, lightweight ambiguity detection, auto-resolution, record unresolved points, update body)
4. Set parent-child relationships via `addSubIssue` GraphQL mutation
5. Set sub-issue dependencies with `addBlockedBy` if applicable
6. Apply `phase/issue` label to each sub-issue
7. Run lightweight triage for each sub-issue (skip Steps 1, 1.5, 7; inherit Type/Priority from parent; determine Size individually per sub-issue scope)
8. Parent phase management: auto-close when all sub-issues done (no cross-cutting conditions); phase/verify + notify when cross-cutting conditions remain
9. **Upgrade parent Size to XL**: If the current parent Size is not already `XL`, read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and update parent Size → XL (steps 1→2→3→4). Use label fallback (step 5) only if GraphQL fails. This ensures routing consistency: downstream skills (`/auto`, etc.) use Size=XL to select the sub-issue route for parent issues.

---

(For non-L/XL or fallback: run standard split assessment. Size change rules: Size XL → L when no split is needed; Size → XL when split is executed.)

### Step 13: Issue Retrospective

**Skip condition**: Skip posting this retrospective comment if ALL of the following hold:
- Zero ambiguity auto-resolutions were made
- Zero acceptance criteria changes were made
- No surprising policy decisions were made

When skipping: output `retrospective skipped: no notable content` to terminal and proceed to the next step without posting a comment.

When NOT skipping: post a retrospective comment covering: judgment rationale for ambiguity resolution, key policy decisions from Q&A, and reasons for acceptance criteria changes.

The comment body must use `## Issue Retrospective` as the top-level heading (canonical key used by `/auto` Step 4b and `/verify`).

```bash
mkdir -p .tmp
# write to .tmp/issue-comment-$NUMBER.md with heading: ## Issue Retrospective
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $NUMBER .tmp/issue-comment-$NUMBER.md
rm -f .tmp/issue-comment-$NUMBER.md
```

### Step 14: Opportunistic Verification

If `opportunistic-verify: true` is set in `.wholework.yml`, read `${CLAUDE_PLUGIN_ROOT}/modules/opportunistic-verify.md` and follow "Processing Steps". Skill name: `/issue`. Skip if not set.

---

## Label Transition on Close

```bash
gh issue close $NUMBER --reason "not planned" --comment "close reason"
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER done
```

---

## Decomposition File Mode

If ARGUMENTS contains `--from-decomposition-file`, extract the file path and run this section only. Do not run New Issue Creation or Existing Issue Refinement.

### Step 1: Read and Validate YAML

Read the file at the specified path using the Read tool. Validate the schema:

- `parent`: integer, required — an existing Issue number
- `sub_issues`: list with at least one entry, required
- Each entry requires:
  - `id`: string, required — unique within YAML (used for `blocked_by` references); must contain only alphanumeric characters, hyphens, and underscores (no path separators or special characters)
  - `title`: string, required — component prefix + verb-first format recommended (warn but proceed if not)
  - `background`: optional string — TBD skeleton used if absent
  - `purpose`: optional string — title summary used if absent
  - `acceptance_criteria`: optional list with `condition` and `verify` keys
  - `blocked_by`: optional list of `id` strings; all referenced `id` values must exist in `sub_issues`

On validation failure (missing required fields, duplicate `id`, unknown `blocked_by` reference): output a descriptive error message and stop. Do not create any Issues.

### Step 2: Detect Circular Dependencies

Build a dependency graph from all `blocked_by` references across all entries. Run DFS (depth-first search) over the graph to detect cycles before creating any Issues. If a cycle is detected, output the cycle path (e.g., `a → b → c → a`) and stop. Do not create any Issues.

DFS pseudo-code:
```
function dfs(node, visiting, visited, graph):
  if node in visited: return
  if node in visiting: report cycle and abort
  mark node as visiting
  for each dep in graph[node]:
    dfs(dep, visiting, visited, graph)
  mark node as visited
  remove from visiting
```

### Step 3: Create Issues

First pass — create all Issues and record their numbers:

For each sub_issue entry:

a. Generate skeleton body using the standard format:
   ```markdown
   ## 背景

   {background value, or: (TBD — XL parent #{parent} の sub-issue として {id} を起票)}

   ## 目的

   {purpose value, or: title summary}

   ## Acceptance Criteria

   ### Pre-merge (auto-verified)

   {acceptance_criteria entries as: - [ ] {condition} <!-- verify: {verify} -->
   if absent: - [ ] TBD}

   ### Post-merge

   なし
   ```

b. Run `mkdir -p .tmp`

c. Write the body to `.tmp/decomp-issue-{id}.md` using the Write tool

d. Run: `gh issue create --title "{title}" --body-file .tmp/decomp-issue-{id}.md`

e. Delete temp file: `rm -f .tmp/decomp-issue-{id}.md`

f. Record the created Issue number for this `id`

g. Set parent-child relationship via `add-sub-issue` GraphQL mutation:
   ```bash
   mapfile -t _parent_id_arr < <(${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --cache --query get-issue-id -F num={parent} --jq '.data.repository.issue.id')
   PARENT_ID="${_parent_id_arr[0]}"
   mapfile -t _child_id_arr < <(${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --cache --query get-issue-id -F num={created_issue_number} --jq '.data.repository.issue.id')
   CHILD_ID="${_child_id_arr[0]}"
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query add-sub-issue -F parentId="$PARENT_ID" -F childId="$CHILD_ID"
   ```

Second pass — set `blocked_by` relationships (after all Issues are created; handles forward references):

For each sub_issue entry that has a `blocked_by` list:
- Look up the Issue number recorded for each referenced `id`
- Set the dependency via `add-blocked-by` GraphQL mutation:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query add-blocked-by -F issueId="{child_node_id}" -F blockingId="{blocking_node_id}"
  ```

### Step 4: Output Summary

Output a text-format summary including:
- Each created Issue number and title (e.g., `#1234 next-init: Next.js プロジェクト初期化 + routing 設定 + middleware 移植`)
- Dependency graph in text format (list `blocked_by` edges, e.g., `#1235 next-theme ← blocked by #1234 next-init`)
- Total count of Issues created

---

## Standard Format

```markdown
## Background
(why this is needed)

## Purpose
(what to achieve)

## Acceptance Criteria

### Pre-merge (auto-verified)
- [ ] <!-- verify: file_exists "path" --> Condition 1 (subject, timing, and criteria clearly stated)
- [ ] <!-- verify: file_contains "path" "text" --> Condition 2 (subject, timing, and criteria clearly stated)

### Post-merge
- [ ] Condition 3 (subject, timing, and criteria clearly stated) <!-- verify-type: manual -->

## Related Issues
Related to #XX
```

---

## Acceptance Criteria Writing Guide

**Bad examples (ambiguous):**
- [ ] Verify behavior
- [ ] Errors are handled appropriately

**Good examples (clear, pre-merge):**
- [ ] <!-- verify: file_exists "skills/review/SKILL.md" --> `skills/review/SKILL.md` has been created
- [ ] <!-- verify: file_contains "CLAUDE.md" "/review" --> CLAUDE.md has `/review` description added

**Good examples (clear, post-merge):**
- [ ] User accesses the health check URL in production after merge and confirms 200 response <!-- verify-type: manual -->
- [ ] Running `/review {PR number}` in Claude Code confirms that a review comment is posted to the PR <!-- verify-type: opportunistic -->

**Do not include test counts (use `github_check` hints for verification):**

Bad:
- [ ] 12 bats tests all pass

Good:
- [ ] <!-- verify: github_check "gh pr checks" "Run bats tests" --> All bats tests pass (PR route)
- [ ] <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (test.yml) all jobs pass (patch route)

Note: Size XS/S → patch route → `gh run list` form; Size M/L → PR route → `gh pr checks` form (details: `modules/verify-classifier.md`).

**Do not embed implementation means in ACs:**

Embedding implementation means — tool names, function names, MCP tool names, specific CLI commands, etc. — directly in ACs creates fragile conditions. When the implementation changes (e.g., an MCP tool is replaced by a CLI command, or a function is renamed), ACs fail even though the feature still works correctly.

**Principle**: Write ACs in terms of **behavior and outcome** — what the system does or produces — not which implementation mechanism achieves it.

Bad (implementation-specific):
- [ ] `allowed-tools` contains `mcp__example__tool`
- [ ] `example_function()` is called with the correct arguments

Good (behavior/outcome-based):
- [ ] <!-- verify: rubric "skills/example/SKILL.md の Step 3 が認証フローを正しく呼び出す手順を記載している" --> Step 3 describes how the authentication flow is invoked
- [ ] <!-- verify: section_contains "skills/example/SKILL.md" "## Step 3" "authentication" --> Step 3 section contains authentication guidance

**rubric for behavioral ACs:**

When an AC describes a behavioral or semantic outcome rather than specific text, use `rubric` as the verify command. The LLM grader assesses whether the implementation satisfies the intent — independent of which specific tool, function, or CLI command was used. Pair with `section_contains` or `file_contains` as a mechanical supplementary check (see the rubric + supplementary guideline in Step 4 above). This `rubric`-first approach is especially important when the AC is about implementation intent (e.g., "correct behavior" or "proper handling") rather than a literal keyword.

---

## Completion Report

After opportunistic verification, get Size with `get-issue-size.sh $NUMBER`.

**For XL issues (after sub-issue splitting)**: list sub-issues with unresolved "Needs Refinement" points and recommend running `/issue N` for each. Do not list sub-issues without needs-refinement points.

**For XS issues only**: transition to `phase/ready` first:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER ready
```

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=issue`
- `ISSUE_NUMBER=$NUMBER`
- `SIZE={fetched size}`
- `RESULT={success|blocked}`

Then read `${CLAUDE_PLUGIN_ROOT}/modules/steering-hint.md` and follow the "Processing Steps" section.

---

## Behavior Test Recommendations

If `scripts/validate-skill-syntax.py` exists, read `skills/issue/spec-test-guidelines.md` and follow its guidelines. Skip if the file does not exist.
