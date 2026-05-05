#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Tests for check-verify-dirty.sh
# Verifies dirty file classification for /verify Step 1:
#   exit 0 — clean
#   exit 1 — related or non-spec dirty files
#   exit 2 — all dirty files are unrelated spec files

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REAL_SCRIPT="$PROJECT_ROOT/scripts/check-verify-dirty.sh"

setup() {
    REPO_DIR="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO_DIR/docs/spec"
    cd "$REPO_DIR"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    # Track docs/spec so individual spec files appear in git status --short
    touch docs/spec/.gitkeep
    git add docs/spec/.gitkeep
    git commit -q -m "init"
}

teardown() {
    rm -rf "$REPO_DIR"
}

# Helper: create and stage an untracked dirty file
make_dirty() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    echo "dirty" >> "$path"
}

@test "clean: exit 0 when working directory has no dirty files" {
    cd "$REPO_DIR"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "unrelated spec dirty: exit 2 when only unrelated spec file is dirty" {
    cd "$REPO_DIR"
    make_dirty "docs/spec/issue-999-some-spec.md"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 2 ]
    [[ "$output" == *"docs/spec/issue-999-some-spec.md"* ]]
}

@test "related spec dirty: exit 1 when related spec file (same issue) is dirty" {
    cd "$REPO_DIR"
    make_dirty "docs/spec/issue-123-my-spec.md"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 1 ]
}

@test "non-spec dirty: exit 1 when non-spec file is dirty" {
    cd "$REPO_DIR"
    make_dirty "scripts/some-script.sh"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 1 ]
}

@test "multiple unrelated spec dirty: exit 2 and lists all files" {
    cd "$REPO_DIR"
    make_dirty "docs/spec/issue-100-alpha.md"
    make_dirty "docs/spec/issue-200-beta.md"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 2 ]
    [[ "$output" == *"docs/spec/issue-100-alpha.md"* ]]
    [[ "$output" == *"docs/spec/issue-200-beta.md"* ]]
}

@test "unrelated spec mixed with non-spec: exit 1" {
    cd "$REPO_DIR"
    make_dirty "docs/spec/issue-999-unrelated.md"
    make_dirty "skills/verify/SKILL.md"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 1 ]
}
