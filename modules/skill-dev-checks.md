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

#### SKILL.md Validation Constraint Check (when SKILL.md is in changed files)

When changed files include SKILL.md (new creation or existing modification), consider the known constraints of `validate-skill-syntax.py` at design time.

| Constraint | Content | Design-Time Response |
|------------|---------|---------------------|
| YAML block scalar not supported | Multi-line notation with `\|` or `>` cannot be used in frontmatter `description` etc. Must write on one line | Design frontmatter values as single-line |
| Half-width exclamation mark prohibited | Half-width exclamation marks cannot appear in SKILL.md body text (outside code fences and inline code). Use full-width "！" or Japanese expressions | Do not include half-width exclamation marks in implementation step text |
| Triple backtick prohibited | Triple backticks cannot appear in SKILL.md body text (validator misidentifies as code fence start) | Explain code examples containing triple backticks using Japanese expressions (e.g., "code fence block", "3 backticks") |

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
