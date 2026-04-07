# Issue #2: structure: Design repository layout and create foundation files

## Overview

Establish the wholework repository foundation: directory layout, symlink-based installer, package.json for future npx support, and Apache 2.0 license. Document everything in `docs/structure.md` as a steering document.

### Install target mapping

| Repo directory | Install destination | Notes |
|---|---|---|
| `skills/` | `~/.claude/skills/wholework/` | Each skill as a subdirectory |
| `modules/` | `~/.claude/skills/wholework/modules/` | Co-located with skills, single reference path |
| `agents/` | `~/.claude/agents/wholework/` | Agent definitions |
| `scripts/` | `~/.claude/skills/wholework/scripts/` | Co-located with skills, same pattern as modules |

## Changed files

- `docs/structure.md`: New — repository layout, install mapping, directory conventions (steering document)
- `install.sh`: New — symlink-based installer with `--uninstall` support
- `package.json`: New — minimal (name, version, bin, license)
- `LICENSE`: New — Apache License 2.0
- `README.md`: Update — add install instructions and project description

## Implementation steps

1. Create `docs/structure.md` with Repository Layout section (tree diagram of `skills/`, `modules/`, `agents/`, `scripts/`, `docs/`) and Install section documenting symlink targets (-> acceptance criteria 1-6)

2. Create `install.sh` with symlink creation for all four directories. Support `--uninstall` flag to remove symlinks. Use `ln -sfn` for idempotent symlink creation. Target paths: `~/.claude/skills/wholework/`, `~/.claude/skills/wholework/modules/`, `~/.claude/agents/wholework/`, `~/.claude/skills/wholework/scripts/` (-> acceptance criteria 7-11)

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

- `modules/` and `scripts/` are placed under `~/.claude/skills/wholework/` (not `~/.claude/modules/` or `~/.claude/scripts/`) to co-locate with skills, avoid duplicate loading, and keep the package self-contained
- `install.sh` should be POSIX-compatible (`#!/bin/sh`) for maximum portability
- `package.json` bin field enables future `npx wholework` usage

## code レトロスペクティブ

### 設計からの逸脱
- 特になし

### 設計の不備・曖昧さ
- 特になし

### 手戻り
- 特になし

## review レトロスペクティブ

### 設計と実装の乖離パターン
- `install.sh` で `SKILLS_DEST`（`~/.claude/skills/wholework`）をシンボリックリンクとして作成した後に `MODULES_DEST`（`~/.claude/skills/wholework/modules`）を作成しようとすると、OS がシンボリックリンクを辿ってリポジトリ内 `skills/` ディレクトリを汚染するバグが検出された。Spec の install target mapping の記述（`modules/ → ~/.claude/skills/wholework/modules/`）は正しかったが、実装がそれを実現できていなかった。

### 頻出する指摘事項
- 特になし（今回は1件のMUST指摘）

### 受け入れ条件の検証困難さ
- 受け入れ条件はファイル存在・内容チェックのみで、実際のシンボリックリンク挙動は「マージ後」の手動検証に委ねられている。インストーラースクリプトの場合、dry-run オプションや POSIX 環境での実行テストを受け入れ条件に含めることで自動検証の精度が上がる可能性がある。
