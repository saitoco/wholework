#!/usr/bin/env bats

# Tests for scripts/reconcile-phase-state.sh
# Ported from watchdog-reconcile.bats (32 cases) + new precondition, JSON schema,
# and --strict/--warn-only tests.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/reconcile-phase-state.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

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

# --- issue completion ---

@test "issue completion: triaged label present -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "triaged"
echo "size/S"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
    [[ "$output" == *'"schema_version":"v1"'* ]]
}

@test "issue completion: triaged label absent -> mismatch (strict exit 1)" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "size/S"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42 --check-completion --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "issue completion: gh failure -> exit 2" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42 --check-completion
    [ "$status" -eq 2 ]
}

# --- spec completion ---

@test "spec completion: spec file + phase/ready label -> matches_expected true" {
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

    run bash "$SCRIPT" spec 99 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "spec completion: spec file missing -> mismatch (strict exit 1)" {
    export MOCK_SPEC_PATH="$BATS_TEST_TMPDIR/empty-spec"
    mkdir -p "$BATS_TEST_TMPDIR/empty-spec"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "phase/ready"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" spec 99 --check-completion --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "spec completion: spec file exists but no ready label -> mismatch" {
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

    run bash "$SCRIPT" spec 99 --check-completion --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "spec completion: phase/code label counts as ready-or-later -> matches_expected true" {
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

    run bash "$SCRIPT" spec 77 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

# --- code-patch completion ---

@test "code-patch completion: commit with closes #N on origin/main -> matches_expected true" {
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

    run bash "$SCRIPT" code-patch 55 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
    [[ "$output" == *'"commits_found":true'* ]]
}

@test "code-patch completion: no matching commit -> mismatch (strict exit 1)" {
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

    run bash "$SCRIPT" code-patch 55 --check-completion --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
    [[ "$output" == *'"commits_found":false'* ]]
}

@test "code-patch completion: git fetch failure -> exit 2" {
    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "fetch" ]]; then exit 1; fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/git"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-patch 55 --check-completion
    [ "$status" -eq 2 ]
}

# --- code-pr completion ---

@test "code-pr completion: open PR exists -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
# Shell strips quotes from -q args, so check bare token
if [[ "$*" == *"-q length"* ]]; then
    echo "1"
elif [[ "$*" == *"-q .[0].number"* ]]; then
    echo "55"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-pr 55 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
    [[ "$output" == *'"pr_state":"OPEN"'* ]]
}

@test "code-pr completion: no open PR -> mismatch, no stage2 recovery" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "0"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-pr 55 --check-completion --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
    [[ "$output" == *"delegated to #316"* ]] || [[ "$output" == *"stage2 recovery"* ]]
}

@test "code-pr completion: gh failure -> exit 2" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-pr 55 --check-completion
    [ "$status" -eq 2 ]
}

# --- review completion ---

@test "review completion: PR comment with Review Response Summary -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "## Review Response Summary"
echo "All good"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" review 42 --pr 10 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "review completion: no Review Summary comment -> mismatch (strict exit 1)" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "some unrelated comment"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" review 42 --pr 10 --check-completion --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "review completion: missing --pr flag -> exit 2" {
    run bash "$SCRIPT" review 42 --check-completion
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires --pr"* ]]
}

# --- merge completion ---

@test "merge completion: PR state MERGED -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "MERGED"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" merge 42 --pr 10 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
    [[ "$output" == *'"pr_state":"MERGED"'* ]]
}

@test "merge completion: PR state OPEN -> mismatch (strict exit 1)" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "OPEN"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" merge 42 --pr 10 --check-completion --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "merge completion: missing --pr flag -> exit 2" {
    run bash "$SCRIPT" merge 42 --check-completion
    [ "$status" -eq 2 ]
    [[ "$output" == *"requires --pr"* ]]
}

# --- verify completion ---

@test "verify completion: issue state CLOSED -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$*" == *"--json state"* ]]; then
    echo "CLOSED"
elif [[ "$*" == *"--json labels"* ]]; then
    echo ""
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" verify 42 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
    [[ "$output" == *'"issue_state":"CLOSED"'* ]]
}

@test "verify completion: issue OPEN + phase/verify label -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$*" == *"--json state"* ]]; then
    echo "OPEN"
elif [[ "$*" == *"--json labels"* ]]; then
    echo "phase/verify"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" verify 42 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "verify completion: issue OPEN + phase/done label -> matches_expected true" {
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

    run bash "$SCRIPT" verify 42 --check-completion --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "verify completion: issue OPEN + no qualifying label -> mismatch (strict exit 1)" {
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

    run bash "$SCRIPT" verify 42 --check-completion --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "verify completion: gh failure -> exit 2" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" verify 42 --check-completion
    [ "$status" -eq 2 ]
}

# --- Precondition checks ---

@test "issue precondition: issue is OPEN -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "OPEN"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42 --check-precondition --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
    [[ "$output" == *'"issue_state":"OPEN"'* ]]
}

@test "issue precondition: issue is CLOSED -> mismatch (strict exit 1)" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "CLOSED"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42 --check-precondition --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "spec precondition: phase/issue label -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "phase/issue"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" spec 42 --check-precondition --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "spec precondition: no phase/issue or phase/spec label -> mismatch" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "triaged"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" spec 42 --check-precondition --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "code-patch precondition: phase/ready label -> matches_expected true" {
    SPEC_DIR="$BATS_TEST_TMPDIR/docs/specpre"
    mkdir -p "$SPEC_DIR"
    touch "$SPEC_DIR/issue-42-spec.md"
    export MOCK_SPEC_PATH="$SPEC_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "phase/ready"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-patch 42 --check-precondition --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "code-patch precondition: no phase/ready label -> mismatch" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "triaged"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-patch 42 --check-precondition --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "code-pr precondition: phase/ready label -> matches_expected true" {
    SPEC_DIR="$BATS_TEST_TMPDIR/docs/specpre2"
    mkdir -p "$SPEC_DIR"
    touch "$SPEC_DIR/issue-42-spec.md"
    export MOCK_SPEC_PATH="$SPEC_DIR"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "phase/ready"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-pr 42 --check-precondition --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "code-pr precondition: no phase/ready label -> mismatch" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "triaged"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-pr 42 --check-precondition --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "review precondition: PR is OPEN -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "OPEN"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" review 42 --pr 10 --check-precondition --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "review precondition: PR is not OPEN -> mismatch" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "MERGED"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" review 42 --pr 10 --check-precondition --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "merge precondition: PR OPEN and APPROVED -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$*" == *"--json state"* ]]; then
    echo "OPEN"
elif [[ "$*" == *"--json reviewDecision"* ]]; then
    echo "APPROVED"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" merge 42 --pr 10 --check-precondition --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "merge precondition: PR OPEN but not APPROVED -> mismatch" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$*" == *"--json state"* ]]; then
    echo "OPEN"
elif [[ "$*" == *"--json reviewDecision"* ]]; then
    echo "REVIEW_REQUIRED"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" merge 42 --pr 10 --check-precondition --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "verify precondition: issue has phase/verify label -> matches_expected true" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$*" == *"--json state"* ]]; then
    echo "OPEN"
elif [[ "$*" == *"--json labels"* ]]; then
    echo "phase/verify"
fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" verify 42 --check-precondition --strict
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":true'* ]]
}

@test "verify precondition: issue OPEN with no phase/verify label -> mismatch" {
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

    run bash "$SCRIPT" verify 42 --check-precondition --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

# --- JSON schema output format ---

@test "JSON schema: all required keys present in output" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "triaged"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42 --check-completion
    [ "$status" -eq 0 ]
    [[ "$output" == *'"schema_version"'* ]]
    [[ "$output" == *'"phase"'* ]]
    [[ "$output" == *'"matches_expected"'* ]]
    [[ "$output" == *'"actual"'* ]]
    [[ "$output" == *'"diagnosis"'* ]]
}

@test "JSON schema: schema_version is always v1" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "triaged"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42 --check-completion
    [ "$status" -eq 0 ]
    [[ "$output" == *'"schema_version":"v1"'* ]]
}

# --- --strict vs --warn-only mode ---

@test "warn-only mode: mismatch exits 0 (default)" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "size/S"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42 --check-completion --warn-only
    [ "$status" -eq 0 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

@test "strict mode: mismatch exits 1" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "size/S"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" issue 42 --check-completion --strict
    [ "$status" -eq 1 ]
    [[ "$output" == *'"matches_expected":false'* ]]
}

# --- Precondition vs completion comparison ---

@test "same phase: precondition passes but completion not yet reached" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "phase/ready"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    export MOCK_SPEC_PATH="$BATS_TEST_TMPDIR/no-spec"
    mkdir -p "$BATS_TEST_TMPDIR/no-spec"

    run bash "$SCRIPT" code-patch 42 --check-precondition --strict
    precondition_status=$status
    precondition_output="$output"

    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "fetch" ]]; then exit 0; fi
echo ""
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" code-patch 42 --check-completion --strict
    completion_status=$status

    [ "$precondition_status" -eq 0 ]
    [[ "$precondition_output" == *'"matches_expected":true'* ]]
    [ "$completion_status" -eq 1 ]
}

@test "same phase: both precondition and completion pass when state is complete" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo "phase/ready"
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
    export PATH="$MOCK_DIR:$PATH"

    SPEC_DIR="$BATS_TEST_TMPDIR/docs/speccmp"
    mkdir -p "$SPEC_DIR"
    touch "$SPEC_DIR/issue-42-spec.md"
    export MOCK_SPEC_PATH="$SPEC_DIR"

    run bash "$SCRIPT" code-patch 42 --check-precondition --strict
    precondition_status=$status

    cat > "$MOCK_DIR/git" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "fetch" ]]; then exit 0; fi
if [[ "$1" == "log" ]]; then echo "abc1234 feat: add (closes #42)"; fi
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/git"
    export PATH="$MOCK_DIR:$PATH"

    run bash "$SCRIPT" code-patch 42 --check-completion --strict
    completion_status=$status

    [ "$precondition_status" -eq 0 ]
    [ "$completion_status" -eq 0 ]
}
