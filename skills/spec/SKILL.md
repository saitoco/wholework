---
name: spec
description: Issue specification (`/spec 123`). Reads Issue requirements and creates an implementation plan. Automatically adjusts investigation depth (light/full) based on Size (`--light`/`--full` to override).
allowed-tools: Bash(gh issue view:*, gh issue create:*, gh issue edit:*, gh issue list:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-graphql.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-type.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*, ${CLAUDE_PLUGIN_ROOT}/scripts/worktree-merge-push.sh:*, git add:*, git commit:*, git push:*, git merge:*, git worktree:*, git branch:*), Glob, Grep, Read, Write, Edit, WebFetch, WebSearch, ToolSearch, EnterWorktree, ExitWorktree, mcp__plugin_figma_figma__get_design_context, mcp__plugin_figma_figma__get_variable_defs, mcp__plugin_figma_figma__get_screenshot, mcp__plugin_figma_figma__get_metadata, mcp__plugin_figma_figma__whoami
---

# Issue Specification

Read Issue requirements, investigate the codebase, and create an implementation plan as a Spec file.

## Non-Interactive Mode Behavior

If ARGUMENTS contains `--non-interactive` (set automatically by `run-spec.sh`), operate in **non-interactive mode**. In this mode, `AskUserQuestion` cannot be used.

Read `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md` and follow the "Non-Interactive Mode Handling" section for the three-tier policy (auto-resolve / skip / hard-error). The specific branching at each step is noted inline below.

Key per-step behavior in non-interactive mode:
- **Step 6** (Codebase Investigation — conflict detection, `SPEC_DEPTH=full`): auto-resolve the conflict using model judgment (note the resolution in the Spec's "Notes" section); record the decision in the Auto-Resolve Log posted as an issue retrospective comment
- **Step 7** (Ambiguity Resolution): auto-resolve each ambiguity point using model judgment; record decisions in the Auto-Resolve Log
- **Step 8** (Uncertainty): verify using the documented method if possible; if verification fails and the design premise is incorrect, record the issue in the Spec's "Notes" section and continue with best-effort implementation approach rather than aborting

## Steps

### Step 0: Mode Detection

If ARGUMENTS contains `--help`, read `${CLAUDE_PLUGIN_ROOT}/modules/skill-help.md` and output help following the "Processing Steps" section. Do not execute further steps.

Parse ARGUMENTS to extract the Issue number and mode options:
- Extract the numeric part as the Issue number
- `--light` flag present: SPEC_DEPTH=light
- `--full` flag present: SPEC_DEPTH=full
- Neither present: auto-detect from Size label (see below)

**Auto-detection rules (when no flag is specified):**

1. `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER` to get Size (Project field first, label fallback)
2. Determine SPEC_DEPTH (rules are hardcoded; no need to read `size-workflow-table.md`):
   - Size XS/S (patch route) → SPEC_DEPTH=light
   - Size M (pr route) → SPEC_DEPTH=light
   - Size L (pr route) → SPEC_DEPTH=full
   - Size XL → SPEC_DEPTH=full
   - Size unset → SPEC_DEPTH=full (safe fallback)
3. Explicit `--light`/`--full` overrides auto-detection

**Input**: ARGUMENTS (Issue number + option flags)
**Output**: `NUMBER` (Issue number), `SPEC_DEPTH` (`light` or `full`)

### Step 1: Fetch Issue Information

```bash
gh issue view $NUMBER --json title,body,labels
```

Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-banner.md` and display the start banner with ENTITY_TYPE="issue", ENTITY_NUMBER=$NUMBER, SKILL_NAME="spec".

Run `${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-type.sh $NUMBER` and store the result in `ISSUE_TYPE`:
- Value (`Bug`/`Feature`/`Task`) stored as-is
- Empty string: `ISSUE_TYPE=unset`

`ISSUE_TYPE` is referenced in Step 10 template selection.

### Step 2: Worktree Entry

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Entry" section.

**Worktree name convention:** `spec/issue-$NUMBER`

Record `ENTERED_WORKTREE` for later use. The Entry section includes running `.claude/hooks/worktree-init.sh` if it exists.

### Step 3: Label Transition (start)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER spec
```

### Step 4: Blocked-by Detection

Check whether the target Issue has unresolved blocked-by relationships:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-check-blocking.sh $NUMBER --dry-run
```

- Exit code 0: no open blockers → `HAS_OPEN_BLOCKING=false`
- Exit code 2: open blockers present → `HAS_OPEN_BLOCKING=true`
- Exit code 1: error → warn and set `HAS_OPEN_BLOCKING=false`

**Retain the result**: if any open blocked-by Issues exist (exit code 2), set `HAS_OPEN_BLOCKING=true` and retain through Step 19.

### Step 5: Reference Steering Documents (if present)

Read `${CLAUDE_PLUGIN_ROOT}/modules/detect-config-markers.md` and follow the "Processing Steps" section. Retain `SPEC_PATH` and `STEERING_DOCS_PATH` for use in subsequent steps.

Check whether the following steering documents exist using Glob, then read only those that exist:

- `$STEERING_DOCS_PATH/structure.md` — directory layout, Key Files (starting point for codebase investigation)
- `$STEERING_DOCS_PATH/tech.md` — tech stack, Architecture Decisions (technical constraints), Coding Conventions
- `$STEERING_DOCS_PATH/product.md` — project vision, Non-Goals, Terms (design priority, terminology)

**If none exist, skip this step.**

Use the referenced documents as the codebase exploration starting point, for technical constraints, design priorities, and terminology consistency.

**Project-local Domain files (if present):**

Read `${CLAUDE_PLUGIN_ROOT}/modules/domain-loader.md` and follow the "Processing Steps" section with `SKILL_NAME=spec`. Domain file content supplements steering documents as additional context for codebase investigation and design.

### Step 6: Codebase Investigation

**Read existing retrospective sections (before codebase investigation):**

If a Spec file already exists for this Issue (from a prior `/spec` run), read any retrospective sections it contains (e.g., `## Spec Retrospective`, `## Code Retrospective`) before proceeding with codebase investigation. These sections carry forward decisions and pitfalls from earlier phases — reading them avoids repeating known mistakes and preserves design continuity.

**Credential/security policy alignment check (before codebase investigation):**

When the Issue design involves credential storage, secret management, CI/CD secrets, API key handling, or access control, verify alignment with the target repository's credential or security policy before writing Implementation Steps:

1. Search for policy documents: `grep -rl "credential\|security" docs/ SECURITY.md 2>/dev/null`
2. Read identified policy files and note any design constraints (e.g., forbidden storage locations, required patterns)
3. Record any detected policy conflicts in the Spec's "Notes" section and resolve the design approach accordingly

**Skip** if the Issue does not involve credential or security-sensitive operations.

Read `${CLAUDE_PLUGIN_ROOT}/modules/measurement-scope.md` and follow its measurement scope guidelines when recording quantitative data (file counts, line counts, grep hit counts, etc.) in the Spec.

**Based on SPEC_DEPTH:**

- **SPEC_DEPTH=full**: read `skills/spec/codebase-search.md` and follow the "Processing Steps" section for codebase investigation.
- **SPEC_DEPTH=light**: skip reading `codebase-search.md`; directly identify changed files using Grep/Read. Infer required files from the issue body, and verify existence/content with Glob/Grep.

**External spec dependency check (regardless of SPEC_DEPTH; only when applicable):**

Read `skills/spec/external-spec.md` and follow the "Processing Steps" section to check official docs and incorporate findings into the design when any of the following applies:

- Specific options/behavior of system commands (`tmux`, `gh`, `git`, etc.)
- Framework/library API specs (Claude Code hooks, GitHub API, etc.)
- Environment variable/config file formats (JSON schemas, YAML structures, etc.)
- Filesystem/OS behavior (symlinks, permissions, etc.)

**Issue body vs. existing implementation conflict detection (regardless of SPEC_DEPTH):**

After codebase investigation, compare Issue body prerequisite statements with existing code implementations to detect conflicts.

Steps:
1. Extract factual claims from the Issue body's Background/Purpose sections ("X is Y", "X can Z", etc.)
2. Compare against existing code investigated in Step 6

**Example (Issue #650):** The issue body stated "`/doc add` accepts arbitrary paths" but the SKILL.md implementation was limited to `docs/`. Failing to detect and note this conflict in the Spec led to implicit implementation decisions.

**On conflict detection:**
- **SPEC_DEPTH=full**: note in Spec's "Notes" section as "Conflict with implementation" (content, issue body quote, actual implementation file/location); confirm resolution approach via AskUserQuestion
- **SPEC_DEPTH=light**: note in Spec's "Notes" section only (no user confirmation)

**If no conflicts**: skip this sub-step.

**Tool detection pattern consistency check (regardless of SPEC_DEPTH; only when applicable):**

When implementation steps include tool detection methods (version checks, MCP ToolSearch, CLI detection, etc.), investigate existing codebase patterns for consistency.

Steps:
1. Extract tool detection methods from implementation steps (e.g., `npx playwright --version`, `which curl`, ToolSearch)
2. Investigate how similar tools are detected in the existing codebase (Grep/Read)
3. If a different detection method is adopted, note the reason in the Spec's "Notes" section

**Example (Issue #781):** Spec specified `npx playwright --version` for Playwright detection, but the existing codebase used MCP ToolSearch. Checking existing patterns in the Spec phase would have prevented divergence.

**Skip** if no tool detection is included in the implementation steps.

**Dependency version pre-check (when Changed Files include new external packages):**

When the Issue's Changed Files or Implementation Steps include adding a new dependency from an external package registry (e.g., `requirements.txt`, `package.json`, `Cargo.toml`, `pyproject.toml`), verify the actual latest release version from the official registry before writing the Spec version specifier:

1. For Python packages: check PyPI for the package's latest stable release
2. For Node.js packages: check the npm registry for the latest version
3. For other registries (crates.io, RubyGems, etc.): use the registry's release page
4. Record the verified version string in the Changed Files entry or the Spec's "Notes" section

**Background**: specifying an unverified version causes a discrepancy at the `/code` phase when the actual registry version differs, resulting in rework (example: Spec wrote `mplfinance>=0.12.10` but PyPI only had `0.12.9b5`).

**Skip** if no new external dependency packages are being added.

**Adapter pattern survey (regardless of SPEC_DEPTH; only when applicable):**

If the Issue body's verify commands include command types not present in the `modules/verify-executor.md` built-in translation table, follow `docs/environment-adaptation.md` Extension Guide Step 0 before accepting the new command type:
1. Enumerate all rows in `modules/verify-executor.md` that delegate via `adapter-resolver.md`
2. List all bundled adapters under `modules/{capability}-adapter.md`
3. Confirm whether the proposed command type can be expressed using existing `adapter-resolver` patterns
4. If expressible, note the recommended approach in the Spec's "Notes" section

**Skip** if all Issue body verify commands use built-in command types.

### Step 7: Ambiguity Resolution (clarify)

**SPEC_DEPTH=full only. Skip if SPEC_DEPTH=light.**

Read `${CLAUDE_PLUGIN_ROOT}/modules/ambiguity-detector.md` and check Issue requirements and implementation points against the pattern table — extract **at most 3** ambiguity points.

**Priority sort:**

Sort ambiguity points in descending order of impact (scope of effect on Spec text, degree of propagation to implementation).

**Auto-resolution (dynamic partitioning):**

Starting from lowest-priority items, check auto-resolution conditions. Conditions:
- Uniquely inferrable from existing patterns (consistent codebase convention)
- Same judgment repeated in past similar issues/specs (recorded in retrospectives)
- Spec text is unaffected regardless of which option is chosen

Present unresolved items to the user.

**Pre-investigation (for each unresolved item):**

Refer to `ambiguity-detector.md`'s "Sources to investigate" column and investigate sequentially:

| Aspect | Content | Source |
|--------|---------|--------|
| Existing patterns | Similar implementations/conventions | Project source code (Grep/Read) |
| Past knowledge | Retrospectives from similar issues/specs | `$SPEC_PATH/*.md`. Skip if absent |
| Trade-offs | Pros and cons of each option | Codebase + Steering Docs |

Format Q&A based on investigation results (with recommendation if found, with "no related patterns" note if not found).

**Present and confirm auto-resolved items:**

If any items were auto-resolved, present them with rationale after Q&A.

**Record auto-resolved items in the Spec's "Notes" section** when creating the Spec in Step 10.

After Q&A, update the Issue body with the new information: `mkdir -p .tmp`, write to `.tmp/issue-body-$NUMBER.md`, update with `gh-issue-edit.sh`, delete temp file.

### Step 8: Identify Uncertainty (uncertainty detection)

**SPEC_DEPTH=full only. Skip if SPEC_DEPTH=light.**

After codebase investigation, identify uncertainty items.

**Detection criteria (examples):**

| Pattern | Example | Response |
|---------|---------|----------|
| Unverified external API/spec dependency | Claude Code hooks target tool list | Check official docs via WebFetch |
| Assumptions about timing/ordering | stdout destination, hook timing | Verify with prototype or note as uncertain |
| Environment-dependent behavior | OS, shell, version differences | Note target environment; verify with tests |
| Implicit assumptions in existing code | Permission pattern matching rules | Check code/docs; note if unclear |

**Response:**
1. Organize items detected in Step 6's external spec check
2. Incorporate WebFetch/WebSearch-resolved items into the design
3. Note unresolved items in an "Uncertainty" section (with verification method and impact scope)
4. Confirm with user via AskUserQuestion if needed

### Step 9: UI Design Phase (if applicable)

**Run regardless of SPEC_DEPTH (UI changes are independent of Size).**

Read `skills/spec/figma-design-phase.md` and follow its steps.

### Step 10: Create Spec

**Prerequisite: all codebase investigation in Step 6 must be complete.**

If SPEC_DEPTH=full, read `${CLAUDE_PLUGIN_ROOT}/modules/skill-dev-checks.md` and follow it at the relevant point in Step 10. Skip if SPEC_DEPTH=light.

Read `${CLAUDE_PLUGIN_ROOT}/modules/doc-checker.md` and use the "Impact Assessment" section to decide whether to include documentation files in the changed-files list.

**`docs/ja/` translation sync check:**

If `docs/translation-workflow.md` exists, read it and follow the sync procedure.

**Rename-type Issue grep check:**

If the issue title or body contains "rename", "renaming", or similar, run `grep -rn 'old-name' .` from the repository root (must be inside the repo — not from `~` or a parent directory; see `modules/filesystem-scope.md`), then per-file with `grep -c`. Add any files not in the changed-files list. Record hit counts in the Spec. Also check:
- Concept names without slashes (section headings, Mermaid labels, table text)
- Context-embedded short forms (e.g., "old-name で", "old-name の")
- Path link references (relative paths in docs)
- Section number cross-references

**`.claude/` files and `git add -f`:**

Files under `.claude/` are in `.gitignore`, so `git add <file>` silently skips them. When grep finds hits in `.claude/` files, include them in the changed-files list and add a note to the Implementation Steps: "For `.claude/` files, use `git add -f` instead of `git add`."

Pre-investigate exclusion conditions (historical records, terminology definitions, comparison contexts) and note them in the Spec's "Exclusions" section. Reflect `grep -v` exclusions in `command` hints.

**Post-replacement scan checklist:**

After completing find-and-replace, scan the changed files for these patterns introduced by mechanical substitution:
- **Article consistency**: check that articles (a/an) are correct after noun replacement (e.g., "an old-term" → "an new-term" should become "a new-term" when appropriate)
- **Compound noun redundancy**: check for word doubling when replacing compound nouns (e.g., "old-term commands" → "new-term commands" but "new-term term commands" is redundant)
- **Japanese boundary space**: check that spacing between Japanese text and replaced English terms is correct after substitution

**Multi-file change grep coverage check:**

For changes affecting many files with a common pattern, run `grep -rl '<keyword>' <dir>` to enumerate all affected files and cross-check against the Spec's changed-files list.

**Test file search check:**

For each changed file, check for corresponding test files under `tests/` and include them in the changed-files list if test updates are needed.

**Variable assignment change — enumerate usage locations:**

When removing or changing variable assignments, explicitly list all usage locations (conditional branches, command arguments, output handling) in the implementation steps.

**Feature deletion impact chain check:**

When the Issue involves deleting a feature (script, function, variable, etc.), identify all files that reference the deleted target (impact chain) and include them in the changed-files list with cleanup ACs:

1. Run `grep -rn '<deleted-target-name>' .` from the repository root to enumerate all referencing files
2. For each file in the impact chain, add a changed-files entry: e.g., `scripts/foo.sh`: remove `<deleted-target>` reference
3. Add a cleanup AC for each impact chain file: e.g., `<!-- verify: file_not_contains "scripts/foo.sh" "<deleted-target>" -->`

**Skip** if the Issue does not involve feature deletion.

*Example: Issue #485 retro — `detect-wrapper-anomaly.sh` retained a dead `VERIFY_FAILED` detection pattern after `run-verify.sh` was deleted because the impact chain was not listed in the Spec's Changed Files.*

**bats test Spec input format:**

For Specs involving new/modified bats tests, explicitly specify the input data format (markdown condition line format, JSON structure, command output format) that the test target script expects. Include test data format details in the Spec's Notes section.

**bats test verify command: `@test` name pattern check:**

When creating `file_contains` verify commands targeting `.bats` test files, inspect the actual `@test` names in the file first (using Grep/Read). Test name conventions vary — colon position, capitalization, and word order differ between test files (e.g., `@test "Size XS: ..."` vs. `@test "Size: XS ..."`) — so deriving the keyword from a description alone is unreliable.

Steps:
1. Grep the target `.bats` file for `@test` to collect test names: `grep "@test" tests/foo.bats`
2. Identify the test name matching the acceptance condition
3. Extract a unique, stable substring from the actual test name as the `file_contains` keyword

**bats test self-reference exclusion check:**

When Implementation Steps include a pattern-detection script (e.g., grep-based forbidden-expression checks), check if the corresponding bats test file will contain the detection targets as test fixtures. If so, explicitly include a self-reference exclusion in the Implementation Steps to prevent false positives.

Example: add `grep -v 'tests/xxx.bats'` to the script invocation so the test fixture file is excluded from detection.

**WHOLEWORK_SCRIPT_DIR mock addition check:**

If implementation steps include adding a new script under `scripts/` (including subdirectories), check if any bats test file sets `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"`. If so, explicitly include adding a mock file for the new script under `$MOCK_DIR` in the Implementation Steps.

**pytest fixture path CWD independence check:**

When the Issue involves adding pytest tests that reference fixture files (detected by "test", "pytest", or "fixture" keywords in the Issue title/body, or when Acceptance Criteria describe pytest fixture file access), add the following note to the Spec's Notes section:

> Pytest fixture file references must use `Path(__file__).parent / "fixtures" / "file"` (not CWD-relative paths like `Path("tests/fixtures/file")`). This ensures the test works regardless of the working directory at pytest invocation time — required in worktree environments and when pytest is run from a directory other than the repository root.

**Mermaid diagram node ID naming check:**

If implementation steps include Mermaid diagram updates, check existing node ID naming patterns and apply them consistently to new nodes.

**Constraint checklist (MUST/SHOULD):** When designing implementation steps for SKILL.md/modules/agents changes, read `${CLAUDE_PLUGIN_ROOT}/skills/spec/skill-dev-constraints.md` and follow the constraint checklist if loaded in Step 5.

**read-then-write jq failure guard:**

When Implementation Steps describe an operation that reads an existing file and writes back the modified result (read-then-write), explicitly state the jq failure guard (e.g., `|| die "..."`) in Implementation Steps.

**Side-effect direction anti-patterns in implementation steps:**

When writing implementation steps that involve priority-ordered data construction (e.g., building dicts with multiple priority sources), avoid methods where the side-effect direction is counterintuitive:

- **Anti-pattern**: `setdefault` or `dict.update` in low-priority-first order — `setdefault` does not overwrite existing keys, so calling it from lowest priority upward locks in the lowest-priority value; `dict.update` in high-priority-first order overwrites previously set higher-priority values with lower-priority ones
- **Recommended**: explicit algorithmic description — e.g., "iterate sources in high-priority-first order; for each key, set `dict[key] = value` only if the key is not yet present (`if key not in dict`)"

When the overwrite direction of a method is non-obvious, spell out the algorithm explicitly rather than specifying the method by name.

**SHOULD-level acceptance criteria consideration:**

When defining acceptance criteria, explicitly consider:
- Documentation additions (README.md, CLAUDE.md, docs/workflow.md, etc.)
- Workflow-impacting doc sync (docs/workflow.md, README.md — for workflow phase/skill behavior/routing changes)
- Config marker additions (.wholework.yml)
- Reference updates in existing files (tables, links, etc.)
- For new modules: include $STEERING_DOCS_PATH/structure.md module table and Mermaid graph updates in changed-files list
- For new output directories (e.g., `docs/stats/`, `docs/reports/`): include $STEERING_DOCS_PATH/structure.md Directory Layout tree update in changed-files list (single-file outputs such as `docs/report.md` are excluded)
- Consistency with existing patterns (naming conventions, structural patterns)
- `docs/ja/*` files (Japanese mirror files): use Japanese-format patterns in verify commands to avoid unintended format changes; if an English pattern must be used, note the format impact explicitly in Notes

Before writing the Spec file, emit a progress line so the watchdog resets its silence counter:
```bash
echo "progress: Writing Spec for issue #$NUMBER..."
```

Save the implementation plan to `$SPEC_PATH/issue-$NUMBER-short-title.md`.

Read `${CLAUDE_PLUGIN_ROOT}/modules/verify-patterns.md` and follow the "Processing Steps" guidelines (especially "3. Pre-verification of target file format").

For acceptance conditions where exact string matching is unreliable (semantic equivalence, subjective quality, meaning-level intent), consider the `rubric` verify command instead of hard-pattern commands. See `modules/verify-patterns.md` §9 for selection criteria.

In particular, when the rubric's grader description contains a numeric literal, constant name, or threshold value (e.g., `BREAKEVEN_THRESHOLD_PCT = 10.0`), add a `file_contains` hint for the corresponding constant alongside the `rubric` to enable deterministic verification of the value (see `modules/verify-patterns.md` §9).

**Data output value accuracy check:**

When Spec descriptions include data output values — column names, enum values, code values (コード値) — verify the exact value against the actual implementation code before writing:

1. Run `grep -rn '<value>' <impl-file>` to confirm the exact string the implementation outputs
2. When Japanese labels and English code values coexist, write both explicitly — e.g., `{rs_new_high (新高値) / rs_leading (Leader)}`
3. For `rubric` ACs that reference output values, cite the actual code value (not the display label) to prevent grader misinterpretation

**Background**: if a Spec writes a Japanese label where the implementation outputs an English code value, a `rubric` grader may fail to infer the correct mapping and produce inconsistent PASS/FAIL results.

**String-matching verify command existence check:**

For string-matching verify commands (`grep`, `file_contains`, `file_not_contains`, `section_contains`), confirm the search pattern actually appears (or will appear) in the implementation target file before finalizing the Spec:

1. For `grep "<pattern>" "<file>"` and `file_contains "<file>" "<pattern>"`: open the target file and confirm the exact pattern string is present, or confirm it is a string the implementation will introduce. If the file does not yet exist, record the expected pattern in the Spec's "Uncertainties" section.
2. For `file_not_contains "<file>" "<pattern>"`: confirm the pattern currently exists in the file (for removal verification) or document why its absence is the expected final state.
3. For `section_contains "<file>" "<section>" "<pattern>"`: verify both that the section heading exists in the file and that the search pattern appears within that section (or will after implementation).

If a pattern cannot be confirmed at Spec creation time, record the uncertainty explicitly (file path, section, pattern) in the Spec's "Uncertainties" section so `/code` can verify it before implementation.

**Notes and verify command consistency (immediately after creating verify commands):**

If Notes contain implementation direction statements, verify they do not contradict the corresponding verify commands. Correct discrepancies immediately.

**Section rename — update verify commands simultaneously:**

If implementation steps include section renaming (e.g., `## Implementation Steps` → `## Changes`), update any `section_contains`/`section_not_contains` verify commands referencing that section name at the same time.

**verify-type tag check:**

If post-merge conditions in the Issue body have `<!-- verify-type: ... -->` tags, read `${CLAUDE_PLUGIN_ROOT}/modules/verify-classifier.md` and verify:
- `auto`-tagged conditions without verify commands — consider adding them
- `opportunistic`-tagged conditions align with `verify-classifier.md`'s `opportunistic` definition
- `manual`-tagged conditions — for each, consult `${CLAUDE_PLUGIN_ROOT}/modules/verify-patterns.md §11` quick reference and check if it can be replaced with `file_exists` / `file_contains` / `http_status` / `rubric`. If replaceable, update the verify command in both the Spec and Issue body AC.

**Text removal verify command preference:**

For verifying text removal (deletion or replacement of specific strings), `file_not_contains` checks are preferred over broad `command "test $(grep ...) -eq 0"` form. `file_not_contains` produces deterministic PASS/FAIL in `/review` safe mode; broad `command` grep form becomes UNCERTAIN. Decompose into per-file `file_not_contains` checks when possible; use `command` only when `file_not_contains` cannot express the condition.

**Spec filename rules:**
- `short-title` generated from Issue title
- English, kebab-case, max 30 characters
- Translate Japanese titles to English
- Example: Issue #76 "Specのファイル名に短いタイトルを追加する" → `issue-76-issue-spec-short-title.md`

**Verify command sync rule:**

Copy `<!-- verify: ... -->` hints from the Issue body's `## Acceptance Criteria > Pre-merge` section into the Spec's `## Verification > Pre-merge` section verbatim. Do not rewrite independently.

**No checkboxes in Spec:** Use plain bullets (`- `) in the Verification section. `- [ ]` format is not used (checkboxes are managed on the Issue side; Spec-side checkboxes are never updated by `/verify`, leaving permanent inconsistency).

**Count alignment check (regardless of SPEC_DEPTH):**

After creating `## Verification > Pre-merge`, count items in:
1. Issue body's `## Acceptance Criteria > Pre-merge`
2. Spec's `## Verification > Pre-merge`

If counts differ, output a warning and continue:
```
Warning: acceptance criteria count does not match verification item count.
  Issue body pre-merge criteria: N items
  Spec pre-merge verification: M items
Check for missing items. Continuing.
```

**Verification conditions vs. Issue body acceptance criteria consistency check (regardless of SPEC_DEPTH):**

After creating `## Verification > Pre-merge`, compare Spec items against Issue body items to reflect verify commands:
- List each Spec `## Verification > Pre-merge` item
- Compare against Issue body `## Acceptance Criteria > Pre-merge` items
- Detect: Spec items not in Issue body (omission), or mismatched `<!-- verify: ... -->` hints
- If mismatched, auto-update Issue body (use Spec's `## Verification > Pre-merge` as source of truth): `mkdir -p .tmp`, write to `.tmp/issue-body-$NUMBER.md`, update with `gh-issue-edit.sh`, delete temp file

**BRE metacharacter detection in verify commands:**

After the consistency check, scan all `<!-- verify: grep "PATTERN" ... -->` commands in the Spec's `## Verification > Pre-merge` section. For each `grep` verify command, extract the PATTERN string (the first quoted argument after `grep`) and check whether it contains BRE metacharacters: `\|`, `\(`, `\)`, `\+`, `\?`.

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

**Patch route verify command check:**

After `## Verification > Pre-merge` is finalized and the Issue body is updated, if Size is `XS` or `S` (patch route — no PR exists), scan `## Verification > Pre-merge` in the Spec for `github_check "gh pr checks"` entries.
- If found: output "Warning: patch route — `github_check "gh pr checks"` is incompatible (no PR exists in patch route). Auto-fixing to `github_check "gh run list"` form." and replace each with `github_check "gh run list --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` (change `expected_value` from the job name to `"success"` — `gh run list` outputs run-level conclusion, not job names; add `--workflow=<filename>` if there are multiple workflow files under `.github/workflows/`). Update Spec file using Edit tool. Also update Issue body via `gh-issue-edit.sh`.

**Changed-file modification types (examples, both templates):**

| Type | Example notation |
|------|-----------------|
| Addition | `new-file.md`: new file |
| Deletion | `old-file.md`: delete |
| Text change | `SKILL.md`: change "old text" → "new text" |
| Content addition | `SKILL.md`: add XXX section to Step N |

**Shell script bash compat note:**

When Changed Files includes shell scripts (`scripts/*.sh`, hook scripts, etc.), add a bash compat note to each entry. Example: `scripts/foo.sh`: add bar function — bash 3.2+ compatible. This prevents issues like using `mapfile` (bash 4+) that fails on macOS system bash (bash 3.2).

**"No change needed" pre-verification rule:**

Before writing "no change needed" for a file in the changed-files section, verify with grep or similar. Unverified "no change needed" judgments lead to implementation oversights (example: #749).

**`run-*.sh` → Skill call migration: propagated flags list:**

When a Changed File replaces a `run-*.sh` invocation with a `Skill(...)` call, explicitly list in the Changed Files entry all flags that the old `run-*.sh` accepted and must be propagated to the new Skill interface. Example notation:

```
`skills/auto/SKILL.md`: replace `run-verify.sh $NUMBER --base $BASE_BRANCH` with `Skill(verify, args="$NUMBER --base $BASE_BRANCH")` — propagated flags: `--base`
```

If any flags are not yet supported by the new Skill interface, note them as a follow-up item. This prevents propagated-flag omissions at the Spec stage (example: Issue #485 retro — `--base` flag dropped during `run-verify.sh` → Skill migration).

**Simplicity rule (see $STEERING_DOCS_PATH/tech.md "Spec Simplicity Rules"):**

Keep implementation step count and pre-merge verification item count within the SPEC_DEPTH limit (light: 5 each; full: 10 each). Group related steps if limits are exceeded.

**Smoke Test section consideration:**

When the Issue involves real external or MCP tool calls (examples: verify commands include `mcp_call`, or `capabilities.mcp` is configured and the Issue body references an MCP tool), propose an optional `## Smoke Test` section in the Spec. Record at least one full-mode verify command (`mcp_call` / `command` / `http_status`) there. Use plain bullets (`- `) with no checkboxes, same as the Verification section. `/code` will execute this section in full mode before commit/push.

**SPEC_DEPTH=light — lightweight template (5-section structure):**

**Type-based section control (light template, exhaustive):**
- `ISSUE_TYPE=Bug`: add "Reproduction Steps" and "Root Cause" sections after Overview
- `ISSUE_TYPE=Feature` / `ISSUE_TYPE=Task` / `ISSUE_TYPE=unset`: no additional sections

```markdown
# Issue #$NUMBER: $TITLE

## Overview
(Issue requirements summary)

<!-- ISSUE_TYPE=Bug only: add these 2 sections -->
## Reproduction Steps
(steps to reproduce the bug)

## Root Cause
(root cause analysis)

## Changed Files
- file1: change content

## Implementation Steps
1. Step 1 (→ acceptance criteria A)

## Verification
### Pre-merge
- <!-- verify: file_contains "path/to/file" "keyword" --> verification item 1

### Post-merge
- confirmation item 1

## Smoke Test

**(Optional. Include only when the Issue involves real external or MCP tool calls. Use existing verify commands — mcp_call, command, http_status, etc. Omit if not applicable.)**
- <!-- verify: mcp_call "tool_name" '{"arg":"value"}' "expected_keyword" --> smoke check description

## Notes
(if applicable)
```

**SPEC_DEPTH=full — full template:**

**Type-based section control (full template, exhaustive):**

| ISSUE_TYPE | Added sections | Omitted sections |
|-----------|---------------|-----------------|
| `Bug` | "Reproduction Steps" and "Root Cause" after Overview | none |
| `Feature` | "Alternatives Considered" after Implementation Steps | none |
| `Task` | none | Omit "Uncertainty" and "UI Design" |
| `unset` | none (maintain existing behavior) | none |

```markdown
# Issue #$NUMBER: $TITLE

## Overview
(Issue requirements summary)

<!-- ISSUE_TYPE=Bug only -->
## Reproduction Steps
(steps to reproduce the bug)

## Root Cause
(root cause analysis and fix approach validity)

## Changed Files
- file1: change content
- file2: change content

## Implementation Steps

**Step recording rules:**
- **Step numbers**: integers only (Step 1, 2, 3...). No decimal numbers (Step 1.5, etc.). Renumber subsequent steps when inserting new ones.
- **Dependencies**: note "(after N)" for sequential deps, "(parallel with N, M)" for parallel-safe steps
- **Acceptance criteria mapping**: note "(→ acceptance criteria X)" for each step
- **post-merge manual steps are required**: even when an AC's verify-type is `post-merge manual`, the corresponding implementation step is mandatory in the current PR. "post-merge manual" describes how the AC is verified (human observation after merge), not whether implementation can be deferred. Record the step explicitly so the code phase does not skip it.
- **Insertion position**: specify by nearby code context (e.g., "immediately before `--dangerously-skip-permissions`") rather than line numbers. Line numbers shift as files change and become unreliable guides for implementation.

1. Step 1 (→ acceptance criteria A)
2. Step 2 (after 1) (→ acceptance criteria B)
3. Step 3 (parallel with 1, 2) (→ acceptance criteria C)

<!-- ISSUE_TYPE=Feature and SPEC_DEPTH=full only -->
## Alternatives Considered
(comparison of adopted implementation approach vs. rejected alternatives)

## Verification
### Pre-merge
- <!-- verify: file_contains "path/to/file" "keyword" --> verification item 1
- <!-- verify: command "bash scripts/validate-permissions.sh" --> verification item 2

### Post-merge
- confirmation item 1
- confirmation item 2

## Smoke Test

**(Optional. Include only when the Issue involves real external or MCP tool calls. Use existing verify commands — mcp_call, command, http_status, etc. Omit if not applicable.)**
- <!-- verify: mcp_call "tool_name" '{"arg":"value"}' "expected_keyword" --> smoke check description

## UI Design

**(Include only for Issues involving UI. Omit if not applicable. See `skills/spec/figma-design-phase.md` for field definitions)**
<!-- ISSUE_TYPE=Task: omit UI Design section -->

## Tool Dependencies

**(Required tool permissions for implementation. Include only if allowed-tools frontmatter additions are needed)**

### Bash Command Patterns
- `command-pattern`: usage description (e.g., `gh issue comment:*` — post Issue comments)

### Built-in Tools
- `Tool name`: usage description (e.g., `Read` — file reading, `Write` — file writing)

### MCP Tools
- `Tool name`: usage description (e.g., `mcp__plugin_figma_figma__get_screenshot` — Figma screenshot)

**(Write "none" for inapplicable categories. No need to list tools already in allowed-tools)**

## Uncertainty

**(Items requiring verification before implementation. Write "none" if not applicable)**
<!-- ISSUE_TYPE=Task: omit Uncertainty section -->

- **[Item name]**: description of the uncertainty
  - **Verification method**: how to verify (official docs, bats test, prototype, etc.)
  - **Impact scope**: affects Implementation Steps X, Y

## Notes
(if applicable)
```

**Self-review (internal consistency check) (SPEC_DEPTH=full only):**

Before committing the Spec, verify internal consistency:

- **Remove or mark rejected alternatives**: if a decision was made, remove or mark as "not adopted" any remaining alternative descriptions
- **Implementation steps vs. acceptance criteria alignment**: verify each step maps to acceptance criteria and no criteria are uncovered
- **Changed files vs. implementation steps alignment**: verify all listed changed files are covered in implementation steps and vice versa
- **Notes vs. changed files alignment**: if Notes contain file update instructions, verify those files are in the changed-files list
- **Template file reference workflow check** (only if implementation steps include reading a template file):
  - Verify fallback behavior (error message, default value) when the template file is missing is documented in implementation steps
  - Verify consistent use of structured format (fixed text) vs. placeholder format (variable content)
- **Post-merge skill name alignment**: if `## Verification > Post-merge` mentions a target skill name (`/foo`), verify it matches the target skill in the Issue purpose

### Step 11: Title Drift Check

Read `${CLAUDE_PLUGIN_ROOT}/modules/title-normalizer.md` and follow the "Title Drift Check" section. Detect semantic drift between the current title and the updated Issue body (drift detection source: Issue body only — do not include Spec content). Update the title if drift is found.

### Step 12: Commit Spec

Commit the Spec (push is done in Step 14 Worktree Exit):

```bash
git add $SPEC_PATH/issue-$NUMBER-short-title.md
git commit -s -m "Add design for issue #$NUMBER"
```

```bash
git log -1 --format='%B' | grep -q "^Signed-off-by:" || { echo "ERROR: missing sign-off"; exit 1; }
```

### Step 13: Spec Retrospective

**SPEC_DEPTH=full only. Skip if SPEC_DEPTH=light.**

Reflect on the specification phase and present improvement suggestions to the user if any.

**Retrospective scope**: this phase (specification)
**Sources**: Issue body, codebase investigation results

**Retrospective aspects:**

| Aspect | Check |
|--------|-------|
| Spec ambiguity | Were there ambiguous expressions or missing information that `/issue` should have resolved? |
| Unexpected complexity | Did codebase investigation reveal more complexity than expected? |
| Volume of uncertainty | Are there many items in the Spec's "Uncertainty" section? |

**Steps:**

1. Identify improvements from the above aspects (organize observations from the design process)
2. **Transfer issue retrospective**:
   - Fetch Issue comments with `gh issue view $NUMBER --json comments` and search for `## issue retrospective` (also search `## spec retrospective` for backward compatibility)
   - If found, prepend it to the Spec as `## issue retrospective` before the `## spec retrospective` section
3. **Persist spec retrospective**:
   - Append `## spec retrospective` section to the end of the Spec
   - If improvements exist, record in spec retrospective only (do not create issues; improvement proposals are aggregated in the `/verify` phase)

**Retrospective writing discipline:**

- One entry per learning — do not bundle multiple lessons into a single bullet
- Record both corrections (what was wrong) and confirmed approaches (what worked and why)
- Link related entries across retrospective sections when one finding affects another
- Do not duplicate what the repository or git history already records (commit messages, PR descriptions, file diffs) — note only the reasoning and judgment that is not captured elsewhere
- Update or delete entries found to be incorrect in subsequent runs; stale or wrong entries degrade memory quality

**Spec retrospective template:**
```markdown
## spec retrospective

### Minor observations
- (items worth noting but not worth filing as issues)

### Judgment rationale
- (decisions and reasoning on spec ambiguity)

### Uncertainty resolution
- (uncertainties at design time and their resolution)
```

**Steps:**
1. Write "Nothing to note" in each section if nothing to record
2. If issue retrospective found, transfer it first (Edit tool to prepend to Spec)
3. Edit tool to append spec retrospective to Spec end
4. **Phase Handoff write** (spec is the first execution phase — write only, no read):
   Read `${CLAUDE_PLUGIN_ROOT}/modules/phase-handoff.md` and follow the "Write Procedure" section.
   Parameters: `SPEC_PATH`, `ISSUE_NUMBER=$NUMBER`, `PHASE_NAME=spec`.
   Include the handoff write in the same commit (next step).
5. Additional commit (push in Step 14 Worktree Exit):
   ```bash
   git add $SPEC_PATH/issue-$NUMBER-short-title.md
   git commit -s -m "Add retrospective notes for issue #$NUMBER"
   ```
   ```bash
   git log -1 --format='%B' | grep -q "^Signed-off-by:" || { echo "ERROR: missing sign-off"; exit 1; }
   ```

### Step 14: Worktree Exit (merge-to-main)

Read `${CLAUDE_PLUGIN_ROOT}/modules/worktree-lifecycle.md` and follow the "Exit: merge-to-main" section.

`ENTERED_WORKTREE` value determines behavior:
- `ENTERED_WORKTREE=true`: ExitWorktree("keep") → merge → push → cleanup
- `ENTERED_WORKTREE=false`: run `git push origin main` directly

### Step 15: Issue Comment

Post a design summary comment to the target Issue.

**Comment content:**
- Key implementation steps extracted from the Spec (with dependencies and acceptance criteria mapping)
- Spec link in GitHub blob URL format

Write to `.tmp/issue-comment-$NUMBER.md` using the Write tool, then post:

```bash
mkdir -p .tmp
${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh $NUMBER .tmp/issue-comment-$NUMBER.md
rm -f .tmp/issue-comment-$NUMBER.md
```

Template:
- `## Design Complete`
- `### Implementation Steps` — numbered list with dependencies and acceptance criteria mapping
- Spec link: `[issue-$NUMBER-short-title.md](https://github.com/{REPO}/blob/main/$SPEC_PATH/issue-$NUMBER-short-title.md)`

### Step 16: Label Transition (design complete)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh $NUMBER ready
```

### Step 17: Opportunistic Verification

If `opportunistic-verify: true` is set in `.wholework.yml`, read `${CLAUDE_PLUGIN_ROOT}/modules/opportunistic-verify.md` and follow "Processing Steps". Skill name: `/spec`. Skip if not set.

### Step 18: Size-to-Workflow Determination (for Step 19)

Read `${CLAUDE_PLUGIN_ROOT}/modules/size-workflow-table.md` and re-evaluate Size using the 2-axis method.

**Steps:**

1. Count files in the Spec's "Changed Files" section and re-evaluate Size using the 2-axis method from `size-workflow-table.md`

2. Get the triage-time Size for comparison (Project field first, label fallback):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/get-issue-size.sh $NUMBER
   ```

3. If re-evaluation differs from triage-time Size, read `${CLAUDE_PLUGIN_ROOT}/modules/project-field-update.md` and update Size (steps 1→2→3→4). Use label fallback (step 5) only if GraphQL fails. When GitHub Projects is not configured, step 1 returns empty `projectsV2.nodes` and falls through to step 5 automatically.

4. Store the final workflow route as `ROUTE`:
   - `XS` or `S` → `patch`
   - `M` or `L` → `pr`
   - `XL` → `sub_issue`

### Step 19: Completion Message

Output "Design complete. Spec created, committed, pushed, and Issue comment posted." as a fixed prefix.

Then read `${CLAUDE_PLUGIN_ROOT}/modules/next-action-guide.md` and follow the "Processing Steps" section with:
- `SKILL_NAME=spec`
- `ISSUE_NUMBER=$NUMBER`
- `ROUTE=$ROUTE`
- `SIZE={fetched size}`
- `RESULT=success`
- `BLOCKED_BY_OPEN=$HAS_OPEN_BLOCKING`

Then read `${CLAUDE_PLUGIN_ROOT}/modules/steering-hint.md` and follow the "Processing Steps" section.

---

## Notes

- This skill covers Spec creation, commit, push, and Issue comment only
- Implementation is not performed here
- After Step 12 commit → Step 13 retrospective → Step 14 Worktree Exit+push → Step 15 Issue comment → Step 17 opportunistic verification → Step 19 completion message
- Always use the Write tool for temp files. Shell redirects trigger confirmation prompts
