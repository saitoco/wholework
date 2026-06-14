#!/usr/bin/env bats

# Tests for scripts/post_merge_check.sh
# Mocks gh via PATH and uses WHOLEWORK_SCRIPT_DIR for sibling script isolation.

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/post_merge_check.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    LABEL_TRANSITION_LOG="$BATS_TEST_TMPDIR/label_transition.log"
    export LABEL_TRANSITION_LOG

    COMMENT_LOG="$BATS_TEST_TMPDIR/comment.log"
    export COMMENT_LOG

    # Mock gh: handle issue view and issue reopen
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "\$GH_CALL_LOG"
if [ "\$1" = "issue" ] && [ "\$2" = "view" ] && [ "\$4" = "--json" ]; then
    echo "- Manual verification step one <!-- verify-type: manual -->"
    exit 0
fi
if [ "\$1" = "issue" ] && [ "\$2" = "reopen" ]; then
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    # Mock gh-label-transition.sh: record invocation
    cat > "$MOCK_DIR/gh-label-transition.sh" <<MOCK
#!/bin/bash
echo "\$@" >> "\$LABEL_TRANSITION_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh-label-transition.sh"

    # Mock gh-issue-comment.sh: record comment body
    cat > "$MOCK_DIR/gh-issue-comment.sh" <<MOCK
#!/bin/bash
echo "issue=\$1" >> "\$COMMENT_LOG"
cat "\$2" >> "\$COMMENT_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh-issue-comment.sh"

    # Create a minimal docs/spec directory for Spec-based extraction tests
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: no arguments exits 1 with usage" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "error: invalid argument (--dry-run) exits 1 with usage" {
    run bash "$SCRIPT" --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not a valid issue number"* ]]
}

@test "error: non-numeric argument exits 1" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not a valid issue number"* ]]
}

@test "spec extraction: manual AC present in Spec is extracted and displayed" {
    # Create a Spec file with a manual AC
    cat > "$BATS_TEST_TMPDIR/docs/spec/issue-501-test.md" <<'SPEC'
## Post-merge

- Verify API integration works correctly <!-- verify-type: manual -->
SPEC

    # Run from the temp dir so docs/spec is found; use file redirect for stdin
    printf "s\n" > "$BATS_TEST_TMPDIR/input.txt"
    cd "$BATS_TEST_TMPDIR"
    run bash "$SCRIPT" 501 < "$BATS_TEST_TMPDIR/input.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Verify API integration works correctly"* ]]
    [[ "$output" == *"Source: Spec"* ]]
}

@test "fallback: no Spec file falls back to gh issue view body" {
    printf "s\n" > "$BATS_TEST_TMPDIR/input.txt"
    cd "$BATS_TEST_TMPDIR"
    run bash "$SCRIPT" 999 < "$BATS_TEST_TMPDIR/input.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Source: Issue body"* ]]
    [[ "$output" == *"Manual verification step one"* ]]
}

@test "all pass: gh-label-transition.sh called with issue N done" {
    cat > "$BATS_TEST_TMPDIR/docs/spec/issue-501-test.md" <<'SPEC'
## Post-merge

- Check endpoint responds <!-- verify-type: manual -->
SPEC

    printf "p\n" > "$BATS_TEST_TMPDIR/input.txt"
    cd "$BATS_TEST_TMPDIR"
    run bash "$SCRIPT" 501 < "$BATS_TEST_TMPDIR/input.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"phase/done"* ]]
    grep -q "501 done" "$LABEL_TRANSITION_LOG"
}

@test "fail: gh issue reopen called when FAIL input given" {
    cat > "$BATS_TEST_TMPDIR/docs/spec/issue-502-test.md" <<'SPEC'
## Post-merge

- Verify data is saved correctly <!-- verify-type: manual -->
SPEC

    printf "f\n" > "$BATS_TEST_TMPDIR/input.txt"
    cd "$BATS_TEST_TMPDIR"
    run bash "$SCRIPT" 502 < "$BATS_TEST_TMPDIR/input.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAIL"* ]]
    grep -q "issue reopen 502" "$GH_CALL_LOG"
}

@test "all skip: no label transition when all ACs are skipped" {
    cat > "$BATS_TEST_TMPDIR/docs/spec/issue-503-test.md" <<'SPEC'
## Post-merge

- Manual check required <!-- verify-type: manual -->
SPEC

    printf "s\n" > "$BATS_TEST_TMPDIR/input.txt"
    cd "$BATS_TEST_TMPDIR"
    run bash "$SCRIPT" 503 < "$BATS_TEST_TMPDIR/input.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No label change"* ]]
    [ ! -f "$LABEL_TRANSITION_LOG" ] || ! grep -q "503" "$LABEL_TRANSITION_LOG"
}

@test "no manual ACs: skips issue with notice" {
    cat > "$BATS_TEST_TMPDIR/docs/spec/issue-504-test.md" <<'SPEC'
## Pre-merge

- [ ] Some automated check <!-- verify: file_exists "foo.sh" -->
SPEC

    cd "$BATS_TEST_TMPDIR"
    run bash "$SCRIPT" 504
    [ "$status" -eq 0 ]
    [[ "$output" == *"No manual ACs found"* ]]
}

@test "multiple issues: processed sequentially" {
    cat > "$BATS_TEST_TMPDIR/docs/spec/issue-601-test.md" <<'SPEC'
## Post-merge

- First issue AC <!-- verify-type: manual -->
SPEC

    cat > "$BATS_TEST_TMPDIR/docs/spec/issue-602-test.md" <<'SPEC'
## Post-merge

- Second issue AC <!-- verify-type: manual -->
SPEC

    printf "p\np\n" > "$BATS_TEST_TMPDIR/input.txt"
    cd "$BATS_TEST_TMPDIR"
    run bash "$SCRIPT" 601 602 < "$BATS_TEST_TMPDIR/input.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Issue #601"* ]]
    [[ "$output" == *"Issue #602"* ]]
    grep -q "601 done" "$LABEL_TRANSITION_LOG"
    grep -q "602 done" "$LABEL_TRANSITION_LOG"
}
