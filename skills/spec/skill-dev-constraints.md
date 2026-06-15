---
type: domain
skill: spec
domain: skill-dev
load_when:
  file_exists_any: [scripts/validate-skill-syntax.py]
  spec_depth: full
applies_to_proposals:
  file_patterns:
    - skills/spec/SKILL.md
    - modules/*.md
  content_keywords:
    - SKILL.md
    - ${CLAUDE_PLUGIN_ROOT}
    - skill-dev
    - validate-skill-syntax
    - spec constraints
  rewrite_target:
    - from: skills/spec/SKILL.md
      to: skills/spec/skill-dev-constraints.md
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
| Test replacement scenario coverage | When implementation includes deleting or replacing existing test cases (e.g., bats `@test` blocks), verify that all scenarios covered by deleted tests are present in new or remaining tests | #526 |
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
| macOS system-level debug fallback | When implementation steps include macOS system-level debugging procedures (e.g., `fs_usage`, Console.app privacy logs) requiring interactive execution, explicitly state that `--non-interactive` mode uses static analysis + hypothesis evaluation as an alternative | #378 |
| Design Gaps → Implementation Steps backfill | When recording specific implementation knowledge (variable names, call forms, parameter passing methods) in spec retrospective sections (e.g., `## Design Gaps/Ambiguities`, `## Implementation Notes`), also write it directly in the corresponding `## Implementation Steps` body. `code` and `review` phases follow Implementation Steps sequentially — knowledge recorded only in retrospective sections is structurally prone to being overlooked | #579 |
| ブランチ分岐ロジックの挙動全列挙 | When defining a helper/watchdog/runner with `if`/`case` branch conditions in the Spec, enumerate all branches with 正常終了条件 / timeout 条件 / kill 条件 / error path / 各ブランチでの監視継続有無. Vague descriptions ("同様に処理", "適切にハンドル") are forbidden — specify concrete thresholds, timer values, and exit signals. See the section below for details | #642 |

## ブランチ分岐ロジックの挙動全列挙

When a Spec defines a helper script, watchdog, or runner that has `if`/`case` branches with different behaviors, enumerate all branches exhaustively. For each branch, specify:

- **正常終了条件**: exact exit code, output format, and return value that indicates success
- **timeout 条件**: timer source, threshold value in seconds, and action taken on timeout (signal, log message, exit code)
- **kill 条件**: signal type (`SIGKILL`/`SIGTERM`/etc.), who sends it, and under what exact condition
- **error path**: what is logged, what exit code is returned, and whether retry/restart occurs
- **各ブランチでの監視継続有無**: whether the watchdog/monitoring loop continues after this branch executes

### Anti-patterns

The following vague expressions are **forbidden** in Spec branch definitions:

| Forbidden expression | Reason | Required alternative |
|----------------------|--------|----------------------|
| 「同様に処理」 | Does not specify which conditions apply to this branch | List each condition individually per branch |
| 「適切にハンドル」 | Leaves the handling undefined | Specify the exact signal, exit code, and log output |
| 「必要に応じて」 | Makes the condition ambiguous | State the exact threshold or condition trigger |

### Example — `claude-watchdog.sh` `OUTPUT_FORMAT_JSON` branch

**Background (#630)**: `scripts/claude-watchdog.sh` has an `OUTPUT_FORMAT_JSON` branch added when extending auto event log metrics. The branch's kill 条件 was left as 「同様に処理」 in the Spec, resulting in a 1800s true hang and watchdog kill during the code phase.

**Correct Spec form (after fix)**:

```
OUTPUT_FORMAT_JSON=1 branch of claude-watchdog.sh:
- 正常終了条件: claude subprocess exits with code 0; JSON output is written to stdout
- timeout 条件: WATCHDOG_TIMEOUT seconds (default 1800; overridable via WATCHDOG_TIMEOUT env var) elapsed since last stdout line; send SIGTERM to claude subprocess; exit 124
- kill 条件: SIGTERM ignored for >10 seconds after timeout; send SIGKILL to claude subprocess; exit 137
- error path: subprocess exits non-zero; pass exit code through; do not retry
- 監視継続: No — watchdog exits after subprocess terminates in all branches
```

The fix also added a bats test that sets `WATCHDOG_TIMEOUT=2` to override the default, making the timeout path testable in CI without a 1800s wait.

## LLM-assisted Skill Phase Test Strategy

When designing a skill phase that includes LLM inference (e.g., a phase that generates content via `claude -p` rather than purely deterministic script logic), split the test strategy into two layers and make both explicit in the Spec:

| Layer | What it covers | How to verify |
|-------|---------------|---------------|
| **Script layer (deterministic)** | CLI parsing, template rendering, file I/O, flag routing — all parts whose input/output is fully deterministic | bats / pytest unit tests; run pre-merge via `command` verify command |
| **LLM layer (non-deterministic)** | Draft quality, inference accuracy, generated content structure — parts that depend on model output | Observation AC + manual review; write as post-merge `verify-type: observation event=...` AC and have a human evaluate draft quality on first run |

**When to apply**: A skill phase is LLM-assisted when it invokes `claude -p` (or equivalent) to produce content, and bats tests cannot deterministically assert the output quality. The deterministic parts (flag parsing, file existence checks, output file creation) are still testable with bats.

**Example — `/audit auto-session --full` (#632)**:

The `--full` flag triggers a `claude -p` sub-agent call to generate an analysis report. Test strategy:
- Script layer: bats covers flag parsing (`--full` vs default), output file path construction, and fallback behavior when events log is empty.
- LLM layer: post-merge observation AC — "Run `/audit auto-session --full` on a session with events; confirm the report contains actionable proposals." Human reviewer evaluates draft quality on first production run.
