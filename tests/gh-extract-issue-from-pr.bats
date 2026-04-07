#!/usr/bin/env bats

# Tests for gh-extract-issue-from-pr.sh
# Mock gh command via PATH to verify behavior

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/gh-extract-issue-from-pr.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

make_gh_mock() {
    local body="$1"
    local title="${2:-Test PR}"
    local base_ref="${3:-main}"
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo '{"body": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$body"), "title": $(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$title"), "baseRefName": "$base_ref"}'
MOCK
    chmod +x "$MOCK_DIR/gh"
}

@test "body: closes #123 is extracted" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo '{"body": "This PR closes #123\n", "title": "Fix something", "baseRefName": "main"}'
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" 1
    [ "$status" -eq 0 ]
    [[ "$output" == *'"issue_number": "123"'* ]]
    [[ "$output" == *'"base_ref": "main"'* ]]
}

@test "body: Related to #456 is extracted" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo '{"body": "Related to #456", "title": "Some feature", "baseRefName": "develop"}'
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" 2
    [ "$status" -eq 0 ]
    [[ "$output" == *'"issue_number": "456"'* ]]
    [[ "$output" == *'"base_ref": "develop"'* ]]
}

@test "title: Issue #789: pattern when body has no match" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo '{"body": "No issue reference here", "title": "Issue #789: some fix", "baseRefName": "main"}'
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" 3
    [ "$status" -eq 0 ]
    [[ "$output" == *'"issue_number": "789"'* ]]
}

@test "no issue reference returns empty string" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo '{"body": "No references at all", "title": "Refactor something", "baseRefName": "main"}'
MOCK
    chmod +x "$MOCK_DIR/gh"
    run bash "$SCRIPT" 4
    [ "$status" -eq 0 ]
    [[ "$output" == *'"issue_number": ""'* ]]
    [[ "$output" == *'"base_ref": "main"'* ]]
}

@test "--help exits 0 and shows usage" {
    run bash "$SCRIPT" --help
    [ "$status" -eq 0 ]
    first_line=$(echo "$output" | head -1)
    [[ "$first_line" == *"Usage"* ]]
}

@test "no arguments exits 1" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "non-numeric PR number exits 1" {
    run bash "$SCRIPT" abc
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive integer"* ]]
}
