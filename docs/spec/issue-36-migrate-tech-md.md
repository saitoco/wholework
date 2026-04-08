# Issue #36: Migrate and refactor tech.md as steering document

## Overview

Migrate `docs/tech.md` from claude-config to wholework as a steering document. Translate to English, remove claude-config-specific sections, and redistribute Coding Conventions to appropriate locations. Most Coding Conventions are already covered by existing mechanisms (validate-skill-syntax.py, Spec SHOULD constraints, verify-patterns.md) or are obsolete for Claude 4.6. Only 3 items need redistribution to `modules/skill-dev-checks.md`.

## Changed Files

- `docs/tech.md`: new file — steering document with Language/Runtime, Key Dependencies, Architecture Decisions (rewritten for plugin architecture), Testing Strategy, Forbidden Expressions
- `modules/skill-dev-checks.md`: add 3 conventions from Coding Conventions (Read instruction placement rule, exhaustive/example markers, modules caller condition propagation)
- `docs/structure.md`: add `tech.md` entry to Directory Layout

## Implementation Steps

1. Create `docs/tech.md` with steering-level sections in English (→ acceptance criteria A-E):
   - Frontmatter: `type: steering`, `ssot_for: [tech-stack, forbidden-expressions]`
   - **Language and Runtime**: Bash/Shell, Markdown, Python, GitHub Actions (same as claude-config but in English)
   - **Key Dependencies**: Claude Code CLI, GitHub CLI, GitHub Copilot, bats
   - **Architecture Decisions**: rewrite for plugin architecture — remove symlink deploy, add plugin-dir model, keep fork context table, skills-based workflow, shared module pattern, spec-first, progressive disclosure
   - **Testing Strategy**: simplify — bats, validate-skill-syntax.py, acceptance checks (3 tools only)
   - **Forbidden Expressions**: translate existing table to English, keep terminology migration scope rule
   - **No Coding Conventions section** — all redistributed or deleted

2. Add 3 conventions to `modules/skill-dev-checks.md` "Design-Time Checks" section (→ acceptance criteria F):
   - **Read instruction placement rule**: Read instructions for shared modules must be placed immediately after the step heading, not buried in numbered lists or tables
   - **Exhaustive/example markers**: Lists/tables in SKILL.md/modules must use "(examples)", "(exhaustive)", or "(project-dependent)" markers
   - **Modules caller condition propagation**: When modules have execution conditions (SPEC_DEPTH branching, etc.), the calling SKILL.md must also state the same condition

3. Update `docs/structure.md` Directory Layout to include `tech.md` (→ acceptance criteria G)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/tech.md" --> `docs/tech.md` exists
- <!-- verify: grep "type: steering" "docs/tech.md" --> frontmatter has `type: steering`
- <!-- verify: grep "Language and Runtime" "docs/tech.md" --> Language and Runtime section exists
- <!-- verify: grep "Architecture Decisions" "docs/tech.md" --> Architecture Decisions section exists
- <!-- verify: grep "Forbidden Expressions" "docs/tech.md" --> Forbidden Expressions section exists
- <!-- verify: section_not_contains "docs/tech.md" "## Architecture" "symlink" --> No symlink references in Architecture Decisions
- <!-- verify: file_not_contains "docs/tech.md" "Build and Deploy" --> No Build and Deploy section
- <!-- verify: file_not_contains "docs/tech.md" "Path Conventions" --> No Path Conventions section
- <!-- verify: file_not_contains "docs/tech.md" "settings.local.json" --> No settings.local.json content
- <!-- verify: file_not_contains "docs/tech.md" "install.sh" --> No install.sh references
- <!-- verify: grep "Read instruction" "modules/skill-dev-checks.md" --> skill-dev-checks.md contains Read instruction placement rule
- <!-- verify: grep "exhaustive" "modules/skill-dev-checks.md" --> skill-dev-checks.md contains exhaustive/example marker rule
- <!-- verify: grep "caller condition" "modules/skill-dev-checks.md" --> skill-dev-checks.md contains caller condition propagation rule
- <!-- verify: grep "tech.md" "docs/structure.md" --> structure.md references tech.md

### Post-merge

- `/spec` execution references `docs/tech.md` Forbidden Expressions

## Code Retrospective

### Deviations from Design
- The "caller condition" phrase was not included in the initial write of the Caller Condition Propagation section in skill-dev-checks.md. The acceptance check `grep "caller condition"` failed, requiring a fix to include that exact phrase in the section text. Added "caller condition branching" wording to align with the acceptance check.

### Design Gaps/Ambiguities
- N/A

### Rework
- skill-dev-checks.md Caller Condition Propagation section: initial wording described "execution conditions dependent on the caller" but did not include the literal phrase "caller condition" required by the acceptance check. Reworded to include "caller condition branching" and "caller condition" explicitly.

## Review Retrospective

### Spec vs. Implementation Divergence Patterns

The Key Dependencies table in `docs/tech.md` contains `Code review (Step 6)` which references a step number from claude-config's review workflow rather than wholework's current Step 7 (External Review Integration). Migration tasks that translate step-number references from source documents should verify step numbers against the target project's current SKILL.md.

### Recurring Issues

Nothing to note.

### Acceptance Criteria Verification Difficulty

All 14 pre-merge conditions verified as PASS with mechanical checks. The one CONSIDER-level issue (step number reference) was not covered by acceptance criteria — adding a `file_not_contains "docs/tech.md" "Step 6"` check would have caught this at code phase.

## Notes

- **Coding Conventions section eliminated from tech.md**: Of 25+ conventions in claude-config's tech.md, analysis shows:
  - 3 items redistributed to `skill-dev-checks.md` (Read placement, markers, caller conditions)
  - ~10 items already covered by existing mechanisms (validate-skill-syntax.py, Spec SHOULD constraints, verify-patterns.md, SKILL.md templates)
  - ~5 items obsolete for Claude 4.6 (agent post-verification, heading reference updates, variable format unification, spec action concreteness, code retrospective skip recording)
  - ~7 items claude-config specific (symlink paths, settings.local.json, install.sh, file edit paths)
- **Architecture Decisions rewrite scope**: Remove symlink deploy, `/auto` run-*.sh description, `~/.claude/` path references. Add `--plugin-dir` distribution model, `$CLAUDE_PLUGIN_ROOT` variable reference
- **Forbidden Expressions translation**: Keep existing forbidden terms but translate descriptions and alternatives to English. The terminology migration scope rule section is also translated
