#!/usr/bin/env bats

# Tests for scripts/watchdog-reconcile.sh

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/watchdog-reconcile.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    # Default get-config-value.sh mock: returns default spec-path
    cat > "$MOCK_DIR/get-config-value.sh" << 'MOCK_EOF'
#!/bin/bash
KEY="$1"
DEFAULT="${2:-}"
case "$KEY" in
    spec-path) echo "${MOCK_SPEC_PATH:-docs/spec}" ;;
    *)         echo "$DEFAULT" ;;
esac
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/get-config-value.sh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# --- Usage / error cases ---

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "error: missing issue number" {
    run bash "$SCRIPT" issue
    [ "$status" -eq 2 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "error: unknown phase" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" unknown-phase 123
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown phase"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" issue abc
    [ "$status" -eq 2 ]
    [[ "$output" == *"invalid issue number"* ]]
}

# --- issue phase ---

@test "issue: triaged label present -> exit 0" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
# gh issue view 42 --json labels -q '.labels[].name'
echo "triaged"
echo "size/S"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "issue: triaged label absent -> exit 143" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "size/S"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "issue: gh failure -> exit 2" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42
    [ "$status" -eq 2 ]
}

# --- spec phase ---

@test "spec: spec file exists + phase/ready label -> exit 0" {
    SPEC_DIR="$BATS_TEST_TMPDIR/docs/spec"
    mkdir -p "$SPEC_DIR"
    touch "$SPEC_DIR/issue-99-my-spec.md"
    export MOCK_SPEC_PATH="$SPEC_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "phase/ready"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" spec 99
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "spec: spec file missing -> exit 143" {
    export MOCK_SPEC_PATH="$BATS_TEST_TMPDIR/empty-spec"
    mkdir -p "$BATS_TEST_TMPDIR/empty-spec"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "phase/ready"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" spec 99
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "spec: spec file exists but no ready label -> exit 143" {
    SPEC_DIR="$BATS_TEST_TMPDIR/docs/spec2"
    mkdir -p "$SPEC_DIR"
    touch "$SPEC_DIR/issue-99-my-spec.md"
    export MOCK_SPEC_PATH="$SPEC_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "triaged"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" spec 99
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "spec: phase/code label counts as ready-or-later -> exit 0" {
    SPEC_DIR="$BATS_TEST_TMPDIR/docs/spec3"
    mkdir -p "$SPEC_DIR"
    touch "$SPEC_DIR/issue-77-some-spec.md"
    export MOCK_SPEC_PATH="$SPEC_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "phase/code"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" spec 77
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

# --- code-patch phase ---

@test "code-patch: commit with closes #N on origin/main -> exit 0" {
    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "fetch" ]]; then exit 0; fi
if [[ "$1" == "log" ]]; then
    echo "abc1234 feat: fix bug (closes #55)"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/git"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-patch 55
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "code-patch: no matching commit -> exit 143" {
    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "fetch" ]]; then exit 0; fi
if [[ "$1" == "log" ]]; then
    echo ""
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/git"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-patch 55
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "code-patch: git fetch failure -> exit 2" {
    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "fetch" ]]; then exit 1; fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/git"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-patch 55
    [ "$status" -eq 2 ]
}

# --- code-pr phase ---

@test "code-pr: open PR exists -> exit 0" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
# gh pr list --head "worktree-code+issue-N" --state open --json number -q 'length'
echo "1"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-pr 55
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "code-pr: no open PR -> exit 143" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "0"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-pr 55
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "code-pr: gh failure -> exit 2" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-pr 55
    [ "$status" -eq 2 ]
}

@test "code-pr: stage2 worktree with implementation commits exists and push and create PR succeed -> exit 0" {
    WORKTREE_DIR="$BATS_TEST_TMPDIR/.claude/worktrees/code+issue-55"
    mkdir -p "$WORKTREE_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "0"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "create" ]]; then
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "-C" ]]; then shift 2; fi
case "$1" in
    log)       echo "abc1234 feat: implement feature (closes #55)" ;;
    rev-parse) echo "worktree-code+issue-55" ;;
    push)      exit 0 ;;
    *)         exit 0 ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" code-pr 55
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "code-pr: stage2 worktree exists but no closes-#N commit -> exit 143" {
    WORKTREE_DIR="$BATS_TEST_TMPDIR/.claude/worktrees/code+issue-55"
    mkdir -p "$WORKTREE_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "0"
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "-C" ]]; then shift 2; fi
case "$1" in
    log) echo "abc1234 feat: implement feature without closing marker" ;;
    *)   exit 0 ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" code-pr 55
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "code-pr: stage2 push fails -> exit 143" {
    WORKTREE_DIR="$BATS_TEST_TMPDIR/.claude/worktrees/code+issue-55"
    mkdir -p "$WORKTREE_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "0"
    exit 0
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "-C" ]]; then shift 2; fi
case "$1" in
    log)       echo "abc1234 feat: implement feature (closes #55)" ;;
    rev-parse) echo "worktree-code+issue-55" ;;
    push)      exit 1 ;;
    *)         exit 0 ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" code-pr 55
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "code-pr: stage2 push succeeds but gh pr create fails -> exit 143" {
    WORKTREE_DIR="$BATS_TEST_TMPDIR/.claude/worktrees/code+issue-55"
    mkdir -p "$WORKTREE_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "pr" && "$2" == "list" ]]; then
    echo "0"
    exit 0
fi
if [[ "$1" == "pr" && "$2" == "create" ]]; then
    exit 1
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "-C" ]]; then shift 2; fi
case "$1" in
    log)       echo "abc1234 feat: implement feature (closes #55)" ;;
    rev-parse) echo "worktree-code+issue-55" ;;
    push)      exit 0 ;;
    *)         exit 0 ;;
esac
MOCK_EOF
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" code-pr 55
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

# --- review phase ---

@test "review: PR comment with Review Summary -> exit 0" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "## Review Summary"
echo "All good"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" review 42 --pr 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "review: no Review Summary comment -> exit 143" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "some unrelated comment"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" review 42 --pr 10
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "review: missing --pr flag -> exit 2" {
    run bash "$SCRIPT" review 42
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires --pr"* ]]
}

# --- merge phase ---

@test "merge: PR state MERGED -> exit 0" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "MERGED"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" merge 42 --pr 10
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "merge: PR state OPEN -> exit 143" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "OPEN"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" merge 42 --pr 10
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "merge: missing --pr flag -> exit 2" {
    run bash "$SCRIPT" merge 42
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires --pr"* ]]
}

# --- verify phase ---

@test "verify: issue state CLOSED -> exit 0" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "CLOSED"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" verify 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "verify: issue OPEN + phase/verify label -> exit 0" {
    CALL_COUNT=0
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
# First call returns state, second call returns labels
if [[ "$*" == *"--json state"* ]]; then
    echo "OPEN"
elif [[ "$*" == *"--json labels"* ]]; then
    echo "phase/verify"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" verify 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "verify: issue OPEN + phase/done label -> exit 0" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$*" == *"--json state"* ]]; then
    echo "OPEN"
elif [[ "$*" == *"--json labels"* ]]; then
    echo "phase/done"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" verify 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"reconciled"* ]]
}

@test "verify: issue OPEN + no qualifying label -> exit 143" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$*" == *"--json state"* ]]; then
    echo "OPEN"
elif [[ "$*" == *"--json labels"* ]]; then
    echo "phase/code"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" verify 42
    [ "$status" -eq 143 ]
    [[ "$output" == *"not reached"* ]]
}

@test "verify: gh failure -> exit 2" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" verify 42
    [ "$status" -eq 2 ]
}
