#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Tests for check-file-overlap.sh
# get-sub-issue-graph.sh is mocked via a temp scripts directory structure

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REAL_SCRIPT="$PROJECT_ROOT/scripts/check-file-overlap.sh"

setup() {
    # Build a temp repo structure so $SCRIPT_DIR-relative calls can be mocked
    REPO_DIR="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$REPO_DIR/scripts" "$REPO_DIR/docs/spec"

    # Symlink the real script into temp scripts dir
    ln -s "$REAL_SCRIPT" "$REPO_DIR/scripts/check-file-overlap.sh"

    # Symlink the real get-config-value.sh into temp scripts dir
    ln -s "$PROJECT_ROOT/scripts/get-config-value.sh" "$REPO_DIR/scripts/get-config-value.sh"

    # Capture log for get-sub-issue-graph.sh calls
    GRAPH_CALL_LOG="$BATS_TEST_TMPDIR/graph_calls.log"
    export GRAPH_CALL_LOG

    # Default mock: return empty sub-issues
    cat > "$REPO_DIR/scripts/get-sub-issue-graph.sh" << 'MOCK_EOF'
#!/bin/bash
echo "$@" >> "${GRAPH_CALL_LOG}"
echo '{"sub_issues":[]}'
MOCK_EOF
    chmod +x "$REPO_DIR/scripts/get-sub-issue-graph.sh"

    SCRIPT="$REPO_DIR/scripts/check-file-overlap.sh"
    SPEC_DIR="$REPO_DIR/docs/spec"
}

teardown() {
    rm -rf "$REPO_DIR"
}

# Helper: create a minimal spec file with changed files listed
create_spec() {
    local issue_num="$1"
    local spec_name="issue-${issue_num}-test-spec.md"
    shift
    {
        echo "# Spec for Issue #${issue_num}"
        echo ""
        echo "## 変更対象ファイル"
        for f in "$@"; do
            echo "- \`${f}\`"
        done
        echo ""
        echo "## Other Section"
        echo "Some other content."
    } > "$SPEC_DIR/$spec_name"
}

# Helper: set the mock to return specified sub-issues
set_sub_issues() {
    local issues_json=""
    for num in "$@"; do
        if [[ -n "$issues_json" ]]; then
            issues_json="${issues_json},"
        fi
        issues_json="${issues_json}{\"number\":${num}}"
    done
    cat > "$REPO_DIR/scripts/get-sub-issue-graph.sh" << MOCK_EOF
#!/bin/bash
echo "\$@" >> "\${GRAPH_CALL_LOG}"
echo '{"sub_issues":[${issues_json}]}'
MOCK_EOF
    chmod +x "$REPO_DIR/scripts/get-sub-issue-graph.sh"
}

@test "help: --help shows usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "help: no arguments shows usage" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
}

@test "error: non-numeric issue number" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error"* ]]
}

@test "success: no sub-issues returns empty overlaps" {
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [ "$output" = '{"overlaps": []}' ]
}

@test "success: sub-issues with no spec files returns empty overlaps" {
    set_sub_issues 101 102
    run --separate-stderr bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [ "$output" = '{"overlaps": []}' ]
}

@test "success: sub-issues with spec files but no overlap returns empty overlaps" {
    set_sub_issues 101 102
    create_spec 101 "skills/auto/SKILL.md" "scripts/run-auto.sh"
    create_spec 102 "skills/spec/SKILL.md" "scripts/run-spec.sh"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [ "$output" = '{"overlaps": []}' ]
}

@test "success: two sub-issues sharing one file reports overlap" {
    set_sub_issues 101 102
    create_spec 101 "skills/auto/SKILL.md" "scripts/run-auto.sh"
    create_spec 102 "skills/auto/SKILL.md" "scripts/run-spec.sh"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [[ "$output" == *'"overlaps"'* ]]
    [[ "$output" == *'"file"'* ]]
    [[ "$output" == *'skills/auto/SKILL.md'* ]]
    [[ "$output" == *'"issues"'* ]]
    [[ "$output" == *'101'* ]]
    [[ "$output" == *'102'* ]]
}

@test "success: three sub-issues two share a file" {
    set_sub_issues 101 102 103
    create_spec 101 "scripts/common.sh"
    create_spec 102 "scripts/common.sh" "scripts/unique-b.sh"
    create_spec 103 "scripts/unique-c.sh"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [[ "$output" == *'scripts/common.sh'* ]]
    [[ "$output" != *'scripts/unique-c.sh'* ]]
}

@test "success: sub-issue with spec but no changed-files section yields no overlap" {
    set_sub_issues 101 102
    # Spec without the 変更対象ファイル section
    echo "# Spec without files section" > "$SPEC_DIR/issue-101-no-files.md"
    create_spec 102 "some/file.md"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [ "$output" = '{"overlaps": []}' ]
}

@test "success: get-sub-issue-graph.sh is called with the parent issue number" {
    run bash "$SCRIPT" 999
    [ "$status" -eq 0 ]
    grep -q "999" "$GRAPH_CALL_LOG"
}

@test "success: custom spec-path in .wholework.yml is used for spec lookup" {
    set_sub_issues 101 102
    # Create custom spec directory
    mkdir -p "$REPO_DIR/custom/specs"
    # Create .wholework.yml pointing to custom path
    echo "spec-path: custom/specs" > "$REPO_DIR/.wholework.yml"
    # Create spec files under custom path
    {
        echo "# Spec for Issue #101"
        echo ""
        echo "## 変更対象ファイル"
        echo "- \`skills/auto/SKILL.md\`"
    } > "$REPO_DIR/custom/specs/issue-101-test.md"
    {
        echo "# Spec for Issue #102"
        echo ""
        echo "## 変更対象ファイル"
        echo "- \`skills/auto/SKILL.md\`"
    } > "$REPO_DIR/custom/specs/issue-102-test.md"

    cd "$REPO_DIR"
    run bash "$SCRIPT" 100
    [ "$status" -eq 0 ]
    [[ "$output" == *'skills/auto/SKILL.md'* ]]
    [[ "$output" == *'101'* ]]
    [[ "$output" == *'102'* ]]
}
