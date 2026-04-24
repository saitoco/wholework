---
name: doc
description: Project foundation document management (`/doc init`). Centrally manages Steering Documents and Project Documents, ensuring consistency through drift detection and normalization (`/doc sync` for bidirectional normalization, `/doc add`/`/doc project` for adding documents, `/doc translate {lang}` for generating multi-language translations).
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(ls:*, wc:*, mkdir:*), Bash(git add:*, git commit:*, git push:*, git status:*, git diff:*)
---

# doc: Project Foundation Information Management

Parse ARGUMENTS and route to the appropriate command.

If ARGUMENTS contains `--help`, Read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and follow the "Processing Steps" section to output help, then stop.

- Empty (no arguments) → status display
- `init` → init wizard
- `product` / `tech` / `structure` → individual create/update
- `sync` → bidirectional normalization (reverse-generate if Steering Documents don't exist; normalize content and detect drift if they do)
- `sync --deep` → extended reverse-generation combining codebase analysis + existing .md file integrated scan (4-pattern classification + absorption target determination)
- `sync {doc}` → individual reverse-generation (doc = product / tech / structure)
- `init --deep` → auto-generate draft by running codebase analysis + .md integration inline, skipping the question flow
- `product --deep` / `tech --deep` / `structure --deep` → auto-generate draft with inline execution equivalent to `--deep` (codebase analysis + .md integration)
- `add {path}` → register an existing document as a project document
- `project` → interactive creation of a new project document
- `translate {lang}` → generate multi-language translations for English documentation (commit and push included)

---

## Configuration Detection

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `SPEC_PATH` and `STEERING_DOCS_PATH` for use in subsequent steps.

---

## Command Routing

If ARGUMENTS is empty: execute status display (see "Status Display" section below) and exit.

If ARGUMENTS is `init`: execute the "init wizard" section and exit.

If ARGUMENTS is `init --deep`: enable `--deep` flag and execute the "init wizard" section and exit.

If ARGUMENTS is `product`, `tech`, or `structure`:
- `/doc product` → create/update `$STEERING_DOCS_PATH/product.md`
- `/doc tech` → create/update `$STEERING_DOCS_PATH/tech.md`
- `/doc structure` → create/update `$STEERING_DOCS_PATH/structure.md`

Execute the "Individual Create/Update" section and exit.

If ARGUMENTS is `product --deep`, `tech --deep`, or `structure --deep`: enable `--deep` flag and execute the "Individual Create/Update" section and exit. When `--deep` flag is enabled, skip the question flow for new file creation and auto-generate a draft by running codebase analysis + existing .md file integration scan inline.

If ARGUMENTS is `sync`: execute the "sync Bidirectional Normalization" section and exit.

If ARGUMENTS is `sync --deep`: enable `--deep` flag and execute the "sync Bidirectional Normalization" section and exit. In the reverse-generation flow (Steps 2–5), `--deep` mode adds codebase analysis and existing .md file integrated scan (4-pattern classification + absorption target determination).

If ARGUMENTS is `sync product`, `sync tech`, or `sync structure`: execute the "sync Individual Reverse-Generation" section and exit.

If ARGUMENTS starts with `add` (format: `add {path}`): execute the "add — Register Existing Document" section and exit. If `{path}` is not specified, display "Usage: /doc add {path}" and exit.

If ARGUMENTS is `project`: execute the "project — Create New Project Document" section and exit.

If ARGUMENTS starts with `translate` (format: `translate {lang}`): extract `{lang}` from ARGUMENTS. If `{lang}` is empty (ARGUMENTS is exactly `translate`), display "Usage: /doc translate {lang}" and exit. Otherwise, execute the "translate — Translation Generation" section and exit.

For any other ARGUMENTS: display "Usage: /doc [init|init --deep|product|tech|structure|product --deep|tech --deep|structure --deep|sync|sync --deep|sync {doc}|add {path}|project|translate {lang}]" and exit.

---

## Template Definitions

Each steering document's template is defined in the following individual files.
Read them when templates are needed within the workflow.
The `type` and `ssot_for` values here are the SSoT for frontmatter (`type: steering` + `ssot_for` block) prepended when writing to `$STEERING_DOCS_PATH/{doc}.md`.

| Document | Template file | type | ssot_for |
|----------|--------------|------|----------|
| product.md | `skills/doc/product-template.md` | steering | vision, non-goals, terminology |
| tech.md | `skills/doc/tech-template.md` | steering | tech-stack, coding-conventions, forbidden-expressions |
| structure.md | `skills/doc/structure-template.md` | steering | directory-layout, agent-includes-catalog |

---

## Document Traversal (common procedure)

Common frontmatter-based document traversal procedure used in status display and sync flows. Instead of fixed traversal via `docs/*.md` Glob, search the entire repository for `.md` files with a `type` field.

1. Search the entire repository with Grep for the `type: project\|type: steering` pattern limited to `*.md` files, getting a list of candidate file paths
2. Skip files matching these exclusion patterns:
   - Paths starting with `$SPEC_PATH/` (specification documents)
   - Paths containing `node_modules/` (external dependencies)
   - Paths starting with `.git/` (Git management files)
   - Paths starting with `.tmp/` (temporary files)
3. Read the beginning of each candidate file and parse the frontmatter to check the `type` field value
4. Collect only files with `type: steering` or `type: project` as traversal targets

---

## Status Display

Search the entire repository for files with a `type` field in frontmatter and display their existence status in table format.

### Step 1: File Existence Check

Follow the "Document Traversal (common procedure)" section to collect target files from the entire repository using frontmatter-based traversal. Get the last modified date of each collected file with `ls -l`.

### Step 2: Table Display

Display in the following format:

```
| Document | type | Status | Last Updated |
|----------|------|--------|-------------|
| product.md | steering | ✓ exists | 2024-01-15 |
| tech.md | steering | ✓ exists | 2024-01-14 |
| workflow.md | project | ✓ exists | 2024-01-13 |
```

The `type` column shows the value of the frontmatter `type` field (`steering` or `project`).

### Step 3: Suggest Next Actions

If any documents with `type: steering` are missing from the ones that the individual create/update command supports (product / tech / structure), display:

```
Some documents are not yet created.
- `/doc product` to create product.md
- `/doc tech` to create tech.md
- `/doc structure` to create structure.md
- `/doc init` to start the sequential creation wizard
```

---

## Individual Create/Update

Create or update the `{doc}` (product / tech / structure) document specified in ARGUMENTS.

### Step 1: File Existence Check

Check for the existence of `$STEERING_DOCS_PATH/{doc}.md` with Glob.

If it exists, proceed to "update flow". If not, proceed to "new creation flow".

### Step 2: New Creation Flow

If `--deep` flag is enabled, skip the AskUserQuestion flow. If analysis results are already available (e.g., called from `init --deep`), use them; otherwise run the `--deep` mode processing from "sync Bidirectional Normalization" Step 2 (codebase analysis + existing .md file integrated scan) inline. Reference entry points, dependency relations, and existing .md content to embed appropriate content in each section for auto-generated draft. Skip Step 3 (Optional section confirmation) and leave Optional section headings and descriptions wrapped in HTML comments (`<!-- ... -->`), so subsequent sync commands can stably recognize section structure.

If `--deep` flag is disabled, collect Required section information step by step with AskUserQuestion (non-interactive mode: auto-resolve — infer content from codebase analysis; proceed as if `--deep` flag were enabled).

**For product.md:**

```
Question 1: What is the Vision (project purpose/goals)?
Question 2: Who are the Target Users?
Question 3: What are the Non-Goals (out of scope)?
Question 4: Are there any Terms (project-specific term definitions)? Enter "none" if not.
```

**For tech.md:**

```
Question 1: What is the Language and Runtime (languages/runtime used)?
Question 2: What are the Key Dependencies (major dependency packages)?
Question 3: What are the Architecture Decisions (important technical decisions)?
```

**For structure.md:**

```
Question 1: What is the Directory Layout (directory structure and each directory's role)?
Question 2: What are the Key Files (description of important files)?
```

### Step 3: Optional Section Confirmation

Ask with AskUserQuestion whether to add Optional sections (non-interactive mode: skip — wrap Optional section headings and descriptions in HTML comments; this is a High-Stakes Decision since optional section preference is user-specific).

If adding, collect the content and include it. If skipping, wrap the Optional section headings and descriptions from the template in HTML comments (`<!-- ... -->`). This allows subsequent sync commands and other skills to identify the section structure.

Example (skipped format):

```markdown
<!-- ## Success Metrics (Optional)

Describe success metrics. -->
```

### Step 4: Document Generation

Read `skills/doc/{doc}-template.md` to check the template structure.
If the file is not found, display the following error and abort:

```
Error: template file `skills/doc/{doc}-template.md` not found.
wholework is not correctly installed. Reinstall the wholework plugin via `/plugin install wholework@saitoco-wholework`.
```

Look up the `type` and `ssot_for` values for `{doc}` from the Template Definitions table and prepend the following frontmatter block before writing with Write:

```yaml
---
type: {type}
ssot_for:
  - {ssot_for_item_1}
  - {ssot_for_item_2}
  ...
---
```

Fill in the template with collected information and save to `$STEERING_DOCS_PATH/{doc}.md` with Write.

Check whether the `$STEERING_DOCS_PATH/` directory exists with Glob for `$STEERING_DOCS_PATH/` (do not use Bash ls as it errors when the directory doesn't exist). If it doesn't exist, display the following error and abort:

```
Error: $STEERING_DOCS_PATH/ directory not found.
Manually run `mkdir -p $STEERING_DOCS_PATH` then re-run the command.
```

### Step 5: Confirm Generation Result

Display the generated document content and confirm with AskUserQuestion (approve / revision request / redo).

### Step 6: Apply Revisions

If Step 5 requires revision, apply it with Edit. Skip this step if no revision is needed.

### Step 7: Load Existing File (update flow)

Read the existing file with Read.

### Step 8: Confirm Update Content

Ask with AskUserQuestion what to update:
```
Which section do you want to update? Please describe the update content.
```

### Step 9: Apply Update

Apply the update content specified in Step 8 with Edit.

### Step 10: Commit and Push Guide

Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-commit-push.md` and follow the "Processing Steps" section with `SUMMARY="update {doc}"`. This step is reached from both the new creation flow (after Step 6) and the update flow (after Step 9).

---

## init Wizard

Sequentially create the three steering documents in recommended order (product → tech → structure).

If `--deep` flag is enabled, before proceeding to Step 3's creation target selection, run the `--deep` mode processing from "sync Bidirectional Normalization" Step 2 (codebase analysis + existing .md file integrated scan) inline, and use the analysis/scan results for each document generation. Normal `init` (without --deep) maintains the existing question flow.

### Step 1: Check Current State

Follow the "Document Traversal (common procedure)" section to collect target files from the entire repository using frontmatter-based traversal. Identify which steering documents (`type: steering`) exist and which are missing.

### Step 2: Display Uncreated Files

List uncreated files. If all exist, display "All steering documents are already created." and exit.

### Step 3: Select Creation Target

Propose the first uncreated file in recommended order and ask with AskUserQuestion:

```
Select the next document to create.
- Create this file (recommended: {doc})
- Choose a different file
- Exit
```

If "Exit" is selected, exit.

If "Choose a different file" is selected, ask with AskUserQuestion to select from the list of uncreated files.

### Step 4: Run Individual Creation Flow

Execute the "Individual Create/Update" section (new creation flow) for the selected file. If `--deep` flag is enabled, use the codebase analysis + .md integration scan results already run in Step 1 to skip the question flow and auto-generate a draft. The user only needs to review and revise the generated draft.

### Step 5: Proceed to Next File

After creation, check remaining uncreated files.

If uncreated files remain, return to Step 3.

When all are created, display "All steering documents have been created." and proceed to Step 6.

### Step 6: Commit and Push Guide

Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-commit-push.md` and follow the "Processing Steps" section with `SUMMARY="init steering documents"`.

---

## sync Bidirectional Normalization

Branch behavior based on whether Steering Documents exist.

### Step 1: Steering Documents Existence Check

Follow the "Document Traversal (common procedure)" section to collect target files from the entire repository using frontmatter-based traversal. Determine whether 1 or more files with `type: steering` or `type: project` exist.

- If 1 or more exist: proceed to "normalization flow" (Step 6 onwards)
- If none exist: proceed to "reverse-generation flow" (Steps 2–5)

### Step 2: Reverse-Generation Flow — Explore Analysis Sources

Search for the following files in the project root with Glob (deduplicate files matching multiple patterns, read each only once):

- `*.md` (all Markdown in root. Captures README.md, CONTRIBUTING.md, ARCHITECTURE.md etc.)
- `README.*` (README files regardless of extension. Supplements non-Markdown formats like .rst, .txt)
- `package.json`, `Gemfile`, `requirements.txt`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `tsconfig.json`, `Makefile`
- `CLAUDE.md`
- `.github/*.md`, `.github/**/*.md` (PR/Issue templates etc.)
- `.github/workflows/*.yml` (CI/CD configuration)
- `docs/**/*.md` (all Markdown including subdirectories. But skip files with a `type` field in frontmatter. After retrieving with Glob, check for `type` field by reading the beginning of each file. If many matches, prioritize files directly under `docs/` and limit to 15)
- `Dockerfile`, `docker-compose.yml`, `.env.example` (infrastructure configuration)
- `justfile`, `Taskfile.yml`, `Brewfile` (task runner type)

Read existing files with Read and retain as analysis targets.

If no analysis source files are found, display "No analysis sources found. Run in a project with README.md, package.json, etc." and exit.

If `--deep` flag is enabled, Read `${CLAUDE_PLUGIN_ROOT}/modules/codebase-analysis.md` and follow the "Processing Steps" section to run codebase analysis and integrate the extracted information into analysis target information. Reflect results in each document following this policy:

- Entry point list + estimated architecture → tech.md Architecture Decisions and structure.md Directory Layout
- Directory role table → structure.md Directory Layout
- Dependency graph → tech.md Key Dependencies and Architecture Decisions
- Test specifications → product.md Target Users/Non-Goals and tech.md Architecture Decisions
- Docstring information → supplementary information in relevant sections of each document

If `--deep` flag is enabled, in addition to codebase analysis, run **existing .md file integrated scan**:

**Scan scope (entire repository excluding protected targets):**

Use Glob `**/*.md` with `path: "."` and skip files matching these exclusion conditions:

- **Protected files**: CLAUDE.md, README.md (skip; not targets for content absorption/movement/deletion)
- **Existing managed targets**: files with `type: steering` or `type: project` in frontmatter (read beginning to check `type` field; skip if present)
- **Spec documents**: files under `$SPEC_PATH/`
- **Package management directories**: files under `node_modules/`, `.git/`, `vendor/`
- **Temporary file directories**: files under `.tmp/`
- **wholework-managed directories**: files under `skills/`, `modules/`, `agents/` (if applicable)
- **Translation output**: README.{lang}.md at project root (language-code-named files matching `README.*.md` pattern), files under `docs/{lang}/` (language-code-named directories under `docs/`) (generated by `/doc translate {lang}`)

If scan count exceeds 30, prioritize files with shallower directory depth, limiting to 30. Read the remaining candidate files and semantically analyze content to classify into the following 4 patterns.

**Absorption target determination table (Pattern 1: absorb into steering documents):**

If file content meets these criteria, absorb it into the relevant steering document section and delete the source file:

| Source content | Absorption target section |
|---------------|--------------------------|
| Deploy procedures, CI/CD configuration | tech.md Build and Deploy (Optional) |
| Development conventions, commit conventions | tech.md Coding Conventions |
| Test policy, frameworks | tech.md Testing Strategy (Optional) |
| File/directory descriptions | structure.md Key Files / Directory Layout |
| Product vision, target users | product.md Vision / Target Users |

**Pattern 2: organize as project documents in docs:**

Information not fitting in steering documents but continuously referenced for project operations. Add `type: project` + `ssot_for` frontmatter and place in `docs/`. Examples: workflow definitions, operation runbooks, external service integration guides, ADRs.

**Pattern 3: save under docs (not as project documents):**

Information worth keeping as records but not for continuous reference. Move to `docs/` without frontmatter. Examples: upgrade history, migration notes, past release notes.

**Pattern 4: delete:**

Information already replaced by other files (CLAUDE.md, README.md, steering documents etc.) with no need to retain. Examples: AI agent integration guides (replaced by CLAUDE.md), duplicate setup procedures (replaced by README.md).

Pass classification results (file list per pattern and absorption target section information) to subsequent processing. In the reverse-generation flow (Steps 2–5), integrate Pattern 1 content as input to draft generation. In the normalization flow (Steps 6–9), add Pattern 2–4 integration proposals to Step 7 normalization proposals.

Read all template files listed in the "Template Definitions" section table. If even one is not found, display the following error and abort:

```
Error: template file not found.
wholework is not correctly installed. Reinstall the wholework plugin via `/plugin install wholework@saitoco-wholework`.
```

Extract information corresponding to the Required sections of each steering document template from analysis sources and generate draft document content (Markdown strings). If `--deep` flag is enabled and Pattern 1 (absorb into steering) files were detected in .md integrated scan, integrate relevant file content into the corresponding draft sections per the absorption target determination table (skip user question flow, auto-generate draft from analysis/scan results).

Extraction policy for each document:

- **product.md**: README (any extension) project description/purpose → Vision; user layer descriptions → Target Users; CLAUDE.md constraints → Non-Goals; project-specific terminology-like descriptions → Terms
- **tech.md**: package.json/Gemfile/requirements.txt/go.mod etc. → Language and Runtime + Key Dependencies; README (any extension)/CLAUDE.md technical descriptions → Architecture Decisions; CLAUDE.md prohibitions → Forbidden Expressions; Dockerfile → Language and Runtime (base image/OS info); `.github/workflows/*.yml` → Key Dependencies (CI/CD tools/deploy targets); `justfile`/`Taskfile.yml`/`Brewfile` → Key Dependencies (task runners/dev tools)
- **structure.md**: project root `ls` results + README (any extension) directory descriptions → Directory Layout; README (any extension)/CLAUDE.md file descriptions → Key Files; `.github/*.md`/`.github/**/*.md` → Key Files (PR/Issue template paths); `docs/**/*.md` → Key Files (project-specific document paths)

### Step 3: Display Draft

Check for the `$STEERING_DOCS_PATH/` directory with Glob. If it doesn't exist, display the following error and abort:

```
Error: $STEERING_DOCS_PATH/ directory not found.
Manually run `mkdir -p $STEERING_DOCS_PATH` then re-run the command.
```

Process one file at a time in recommended order (product → tech → structure).

For each file:

1. Display the generated draft content and explicitly state "This is a draft auto-generated from analysis sources. Please review the content and select a save method."

### Step 4: Select Save Method

Ask the user with AskUserQuestion to select a save method for each file.

If `$STEERING_DOCS_PATH/{doc}.md` does not exist:
- "Save"
- "Revise and save"
- "Skip"

If `$STEERING_DOCS_PATH/{doc}.md` already exists:
- "Overwrite"
- "Check diff"
- "Skip"

### Step 5: Execute Save

Save with Write based on the Step 4 selection result. When creating a new file (`$STEERING_DOCS_PATH/{doc}.md` does not exist), look up the `type` and `ssot_for` values for `{doc}` from the Template Definitions table and prepend the frontmatter block before the generated content:

```yaml
---
type: {type}
ssot_for:
  - {ssot_for_item_1}
  - {ssot_for_item_2}
  ...
---
```

After processing all files, display the list of saved files.

Regardless of the number of files saved, display the following message to complete:

```
sync (reverse-generation) complete.
To normalize Steering Documents and project files, run `/doc sync` again.
```

Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-commit-push.md` and follow the "Processing Steps" section with `SUMMARY="sync (reverse-generation)"`.

### Step 6: Content Classification

**Load analysis sources and Steering Documents:**

Search for the following files in the project root with Glob (deduplicate files matching multiple patterns, read each only once):

- `*.md` (all Markdown in root. Captures README.md, CONTRIBUTING.md, ARCHITECTURE.md etc.)
- `README.*` (README files regardless of extension. Supplements non-Markdown formats like .rst, .txt)
- `package.json`, `Gemfile`, `requirements.txt`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `tsconfig.json`, `Makefile`
- `CLAUDE.md`
- `.github/*.md`, `.github/**/*.md` (PR/Issue templates etc.)
- `.github/workflows/*.yml` (CI/CD configuration)
- `docs/**/*.md` (all Markdown including subdirectories. But skip files with a `type` field in frontmatter. After retrieving with Glob, check for `type` field by reading the beginning of each file. If many matches, prioritize files directly under `docs/` and limit to 15)
- `Dockerfile`, `docker-compose.yml`, `.env.example` (infrastructure configuration)
- `justfile`, `Taskfile.yml`, `Brewfile` (task runner type)

Read existing files with Read and retain as analysis targets.

If no analysis source files are found, display "No analysis sources found. Run in a project with README.md, package.json, etc." and exit.

If the `--deep` flag is enabled, also Read `${CLAUDE_PLUGIN_ROOT}/modules/codebase-analysis.md` and follow the "Processing Steps" section to run codebase analysis; retain the extracted results (entry points, dependency graph, directory roles, etc.) for use in subsequent steps including the Narrative Semantic Drift Check.

**Collect normalization targets via frontmatter-based traversal:**

Follow the "Document Traversal (common procedure)" section to collect normalization target files from the entire repository using frontmatter-based traversal. Skip files without frontmatter (no warning, for backward compatibility).

If no normalization target files are found, display "Steering Documents not found. Create them with `/doc init`." and exit.

Read each collected file with Read.

**Dynamically build SSoT mapping:**

Read the `ssot_for` list from each file's frontmatter and dynamically build SSoT mapping. Example:
- `docs/product.md` (ssot_for: [vision, non-goals]) → SSoT for vision and non-goals is product.md
- `docs/workflow.md` (ssot_for: [workflow-phases, label-transitions]) → SSoT for workflow-phases and label-transitions is workflow.md

**Check for duplicate content between documents:**

Group all collected documents (`type: steering` and `type: project`) by same directory. If 2 or more documents exist in the same directory, run the following similarity check for each pair:

1. Extract section headings (lines starting with `## ` or `### `) from each document with Grep
2. Compare heading text similarity (treat as "similar" if exact match or either heading is a substring of the other)
3. If 1 or more similar headings are found, compare content lines (excluding blank lines, heading lines, HTML comment lines) of the relevant sections and calculate duplication rate as: common lines ÷ smaller section's line count (duplicate detection scoring)
4. If duplication rate is 50% or above and common lines are 5 or more, include in Step 7 proposals. Proposed actions differ based on pair type:
   - **project ↔ project**: include as "duplicate integration proposal"
   - **steering ↔ project**: include only as "drift report" (may be intentional duplication; don't auto-fix, ask for user judgment)
   - **steering ↔ steering**: include only as "drift report" (same)

**Scope limits and false positive avoidance:**
- Limit comparison to document pairs within the same directory (avoid N×N comparison across entire repository)
- Exclude short lines (20 characters or less) like tool names, command names, URLs from common line count (tool/command name occurrences are often normal)
- Only detect structural similarity at section level
- Existing SSoT category-based drift detection (between steering/project ↔ source files) is a separate mechanism unaffected by this change

If `scripts/validate-skill-syntax.py` exists or `skills/` directory exists, Read `${CLAUDE_PLUGIN_ROOT}/skills/doc/skill-dev-sync.md` and follow the "Processing Steps" section.

**Narrative Semantic Drift Check (--deep only):**

This sub-step runs only when the `--deep` flag is enabled. It detects drift in narrative sections of Steering Documents using AI judgment, without requiring `ssot_for` category declarations.

**Identify narrative sections:**

For each Steering Document loaded above, use AI judgment to identify sections that are primarily prose or bullet-point narrative (as opposed to purely structured tables or code blocks). Examples of narrative sections: Architecture Decisions, Non-Goals, Coding Conventions, Vision. This classification is intentionally AI-driven rather than based on a fixed list, to accommodate the variety of section names across user projects.

**Input sources for comparison:**

- The narrative section text from each Steering Document
- Codebase analysis results retained in this step (entry points, dependency graph, directory roles, etc.)
- Implementation files loaded in "Scan implementation code" above (`skills/*/SKILL.md`, `modules/*.md`, `agents/*.md`, `scripts/*.sh`) — available only when skill-dev project condition is met

**Detect drift in 4 categories (missing coverage, partial description, obsolete mention, skill coverage gap):**

| Category | Definition | Example |
|---|---|---|
| Missing coverage | An important pattern present in the implementation has no mention at all in the Steering Document | A newly introduced agent is not mentioned in Architecture Decisions |
| Partial description | An existing description mentions only specific cases, leaving other instances of the same pattern undocumented | "Sub-agent splitting: `/review` splits…" with no mention of `/issue`'s parallel investigation sub-agents |
| Obsolete mention | A description refers to an element that no longer exists in the implementation | A reference to a deleted agent or removed flag |
| Skill Coverage Gap | A skill exists in `skills/*/SKILL.md` but has no independent top-level section heading in the Steering Document — **skill-dev projects only** (skipped when skill-dev condition is not met) | `/triage` exists in `skills/` but is mentioned only within a subsection, without an independent heading |

**Output findings as drift report:**

Do not auto-fix any detected narrative drift. Accumulate all findings as drift report items and pass them to Step 7 (normalization proposals). Each finding should include: the Steering Document and section name, the drift category, a brief description of the gap, and a suggested update direction for the user to evaluate.

**Structural Antipattern Detection (--deep only):**

This sub-step runs only when the `--deep` flag is enabled.

**SSoT Reverse Reference Check:**

For each file with `ssot_for` frontmatter, scan all sections. If a section's content primarily consists of a reference pointing to another file (e.g., "See docs/X.md for Y") where the referenced content logically belongs in the current file's `ssot_for` category, flag it as a "SSoT Reverse Reference" antipattern — the SSoT file is delegating its own content outward.

**Pointer-only Section Detection:**

For each `type: steering` file, scan all sections. If a section contains no substantive content — only pointer/reference text (e.g., "See README.md for the skill list.") with no bullets, tables, or descriptive sentences beyond the pointer — flag it as a "Pointer-only Section" antipattern.

Accumulate all findings as drift report items and pass them to Step 7 (normalization proposals). Do not auto-fix any detected structural antipatterns.

**Content classification based on dynamic SSoT mapping:**

Based on the constructed SSoT mapping, determine the "source of truth (Single Source of Truth)" for each section/description. Detect references by dynamically searching other files (README.md, CLAUDE.md etc.) with Grep for information corresponding to each SSoT file's `ssot_for` category.

Classification of each section/description:
- **Duplicate**: same information exists in multiple places (both SSoT side and reference side have substantive descriptions)
- **Drift**: implementation code and Steering Documents descriptions differ
- **Unreflected**: description exists in analysis source/implementation code but not recorded in Steering Documents

**Idempotency consideration:**

Locations with 2 or fewer substantive lines (text/list/code block lines, excluding blank lines, heading lines, HTML comment lines) + reference link patterns (lines containing links or mentions to `docs/` like `Details: {path}`, `[{path}]({path}) reference`, `See docs/`, `→ docs/`, `Reference: docs/`) are treated as "normalized" and excluded from proposals.

**Summary display:**

Display only the count of "issues" (duplicates + drift + unreflected). Normal items are counted only. Declare completion here and exit if 0 issues.

### Step 7: Normalization Proposals

Based on Step 6 classification results, propose one of 3 actions for each item:

- **Absorb**: incorporate descriptions from analysis source/implementation code into Steering Documents and replace original descriptions with reference links. Check for duplicate content in Steering Documents before executing
- **Reference**: replace duplicate descriptions in analysis source/implementation code with reference links to Steering Documents (when Steering Documents already have the information). Treat Steering Documents as the source of truth; other files hold references to them
- **Drift report**: report drift between implementation code and Steering Documents (no auto-fix, ask for user judgment). When `--deep` is enabled, narrative semantic drift check findings (Missing coverage / Partial description / Obsolete mention / Skill Coverage Gap) and structural antipattern detection findings (SSoT Reverse Reference, Pointer-only Section) are also surfaced through this path and never auto-fixed

If `--deep` flag is enabled and Step 2's .md integration scan results exist, add integration proposals for Pattern 2–4 unintegrated .md files to the existing proposal table:

- **Pattern 2 (organize as project document)**: propose "move to `docs/` and add `type: project` frontmatter"
- **Pattern 3 (save in docs)**: propose "move to `docs/` (no frontmatter)"
- **Pattern 4 (delete)**: propose "delete (replaced by other files)"

Display proposals in table format (filename, content summary, action, change summary).

### Step 8: Select Approval Method

Ask with AskUserQuestion for a bulk approval option (non-interactive mode: skip — bulk approvals are a High-Stakes Decision; output "[non-interactive mode] Skipping high-stakes action: bulk sync approval. To apply sync proposals, run `/doc sync` interactively." and exit this section):
- "Apply all"
- "Confirm one by one"
- "Skip all"

### Step 9: Apply Changes

Execute application based on Step 8 selection.

If "Apply all": display the list of files to change and change count, then ask for final confirmation with AskUserQuestion ("Apply the following N items. Proceed?"). Apply all after confirmation.

If "Confirm one by one": display before/after diff for each proposal and ask with AskUserQuestion to "Apply" or "Skip".

Apply only locations where the user selected "Apply" with Edit. "Absorb" action executes in 2 stages (append to Steering Documents → replace reference links in source file). Only perform source file replacement if writing to Steering Documents succeeded. If source file replacement fails, report Steering Documents changes as rollback targets. Skip and continue on other Edit failures (error tolerance).

After processing all proposals, display "Applied: N, Skipped (failed): M" with the list of changed files and report completion.

**Update references (after absorb/move/delete):**

If integration operations (absorb/move/delete) occurred, Grep the following files for reference links to target files and apply reference link updates or reference deletions with Edit:

- CLAUDE.md (protected but update reference links)
- README.md (protected but update reference links)
- `skills/*/SKILL.md`
- `$SPEC_PATH/*.md` (best effort)

If references are found, display before/after diff then update. Skip if no references found. After updating, display the list of updated files and change count.

### Step 10: Commit and Push Guide

Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-commit-push.md` and follow the "Processing Steps" section with `SUMMARY="sync (normalization)"`.

---

## sync Individual Reverse-Generation

Execute when ARGUMENTS is in `sync {doc}` format. Reverse-generate only the 1 document corresponding to `{doc}`.

Corresponding `{doc}` and target files:
- `sync product` → reverse-generate only `$STEERING_DOCS_PATH/product.md`
- `sync tech` → reverse-generate only `$STEERING_DOCS_PATH/tech.md`
- `sync structure` → reverse-generate only `$STEERING_DOCS_PATH/structure.md`

Execute "sync Bidirectional Normalization" Step 2 (Reverse-Generation Flow — Explore Analysis Sources) and draft generation, then execute Steps 3–5 (Reverse-Generation Flow — Display Draft, Select Save Method, Execute Save) targeting only the specified document.

After completion, display:

```
sync individual reverse-generation complete.
To bidirectionally normalize all documents, run `/doc sync` without arguments.
```

Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-commit-push.md` and follow the "Processing Steps" section with `SUMMARY="sync {doc} (reverse-generation)"`.

---

## add — Register Existing Document

Execute when ARGUMENTS is in `add {path}` format. Add `type: project` and `ssot_for` frontmatter to the specified file and register it as a project document.

### Step 1: File Existence Check and Path Validation

Execute these validations in order:

1. **Path restriction check**: confirm `{path}` has a `.md` extension (paths outside `docs/` are also allowed). If not met, display "Error: please specify a .md file for {path}." and exit.
2. **Wildcard check**: if `{path}` contains `*`, `?`, or `[`, display "Error: wildcards cannot be used. Specify a single file path." and exit.
3. **File existence check**: check existence of `{path}` with Glob. If the file doesn't exist, display "Error: {path} not found." and exit.

### Step 2: Check Existing Frontmatter

Read the file with Read. Check whether the file starts with `---` (has YAML frontmatter).

If frontmatter exists, check for the `type` field:
- If `type` field already exists → display "{path} is already registered as type: {value}." and exit (prevent duplicate registration)
- If `type` field doesn't exist → proceed to add `type` and `ssot_for` to frontmatter

If no frontmatter exists → proceed to insert new frontmatter at the beginning

### Step 3: Collect ssot_for Categories

Collect `ssot_for` categories with AskUserQuestion:

```
Please specify the categories for which {path} will be the SSoT (Single Source of Truth).
Multiple values can be specified comma-separated.
Example: workflow-phases, label-transitions
```

Split the input value by commas. Trim whitespace from each element and exclude elements that become empty strings. Treat remaining elements as the `ssot_for` list.

If the list is empty (all elements became empty strings), display "No categories were entered. Please enter them again." and repeat AskUserQuestion.

### Step 4: Insert/Update Frontmatter

**If existing frontmatter exists (no `type`):**

Add the following before the closing `---` of the existing frontmatter with Edit:

```yaml
type: project
ssot_for:
  - {category1}
  - {category2}
```

**If no frontmatter exists:**

Insert the following at the beginning of the file with Edit:

```yaml
---
type: project
ssot_for:
  - {category1}
  - {category2}
---

```

If Edit fails, display "Error: failed to update frontmatter. Please manually check the file." and exit.

### Step 5: Display Registration Result

Display the following message to complete:

```
{path} has been registered as a project document.
  type: project
  ssot_for: {category1}, {category2}

Run `/doc` to check registration status.
Run `/doc sync` to reflect in SSoT mapping.
```

### Step 6: Commit and Push Guide

Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-commit-push.md` and follow the "Processing Steps" section with `SUMMARY="register {path} as project document"`.

---

## project — Create New Project Document

Execute when ARGUMENTS is `project`. Collect information interactively and create a new document with `type: project` + `ssot_for` frontmatter in `docs/`.

### Step 1: Check docs/ Directory

Check for the `docs/` directory with Glob. If it doesn't exist, display the following error and abort:

```
Error: docs/ directory not found.
Manually run `mkdir docs` then re-run the command.
```

### Step 2: Collect Document Information

Collect the following in sequence with AskUserQuestion:

```
Question 1: What is the document name (without extension)?
Only alphanumerics, hyphens, and underscores are allowed.
Example: workflow, adr, runbook, decisions
```

If the input contains characters other than alphanumerics, hyphens, and underscores (slashes, dots, spaces, `..` etc.), display "Error: the document name contains invalid characters. Please use only alphanumerics, hyphens, and underscores." and repeat Question 1.

```
Question 2: What is the purpose/usage of this document?
Example: workflow definitions, architecture decision records
```

```
Question 3: What categories will this document be the SSoT for?
Multiple values can be specified comma-separated.
Example: workflow-phases, label-transitions
```

```
Question 4: What are the main sections (headings)?
Specify comma-separated. Enter "none" if there are no sections.
Example: Overview, Flow Definition, Operations
```

### Step 3: File Duplicate Check

Check for existence of `docs/{name}.md` with Glob. If it already exists, ask with AskUserQuestion:

```
docs/{name}.md already exists. Overwrite?
(All existing content including frontmatter will be overwritten)
- Overwrite
- Use a different filename
- Cancel
```

If "Use a different filename" is selected, return to Step 2 Question 1. If "Cancel", exit.

### Step 4: Document Generation

Generate a file with the following structure based on collected information:

```markdown
---
type: project
ssot_for:
  - {category1}
  - {category2}
---

# {name}

{purpose/usage}

## {section 1}

(Write content here)

## {section 2}

(Write content here)
```

If sections are "none", include only the purpose description without headings.

Save to `docs/{name}.md` with Write.

### Step 5: Confirm Generation Result

Display the generated document content and confirm with AskUserQuestion (approve / revision request).

If revision requested, apply with Edit.

### Step 6: Completion Report

Display the following message to complete:

```
docs/{name}.md has been created.
  type: project
  ssot_for: {category1}, {category2}

Run `/doc` to check registration status.
Run `/doc sync` to reflect in SSoT mapping.
```

### Step 7: Commit and Push Guide

Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-commit-push.md` and follow the "Processing Steps" section with `SUMMARY="create project document {name}"`.

---

## translate — Translation Generation

Execute when ARGUMENTS starts with `translate {lang}`. Generate translations of English documentation to the target language using LLM, place output under `docs/{lang}/` (README → `README.{lang}.md` at project root), commit and push automatically.

Read `skills/doc/translate-phase.md` and follow its "Steps" section.
