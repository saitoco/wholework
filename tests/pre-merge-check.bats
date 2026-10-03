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
# Always adds a unique marker file to ensure the commit is non-empty even when
# skills/x.md content is identical to main.
_setup_feature_branch() {
    local branch="$1"
    local content="${2:-clean content}"

    git checkout -b "$branch" main >/dev/null 2>&1
    echo "$content" > skills/x.md
    echo "branch: $branch" > "skills/marker-${branch}.md"
    git add skills/x.md "skills/marker-${branch}.md"
    git commit -m "feature commit" >/dev/null 2>&1
    git push origin "$branch" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1
}

# Helper: remove the check script from a branch (commit + push), then return to main
_remove_check_script_on_branch() {
    local branch="$1"

    git checkout "$branch" >/dev/null 2>&1
    git rm -q scripts/check-forbidden-expressions.sh
    git commit -m "remove check script" >/dev/null 2>&1
    git push origin "$branch" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1
}

# Helper: install a git shim that fails for one subcommand and delegates everything else
# to the real git. Usage: _mock_git_failure <subcommand> <exit-code> [stderr-message]
_mock_git_failure() {
    local subcommand="$1"
    local exit_code="$2"
    local message="${3:-}"
    local real_git
    real_git="$(command -v git)"

    cat > "$MOCK_DIR/git" <<SHIM
#!/bin/bash
if [[ "\$1" == "$subcommand" ]]; then
  echo "$message" >&2
  exit $exit_code
fi
exec "$real_git" "\$@"
SHIM
    chmod +x "$MOCK_DIR/git"
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

@test "NOT_APPLICABLE: script absent from both refs exits 0 with NOT_APPLICABLE label" {
    _remove_check_script_on_branch main
    _setup_feature_branch "feature-no-check" "clean content"
    _mock_gh_refs "feature-no-check" "main"

    run bash "$SCRIPT" 99
    [ "$status" -eq 0 ]
    [[ "$output" == *"NOT_APPLICABLE:"* ]] || false
    [[ "$output" == *"not applicable"* ]] || false
    [[ "$output" != *"Error"* ]] || false
    [[ "$output" != *"Warning"* ]] || false
}

@test "env error: check script present on base only exits 1" {
    _setup_feature_branch "feature-drops-check" "clean content"
    _remove_check_script_on_branch "feature-drops-check"
    _mock_gh_refs "feature-drops-check" "main"

    run bash "$SCRIPT" 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"only one of"* ]] || false
    [[ "$output" != *"NOT_APPLICABLE"* ]] || false
}

@test "env error: check script present on head only exits 1" {
    _setup_feature_branch "feature-adds-check" "clean content"
    _remove_check_script_on_branch main
    _mock_gh_refs "feature-adds-check" "main"

    run bash "$SCRIPT" 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"only one of"* ]] || false
    [[ "$output" != *"NOT_APPLICABLE"* ]] || false
}

@test "env error: git fetch failure exits 1" {
    _mock_gh_refs "no-such-branch" "main"

    run bash "$SCRIPT" 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"git fetch failed"* ]] || false
}

@test "env error: git worktree add failure exits 1" {
    _setup_feature_branch "feature-clean" "clean content"
    _mock_gh_refs "feature-clean" "main"
    _mock_git_failure "worktree" 1

    run bash "$SCRIPT" 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"git worktree add failed"* ]] || false
}

@test "env error: git ref inspection failure is not read as absent exits 1" {
    _setup_feature_branch "feature-clean" "clean content"
    _mock_gh_refs "feature-clean" "main"
    _mock_git_failure "ls-tree" 128 "fatal: simulated ls-tree failure"

    run bash "$SCRIPT" 99
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not inspect"* ]] || false
    [[ "$output" != *"NOT_APPLICABLE"* ]] || false
}

@test "CLEAN: check script is detected when run from a repository subdirectory" {
    _setup_feature_branch "feature-clean" "clean content"
    _mock_gh_refs "feature-clean" "main"

    cd skills
    run bash "$SCRIPT" 99
    [ "$status" -eq 0 ]
    [[ "$output" == *"CLEAN:"* ]] || false
    [[ "$output" != *"NOT_APPLICABLE"* ]] || false
}
