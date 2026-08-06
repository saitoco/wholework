#!/usr/bin/env bats

# Tests for post-fallback-review-summary.sh
# Mocks: gh (pr view --json reviews, pr comment)

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/post-fallback-review-summary.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    GH_CALL_LOG="$BATS_TEST_TMPDIR/gh_calls.log"
    export GH_CALL_LOG
    GH_COMMENT_BODY_FILE="$BATS_TEST_TMPDIR/gh_comment_body.txt"
    export GH_COMMENT_BODY_FILE
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "no AC Verification Results review: exits 1 without posting" {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
    echo '[{"state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z","body":"Looks good to me, no concerns."}]'
    exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "comment" ]]; then
    echo "ERROR: comment should not have been posted" >&2
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"skipping fallback post"* ]]
    ! grep -q "pr comment" "$GH_CALL_LOG"
}

@test "AC Verification Results review exists: posts marker comment" {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
    echo '[{"state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z","body":"## Acceptance Criteria Verification Results"}]'
    exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "comment" ]]; then
    for arg in "\$@"; do
        if [[ "\$prev" == "--body" ]]; then
            echo "\$arg" > "$GH_COMMENT_BODY_FILE"
        fi
        prev="\$arg"
    done
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "pr comment" "$GH_CALL_LOG"
    [[ "$(cat "$GH_COMMENT_BODY_FILE")" == "<!-- review-summary -->"* ]]
    grep -q "<!-- wholework-event: type=review-incomplete phase=review pr=123 -->" "$GH_COMMENT_BODY_FILE"
    grep -q "## Review Response Summary" "$GH_COMMENT_BODY_FILE"
}

@test "gh pr comment failure propagates as exit 1" {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
    echo '[{"state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z","body":"## Acceptance Criteria Verification Results"}]'
    exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "comment" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed to post fallback Review Response Summary"* ]]
}

@test "latest review is CHANGES_REQUESTED: exits 2 without posting (MUST unresolved guard)" {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
    echo '[{"state":"CHANGES_REQUESTED","submittedAt":"2026-01-01T00:00:00Z","body":"## Acceptance Criteria Verification Results\n\nMUST: fix X"}]'
    exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "comment" ]]; then
    echo "ERROR: comment should not have been posted" >&2
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 2 ]
    [[ "$output" == *"CHANGES_REQUESTED"* ]]
    ! grep -q "pr comment" "$GH_CALL_LOG"
}

@test "only latest review is judged: older CHANGES_REQUESTED, newer COMMENTED with AC results posts" {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
    echo '[{"state":"CHANGES_REQUESTED","submittedAt":"2026-01-01T00:00:00Z","body":"## Acceptance Criteria Verification Results\n\nMUST: fix X"},{"state":"COMMENTED","submittedAt":"2026-01-02T00:00:00Z","body":"## Acceptance Criteria Verification Results\n\nAll resolved."}]'
    exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "comment" ]]; then
    for arg in "\$@"; do
        if [[ "\$prev" == "--body" ]]; then
            echo "\$arg" > "$GH_COMMENT_BODY_FILE"
        fi
        prev="\$arg"
    done
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "pr comment" "$GH_CALL_LOG"
}

@test "author filter: third-party newer APPROVED does not override self CHANGES_REQUESTED" {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [[ "\$1" == "api" && "\$2" == "user" ]]; then
    echo "self-actor"
    exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
    echo '[{"state":"CHANGES_REQUESTED","submittedAt":"2026-01-01T00:00:00Z","body":"## Acceptance Criteria Verification Results\n\nMUST: fix X","author":{"login":"self-actor"}},{"state":"APPROVED","submittedAt":"2026-01-02T00:00:00Z","body":"LGTM","author":{"login":"third-party-bot"}}]'
    exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "comment" ]]; then
    echo "ERROR: comment should not have been posted" >&2
    exit 1
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 2 ]
    [[ "$output" == *"CHANGES_REQUESTED"* ]]
    ! grep -q "pr comment" "$GH_CALL_LOG"
}

@test "author filter: gh api user failure falls back to unfiltered latest-review behavior" {
    cat > "$MOCK_DIR/gh" <<MOCK
#!/bin/bash
echo "\$@" >> "$GH_CALL_LOG"
if [[ "\$1" == "api" && "\$2" == "user" ]]; then
    exit 1
fi
if [[ "\$1" == "pr" && "\$2" == "view" ]]; then
    echo '[{"state":"COMMENTED","submittedAt":"2026-01-01T00:00:00Z","body":"## Acceptance Criteria Verification Results","author":{"login":"self-actor"}}]'
    exit 0
fi
if [[ "\$1" == "pr" && "\$2" == "comment" ]]; then
    for arg in "\$@"; do
        if [[ "\$prev" == "--body" ]]; then
            echo "\$arg" > "$GH_COMMENT_BODY_FILE"
        fi
        prev="\$arg"
    done
    exit 0
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"

    run bash "$SCRIPT" 123
    [ "$status" -eq 0 ]
    grep -q "pr comment" "$GH_CALL_LOG"
}
