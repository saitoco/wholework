#!/usr/bin/env bats

# Tests for gh-pr-review.sh (Pending Review + Line Comments approach)
# Mock external commands (gh) by placing them at the front of PATH

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/gh-pr-review.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Record file for verifying gh calls (args)
    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG

    # Record file for capturing API request body (stdin when --input -)
    GH_API_STDIN="$BATS_TEST_TMPDIR/gh_api_stdin.json"
    export GH_API_STDIN

    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "ARGS: \$@" >> "$GH_CALL_LOG"
# repo view: return dummy owner/repo
if [ "\$1" = "repo" ] && [ "\$2" = "view" ]; then
    echo "owner/repo"
    exit 0
fi
# api: capture stdin when --input - is used
if [ "\$1" = "api" ]; then
    if echo "\$@" | grep -q -- "--input"; then
        cat > "$GH_API_STDIN"
    fi
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

# --- Success cases ---

@test "success: review body only (no line comments) - COMMENT event" {
    echo "review body text" > "$BATS_TEST_TMPDIR/review.md"
    run bash "$SCRIPT" 159 "$BATS_TEST_TMPDIR/review.md"
    [ "$status" -eq 0 ]
    # gh api was called
    grep -q "ARGS: api repos/owner/repo/pulls/159/reviews --method POST --input -" "$GH_CALL_LOG"
    # payload contains event field
    grep -q '"event"' "$GH_API_STDIN"
    python3 -c "
import json, sys
payload = json.load(open('$GH_API_STDIN'))
assert payload['event'] == 'COMMENT', f'Expected COMMENT, got {payload[\"event\"]}'
assert 'comments' not in payload, 'comments should not be present'
"
}

@test "success: line comments with no MUST - COMMENT event" {
    echo "review body text" > "$BATS_TEST_TMPDIR/review.md"
    cat > "$BATS_TEST_TMPDIR/comments.json" <<'JSON'
[
  {"path": "scripts/example.sh", "line": 10, "body": "SHOULD fix this", "side": "RIGHT", "severity": "SHOULD"},
  {"path": "scripts/other.sh", "line": 20, "body": "CONSIDER refactor", "side": "RIGHT", "severity": "CONSIDER"}
]
JSON
    run bash "$SCRIPT" 159 "$BATS_TEST_TMPDIR/review.md" "$BATS_TEST_TMPDIR/comments.json"
    [ "$status" -eq 0 ]
    grep -q "ARGS: api repos/owner/repo/pulls/159/reviews --method POST --input -" "$GH_CALL_LOG"
    python3 -c "
import json
payload = json.load(open('$GH_API_STDIN'))
assert payload['event'] == 'COMMENT', f'Expected COMMENT, got {payload[\"event\"]}'
assert len(payload['comments']) == 2
# severity field should be excluded
for c in payload['comments']:
    assert 'severity' not in c, 'severity should be removed from API payload'
"
}

@test "success: line comments with MUST - REQUEST_CHANGES event" {
    echo "review body text" > "$BATS_TEST_TMPDIR/review.md"
    cat > "$BATS_TEST_TMPDIR/comments.json" <<'JSON'
[
  {"path": "scripts/example.sh", "line": 42, "body": "MUST fix this", "side": "RIGHT", "severity": "MUST"},
  {"path": "scripts/other.sh", "line": 10, "body": "SHOULD fix", "side": "RIGHT", "severity": "SHOULD"}
]
JSON
    run bash "$SCRIPT" 159 "$BATS_TEST_TMPDIR/review.md" "$BATS_TEST_TMPDIR/comments.json"
    [ "$status" -eq 0 ]
    grep -q "ARGS: api repos/owner/repo/pulls/159/reviews --method POST --input -" "$GH_CALL_LOG"
    python3 -c "
import json
payload = json.load(open('$GH_API_STDIN'))
assert payload['event'] == 'REQUEST_CHANGES', f'Expected REQUEST_CHANGES, got {payload[\"event\"]}'
assert len(payload['comments']) == 2
for c in payload['comments']:
    assert 'severity' not in c, 'severity should be removed from API payload'
"
}

@test "success: empty comments array - COMMENT event body only" {
    echo "review body text" > "$BATS_TEST_TMPDIR/review.md"
    echo "[]" > "$BATS_TEST_TMPDIR/comments.json"
    run bash "$SCRIPT" 159 "$BATS_TEST_TMPDIR/review.md" "$BATS_TEST_TMPDIR/comments.json"
    [ "$status" -eq 0 ]
    grep -q "ARGS: api repos/owner/repo/pulls/159/reviews --method POST --input -" "$GH_CALL_LOG"
    python3 -c "
import json
payload = json.load(open('$GH_API_STDIN'))
assert payload['event'] == 'COMMENT', f'Expected COMMENT, got {payload[\"event\"]}'
assert 'comments' not in payload, 'comments should not be present when input comments is empty'
"
}

@test "success: comments with null path/line are filtered" {
    echo "review body text" > "$BATS_TEST_TMPDIR/review.md"
    cat > "$BATS_TEST_TMPDIR/comments.json" <<'JSON'
[
  {"path": null, "line": 10, "body": "MUST but invalid path", "side": "RIGHT", "severity": "MUST"},
  {"path": "scripts/valid.sh", "line": 5, "body": "MUST valid comment", "side": "RIGHT", "severity": "MUST"},
  {"path": "scripts/other.sh", "line": null, "body": "SHOULD but invalid line", "side": "RIGHT", "severity": "SHOULD"}
]
JSON
    run bash "$SCRIPT" 159 "$BATS_TEST_TMPDIR/review.md" "$BATS_TEST_TMPDIR/comments.json"
    [ "$status" -eq 0 ]
    grep -q "ARGS: api repos/owner/repo/pulls/159/reviews --method POST --input -" "$GH_CALL_LOG"
    python3 -c "
import json
payload = json.load(open('$GH_API_STDIN'))
assert payload['event'] == 'REQUEST_CHANGES', f'Expected REQUEST_CHANGES, got {payload[\"event\"]}'
assert 'comments' in payload, 'comments should be present when there is at least one valid comment'
comments = payload['comments']
assert len(comments) == 1, f'Expected 1 valid comment, got {len(comments)}'
for c in comments:
    assert c.get('path') is not None, 'comment path should not be null'
    assert c.get('line') is not None, 'comment line should not be null'
    assert 'severity' not in c, 'severity should be removed from API payload'
"
}

# --- Error cases ---

@test "error: no arguments" {
    run bash "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "error: missing file path argument" {
    run bash "$SCRIPT" 159
    [ "$status" -eq 1 ]
}

@test "error: invalid PR number (non-numeric)" {
    echo "body" > "$BATS_TEST_TMPDIR/review.md"
    run bash "$SCRIPT" abc "$BATS_TEST_TMPDIR/review.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PR number must be a positive integer"* ]]
}

@test "error: review body file not found" {
    run bash "$SCRIPT" 159 "$BATS_TEST_TMPDIR/nonexistent.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"file not found"* ]]
}

@test "error: empty review body file" {
    echo -n "" > "$BATS_TEST_TMPDIR/empty.md"
    run bash "$SCRIPT" 159 "$BATS_TEST_TMPDIR/empty.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty review body"* ]]
}

@test "error: line comments file not found" {
    echo "review body" > "$BATS_TEST_TMPDIR/review.md"
    run bash "$SCRIPT" 159 "$BATS_TEST_TMPDIR/review.md" "$BATS_TEST_TMPDIR/nonexistent.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"file not found"* ]]
}

@test "error: line comments JSON is invalid" {
    echo "review body" > "$BATS_TEST_TMPDIR/review.md"
    echo "not valid json" > "$BATS_TEST_TMPDIR/bad.json"
    run bash "$SCRIPT" 159 "$BATS_TEST_TMPDIR/review.md" "$BATS_TEST_TMPDIR/bad.json"
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid line comments JSON"* ]]
}
