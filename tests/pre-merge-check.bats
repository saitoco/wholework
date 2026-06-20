#!/usr/bin/env bats

# Tests for pre-merge-check.sh
# Uses a real git fixture with a bare origin remote, stub check script, and gh mock.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/pre-merge-check.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    # Create a bare remote (origin)
    BARE_DIR="$BATS_TEST_TMPDIR/origin.git"
    git init --bare "$BARE_DIR" >/dev/null 2>&1

    # Create the working repo and set origin
    REPO_DIR="$BATS_TEST_TMPDIR/repo"
    git init "$REPO_DIR" >/dev/null 2>&1
    git -C "$REPO_DIR" config user.email "test@example.com"
    git -C "$REPO_DIR" config user.name "Test"
    git -C "$REPO_DIR" remote add origin "$BARE_DIR"

    # Initial commit on main
    mkdir -p "$REPO_DIR/scripts"
    cat > "$REPO_DIR/scripts/check-forbidden-expressions.sh" <<'STUB'
#!/bin/bash
# Stub: exit 1 if any skills/*.md file contains "FORBIDDEN"
if grep -rq 'FORBIDDEN' skills/ 2>/dev/null; then
  exit 1
fi
exit 0
STUB
    chmod +x "$REPO_DIR/scripts/check-forbidden-expressions.sh"

    mkdir -p "$REPO_DIR/skills"
    echo "clean content" > "$REPO_DIR/skills/x.md"

    git -C "$REPO_DIR" add .
    git -C "$REPO_DIR" commit -m "initial" >/dev/null 2>&1
    git -C "$REPO_DIR" branch -M main
    git -C "$REPO_DIR" push origin main >/dev/null 2>&1

    # Change to the working repo for subsequent git operations
    cd "$REPO_DIR"

    # Place gh mock in MOCK_DIR — tests override headRefName/baseRefName per scenario
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
# Default stub — overridden per test
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    cd "$BATS_TEST_TMPDIR"
    rm -rf "$MOCK_DIR" "$BATS_TEST_TMPDIR/origin.git" "$BATS_TEST_TMPDIR/repo"
}

# Helper: create a feature branch with optional FORBIDDEN content in skills/x.md
_setup_feature_branch() {
    local branch="$1"
    local content="${2:-clean content}"

    git checkout -b "$branch" main >/dev/null 2>&1
    echo "$content" > skills/x.md
    git add skills/x.md
    git commit -m "feature commit" >/dev/null 2>&1
    git push origin "$branch" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1
}

# Helper: set the gh mock to return specific head/base refs
_mock_gh_refs() {
    local head_ref="$1"
    local base_ref="$2"
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
if [[ "\$*" == *"headRefName"* ]]; then
  echo "$head_ref"
elif [[ "\$*" == *"baseRefName"* ]]; then
  echo "$base_ref"
else
  echo ""
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

@test "usage error: no arguments exits 1" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "unknown check name exits 1" {
    _mock_gh_refs "feature" "main"
    run bash "$SCRIPT" 99 "nonexistent-check"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown check"* ]]
}

@test "NEW_FAILURE: base PASS / head FAIL exits 2" {
    _setup_feature_branch "feature-bad" "FORBIDDEN content here"
    _mock_gh_refs "feature-bad" "main"

    run bash "$SCRIPT" 99
    [ "$status" -eq 2 ]
    [[ "$output" == *"NEW_FAILURE"* ]]
}

@test "PRE_EXISTING: both FAIL exits 0 with PRE_EXISTING label" {
    # Put FORBIDDEN content on main too
    echo "FORBIDDEN content here" > skills/x.md
    git add skills/x.md
    git commit -m "add forbidden on main" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1

    _setup_feature_branch "feature-also-bad" "FORBIDDEN content here"
    _mock_gh_refs "feature-also-bad" "main"

    run bash "$SCRIPT" 99
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRE_EXISTING"* ]]
}

@test "CLEAN: both PASS exits 0 with CLEAN label" {
    _setup_feature_branch "feature-clean" "clean content"
    _mock_gh_refs "feature-clean" "main"

    run bash "$SCRIPT" 99
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEAN"* ]]
}

@test "FIXED: base FAIL / head PASS exits 0 with FIXED label" {
    # Put FORBIDDEN on main
    echo "FORBIDDEN content here" > skills/x.md
    git add skills/x.md
    git commit -m "add forbidden on main" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1

    # Feature branch fixes it
    _setup_feature_branch "feature-fix" "clean content"
    _mock_gh_refs "feature-fix" "main"

    run bash "$SCRIPT" 99
    [ "$status" -eq 0 ]
    [[ "$output" == *"FIXED"* ]]
}

@test "env error: headRefName empty exits 1" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"headRefName"* ]]; then
  echo ""
elif [[ "$*" == *"baseRefName"* ]]; then
  echo "main"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"headRefName"* ]]
}

@test "env error: baseRefName empty exits 1" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$*" == *"headRefName"* ]]; then
  echo "feature"
elif [[ "$*" == *"baseRefName"* ]]; then
  echo ""
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"baseRefName"* ]]
}
