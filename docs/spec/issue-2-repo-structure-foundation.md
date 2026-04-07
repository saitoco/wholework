# Issue #2: structure: Design repository layout and create foundation files

## Overview

Establish the wholework repository foundation: directory layout, symlink-based installer, package.json for future npx support, and Apache 2.0 license. Document everything in `docs/structure.md` as a steering document.

### Install target mapping

| Repo directory | Install destination | Notes |
|---|---|---|
| `skills/` | `~/.claude/skills/wholework/` | Each skill as a subdirectory |
| `modules/` | `~/.claude/skills/wholework/modules/` | Co-located with skills, single reference path |
| `agents/` | `~/.claude/agents/wholework/` | Agent definitions |
| `scripts/` | `~/.claude/scripts/wholework/` | Helper scripts, namespaced to avoid conflicts |

## Changed files

- `docs/structure.md`: New — repository layout, install mapping, directory conventions (steering document)
- `install.sh`: New — symlink-based installer with `--uninstall` support
- `package.json`: New — minimal (name, version, bin, license)
- `LICENSE`: New — Apache License 2.0
- `README.md`: Update — add install instructions and project description

## Implementation steps

1. Create `docs/structure.md` with Repository Layout section (tree diagram of `skills/`, `modules/`, `agents/`, `scripts/`, `docs/`) and Install section documenting symlink targets (-> acceptance criteria 1-6)

2. Create `install.sh` with symlink creation for all four directories. Support `--uninstall` flag to remove symlinks. Use `ln -sfn` for idempotent symlink creation. Target paths: `~/.claude/skills/wholework/`, `~/.claude/skills/wholework/modules/`, `~/.claude/agents/wholework/`, `~/.claude/scripts/wholework/` (-> acceptance criteria 7-11)

3. Create `package.json` with name `wholework`, version `0.1.0`, license `Apache-2.0`, bin pointing to `install.sh` (-> acceptance criteria 12-13)

4. Create `LICENSE` with full Apache License 2.0 text (-> acceptance criteria 14)

5. Update `README.md` with project description and install instructions referencing `install.sh` (-> SHOULD: doc-checker guidance)

## Verification

### Pre-merge
- <!-- verify: file_exists "docs/structure.md" --> `docs/structure.md` exists
- <!-- verify: section_contains "docs/structure.md" "## Repository Layout" "skills/" --> Repository Layout contains `skills/`
- <!-- verify: section_contains "docs/structure.md" "## Repository Layout" "modules/" --> Repository Layout contains `modules/`
- <!-- verify: section_contains "docs/structure.md" "## Repository Layout" "agents/" --> Repository Layout contains `agents/`
- <!-- verify: section_contains "docs/structure.md" "## Repository Layout" "scripts/" --> Repository Layout contains `scripts/`
- <!-- verify: section_contains "docs/structure.md" "## Install" "install.sh" --> Install section references install.sh
- <!-- verify: file_exists "install.sh" --> `install.sh` exists
- <!-- verify: file_contains "install.sh" "skills/wholework" --> install.sh targets skills/wholework/
- <!-- verify: file_contains "install.sh" "modules" --> install.sh handles modules
- <!-- verify: file_contains "install.sh" "agents/wholework" --> install.sh targets agents/wholework/
- <!-- verify: grep "scripts" "install.sh" --> install.sh handles scripts
- <!-- verify: file_exists "package.json" --> package.json exists
- <!-- verify: json_field "package.json" ".name" "wholework" --> package.json name is wholework
- <!-- verify: file_exists "LICENSE" --> LICENSE file exists

### Post-merge
- Run `install.sh` and verify symlinks are created at expected paths <!-- verify-type: manual -->
- Run `install.sh --uninstall` and verify symlinks are removed <!-- verify-type: manual -->

## Notes

- `modules/` is placed under `~/.claude/skills/wholework/modules/` (not `~/.claude/modules/`) to co-locate with skills and avoid duplicate module loading across different packages
- `scripts/` uses `~/.claude/scripts/wholework/` namespace to avoid conflicts with other packages' scripts while following the `~/.claude/scripts/` convention
- `install.sh` should be POSIX-compatible (`#!/bin/sh`) for maximum portability
- `package.json` bin field enables future `npx wholework` usage
