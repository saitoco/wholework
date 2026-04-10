---
model: sonnet
name: triage
description: Issue triage. Automates title normalization, Type/Priority/Size/Value assignment (`/triage 123` for single issue + lightweight analysis, `/triage` for bulk execution, `/triage --backlog` for bulk processing + 4-perspective deep analysis).
allowed-tools: Bash(gh:*, cat:*, echo:*, grep:*, jq:*, test:*, bash:*, printf:*, wc:*, head:*, tail:*, sed:*, awk:*, mkdir:*, rm:*, ${CLAUDE_PLUGIN_ROOT}/scripts/triage-backlog-filter.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*), Read, Write, Glob, Grep
---

# Issue Triage

A skill that automates Issue metadata maintenance. When invoked, execute immediately. No explanations, confirmations, or questions needed.

## Argument Parsing (execute first)

If ARGUMENTS contains `--help`, Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and follow the "Processing Steps" section to output help, then stop.

**If ARGUMENTS is empty (unspecified, empty string, or whitespace only) or contains only `--limit N` → skip the single-issue section and proceed immediately to the "Bulk Execution" section (default: `--limit 100`)**

**`--assignee {value}` resolution (execute before routing):**

If ARGUMENTS contains `--assignee {value}`, determine ASSIGNEE_FILTER as follows:
- If `{value}` is `me`: run `gh api user --jq '.login'` to get the current authenticated username, set `ASSIGNEE_FILTER=--assignee {resolved_user}`
- If `{value}` is `none`: set `ASSIGNEE_FILTER=--no-assignee`
- Otherwise (username): set `ASSIGNEE_FILTER=--assignee {value}`

If `--assignee` is not specified, set ASSIGNEE_FILTER to empty (all issues).

Check ARGUMENTS and proceed immediately to the matching section:

- **ARGUMENTS is empty** (unspecified, empty string, whitespace only) **or contains only `--limit N` → start "Bulk Execution" section immediately** (default: `--limit 100`). Skip the single-issue section
- ARGUMENTS is a number (e.g., `123`) → start "Single Issue Execution" section immediately
- ARGUMENTS contains `--backlog` → start "Backlog Analysis" section immediately
- Only `--assignee` is present with no number or `--backlog` → start "Bulk Execution" section immediately

## Command Execution Constraints

To avoid confirmation dialogs, strictly follow these rules:

1. **Single line**: Write commands on a single line (no `\` line continuations)
2. **No comment lines**: Do not include `# ...` comment lines before commands
3. **No leading variable assignments**: Do not start with `VAR=... && command` or `VAR=$(...)`
4. **Start with a script or command**: Begin with `${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh` or `gh` directly
5. **No `&&` chaining**: Execute only one command per Bash call
6. **No inline GraphQL**: Do not pass inline GraphQL query strings to `gh-graphql.sh`. Always use `--query <n>` format

**Good examples:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --query get-issue-id -F num=123 --jq '.data.repository.issue.id'
```

```bash
gh issue view 123 --json number,title,body,labels
```

**Bad examples (do not use):**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh 'mutation(...)' \
  -F projectId="PVT_xxx" \
  -F itemId="PVTI_xxx"
```

```bash
gh issue view 123 --json number,title,body,labels && echo "---" && gh issue view 124 --json number,title,body,labels
```

---

## Single Issue Execution (`/triage 123`)

### Step 1: Issue Information Retrieval

```bash
gh issue view $NUMBER --json title,body,labels
```

- If the `triaged` label is already present, skip and notify the user

### Step 2: Duplicate Candidate Detection

Semantically compare against existing open issues to detect duplicate candidates.

```bash
gh issue list --state open --json number,title,body --limit 100
```

- Claude directly compares titles and bodies semantically to identify issues covering the same topic
- Exclude the target issue itself
- If duplicate candidates are found, report via issue comment (**do not auto-close**):
  - Comment format example: `⚠️ Possible duplicate: similar to #123 "test-runner: Add Vitest detection"`
  - Run `mkdir -p .tmp` to create the directory in advance
  - Write comment body to `.tmp/triage-duplicate-comment-$NUMBER.md` using the Write tool
  - Post: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $NUMBER .tmp/triage-duplicate-comment-$NUMBER.md`
  - Delete: `rm -f .tmp/triage-duplicate-comment-$NUMBER.md`
- If no duplicate candidates, skip without comment

### Step 3: Title Normalization

Read `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` and follow the "Processing Steps" section to normalize the title.

### Step 4: Type Assignment (Issue Types + label fallback)

Read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and execute Steps 1→2 from the "Type Field Update" section to set the Type. Complete on GraphQL success; only execute Step 3 label fallback on failure.

Named queries to use (`--query <n>` format): `get-issue-types`, `get-issue-id`, `update-issue-type`

Determine Bug / Feature / Task from the issue body.

**Classification criteria (exhaustive):**
- **Bug**: Keywords like defect, error, fix, broken, or descriptions of "behavior different from expected"
- **Feature**: Keywords like new addition, new feature, implementation, enhancement
- **Task**: Keywords like refactoring, configuration change, documentation update, maintenance

### Step 5: Priority Assignment (Projects field)

Read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and execute Steps 1→2→3→4 from the "Priority / Size Field Update" section to set Priority. Complete on GraphQL success; only execute Step 5 label fallback on failure.

Named queries to use (`--query <n>` format): `get-projects-with-fields`, `get-issue-id`, `add-project-item`, `update-field-value`

**Skip when Projects is not configured**: If the repository has no GitHub Projects, `projectsV2.nodes` returns an empty array in Step 1 of `project-field-update.md`, automatically proceeding to Step 5 (label fallback). No additional branching needed.

Detect priority information from the title or body and reflect it in the project's Priority field. Skip without warning if neither title nor body contains priority information.

**Detection targets:**
1. Prefixes like `[Priority:High]` in the title (information before Step 2 removal)
2. Priority-related mentions in the body

**Precedence:** If priority information appears in both title and body, prefer the title.

**Keyword examples (reference):**

| Priority | Example keywords |
|----------|-----------------|
| `urgent` | `urgent`, `blocker`, `ASAP`, `critical` |
| `high` | `high priority`, `important`, `high` |
| `medium` | `medium priority`, `medium` |
| `low` | `low priority`, `low`, `nice-to-have` |

### Step 6: Size Assignment (Projects field)

Read `${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md` and follow the "Processing Steps" section's Size determination flow (2-axis method) to determine Size.

Read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and execute Steps 1→2→3→4 from the "Priority / Size Field Update" section to set Size. Complete on GraphQL success; only execute Step 5 label fallback on failure.

Named queries to use (`--query <n>` format): `get-projects-with-fields`, `get-issue-id`, `add-project-item`, `update-field-value`

**Skip when Projects is not configured**: If the repository has no GitHub Projects, `projectsV2.nodes` returns an empty array in Step 1 of `project-field-update.md`, automatically proceeding to Step 5 (label fallback). No additional branching needed.

Estimate the scope of change from the issue body's acceptance conditions and technical notes, and set the project's Size field. Determine in 5 levels: XS/S/M/L/XL.

### Step 7: Value Assignment (Projects field)

Since the Value field is a SingleSelect type, update it using the same Steps 1→2→3→4 from `project-field-update.md`'s "Priority / Size Field Update" section (always calculate and update regardless of existing Value):

1. Fetch project fields with `--query get-projects-with-fields` and look for a `SingleSelect` type `Value` field
2. If the field does not exist: prompt "Please manually create a `Value` field (Single Select type, options: 1–5) in Projects, then re-run" and skip
3. If the issue is not yet in the project, add it with `--query add-project-item`
4. Set Value with `--query update-field-value` (pass the optionId corresponding to the score value via `-F optionId=<option-id>`)
5. If GraphQL fails: label fallback (assign `value/N` label)

Named queries to use (`--query <n>` format): `get-projects-with-fields`, `get-issue-id`, `add-project-item`, `update-field-value`

**Fallback level determination (read Steering Documents):**

Determine the fallback level using this flow:

```
1. Does docs/product.md exist with type: steering?
   → Yes: Level 1 (full precision)
   → No: next
2. Does README.md or CLAUDE.md exist with project purpose/constraint descriptions?
   → Yes: Level 2 (medium precision) — Read README.md / CLAUDE.md to extract policy
   → No: Level 3 (minimal)
```

**Value scoring (same logic as backlog analysis):**

Reuse the full open issues data already retrieved in Step 2 to calculate Impact (no additional API calls). Calculate Alignment based on fallback level.

- `Impact = min(10, blocking × 3 + mentions × 1 + parent_flag × 2 + shared_flag × 2)`
- Alignment: Level 1 (-3 to 5), Level 2 (-2 to 3), Level 3 (Type correction only -1 to 1)
- Use the normalization table with level-specific thresholds to convert to Value 1–5

**Normalization table (Value determination):**

| Value | Level 1 (raw -3 to 16) | Level 2 (raw -2 to 13) | Level 3 (raw -1 to 11) |
|-------|------------------------|------------------------|------------------------|
| 5 | 10–16 | 9–13 | 8–11 |
| 4 | 7–9 | 6–8 | 5–7 |
| 3 | 4–6 | 3–5 | 3–4 |
| 2 | 1–3 | 1–2 | 1–2 |
| 1 | 0 or below | 0 or below | 0 or below |

**Skip when Projects is not configured**: Same as Step 5/6.

### Step 8: Lightweight Analysis

Using the full open issues data already retrieved in Step 2, run the following two lightweight analyses (minimal additional API calls).

**Stale single-issue check:**

Determine if the issue is stagnating based on these criteria (report only, no comment posted):

| Criterion | How to check |
|-----------|-------------|
| Acceptance conditions undefined or ambiguous | Check issue body |
| "TBD", "investigating", "blocked" etc. in body | Check issue body and title |
| Many implementation steps (sub-issue split not done) | Check bullet count in issue body |

If stagnation patterns are detected, include in completion report. If none detected, report "no stagnation".

**Dependency blocked-by check:**

Extract `Blocked by #N` patterns from the issue body and check the status of blocked-by issues:

1. If no `Blocked by #N` text, skip
2. If found, use already-retrieved data from Step 2 if the blocked-by issue is included. Otherwise, check status with `gh issue view N --json state,title`
3. If the blocked-by issue is CLOSED: report as "resolved dependency (#N is CLOSED)"

### Step 9: Triage Marker

```bash
gh issue edit $NUMBER --add-label "triaged"
```

### Step 10: Completion Report

Output a summary of the processing results to the user:

```
## Triage Result: #123

- Title: `old title` → `new title`
- Type: Feature (label fallback)
- Priority: high
- Size: M (determined from XS/S/M/L/XL)
- Value: 4 (Impact medium: mentions #456, Alignment medium)
- Duplicate candidates: none (or #456 "similar title" → comment posted)
- Stale check: no stagnation (or "investigating" pattern detected)
- Dependency check: no dependencies (or "resolved dependency (#200 is CLOSED)")
```

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=triage`
- `ISSUE_NUMBER=$NUMBER`
- `SIZE={triaged size}`
- `RESULT=success`

---

## Bulk Execution (`/triage`)

**Using `/triage --backlog` (no perspective) runs bulk processing plus integrated deep analysis of all 4 perspectives.** See the "Backlog Analysis" section for details.

### Arguments

- `--limit N`: limit processing count (default: 100)

### 3-Step Structure

Bulk execution uses the following 3 steps. Do not use Task sub-agents.

#### Step 1: Bulk Retrieval

1. Get target issue numbers using the helper script (add `$ASSIGNEE_FILTER` if set):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/triage-backlog-filter.sh --limit $LIMIT
   ```
   With `--assignee {user}`:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/triage-backlog-filter.sh --limit $LIMIT --assignee {user}
   ```
   With `--no-assignee`:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/triage-backlog-filter.sh --limit $LIMIT --no-assignee
   ```

   This script outputs issue numbers without the `triaged` label one per line.

2. Fetch details for each target issue (**run commands individually per issue**):
   ```bash
   gh issue view 123 --json number,title,body,labels
   ```
   ```bash
   gh issue view 124 --json number,title,body,labels
   ```
   - **Note**: Do not chain multiple commands with `&&`. Fetch each issue in a separate Bash call.

#### Step 2: Bulk Classification

Based on all issue information retrieved in Step 1, Claude directly classifies all issues in a single inference pass.

**Classification per issue:**
- Title normalization (follow `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` naming conventions)
- Type determination (Bug / Feature / Task)
- Size estimation (XS / S / M / L / XL)
- Priority detection (urgent / high / medium / low / null)
- Value score calculation (1–5, normalized from Impact + Alignment)

**Load Steering Documents once at the start of Phase 2 (fallback level determination):**

```
1. Does docs/product.md exist with type: steering?
   → Yes: Level 1 (full precision) — Read product.md / tech.md
   → No: next
2. Does README.md or CLAUDE.md exist?
   → Yes: Level 2 (medium precision) — Read README.md / CLAUDE.md to extract policy
   → No: Level 3 (minimal)
```

**Value scoring (same logic as backlog analysis):**

Reuse all open issues data already retrieved in Step 1 to calculate Impact (no additional API calls).

- `Impact = min(10, blocking × 3 + mentions × 1 + parent_flag × 2 + shared_flag × 2)`
- Alignment: Level 1 (-3 to 5), Level 2 (-2 to 3), Level 3 (Type correction -1 to 1)
- Use normalization table to convert to Value 1–5 (same table as backlog analysis)

**Output JSON schema:**

```json
[
  {
    "number": 101,
    "new_title": "component: verb-starting description",
    "type": "Feature",
    "size": "M",
    "priority": "high",
    "value": 4,
    "duplicate_candidates": [123]
  }
]
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `number` | number | ✓ | Issue number |
| `new_title` | string | ✓ | Normalized title (following naming conventions) |
| `type` | string | ✓ | `"Bug"` / `"Feature"` / `"Task"` |
| `size` | string | ✓ | `"XS"` / `"S"` / `"M"` / `"L"` / `"XL"` |
| `priority` | string \| null | ✓ | `"urgent"` / `"high"` / `"medium"` / `"low"` / `null` (not detected) |
| `value` | number | ✓ | `1`–`5` (normalized from Impact + Alignment) |
| `duplicate_candidates` | number[] | ✓ | List of duplicate candidate issue numbers (empty array `[]` if none) |

**Duplicate detection in bulk execution (done in Step 2):**

Using all issue information retrieved in Step 1, semantically compare each issue against existing open issues to detect duplicates in bulk. Exclude the issue itself. If duplicate candidates are found, store their numbers in `duplicate_candidates`; otherwise set to empty array `[]`.

#### Step 3: Bulk Update

Loop through the Step 2 JSON results and execute the following API calls for each issue (**execute each command individually**).

```
for each issue in Step 2 results:
  1. Update title: gh issue edit $NUMBER --title "$NEW_TITLE"
  2. Set Type: execute Steps 1→2 from project-field-update.md "Type Field Update" (complete on GraphQL success, only Step 3 label fallback on failure). Queries: `get-issue-types`, `get-issue-id`, `update-issue-type`
  3. Set Priority: only if priority is not null, execute Steps 1→2→3→4 from project-field-update.md "Priority / Size Field Update" (complete on GraphQL success, only Step 5 label fallback on failure. null = skip without warning). Queries: `get-projects-with-fields`, `get-issue-id`, `add-project-item`, `update-field-value`
  4. Set Size: execute Steps 1→2→3→4 from project-field-update.md "Priority / Size Field Update" (complete on GraphQL success, only Step 5 label fallback on failure). Queries: `get-projects-with-fields`, `get-issue-id`, `add-project-item`, `update-field-value`
  5. Set Value: skip if Value is already set (Projects V2 Value field is non-empty, or `value/*` label is assigned). Only set if unset using `update-field-value` query (`-F optionId=<optionId for score value>`). Skip if field doesn't exist, label fallback (`value/N`) on GraphQL failure. Queries: `get-projects-with-fields`, `get-issue-id`, `add-project-item`, `update-field-value`
  6. Add triaged label: gh issue edit $NUMBER --add-label "triaged"
  7. Duplicate comment: if duplicate_candidates is non-empty, report via issue comment (**do not auto-close**)
     - Comment format example: `⚠️ Possible duplicate: similar to #123 "test-runner: Add Vitest detection"`
     - Run mkdir -p .tmp to create the directory in advance
     - Write comment body to `.tmp/triage-duplicate-comment-$NUMBER.md` using the Write tool
     - Post: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $NUMBER .tmp/triage-duplicate-comment-$NUMBER.md`
     - Delete: `rm -f .tmp/triage-duplicate-comment-$NUMBER.md`
```

**Error handling:**
- If API updates fail for some issues, skip them and process the next issue, reporting failures in the final summary
- Skipped issues do not receive the triaged label

**Fetch project information once at the start of Step 3:**
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh --cache --query get-projects-with-fields
```
- Fetch and cache Priority / Size field IDs and option IDs
- Also fetch Issue Types once at the start of Step 3

### Completion Report

After processing all issues, output a results summary:

```
## Bulk Triage Results

| # | Title Change | Type | Priority | Size | Value | Duplicates | Status |
|---|-------------|------|----------|------|-------|------------|--------|
| #101 | old → new | Feature | high | S | 4 | #456 | ✅ |
| #102 | unchanged | Bug | — | M | 2 | none | ✅ |
| #103 | — | — | — | — | — | — | ❌ API error |
```

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=triage`
- `RESULT=success`
- (omit `ISSUE_NUMBER` — bulk run with multiple issues, guide will be omitted per module logic)

---

---

## Backlog Analysis (`/triage --backlog`)

### Arguments

- Perspective specification (omit for no-perspective = integrated execution):
  - No perspective (`--backlog` only): bulk process untriaged + integrated execution of all 4 perspectives. Assigns `triaged` label
  - `value`: Value map display + differential update → proceed to Step 2 (no `triaged` assignment)
  - `duplicate`: N:N semantic duplicate clustering → proceed to Step 2d (no `triaged` assignment)
  - `stale`: stagnation pattern classification → proceed to Step 2s (no `triaged` assignment)
  - `dependency`: dependency health check (circular deps, resolved blocked-by, orphan deps) → proceed to Step 2b (no `triaged` assignment)
- `--limit N`: issue fetch limit (default: 100)

### Step 1: Data Collection

**Without `--assignee` (normal flow):**

```bash
gh issue list --state open --json number,title,body,labels,comments --limit $LIMIT
```

**With `--assignee` (Phase 1a/1b split):**

Phase 1a — full lightweight fetch (for Impact calculation, no `--assignee` filter):

```bash
gh issue list --state open --json number,body --limit $LIMIT
```

Phase 1b — target issue fetch (for detailed analysis, with `--assignee` filter):

With `--assignee {user}`:
```bash
gh issue list --state open --json number,title,body,labels,comments --limit $LIMIT --assignee {user}
```
With `--no-assignee`:
```bash
gh issue list --state open --json number,title,body,labels,comments --limit $LIMIT --no-assignee
```

Phase 1b results are the "analysis target issue list". Impact calculation (blocking/mention aggregation) references Phase 1a full data. Alignment scoring and duplicate/stale analysis run only on Phase 1b target issues.

- Check Steering Documents with Glob and Read if they exist:
  - `docs/product.md` — Vision / Non-Goals reference
  - `docs/tech.md` — technical policy reference
- Comment history is already retrieved via `--json comments` above; no individual fetch needed

**Fallback level determination (execute after loading Steering Documents):**

Determine the fallback level using this flow and use it in Steps 2 and 3:

```
1. Does docs/product.md exist with type: steering?
   → Yes: Level 1 (full precision)
   → No: next
2. Does README.md or CLAUDE.md exist with project purpose/constraint descriptions?
   → Yes: Level 2 (medium precision) — Read README.md / CLAUDE.md to extract policy
   → No: Level 3 (minimal)
```

| Level | Description | Alignment source |
|-------|-------------|-----------------|
| Level 1 | Steering Documents available (full precision) | product.md / tech.md |
| Level 2 | README/CLAUDE.md only (medium precision) | Approximate from README.md / CLAUDE.md |
| Level 3 | GitHub data only (minimal) | Type correction only |

### Step 2: Value Analysis (Scoring)

Run Impact + Alignment scoring on the issue set collected in Step 1.

**Impact scoring (0–10):**

| Signal | Detection method | Weight |
|--------|-----------------|--------|
| Blocking count | Number of issues referencing this issue with `Blocked by` | ×3 |
| Mention count | Number of times `#N` is mentioned in other issues' bodies/comments | ×1 |
| Parent issue | Is this a parent issue with sub-issues? | +2 |
| Shared component | Does the change target files referenced by modules/ or multiple skills? | +2 |

```
Impact = min(10, blocking × 3 + mentions × 1 + parent_flag × 2 + shared_flag × 2)
```

**Alignment scoring (by level):**

**Level 1 (-3 to 5): Steering Documents available**

| Signal | Score |
|--------|-------|
| Semantic relevance to product.md Vision | 0–5 (Claude scores directly) |
| Proximity to product.md Non-Goals | 0 to -3 (penalty for closeness) |
| Is the issue directly mentioned in Steering Documents? | +1 |

```
Alignment = vision_similarity + non_goals_penalty + steering_mention
```

**Level 2 (-2 to 3): Approximate from README/CLAUDE.md**

| Alternative source | Substitutable judgment | Score |
|-------------------|----------------------|-------|
| Relevance to README.md project description/purpose | Vision approximation | 0–3 |
| Proximity to CLAUDE.md constraints/prohibitions | Non-Goals approximation | 0 to -2 |

```
Alignment = readme_vision_similarity + claude_constraint_penalty
```

**Level 3 (-1 to 1): Type correction only**

Bugs accumulate risk if left unaddressed, so elevate their baseline priority.

| Type | Correction |
|------|-----------|
| Bug | +1 |
| Feature | 0 |
| Task | -1 |

```
Alignment = type_correction
```

**Normalization table (Value determination, by level):**

Since the practical range of raw scores varies by fallback level, adjust thresholds by level to avoid skewed Value 1–5 distribution.

| Value | Level 1 (raw -3 to 16) | Level 2 (raw -2 to 13) | Level 3 (raw -1 to 11) |
|-------|------------------------|------------------------|------------------------|
| 5 | 10–16 | 9–13 | 8–11 |
| 4 | 7–9 | 6–8 | 5–7 |
| 3 | 4–6 | 3–5 | 3–4 |
| 2 | 1–3 | 1–2 | 1–2 |
| 1 | 0 or below | 0 or below | 0 or below |

### Step 2b: Dependency Analysis

Execute only when the `dependency` perspective is specified. Check dependency health for the issue set collected in Step 1.

**Build dependency graph:**

1. Extract `Blocked by #N` patterns (case-insensitive, e.g., `blocked by #123`, `Blocked by #456`) from each issue body using regex
2. Build a graph with issue numbers as nodes and blocked-by as directed edges (N → M: issue N is blocked by issue M)
3. Keep extracted dependencies in memory as a dictionary: `{ issue_num: [blocked_by_num, ...], ... }`

**Anomaly detection logic (3 types):**

| Anomaly type | Definition | Detection method |
|-------------|-----------|-----------------|
| Circular dependency | Cycle in graph (A→B→C→A etc.) | Cycle detection via DFS |
| Resolved blocked-by | Blocked-by target is CLOSED but dependency text remains | Check status with `gh issue view N --json state` |
| Orphan dependency | Blocked-by target issue number doesn't exist in repo | `gh issue view N` returns an error |

**Verification order:**

1. **Graph construction**: Extract blocked-by relations from all issue bodies and build the graph
2. **Circular dependency detection**: Run DFS on entire graph to detect cycles (Claude tracks logically)
3. **Resolved blocked-by detection**: Use already-collected data for blocked-by targets in Step 1; check status with `gh issue view N --json state` for issues not in Step 1 data (closed)
4. **Orphan dependency detection**: Run `gh issue view N --json state` for blocked-by targets not collected in Step 1; those that return errors (don't exist) are orphan dependencies

**Notes (exhaustive):**
- No auto-correction. Only output report and manual action guidance
- Display "no dependency anomalies" if none detected

After analysis, output the report in the Step 3 dependency format.

### Step 2d: Duplicate Analysis (Clustering)

Execute only when the `duplicate` perspective is specified. Detect duplicate clusters via AI semantic comparison for the issue set retrieved in Step 1.

**Clustering procedure:**

1. List all issue titles and bodies
2. Claude semantically compares them and groups issues judged to cover "the same topic"
   - Same judgment criteria as single issue Step 2 (1-to-N), but extended to N:N full-pair comparison
   - Similarity criteria: "essentially the same problem to solve", "overlapping implementation targets", "identical purpose/effect"
3. Group each cluster as "issues covering the same topic"
4. Exclude issues not in any cluster (no duplicates) from output
5. Avoid over-detection: do not include in cluster if judged "similar but different topics"

**Notes (exhaustive):**
- The `--limit` option applies, so the default cap for N:N comparison is 100 issues
- Do not run value analysis (Step 2). duplicate and value are separate parallel perspectives

After analysis, output the report in the Step 3 duplicate format.

### Step 2s: Stale Analysis

Execute only when the `stale` perspective is specified. AI classifies stagnation patterns for the issue set collected in Step 1.

**Stagnation pattern classification (5 types):**

| Pattern | Description | Detection hints |
|---------|-------------|----------------|
| Unclear goal | No definition of what completes the issue | Ambiguous acceptance conditions, abstract body, diverging discussion |
| Awaiting investigation | Information gathering or external dependency not resolved | "investigating", "TBD", "blocked" text, comments show waiting state |
| Oversized scope | Too large to handle as a single issue | Many implementation steps, sub-issue split not done |
| Priority loss | Pushed aside by other important issues | Long-term neglect, no references from other issues, low Priority |
| No longer needed | Issue became obsolete due to environment/policy change | Related feature already implemented, premise changed, no mentions |

**Analysis procedure:**

1. AI makes overall judgment based on each issue's body, labels, and comment history
2. No quantitative thresholds. Classify if determined to be "stagnating"
3. If multiple patterns apply, select the most primary pattern
4. Exclude issues not judged as stagnating from output
5. Assign recommended action (suggest review / suggest close) for each issue:
   - "Unclear goal", "Awaiting investigation", "Oversized scope" → suggest review
   - "Priority loss" → suggest review (also suggest close if long neglect)
   - "No longer needed" → suggest close

After analysis, output the report in the Step 3 stale format.

### Step 3: Report Output

Output the report to console (no file saving).

**Report header:** If `--assignee` is specified, note the target count and total count:
- With `--assignee {user}`: `## Backlog Analysis Report (target: @{user} N issues / total open: M issues)`
- Without: `## Backlog Analysis Report`

**For value perspective:** Classify in descending order Value 5→1, displaying title, Size, Priority, and score rationale for each issue. For Value 1 issues, add "needs review" with proposed action (close etc.).

**Fallback notification (display at report header for value perspective):**

Display the following notification at the report header based on the fallback level determined in Step 1:

- Level 1 (Steering Documents available): no notification (normal state)
- Level 2 (README/CLAUDE.md only):
  ```
  ⚠️ Steering Documents not found. Estimating policy from README.md/CLAUDE.md.
     Run `/doc init` to create Steering Documents for more accurate Alignment evaluation.
  ```
- Level 3 (GitHub data only):
  ```
  ⚠️ No project policy information source found. Running Impact-based analysis only.
     Run `/doc init` to create Steering Documents for policy-based evaluation.
  ```

```
## Backlog Analysis Report

### Value 5 (top priority)
- #123 "issue-title" Size: M, Priority: high
  Rationale: Blocking=2 (×3=6), parent issue (+2), Alignment=2 → Impact=8, raw=10

### Value 4
...

### Value 1 (needs review)
- #456 "old-issue"
  Proposal: close or re-evaluate after resolving dependencies
```

**For duplicate perspective:** Display issue list and similarity reason per detected cluster. Display "no duplicate candidates" if no clusters detected.

```
## Backlog Analysis Report (Duplicate Clustering)

### Cluster 1 (2 issues)
- #123 "issue-A"
- #456 "issue-B"
  Similarity: Both deal with adding the same feature; implementation targets overlap

### Cluster 2 (3 issues)
- #101 "issue-C"
- #102 "issue-D"
- #103 "issue-E"
  Similarity: All address the same error handling issue from different angles

---
Total: 2 clusters, 5 duplicate candidates
```

**For stale perspective:** Classify by stagnation pattern and display recommended action for each issue. Display "no stagnation candidates" if none detected.

```
## Backlog Analysis Report (Stale Analysis)

### Unclear Goal (suggest review)
- #123 "issue-A"
  Reason: Acceptance conditions undefined. "Improve X" mentioned but completion criteria ambiguous

### Awaiting Investigation (suggest review)
- #456 "issue-B"
  Reason: Comment says "waiting for X investigation results"; no progress

### Oversized Scope (suggest review)
- #789 "issue-C"
  Reason: 8 implementation steps listed; sub-issue split recommended

### Priority Loss (suggest review)
- #101 "issue-D"
  Reason: No comments or updates for a long time. Not referenced by other issues

### No Longer Needed (suggest close)
- #102 "issue-E"
  Reason: Related feature already implemented in #200; issue is obsolete

---
Total: 5 stagnation candidates
```

**For dependency perspective:** Classify by anomaly type and display manual action for each issue. Display "no dependency anomalies" if none detected.

```
## Backlog Analysis Report (Dependency Analysis)

### Circular Dependency (suggest manual resolution)
- #123 → #456 → #789 → #123
  Action: Delete one of the blocked-by descriptions or merge the issues

### Resolved Blocked-by (suggest removing dependency text)
- #101 "issue-A" is blocked by #200 (CLOSED)
  Action: Remove `Blocked by #200` from #101 body

### Orphan Dependency (suggest removing dependency text)
- #102 "issue-B" is blocked by #999 (issue does not exist)
  Action: Remove `Blocked by #999` from #102 body

---
Total: 1 circular dependency, 1 resolved blocked-by, 1 orphan dependency
```

### Step 4: Apply Analysis Results (approval flow per perspective)

After each perspective's analysis is complete, always run the application flow. Ask for user approval via AskUserQuestion before applying.

**Value perspective application flow:**

1. Ask for user approval (use AskUserQuestion):
   - "Update N Value fields? (Value 5: X issues, Value 4: Y issues...)"
2. After approval, update Value fields:
   - If Projects V2 is configured:
     - Fetch project fields with `--query get-projects-with-fields`
     - Find `SingleSelect` type `Value` field
     - If field exists: set using `--query update-field-value` with optionId for the score value
     - If field doesn't exist: prompt "Please manually create a `Value` field (Single Select type, options: 1–5) in Projects, then re-run" and skip
   - If Projects V2 is not configured: label fallback:
     - Determine label name based on issue's Value (e.g., Value 5 → `value/5`)
     - If the label doesn't exist in the repo, create it with `gh label create --force "value/5" --color "BFD4F2" --description "Value 5"` (color/description arbitrary)
     - After creation (or if already exists), assign with `gh issue edit <number> --add-label "value/5"`
3. Record rationale in a comment for issues whose Value changed:
   - Run `mkdir -p .tmp` first
   - Write comment body to `.tmp/triage-value-comment-$N.md` using the Write tool
   - Post: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $N .tmp/triage-value-comment-$N.md`
   - Delete: `rm -f .tmp/triage-value-comment-$N.md`

**Duplicate perspective application flow:**

1. Ask for user approval (use AskUserQuestion):
   - "Post N duplicate comments? (no auto-close)"
2. After approval, post duplicate comments to all issues in each cluster:
   - Post comment listing other issue numbers in the cluster
   - Comment format example: `⚠️ Possible duplicate: similar to #456 "issue-B". Consider merging or closing (no auto-close)`
   - Run `mkdir -p .tmp` first
   - Write comment body to `.tmp/triage-duplicate-comment-$N.md` using the Write tool
   - Post: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $N .tmp/triage-duplicate-comment-$N.md`
   - Delete: `rm -f .tmp/triage-duplicate-comment-$N.md`
3. After posting, report "Posted duplicate comments to N issues"

**Stale perspective application flow:**

1. Ask for user approval (use AskUserQuestion):
   - "Post N stale analysis comments? (no auto-close)"
2. After approval, post analysis comments to stagnating issues:
   - Record stagnation pattern and recommended action as comments
   - Comment format (suggest review): `Stale analysis: classified as pattern "Awaiting Investigation". Reason: X. Recommended action: review situation and decide whether to continue or close`
   - Comment format (suggest close): `Stale analysis: classified as pattern "No Longer Needed". Reason: X. Recommended action: consider closing (no auto-close)`
   - Run `mkdir -p .tmp` first
   - Write comment body to `.tmp/triage-stale-comment-$N.md` using the Write tool
   - Post: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $N .tmp/triage-stale-comment-$N.md`
   - Delete: `rm -f .tmp/triage-stale-comment-$N.md`
3. After posting, report "Posted stale analysis comments to N issues" (no auto-close)

**Dependency perspective application flow:**

1. Ask for user approval (use AskUserQuestion):
   - "Post N dependency analysis comments? (circular: X, resolved blocked-by: Y, orphan: Z)"
2. After approval, post analysis comments to each anomalous issue (no auto-correction):
   - Comment format (circular): `Dependency analysis: circular dependency detected. Cycle: #123 → #456 → #789 → #123. Delete one of the blocked-by descriptions or merge the issues (no auto-correction)`
   - Comment format (resolved blocked-by): `Dependency analysis: blocked-by target #200 is already CLOSED. Recommend removing Blocked by #200 from body (no auto-correction)`
   - Comment format (orphan): `Dependency analysis: blocked-by target #999 does not exist. Recommend removing Blocked by #999 from body (no auto-correction)`
   - Run `mkdir -p .tmp` first
   - Write comment body to `.tmp/triage-dependency-comment-$N.md` using the Write tool
   - Post: `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $N .tmp/triage-dependency-comment-$N.md`
   - Delete: `rm -f .tmp/triage-dependency-comment-$N.md`
3. After posting, report "Posted dependency analysis comments to N issues" (no auto-correction)

### Step 5: Integrated Execution Flow (no perspective)

Execute only when `--backlog` is specified without a perspective.

**Phase 1: Untriaged bulk processing (same as Bulk Execution)**

Process untriaged issues using the same steps as Bulk Execution's "Step 1: Bulk Retrieval" → "Step 2: Bulk Classification" → "Step 3: Bulk Update". Assign `triaged` label.

**Phase 2: Deep analysis of all 4 perspectives**

After Phase 1 completes, run deep analysis of all 4 perspectives (value → duplicate → stale → dependency in order). After each perspective's analysis, sequentially run the corresponding application flow from Step 4 (AskUserQuestion approval → execute).

**Phase 3: Integrated report output**

```
## /triage --backlog Integrated Execution Report

### Triage Results
- Issues processed: N
- triaged label assigned: M

### Analysis Summary
- value: N issues updated
- duplicate: N clusters detected
- stale: N stagnation candidates
- dependency: N anomalies
```

---

## Notes

- `/triage` is a utility skill operating outside the workflow (`/issue → /spec → /code → /review → /merge → /verify`). It targets all issues in the repository
- Uses the `triaged` label independent of `status/*` labels
- Always use the Write tool to create temporary files
