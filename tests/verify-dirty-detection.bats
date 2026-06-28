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

@test "verify-ignore-paths: vault only dirty -> exit 0 with warning" {
    cd "$REPO_DIR"
    cat > .wholework.yml <<'EOF'
verify-ignore-paths:
  - vault/**
EOF
    git add .wholework.yml && git commit -q -m "add config"
    make_dirty "vault/knowledge/note.md"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning: ignoring dirty file excluded by verify-ignore-paths" ]]
}

@test "verify-ignore-paths: vault and scripts both dirty -> exit 1" {
    cd "$REPO_DIR"
    cat > .wholework.yml <<'EOF'
verify-ignore-paths:
  - vault/**
EOF
    git add .wholework.yml && git commit -q -m "add config"
    make_dirty "vault/note.md"
    make_dirty "scripts/foo.sh"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 1 ]
}

@test "verify-ignore-paths: .obsidian workspace dirty -> exit 0" {
    cd "$REPO_DIR"
    cat > .wholework.yml <<'EOF'
verify-ignore-paths:
  - vault/.obsidian/**
EOF
    git add .wholework.yml && git commit -q -m "add config"
    make_dirty "vault/.obsidian/workspace.json"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning: ignoring dirty file excluded by verify-ignore-paths" ]]
}

@test "verify-ignore-paths: unrelated spec dirty -> exit 2 regression check" {
    cd "$REPO_DIR"
    cat > .wholework.yml <<'EOF'
verify-ignore-paths:
  - vault/**
EOF
    git add .wholework.yml && git commit -q -m "add config"
    make_dirty "docs/spec/issue-999-unrelated.md"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 2 ]
    [[ "$output" == *"docs/spec/issue-999-unrelated.md"* ]]
}

@test "loop-state heartbeat only dirty: exit 0 (built-in exempt)" {
    cd "$REPO_DIR"
    mkdir -p "docs/sessions/_daily"
    make_dirty "docs/sessions/_daily/loop-state-2026-06-28.md"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning: ignoring dirty file excluded by verify-ignore-paths" ]]
}

@test "loop-state mixed with non-spec dirty: exit 1" {
    cd "$REPO_DIR"
    mkdir -p "docs/sessions/_daily"
    make_dirty "docs/sessions/_daily/loop-state-2026-06-28.md"
    make_dirty "scripts/some-script.sh"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 1 ]
}

@test "auto-events-rollup only dirty: exit 0 (built-in exempt)" {
    cd "$REPO_DIR"
    mkdir -p "docs/sessions/_daily"
    make_dirty "docs/sessions/_daily/auto-events-rollup-2026-06-28.md"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Warning: ignoring dirty file excluded by verify-ignore-paths" ]]
}

@test "auto-events-rollup mixed with non-spec dirty: exit 1" {
    cd "$REPO_DIR"
    mkdir -p "docs/sessions/_daily"
    make_dirty "docs/sessions/_daily/auto-events-rollup-2026-06-28.md"
    make_dirty "scripts/some-script.sh"
    run bash "$REAL_SCRIPT" 123
    [ "$status" -eq 1 ]
}
