---
name: audit
description: Detect documentation/implementation drift and auto-generate Issues (`/audit drift`), and detect structural fragility (`/audit fragility`). AI detects semantic drift between Steering Documents + Project Documents and codebase implementation, and auto-generates Issues for code-side fixes. Where `/doc sync` proposes documentation-side fixes, `/audit` is the complementary skill that creates Issues for code-side fixes. Running without arguments executes both drift and fragility perspectives in an integrated run. `/audit stats` aggregates Issue metadata across the project and generates a project health diagnostic report (throughput / composition / First-try success / Backlog Health, etc.), providing a third lens for project health alongside drift and fragility detection.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(gh issue create:*, gh issue list:*, gh issue view:*, gh issue edit:*, gh label create:*, ls:*, mkdir:*, rm:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-type.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-priority.sh:*)
---

# audit: Documentation × Implementation Drift Detection

Parse ARGUMENTS and route to the appropriate subcommand.

If ARGUMENTS contains `--help`, Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and follow the "Processing Steps" section to output help, then stop.

## Command Routing

If ARGUMENTS is `drift` or starts with `drift` (including options like `--dry-run`, `--limit N`): execute the "drift subcommand" section and exit.

If ARGUMENTS is `fragility` or starts with `fragility` (including options like `--dry-run`, `--limit N`): execute the "fragility subcommand" section and exit.

If ARGUMENTS is `stats` or starts with `stats` (including options like `--since DATE`, `--limit N`, `--no-save`): execute the "stats Subcommand" section and exit.

If ARGUMENTS is empty (no arguments), `--dry-run`, or starts with `--limit`: execute the "Integrated Execution (drift + fragility)" section and exit.

For any other ARGUMENTS: display "Usage: /audit [drift|fragility|stats] [--dry-run] [--limit N] [--since DATE] [--no-save] (running `/audit` without arguments executes drift + fragility integrated run)" and exit.

---

## drift Subcommand

Detect semantic drift between Steering Documents + Project Documents and codebase implementation, and generate Issues for code-side fixes.

### Option Parsing

Parse the following options from ARGUMENTS:

- `--dry-run`: display the drift report only without generating Issues
- `--limit N`: limit Issue generation to N items (in descending severity order)

---

### Step 1: Context Collection

Read `${CLAUDE_PLUGIN_ROOT}/modules/codebase-analysis.md` and follow the "Processing Steps" section to execute cross-codebase analysis.

Then collect documents using the following procedure:

**Load Steering Documents:**

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `SPEC_PATH` and `STEERING_DOCS_PATH` for use in subsequent steps.

Search for `$STEERING_DOCS_PATH/product.md`, `$STEERING_DOCS_PATH/tech.md`, `$STEERING_DOCS_PATH/structure.md` with Glob and Read any that exist. If none exist, display "Steering Documents not found. Run `/doc init`." and exit with error.

**Load Project Documents:**

Following the document traversal pattern from `/doc`, dynamically detect `type: project` documents using this procedure:

1. Search the entire repository with Grep for the `type: project` pattern limited to `*.md` files, getting a list of candidate file paths
2. Skip files matching these exclusion patterns:
   - Paths starting with `$SPEC_PATH/`
   - Paths containing `node_modules/`
   - Paths starting with `.git/`
   - Paths starting with `.tmp/`
3. Read each candidate file and collect its contents

**Fetch existing open Issues (for duplicate check):**

```bash
gh issue list --state open --json number,title,body --limit 100
```

The retrieved issue list is used for duplicate checking in Step 3 (after drift detection).

---

### Step 2: Drift Detection

Cross-reference the Steering Documents, Project Documents, and codebase analysis results collected in Step 1 to detect semantic drift.

**Steering Documents categories (examples):**

| Category | Detection method |
|---------|----------------|
| tech.md Architecture Decisions vs actual code | Compare with Read + Grep pattern comparison (inconsistencies between documented architecture and actual code) |
| tech.md Key Dependencies vs actual dependencies | Extract actual deps from `package.json`/`go.mod` etc. with Grep → compare with tech.md table |
| tech.md Coding Conventions vs actual code | Detect naming convention violations / Forbidden Expressions usage with Grep |
| structure.md Directory Layout vs actual directory | Get actual directory listing with `ls` + Glob → diff against structure.md entries |
| structure.md Key Files vs actual files | Detect absent listed files and unlisted important files with Glob |
| product.md Non-Goals vs implementation | AI judgment to detect implemented features that violate Non-Goals |
| product.md Terms vs code terminology | Detect usages of different notation from defined terms with Grep |

**Project Documents categories (examples):**

| Category | Detection method |
|---------|----------------|
| workflow.md skill list vs actual skills | Match Glob results of `skills/*/SKILL.md` against skill names/subcommands listed in workflow.md |
| workflow.md phase descriptions vs SKILL.md implementation | Compare phase role descriptions (routing, options, etc.) with actual behavior in SKILL.md via Read |
| workflow.md path references vs actual files | Extract path references (like `skills/<name>/SKILL.md`) with Grep → verify file existence with Glob |

**Severity scoring (AI judgment):**

Assign severity to each detection result using these guidelines (not strict rule-based, AI judgment):

- **high**: Code doesn't work, security issues, complete contradiction between documentation and implementation
- **medium**: Minor functional impact, documentation description is outdated
- **low**: Notation inconsistency, style mismatch, minor irregularities

---

### Step 3: Duplicate Check

Semantically compare the detected drift against existing open Issues retrieved in Step 1.

Reference titles and bodies; if the content is similar to an existing Issue (pointing out the same drift), judge as duplicate and skip. Duplicate check is AI-judgment-based.

Display duplicates as "duplicate (existing Issue #N)" in the results report.

---

### Step 4: Results Output

Display drift detection results in table format:

```
| No | Category | Severity | Description | Affected Files | Duplicate |
|----|---------|----------|-------------|---------------|-----------|
| 1  | tech.md Coding Conventions | high | ... | skills/foo/SKILL.md | - |
| 2  | workflow.md skill list | medium | ... | docs/workflow.md | - |
| 3  | structure.md Key Files | low | ... | docs/structure.md | existing #123 |
```

**In `--dry-run` mode**: display the table and exit (do not generate Issues).

**In normal mode**:

If `--limit N` is specified, select N items in descending severity order. Exclude duplicates ("existing #N") from the count.

Ask the user with AskUserQuestion (non-interactive mode: auto-resolve — automatically select "Generate all" for non-duplicate items up to `--limit N`; record the decision in an issue comment):

- "Generate all": generate Issues for all non-duplicate drift items
- "Select": enter item numbers to generate separated by commas (e.g., 1,3,5)
- "Cancel": exit without generating Issues

If "Cancel": display "Issue generation cancelled." and exit.

---

### Step 5: Issue Generation

Generate Issues in `/issue` standard format for approved drift items.

Each Issue body:

```markdown
## Background

{Context where the drift was found, quoting the relevant Steering/Project Document section}

## Purpose

{Problem resolved by the fix}

## Acceptance Conditions

### Pre-merge (automated verification)

- [ ] <!-- verify: {verify command} --> {condition 1}
- [ ] {condition 2}

### Post-merge

- [ ] {verification items}
```

**Label assignment:**

After Issue generation, assign the following label:

- `audit/drift`: tracking label indicating the drift was detected by the audit skill

If the `audit/drift` label doesn't exist, create it with `gh label create` (color: `#e4e669`).

Do not assign the `triaged` label when creating Issues. The `triaged` label is assigned by the `/triage` skill after triage is actually executed; pre-assigning it causes the Issue to be skipped by the triage pipeline, leaving Type/Size/Priority/Value unset.

**Type/Size assignment:**

Set Type and Size from AI estimation of drift scope (update project fields via `${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh`).

**After generation:**

Display the list of generated Issue numbers and titles.

Then read `${CLAUDE_PLUGIN_ROOT}/modules/steering-hint.md` and follow the "Processing Steps" section.

---

## stats Subcommand

Aggregate Issue metadata across the project and generate a project health diagnostic report. This is a read-only tool — it generates new `docs/stats/YYYY-MM-DD.md` files only, and does not edit existing files or create Issues.

### Option Parsing

Parse the following options from ARGUMENTS:

- `--since DATE`: aggregation start date (default: 90 days before today; format: `YYYY-MM-DD`)
- `--limit N`: maximum number of Issues to fetch (default: 500)
- `--no-save`: skip saving to `docs/stats/`; output to stdout only

---

### Step 1: Data Collection

**Fetch Issue list:**

```bash
gh issue list --state all --json number,title,body,labels,createdAt,closedAt,state --limit {N}
```

Filter to Issues created on or after `--since DATE`. If `--since` is not specified, use 90 days before today as the default.

**Fetch timeline items for each Issue (for reopen and phase label transition analysis):**

For each Issue in the filtered list:

```bash
gh issue view {number} --json timelineItems
```

Extract the following from `timelineItems`:

- **Reopen events**: `ReopenedEvent` entries → mark the Issue as having reopen history
- **Phase label transition history**: `LabeledEvent` and `UnlabeledEvent` entries for `phase/*` labels → record the sequence of phase transitions in chronological order

**Spec file existence check (for retrospective presence):**

Use Glob to check whether `$SPEC_PATH/issue-{number}-*.md` exists for each Issue. Record existence as a boolean (do not read Spec content).

---

### Step 2: Computation

#### Success/Failure Definitions (3 levels, displayed simultaneously)

- **First-try success** (strictest): Issue reached `phase/done` AND has no reopen history
- **Completed**: Issue reached `phase/done` (reopen history does not affect this)
- **Rework**: number of times the phase sequence went from `phase/verify` back to `phase/code`

#### Composition (Type / Size / Priority)

For each Issue in the filtered list, resolve Type, Size, and Priority from GitHub Projects fields (with label fallback) by calling the helper scripts:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-type.sh {number}      # -> Bug / Feature / Task (empty if unset)
${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh {number}      # -> XS / S / M / L / XL (exit 1 if unset)
${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-priority.sh {number}  # -> urgent / high / medium / low (exit 1 if unset)
```

Classify as "unset" when the script exits with a non-zero status or outputs an empty string. The `gh-graphql.sh --cache` flag used internally in each script deduplicates GraphQL requests for the same Issue.

#### Content Segment Classification (MVP: keyword-based)

Classify each Issue by checking whether its title or body contains any of the following keywords (case-sensitive partial match). Assign the first matching segment in order; if none match, assign "other".

| Segment | Keywords |
|---------|---------|
| ui/design | `UI`, `デザイン`, `画面`, `レイアウト`, `Figma`, `design` |
| backend | `API`, `サーバー`, `サーバ`, `DB`, `データベース`, `backend` |
| infra | `CI`, `CD`, `Docker`, `環境`, `deploy`, `インフラ`, `runner` |
| docs | `ドキュメント`, `doc`, `README`, `CLAUDE.md`, `文書` |
| test | `テスト`, `test`, `bats`, `spec` |
| other | (none of the above) |

This section is structured as an independent subsection to allow future replacement with LLM-based classification.

#### Work Origin Classification

Classify each Issue based on its labels:

- `audit/drift` label present → audit (drift)
- `audit/fragility` label present → audit (fragility)
- `retro/verify` label present → retrospective
- None of the above → manual

Note: `retro/verify` label may not yet exist in the repository. When the label is absent or no Issue has it, the "retrospective" category will show 0 — this is expected behavior. Once the companion Issue adding `retro/verify` label assignment to `/verify` Step 13 is merged, retrospective-derived Issues will be separated automatically.

#### Trend Analysis (30-day window × 3)

Split the past 90 days into three 30-day windows (window 1: oldest, window 3: most recent). For each window, compute:

- Created: number of Issues created in the window
- Closed: number of Issues closed in the window
- Net: Closed − Created
- Open end: total Open Issues at the end of the window

#### Backlog Health Thresholds

- **Stale candidates**: Open Issues with no update for 90 or more days (same set as age ≥ 90d Open)
- **Untriaged candidates**: Open Issues without the `triaged` label

#### Highlights Auto-Detection Logic

Collect items meeting any of the following criteria to display in the Highlights section:

- Failure rate for a specific Size, Type, or Content segment is 2x or more above the overall average
- Trend direction (Net) is the same direction for 2 or more consecutive 30-day windows (↑↑ or ↓↓)
- Backlog net change in the most recent window has worsened by 20% or more

Highlights contain only auto-detected items. Do not include interpretation or inference in the report.

---

### Step 3: Report Generation

Generate a Markdown report containing all 6 sections below. Output to stdout.

#### Section 1: Highlights

List items that meet the auto-detection criteria from Step 2. If no items meet the criteria, output "No highlights detected."

Do not interpret or infer. Only enumerate items that meet the detection thresholds.

#### Section 2: Flow

Display Created / Closed / Net / Open end for each of the three 30-day windows in table format.

```
| Window | Period | Created | Closed | Net | Open end |
|--------|--------|---------|--------|-----|----------|
| W1 (oldest) | YYYY-MM-DD – YYYY-MM-DD | N | N | N | N |
| W2 | ... | N | N | N | N |
| W3 (recent) | ... | N | N | N | N |
```

#### Section 3: Composition

Display counts by Type, Size, and Priority. Also show the ratio change for the most recent 30-day window vs. the prior two windows combined.

#### Section 4: Work Origin

Display distribution of audit (drift) / audit (fragility) / retrospective / manual. Include percentage of total.

If the `retro/verify` label does not exist, display "retrospective" as 0 with a note: "(retro/verify label not yet assigned — will be separated once companion Issue is merged)".

#### Section 5: Outcome

Display the following:

- **By Size**: First-try success rate, Completed rate, and average Rework count for each Size
- **Phase regression points**: which `phase/verify → phase/code` regressions occurred most frequently
- **By Content segment**: First-try success rate and reopen rate vs. overall average for each segment
- **Trend**: First-try success rate per 30-day window × 3

#### Section 6: Backlog Health

Display the following:

- Total Open Issue count
- Age distribution: 0–7d / 7–30d / 30–90d / 90d+
- Stale candidate count (≥ 90d, same as 90d+ Open)
- Untriaged candidate count (Open without `triaged` label)

---

### Step 4: Save

If `--no-save` is specified: output to stdout only and exit.

If `--no-save` is not specified:

1. Determine today's date in `YYYY-MM-DD` format
2. Create directory if it does not exist:
   ```bash
   mkdir -p docs/stats
   ```
3. Write report content to `docs/stats/YYYY-MM-DD.md` (overwrite if the file already exists for the same date)
4. Display: "Report saved to docs/stats/YYYY-MM-DD.md"

Then read `${CLAUDE_PLUGIN_ROOT}/modules/steering-hint.md` and follow the "Processing Steps" section.

---

## fragility Subcommand

Detect structural fragility based on project context (Steering Documents) and generate risk improvement Issues.

### Option Parsing

Parse the following options from ARGUMENTS (same system as drift):

- `--dry-run`: display the fragility report only without generating Issues
- `--limit N`: limit Issue generation to N items (in descending severity order)

---

### Step 1: Context Collection

Execute the same procedure as drift's Step 1 (run `${CLAUDE_PLUGIN_ROOT}/modules/codebase-analysis.md` + load Steering Documents / Project Documents + fetch existing open Issues).

---

### Step 2: Fragility Detection

Based on context collected in Step 1, detect structural fragility in the following 5 categories.

**Detection categories (exhaustive):**

| Category | Detection method |
|---------|----------------|
| Missing tests for core modules | For modules positioned as core in product.md / structure.md, check for test files in `tests/` with Glob. Detect modules without tests (test coverage gap detection) |
| Architecture Decisions violations | Read the Architecture Decisions section of tech.md and detect code patterns contradicting the documented design decisions with Grep + Read |
| Missing error handling for critical external deps | Identify call sites for dependencies deemed critical in tech.md Key Dependencies with Grep, and verify presence/absence of try/catch etc. error handling |
| Single point of failure | Identify files that many modules depend on from structure.md dependency relations, and verify presence/absence of corresponding tests/documentation |
| Scattered configuration | Detect cases where environment variables/config values are scattered across multiple files without an SSoT (Single Source of Truth) with Grep, and cross-reference with tech.md descriptions |

**Severity scoring (AI judgment):**

Use the same guidelines as drift:

- **high**: high risk that critical features break, fragility with wide impact
- **medium**: risk under specific conditions, partial impact
- **low**: minor risk, seeds of future problems

**Boundary with drift:**

- **drift**: "documentation says X, but code is Y" (factual inconsistency)
- **fragility**: "given this project's structure, this is likely to break" (risk indication)

If the same location applies to both, prioritize drift and skip the fragility side.

---

### Step 3: Duplicate Check

Follow the same procedure as drift's Step 3 to check for duplicates with existing open Issues. Display duplicates as "duplicate (existing Issue #N)" in the results report.

---

### Step 4: Results Output

Display fragility detection results in table format:

```
| No | Category | Severity | Description | Affected Files | Duplicate |
|----|---------|----------|-------------|---------------|-----------|
| 1  | Missing tests for core modules | high | ... | modules/foo.md | - |
| 2  | Architecture Decisions violations | medium | ... | skills/bar/SKILL.md | - |
| 3  | Scattered configuration | low | ... | scripts/setup.sh | existing #456 |
```

**In `--dry-run` mode**: display the table and exit (do not generate Issues).

**In normal mode**:

If `--limit N` is specified, select N items in descending severity order. Exclude duplicates from the count.

Ask the user with AskUserQuestion (non-interactive mode: auto-resolve — automatically select "Generate all" for non-duplicate items up to `--limit N`; record the decision in an issue comment):

- "Generate all": generate Issues for all non-duplicate fragility items
- "Select": enter item numbers to generate separated by commas (e.g., 1,3)
- "Cancel": exit without generating Issues

If "Cancel": display "Issue generation cancelled." and exit.

---

### Step 5: Issue Generation

Generate Issues in `/issue` standard format for approved fragility items.

Each Issue body:

```markdown
## Background

{Context where the fragility was found, quoting the relevant Steering/Project Document section}

## Purpose

{Risk reduced by the improvement}

## Acceptance Conditions

### Pre-merge (automated verification)

- [ ] <!-- verify: {verify command} --> {condition 1}
- [ ] {condition 2}

### Post-merge

- [ ] {verification items}
```

**Label assignment:**

After Issue generation, assign the following label:

- `audit/fragility`: tracking label indicating the fragility was detected by the audit skill

If the `audit/fragility` label doesn't exist, create it with `gh label create` (color: `#f9d0c4`).

Do not assign the `triaged` label when creating Issues. The `triaged` label is assigned by the `/triage` skill after triage is actually executed; pre-assigning it causes the Issue to be skipped by the triage pipeline, leaving Type/Size/Priority/Value unset.

**Type/Size assignment:**

Set Type and Size from AI estimation of fragility scope (update project fields via `${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh`).

**After generation:**

Display the list of generated Issue numbers and titles.

Then read `${CLAUDE_PLUGIN_ROOT}/modules/steering-hint.md` and follow the "Processing Steps" section.

---

## Integrated Execution (drift + fragility)

`/audit` (no arguments) sequentially executes both drift and fragility perspectives and displays detection results in an integrated table.

### Option Parsing

Parse the following options from ARGUMENTS (same system as drift/fragility):

- `--dry-run`: display the integrated report only without generating Issues
- `--limit N`: limit total Issue generation to N items (in descending severity order)

---

### Step 1: Drift Detection

Execute Steps 1–3 from the "drift subcommand" (context collection, drift detection, duplicate check). Don't proceed to Issue generation at this step — `--dry-run`/`--limit` are applied at final output; collect detection results only.

---

### Step 2: Fragility Detection

Execute Steps 1–3 from the "fragility subcommand" (context collection, fragility detection, duplicate check). Reuse the same Steering/Project Documents context from drift if available (skip re-fetching).

If fragility detection results overlap with drift detections (pointing out the same location), prioritize drift and skip the fragility side.

---

### Step 3: Integrated Results Output

Display drift and fragility detection results in an integrated table with a `lens` column:

```
| No | lens | Category | Severity | Description | Affected Files | Duplicate |
|----|------|---------|----------|-------------|---------------|-----------|
| 1  | drift | tech.md Coding Conventions | high | ... | skills/foo/SKILL.md | - |
| 2  | fragility | Missing tests for core modules | medium | ... | modules/bar.md | - |
| 3  | drift | workflow.md skill list | low | ... | docs/workflow.md | existing #789 |
```

**In `--dry-run` mode**: display the integrated table and exit (do not generate Issues).

**In normal mode**:

If `--limit N` is specified, select N items in descending severity order. Exclude duplicates from the count.

Ask the user with AskUserQuestion (non-interactive mode: auto-resolve — automatically select "Generate all" for non-duplicate items up to `--limit N`; record the decision in an issue comment):

- "Generate all": generate Issues for all non-duplicate items
- "Select": enter item numbers to generate separated by commas
- "Cancel": exit without generating Issues

---

### Step 4: Issue Generation

Generate Issues using the appropriate label based on each item's `lens`:

- Items with `lens: drift` → assign `audit/drift` label (same procedure as drift subcommand Step 5)
- Items with `lens: fragility` → assign `audit/fragility` label (same procedure as fragility subcommand Step 5)

Display the list of generated Issue numbers and titles grouped by `lens`.

Then read `${CLAUDE_PLUGIN_ROOT}/modules/steering-hint.md` and follow the "Processing Steps" section.
