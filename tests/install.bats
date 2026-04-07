#!/usr/bin/env bats

# Tests for install.sh (wholework version)
# Replaces HOME with a temp directory to avoid affecting the real environment.
# Note: test names use ASCII only (bats cannot parse multibyte characters in test names)

INSTALL_SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/install.sh"
REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    ORIG_HOME="$HOME"
    TEST_HOME="$(mktemp -d)"
    export HOME="$TEST_HOME"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -rf "$TEST_HOME"
}

# --- Clean install ---

@test "clean install: creates ~/.claude/skills/wholework directory" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ -d "$TEST_HOME/.claude/skills/wholework" ]
}

@test "clean install: skills/wholework is a real directory, not a symlink" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ -d "$TEST_HOME/.claude/skills/wholework" ]
    [ ! -L "$TEST_HOME/.claude/skills/wholework" ]
}

@test "clean install: each skill is symlinked inside skills/wholework" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    # At least one skill symlink should exist
    skill_count=$(find "$TEST_HOME/.claude/skills/wholework" -maxdepth 1 -type l | wc -l)
    [ "$skill_count" -gt 0 ]
}

@test "clean install: modules symlink is created" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.claude/skills/wholework/modules" ]
}

@test "clean install: agents symlink is created" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.claude/agents/wholework" ]
}

@test "clean install: scripts symlink is created" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.claude/skills/wholework/scripts" ]
}

@test "clean install: symlinks point to correct source" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(readlink "$TEST_HOME/.claude/skills/wholework/modules")" = "$REPO_DIR/modules" ]
    [ "$(readlink "$TEST_HOME/.claude/agents/wholework")" = "$REPO_DIR/agents" ]
    [ "$(readlink "$TEST_HOME/.claude/skills/wholework/scripts")" = "$REPO_DIR/scripts" ]
}

@test "clean install: individual skill symlinks point to correct source directories" {
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    # Check each skill symlink
    for skill_dir in "$REPO_DIR/skills"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        link="$TEST_HOME/.claude/skills/wholework/$skill_name"
        [ -L "$link" ]
        [ "$(readlink "$link")" = "$skill_dir" ]
    done
}

# --- Idempotent install ---

@test "idempotent: running install twice succeeds" {
    bash "$INSTALL_SCRIPT"
    run bash "$INSTALL_SCRIPT"
    [ "$status" -eq 0 ]
    [ -L "$TEST_HOME/.claude/skills/wholework/modules" ]
}

# --- Uninstall ---

@test "uninstall: removes skill symlinks" {
    bash "$INSTALL_SCRIPT"
    run bash "$INSTALL_SCRIPT" --uninstall
    [ "$status" -eq 0 ]
    # Individual skill symlinks should be removed
    for skill_dir in "$REPO_DIR/skills"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name=$(basename "$skill_dir")
        [ ! -L "$TEST_HOME/.claude/skills/wholework/$skill_name" ]
    done
}

@test "uninstall: removes modules symlink" {
    bash "$INSTALL_SCRIPT"
    run bash "$INSTALL_SCRIPT" --uninstall
    [ "$status" -eq 0 ]
    [ ! -L "$TEST_HOME/.claude/skills/wholework/modules" ]
}

@test "uninstall: removes agents symlink" {
    bash "$INSTALL_SCRIPT"
    run bash "$INSTALL_SCRIPT" --uninstall
    [ "$status" -eq 0 ]
    [ ! -L "$TEST_HOME/.claude/agents/wholework" ]
}

@test "uninstall: removes scripts symlink" {
    bash "$INSTALL_SCRIPT"
    run bash "$INSTALL_SCRIPT" --uninstall
    [ "$status" -eq 0 ]
    [ ! -L "$TEST_HOME/.claude/skills/wholework/scripts" ]
}

# --- Help option ---

@test "help: shows usage with --uninstall description" {
    run bash "$INSTALL_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--uninstall"* ]]
}

# --- Unknown option ---

@test "unknown option: exits with error" {
    run bash "$INSTALL_SCRIPT" --foo
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option"* ]] || [[ "$output" == *"unknown option"* ]]
}
