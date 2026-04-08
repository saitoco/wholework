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
