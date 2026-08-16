#!/usr/bin/env bats

# Tests for scripts/scan-pending-ac.sh's Issue population fetch.
#
# Scope: this suite only verifies the `--state all` population fix (Issue
# #1242). Post-merge section scoping, --facts token filtering, gh-failure
# fail-open behavior, and --max-candidates truncation are already covered by
# tests/run-fact-matching.bats and are not duplicated here.

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/scan-pending-ac.sh"

setup() {
    cd "$PROJECT_ROOT"

    export MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    printf '%s\n' "$@" >> "$MOCK_DIR/gh-list-args.txt"
    echo "[]"
    exit 0
fi
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "population: gh issue list is called with --state all, not --state closed (issue #1242)" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    args_joined="$(tr '\n' ' ' < "$MOCK_DIR/gh-list-args.txt")"
    [[ "$args_joined" == *"--state all"* ]]
    [[ "$args_joined" != *"--state closed"* ]]
}

@test "population: gh issue list is called with the phase/verify label and --json number,body" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    args_joined="$(tr '\n' ' ' < "$MOCK_DIR/gh-list-args.txt")"
    [[ "$args_joined" == *"--label phase/verify"* ]]
    [[ "$args_joined" == *"--json number,body"* ]]
}

@test "html-comment scoped tag extraction: prose quoting a tag name does not override the real tag (issue #1273)" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
if [[ "$1" == "issue" && "$2" == "list" ]]; then
    printf '%s' '[{"number":9001,"body":"## Acceptance Criteria\n\n### Post-merge\n\n- [ ] prose quotes `verify-type: manual` but the real tag is observation <!-- verify-type: observation -->\n- [ ] a normal observation line <!-- verify-type: observation event=auto-run -->\n- [ ] a line with no tag and no verify command\n"}]'
    exit 0
fi
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]

    # (a) condition prose quoting a different tag name is classified by the real
    # (HTML-comment-scoped) tag, not by the substring the prose quotes.
    ac1_type=$(echo "$output" | jq -r '.[] | select(.ac_index==1) | .verify_type')
    [ "$ac1_type" = "observation" ]

    # (b) a normal tagged line is classified as before.
    ac2_type=$(echo "$output" | jq -r '.[] | select(.ac_index==2) | .verify_type')
    [ "$ac2_type" = "observation" ]

    # (c) a line with neither a verify-type tag nor a verify command falls back
    # to manual.
    ac3_type=$(echo "$output" | jq -r '.[] | select(.ac_index==3) | .verify_type')
    [ "$ac3_type" = "manual" ]
}
