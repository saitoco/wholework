---
type: domain
skill: spec
load_when:
  file_exists_any: [scripts/validate-skill-syntax.py]
  spec_depth: full
---

# Skill Development Constraint Checklist

## Purpose

Provides MUST/SHOULD constraints for designing implementation steps for SKILL.md, modules, and agent changes in skill-development projects (projects with `validate-skill-syntax.py`).

## Constraint checklist (MUST/SHOULD)

When designing implementation steps for SKILL.md/modules/agents changes:

MUST constraints (detected by validator — exhaustive):

| Constraint | Content | Detection |
|-----------|---------|-----------|
| No half-width `!` | No `!` in SKILL.md body outside code fences, inline code, HTML comments | validate-skill-syntax.py |
| No decimal step numbers | No `Step 1.5` etc. Use integers only | validate-skill-syntax.py |
| No Phase-only headings | Do not use `### Phase N:` alone; use `### Step N: title (Phase N)` | validate-skill-syntax.py |
| `command` hint path format | Use repo-relative paths (`scripts/xxx`) in `<!-- verify: command "..." -->` | validate-skill-syntax.py |

SHOULD constraints (best practices, manual check — examples):

| Constraint | Content | Reference |
|-----------|---------|-----------|
| Heading format | Use `### Step N: title` for procedural steps | tech.md |
| Read instruction placement | Place shared module Read instructions immediately after step heading | tech.md |
| Module standard structure | New modules follow 4-section structure (Purpose/Input/Processing Steps/Output) | tech.md |
| Example/exhaustive markers | Add (examples), (exhaustive), (project-dependent) markers to lists/tables | tech.md |
| Input interface | Explicitly state input/output for new components in implementation steps | tech.md |
| Edge cases | Include error cases (empty args, missing files, uncommitted changes, permission errors) in new skill/step design | #423 |
| Argument parser edge cases | Include unclosed quotes, empty values, invalid chars, escape edge cases in test case lists | #672 |
| Verify existing parser behavior | When reusing parsers/libraries, include steps to verify actual behavior (quoting, spaces) in the Spec | #825 |
| New tools in allowed-tools | When introducing new tools (MCP, ToolSearch), include allowed-tools addition in acceptance criteria | #690 |
| New gh command patterns in allowed-tools | When adding new `gh` subcommand patterns (`gh issue view:*`, `gh run list:*`, etc.), include `allowed-tools` frontmatter update in Spec's changed-files list | #75 |
| KNOWN_TOOLS sync | When adding tools to allowed-tools, also include `validate-skill-syntax.py` KNOWN_TOOLS update | #760 |
| Shared module reference paths | Use full `${CLAUDE_PLUGIN_ROOT}/modules/xxx.md` paths (no abbreviations) | tech.md |
| False positive exclusion set | Note false-positive exclusion policy for broadly-used terms (Task, Agent, etc.) in validation implementations | #810 |
| bats self-reference exclusion | When a detection script's bats test file contains the detected patterns as test fixtures, add self-reference exclusion (`grep -v 'tests/xxx.bats'`) to the script invocation in Implementation Steps to prevent false positives | #272 |
| `settings.json` Skill entry | Include `settings.json` `Skill(skill-name)` permission for new skills | #725 |
| Read instruction for extracted modules | When extracting to a module, write Read instruction as "read `${CLAUDE_PLUGIN_ROOT}/modules/xxx.md` and follow the `Processing Steps` section" | #716 |
| `git add -f` for .gitignore targets | Note `git add -f` requirement in implementation steps for `.gitignore`-tracked files | #901 |
| Post-merge skill name alignment | Verify skill name in `## Verification > Post-merge` matches the target skill in Issue purpose | #684 |
| Patch route CI verify | For patch route Issues (no PR), use `github_check "gh run list"` instead of `github_check "gh pr checks"` (no PR exists in patch route). See `${CLAUDE_PLUGIN_ROOT}/modules/verify-classifier.md` | #112 |
| Permission pattern verification | When implementation includes `settings.json` `permissions.allow` pattern changes, test with simple invocation only (no shell operators: `2>&1`, `|`, `&&`); restart the session before testing (settings.json is not hot-reloaded); ensure no conflicting pre-approval in `settings.local.json` | #82 |
| GitHub Actions workflow CI verify | When `.github/workflows/*.yml` is changed, include both `file_contains` (config content) and `github_check "gh run list"` (CI execution result) in acceptance criteria. See `${CLAUDE_PLUGIN_ROOT}/modules/verify-patterns.md` | #73 |
| External GitHub Action required inputs | When `.github/workflows/*.yml` is in the changed files and references an external Action, check the Action's `action.yml` (via WebFetch or repository reference) and verify all `required: true` inputs are included in the snippet | #144 |
| External command dependencies | When Implementation Steps use commands with external dependencies (packages requiring installation: apt packages, brew formulas, npm modules, OS-specific binaries), include install steps for each package explicitly | #179 |
| Audit report Findings/Remediation consistency | When Implementation Steps include audit report generation: add a step to verify that each row in the Remediation table has a corresponding entry in the Findings section | #238 |
| Architecture Decisions impact | When adding new `.wholework.yml` keys or new CLI flags passed to `claude -p` in `run-*.sh`, check the Architecture Decisions section in `docs/tech.md` and include `tech.md` in the Changed Files list | #250 |
| Documentation condition step | When acceptance criteria contain a "documentation condition" (e.g., "X is documented", "document X", "ドキュメント化"), add a corresponding documentation step to Implementation Steps — omitting it leaves the condition permanently unchecked | #273 |
| New subsection heading level | When Implementation Steps describe adding a new subsection to a target implementation file, explicitly specify the heading level (e.g., h4/`####`) so `/code` implementers do not need to infer the level from the surrounding document structure | #296 |
| Counter variable change | When describing counter variable changes (increment/decrement/reset) in Implementation Steps, explicitly state: the value before the change, the value after the change, and the timing of the change (before or after which operation) | #344 |
| read-then-write jq guard | When describing read-then-write operations (using an existing file as input for writes), explicitly state the jq failure guard (e.g., `|| die "..."`) in Implementation Steps | #345 |
