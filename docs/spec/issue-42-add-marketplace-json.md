# Issue #42: plugin: Add marketplace.json and fix README Install section

## Overview

The README Install section contains an invalid `pluginDirectories` setting that does not exist in Claude Code. The repo also lacks a `marketplace.json` required for marketplace-based plugin installation. Fix the README and add the marketplace manifest.

## Reproduction Steps

1. Follow README instructions to add `pluginDirectories` to Claude Code settings
2. The setting is silently ignored — plugin is not loaded

## Root Cause

`pluginDirectories` was never a valid Claude Code setting key. The correct persistent installation uses the marketplace system (`/plugin marketplace add` + `/plugin install`), which requires a `.claude-plugin/marketplace.json` file.

## Changed Files

- `.claude-plugin/marketplace.json`: new file — marketplace manifest
- `README.md`: rewrite Install section (remove `pluginDirectories`, add marketplace commands)
- `docs/structure.md`: add `marketplace.json` to directory layout and update Install section

## Implementation Steps

1. Create `.claude-plugin/marketplace.json` with marketplace name `saitoco-wholework` and plugin entry (→ acceptance criteria A-D)
2. Rewrite `README.md` Install section: remove `pluginDirectories` block, add `/plugin marketplace add` + `/plugin install` as primary method, keep `--plugin-dir` as development option (→ acceptance criteria E-I)
3. Update `docs/structure.md`: add `marketplace.json` to `.claude-plugin/` in directory layout tree, update Install section to mention marketplace-based installation (→ acceptance criteria J)

## Verification

### Pre-merge

- <!-- verify: file_exists ".claude-plugin/marketplace.json" --> `.claude-plugin/marketplace.json` has been created
- <!-- verify: file_contains ".claude-plugin/marketplace.json" "saitoco-wholework" --> marketplace.json contains `name: "saitoco-wholework"`
- <!-- verify: grep "\"wholework\"" ".claude-plugin/marketplace.json" --> marketplace.json contains plugin entry with name `wholework`
- <!-- verify: grep "\"\.\/\"" ".claude-plugin/marketplace.json" --> marketplace.json contains relative source `"./"`
- <!-- verify: file_not_contains "README.md" "pluginDirectories" --> README.md no longer references the invalid `pluginDirectories` setting
- <!-- verify: grep "plugin marketplace add" "README.md" --> README.md contains `/plugin marketplace add` instruction
- <!-- verify: grep "plugin install" "README.md" --> README.md contains `/plugin install` instruction
- <!-- verify: grep "saitoco-wholework" "README.md" --> README.md references the correct marketplace name `saitoco-wholework`
- <!-- verify: grep "plugin-dir" "README.md" --> README.md retains `--plugin-dir` as a development option
- <!-- verify: file_contains "docs/structure.md" "marketplace.json" --> docs/structure.md lists marketplace.json in directory layout

### Post-merge

- Running `/plugin marketplace add saitoco/wholework` in Claude Code successfully adds the marketplace <!-- verify-type: manual -->

## Notes

- `docs/tech.md` line 29 mentions `--plugin-dir` in Architecture Decisions. No change needed — `--plugin-dir` remains valid for development use and correctly describes the runtime mechanism.
- `owner.name` in marketplace.json uses "Saito & Co." as placeholder. Adjust if needed.

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Acceptance conditions were well-scoped and fully auto-verifiable (10/11 conditions had `<!-- verify: ... -->` hints). The one manual condition (`verify-type: manual`) for runtime marketplace installation is appropriately deferred, as it requires actual Claude Code execution.
- No Issue Retrospective or Spec Retrospective sections found in Spec — these phases may have been skipped or combined in the patch route.

#### design
- Design was straightforward: 3 files changed, clear 1:1 mapping from implementation steps to acceptance criteria. No design ambiguities were noted.

#### code
- Single clean commit `a1e869b` with no rework or fixup patterns. Code Retrospective recorded N/A for all dimensions.
- Patch route (direct push to main) was appropriate for this small documentation + file addition change.

#### review
- Patch route: no formal review phase. Given the minimal scope (JSON manifest + README rewrite + structure.md update), skipping review was acceptable.

#### merge
- Direct push to main via patch route. No conflicts or CI failures detected in git log.

#### verify
- All 10 pre-merge conditions passed on re-verification. No regressions detected.
- Post-merge manual verification (`/plugin marketplace add saitoco/wholework`) remains as user verification item; `phase/verify` label assigned.

### Improvement Proposals
- N/A
