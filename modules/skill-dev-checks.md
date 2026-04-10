# skill-dev-checks

Skill development checks for skill development repositories.

## Purpose

Defines design-time checks and cross-skill consistency checks for skill development repositories where `scripts/validate-skill-syntax.py` is present.

Calling skills: `/spec` (design-time checks), `/doc sync` (cross-skill consistency checks)

Execution scope branching by caller:
- Called from `/spec`: Execute design-time checks only (settings.json, shared modules/agents, tool dependencies, validation constraints). Execute only when SPEC_DEPTH=full (do not Read this file when SPEC_DEPTH=light)
- Called from `/doc sync`: Execute cross-skill consistency checks only

## Input

The following information is expected to be available from the caller:

- **Changed files list**: "Changed files" section of the Spec (when called from `/spec`)
- **SPEC_DEPTH**: `light` or `full` (when called from `/spec`)
- **Calling skill name**: `/spec` or `/doc sync`

## Processing Steps

### Design-Time Checks (called from /spec, execute only when SPEC_DEPTH=full)

#### settings.json Addition Check (when adding new skills)

If the changed files include a new skill (`skills/{name}/SKILL.md` newly created), add the following to the changed files list:

- `settings.json`: Add `Skill({name})` entry to `permissions.allow` array
- `settings.json`: For any Bash patterns listed in the new skill's SKILL.md `allowed-tools` frontmatter that are not yet registered in `settings.json`'s `permissions.allow`, add them

Check procedure:
1. Extract `allowed-tools` from the new skill's SKILL.md frontmatter
2. List `Bash(...)` patterns in `allowed-tools`
3. Cross-reference with `settings.json`'s `permissions.allow` to identify unregistered patterns
4. Record unregistered patterns in the `settings.json` changes section of the changed files list

#### Shared Module Check (modules/agents)

When changes span multiple skills, or when reusing content from existing skills in another skill, confirm the following:

- `modules/`: Consider extracting rules, logic, or patterns common to 2 or more skills (component parts of skill execution procedures)
- `agents/`: Consider extracting autonomous agents (subtasks involving judgment and execution) called from multiple skills
- Check whether any existing `modules/` or `agents/` files can be reused

Decision criteria: Direct description in SKILL.md is fine for single-use. Extraction to `modules/` is recommended when the same rules/logic are used in 2 or more places. Extraction to `agents/` is recommended when independent judgment and execution is needed from multiple skills.

**When creating new modules files**: If the changed files include new module file creation, include the 4-section structure (Purpose / Input / Processing Steps / Output) following the "Standard Structure Template for Shared Modules" in CLAUDE.md in the Spec's implementation steps.

#### Tool Dependency Check

List all tools (Bash commands, built-in tools, MCP tools) used in implementation steps, and record any not included in the target skill's `allowed-tools` frontmatter in the "Tool Dependencies" section.

Check procedure:
1. List all tools used in implementation steps
2. Cross-reference with target skill's SKILL.md frontmatter `allowed-tools`
3. Record missing tools in "Tool Dependencies" section
4. If the design includes adding new tools (base tool names without `mcp__` prefix) to `allowed-tools`, Grep `scripts/validate-skill-syntax.py` for the `KNOWN_TOOLS` definition and include `scripts/validate-skill-syntax.py` in the changed files if not registered

#### Read Instruction Placement Rule

When changed files include SKILL.md or new modules files that reference shared modules with Read instructions, verify placement follows this rule:

Read instructions for shared modules (`modules/*.md`) must be placed in the **first paragraph immediately after the step or section heading** (a blank line between heading and paragraph is allowed).

Prohibited patterns:
- Read instruction at the end or middle of a numbered list (LLM may complete list processing and skip the Read)
- Read instruction embedded in a table cell (LLM treats it as table description and skips)

When the Spec includes steps that reference shared modules, ensure the implementation step description places the Read instruction at the heading level, not nested inside lists or tables.

#### Exhaustive/Example Markers

When changed files include new lists or tables in SKILL.md or modules files, verify that each enumeration uses one of the following markers to distinguish coverage:

| Marker | Meaning | When to use |
|--------|---------|-------------|
| **(examples)** | Representative cases shown; other cases may apply | List or table covers only some patterns |
| **(exhaustive)** | All cases listed; nothing else applies | List or table intentionally covers all patterns |
| **(project-dependent)** | Target changes based on project configuration or settings | List covers project-specific values, paths, or tool names |

Exceptions: Marker not required when context already makes coverage clear (e.g., sentences starting with "e.g.," or "for example", "Example" column in a table, templates inside code fences, or text like "all N types").

#### Caller Condition Propagation

When changed files include modules files that have caller condition branching (SPEC_DEPTH branching, skill name branching, etc.), verify that the calling SKILL.md also explicitly states the same caller condition.

Rule: If a modules file executes certain checks only under specific conditions (e.g., only when `SPEC_DEPTH=full`), the SKILL.md that calls it must state this caller condition explicitly so the implementer is aware of when the module's logic applies.

Example: `skill-dev-checks.md` runs design-time checks only when `SPEC_DEPTH=full` → the `/spec` SKILL.md must also state "Read skill-dev-checks.md only when SPEC_DEPTH=full".

When the Spec includes a step that calls a modules file with caller-dependent conditions, add "propagate the condition to the calling SKILL.md" as part of that implementation step.

#### SKILL.md Validation Constraint Check (when SKILL.md is in changed files)

When changed files include SKILL.md (new creation or existing modification), consider the known constraints of `validate-skill-syntax.py` at design time.

| Constraint | Content | Design-Time Response |
|------------|---------|---------------------|
| YAML block scalar not supported | Multi-line notation with `\|` or `>` cannot be used in frontmatter `description` etc. Must write on one line | Design frontmatter values as single-line |
| Half-width exclamation mark prohibited | Half-width exclamation marks cannot appear in SKILL.md body text (outside code fences and inline code). Use full-width "！" or Japanese expressions | Do not include half-width exclamation marks in implementation step text |
| Triple backtick prohibited | Triple backticks cannot appear in SKILL.md body text (validator misidentifies as code fence start) | Explain code examples containing triple backticks using Japanese expressions (e.g., "code fence block", "3 backticks") |

#### Migration Step-Number Reference Check

When changed files include migration of a workflow document (SKILL.md, modules file, docs page) from another repository, add `file_not_contains` verify commands for step numbers, workflow names, or other repository-specific references from the source repository that must not survive migration.

Check procedure:
1. Identify any step-number references in the source document (e.g., "Step 6", "Step 3")
2. Confirm whether each referenced step number is valid in the target repository's workflow
3. For step numbers that are source-specific and should not appear in the migrated file, add a `file_not_contains` verify command

Example (from #36 tech.md migration — `Code review (Step 6)` was a claude-config step number that leaked into wholework's docs):
```
- <!-- verify: file_not_contains "docs/tech.md" "Step 6" --> No source-repo step numbers remain in migrated file
```

Apply this check to any string that is repository-specific: step numbers, phase names, tool names, or internal references tied to the source repository's structure.

### Cross-Skill Consistency Checks (called from /doc sync)

Run regardless of SPEC_DEPTH condition (sync is not a design phase).
Output check results as "divergence report" only; do not auto-fix (follows existing doc sync patterns).

#### Size Routing Definition Cross-Check

Extract Size routing-related descriptions from all skills' SKILL.md files and verify no conflicts between skills.

Targets: `skills/*/SKILL.md` (all skills), `modules/size-workflow-table.md`

Items to extract:
- Mapping tables of XS/S/M/L/XL to patch/pr
- Descriptions of `--patch`/`--pr` options
- Size→route determination logic descriptions

On conflict detection: Output as divergence report with "filename, location, conflict content, authoritative definition (`modules/size-workflow-table.md`)"

#### Review Mode Definition Cross-Check

Verify `--light`/`--full` and other mode descriptions are consistent across skills and documents.

Targets: `skills/review/SKILL.md`, `skills/auto/SKILL.md`, `skills/code/SKILL.md` (examples), `docs/workflow.md`, `modules/size-workflow-table.md`

Check content:
- `--light` definition (which processing is skipped) is consistent across skills
- `--full` definition is consistent across skills
- No variation in mode aliases or descriptions

On conflict detection: Output as divergence report with "filename, location, conflict content"

#### Workflow Call Order Cross-Check

Verify that pre/post skill names referenced by each skill (e.g., `/code` → `/review` → `/merge`) are consistent across all locations.

Targets: All `skills/*/SKILL.md`, `docs/workflow.md`, `docs/product.md`

Check content:
- Next skill guidance like "next run `/xxx`" is consistent
- Workflow order descriptions (issue → spec → code → review → merge → verify, etc.) are consistent across skills and documents
- `/auto`'s internal call order is consistent with each skill's guidance

On conflict detection: Output as divergence report with "filename, location, conflict content, authoritative definition (`docs/workflow.md`)"

## Output

### When called from /spec

Reflect each check result in the relevant Spec section:
- Add missing settings.json entries to changed files list
- Add modules/agents files to changed files if sharing is needed
- Record tool dependencies in "Tool Dependencies" section
- Record validation constraint violation risks in "Notes" section

### When called from /doc sync

Output cross-skill consistency check results in the following format:

```
## Cross-Skill Consistency Check Results

### Size Routing Definition
- PASS / N divergences

If divergences:
| File | Location | Conflict Content | Authoritative Definition |
|------|----------|-----------------|------------------------|
| ...  | ...      | ...             | ...                    |

### Review Mode Definition
- PASS / N divergences

### Workflow Call Order
- PASS / N divergences
```
