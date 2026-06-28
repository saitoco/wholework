#!/usr/bin/env bats

# Tests for scripts/append-consumed-comments-section.sh
# Tests the verify-phase scenario: deterministic Consumed Comments writeback.
# Mocks: gh, git, get-config-value.sh (via MOCK_DIR + WHOLEWORK_SCRIPT_DIR)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/append-consumed-comments-section.sh"

setup() {
    cd "$BATS_TEST_TMPDIR"
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
    export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"

    # Mock get-config-value.sh: return default spec path
    cat > "$MOCK_DIR/get-config-value.sh" <<'MOCK'
#!/bin/bash
KEY="$1"; DEFAULT="${2:-}"
case "$KEY" in
    spec-path) echo "docs/spec" ;;
    *) echo "$DEFAULT" ;;
esac
exit 0
MOCK
    chmod +x "$MOCK_DIR/get-config-value.sh"

    # Default gh mock: returns empty timeline cutoff and empty comments array
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json title"* ]]; then
    echo "Test Issue Title"
    exit 0
fi
if [[ "$1" == "api" ]]; then
    # Timeline query: return empty (no cutoff)
    echo ""
    exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json comments"* ]]; then
    # Comments: empty array
    echo "[]"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    # Default git mock: no changes (diff --quiet exits 0 = no diff)
    cat > "$MOCK_DIR/git" <<'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "error: missing arguments → exit 0 with warning" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING"*"missing ISSUE_NUMBER"* ]] || [[ "$output" == "" ]]
}

@test "section absent: creates ## Consumed Comments with no-comments message" {
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    printf '%s\n' "# Issue #42: Test" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    run bash "$SCRIPT" 42 verify
    [ "$status" -eq 0 ]

    grep -q "^## Consumed Comments" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    grep -q "No new comments since last phase." "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
}

@test "spec absent: creates skeleton file with ## Consumed Comments section" {
    # No spec file exists — script should create skeleton
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"

    run bash "$SCRIPT" 99 verify
    [ "$status" -eq 0 ]

    # A spec file for issue 99 should have been created
    CREATED=$(ls "$BATS_TEST_TMPDIR/docs/spec/issue-99-"*.md 2>/dev/null | head -1 || true)
    [ -n "$CREATED" ]
    grep -q "^## Consumed Comments" "$CREATED"
}

@test "section exists: skip and exit 0 without adding another section" {
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    printf '%s\n' "# Issue #42: Test" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    printf '\n%s\n' "## Consumed Comments" >> "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    printf '%s\n' "No new comments since last phase." >> "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    GIT_LOG="$BATS_TEST_TMPDIR/git.log"
    export GIT_LOG
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
echo "GIT_CALLED: \$*" >> "${GIT_LOG}"
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42 verify
    [ "$status" -eq 0 ]

    # Section count should remain 1 (not duplicated)
    COUNT=$(grep -c "^## Consumed Comments" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md")
    [ "$COUNT" -eq 1 ]

    # git should not have been called (section already existed → skip before any write)
    [ ! -f "$GIT_LOG" ]
}

@test "verify-fail marker comment included regardless of cutoff" {
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    printf '%s\n' "# Issue #42: Test" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    # gh mock: return a recent cutoff + one verify-fail bot comment before cutoff
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
if [[ "$1" == "api" ]]; then
    # Return cutoff: 2026-06-01 (recent)
    echo "2026-06-01T00:00:00Z"
    exit 0
fi
if [[ "$1" == "issue" && "$2" == "view" && "$*" == *"--json comments"* ]]; then
    # One verify-fail bot comment with date before cutoff
    printf '%s\n' '[{"author":{"login":"wholework-bot[bot]"},"authorAssociation":"NONE","body":"<!-- wholework-event: type=verify-fail phase=verify issue=42 -->\nFAIL on AC2","url":"https://github.com/test/issues/42#issuecomment-1","createdAt":"2026-05-01T00:00:00Z"}]'
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 42 verify
    [ "$status" -eq 0 ]

    grep -q "^## Consumed Comments" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
    # verify-fail bot comment should be included (wholework-event exception)
    grep -q "wholework-bot\[bot\]" "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"
}

@test "git commit called when spec file is modified" {
    mkdir -p "$BATS_TEST_TMPDIR/docs/spec"
    printf '%s\n' "# Issue #42: Test" > "$BATS_TEST_TMPDIR/docs/spec/issue-42-test.md"

    GIT_LOG="$BATS_TEST_TMPDIR/git.log"
    export GIT_LOG

    # git mock: diff --quiet exits 1 (change detected), other calls log and exit 0
    # Note: script calls "git -C /repo/root diff --quiet", so $3 == "diff"
    cat > "$MOCK_DIR/git" <<MOCK
#!/bin/bash
if [[ "\$3" == "diff" && "\$*" == *"--quiet"* ]]; then
    exit 1
fi
echo "GIT_CALLED: \$*" >> "${GIT_LOG}"
exit 0
MOCK
    chmod +x "$MOCK_DIR/git"

    run bash "$SCRIPT" 42 verify
    [ "$status" -eq 0 ]

    [ -f "$GIT_LOG" ]
    grep -q "GIT_CALLED:.*add" "$GIT_LOG"
    grep -q "GIT_CALLED:.*commit" "$GIT_LOG"
    grep -q "GIT_CALLED:.*push" "$GIT_LOG"
}
