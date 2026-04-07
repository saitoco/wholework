# Repository Structure

This document describes the wholework repository layout and installation conventions.

## Repository Layout

```
wholework/
├── skills/              # Claude Code skills (one subdirectory per skill)
│   └── <skill-name>/
│       └── SKILL.md
├── modules/             # Shared modules referenced by skills
│   └── <module-name>.md
├── agents/              # Agent definitions
│   └── <agent-name>.md
├── scripts/             # Utility scripts used by skills and agents
│   └── <script-name>.sh
├── docs/                # Documentation and steering documents
│   ├── structure.md     # This file
│   └── spec/            # Issue specifications
├── install.sh           # Symlink-based installer
├── package.json         # npm package manifest (for future npx support)
├── LICENSE              # Apache License 2.0
├── README.md            # Project overview
└── CLAUDE.md            # Claude Code project instructions
```

## Install

Run `install.sh` to create symlinks from this repository into your `~/.claude/` directory:

```sh
./install.sh
```

To remove the installed symlinks:

```sh
./install.sh --uninstall
```

### Install target mapping

| Repository directory | Install destination | Notes |
|---|---|---|
| `skills/` | `~/.claude/skills/wholework/` | Each skill as a subdirectory |
| `modules/` | `~/.claude/skills/wholework/modules/` | Co-located with skills; single reference path |
| `agents/` | `~/.claude/agents/wholework/` | Agent definitions |
| `scripts/` | `~/.claude/skills/wholework/scripts/` | Co-located with skills; same pattern as modules |

### Design rationale

- `~/.claude/skills/wholework/` is a real directory (not a symlink). Individual skills are symlinked inside it as subdirectories, allowing `modules/` and `scripts/` to coexist as sibling symlinks.
- `modules/` and `scripts/` are placed under `~/.claude/skills/wholework/` rather than `~/.claude/modules/` or `~/.claude/scripts/` to avoid duplicate loading and keep the package self-contained.
- Symlinks are created with `ln -sfn` for idempotent installs (safe to run multiple times).
- `install.sh` is POSIX-compatible (`#!/bin/sh`) for maximum portability.

## Directory conventions

### `skills/`

Each skill lives in its own subdirectory containing a `SKILL.md` file. Skills are the primary unit of distribution for wholework.

### `modules/`

Shared markdown modules referenced by skills. Module files use the `.md` extension and follow the naming convention `<module-name>.md`.

### `agents/`

Agent definitions as markdown files. Each agent is a single `.md` file.

### `scripts/`

Shell scripts used by skills and agents. Scripts should be POSIX-compatible where possible.
