#!/usr/bin/env bats

# Tests for scripts/resolve-preview-ac-fallback.sh
# Mocks: gh (via PATH prepend). The mock does not interpret --jq — it returns
# canned output representing what `gh issue view --json comments --jq '...'`
# would print for the *latest* type=preview-ac-unverified marker comment body
# (the sort_by(.createdAt) | .[-1] narrowing is real gh's responsibility, not
# this script's — see Spec Uncertainty section).

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SCRIPT="$PROJECT_ROOT/scripts/resolve-preview-ac-fallback.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"
}

@test "fix-cycle re-verification: latest marker ac=none yields empty output" {
    # Simulates the staleness scenario this Issue fixes: an earlier /review run
    # left AC 2 and 5 UNCERTAIN, then a fix-cycle re-run verified them and the
    # latest marker (already narrowed to the single most-recent comment by
    # gh's jq sort_by/.[-1]) now carries ac=none.
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo '<!-- wholework-event: type=preview-ac-unverified phase=review issue=42 ac=none -->
All preview-tier AC were verified against the preview URL before merge.'
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "unresolved preview AC: latest marker ac=3 yields 3" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo '<!-- wholework-event: type=preview-ac-unverified phase=review issue=42 ac=3 -->
Preview-tier AC 3 could not be verified against the preview URL (UNCERTAIN) before merge.'
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ "$output" = "3" ]
}

@test "unresolved preview AC with multiple indices: latest marker ac=2,5 yields 2,5" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo '<!-- wholework-event: type=preview-ac-unverified phase=review issue=42 ac=2,5 -->
Preview-tier AC 2 and 5 could not be verified against the preview URL (UNCERTAIN) before merge.'
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ "$output" = "2,5" ]
}

@test "no marker comment: empty output, exit 0" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo ""
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "gh failure: fails open with empty output, exit 0" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
exit 1
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "multi-line body: marker line is picked over surrounding human-readable text" {
    cat > "$MOCK_DIR/gh" << 'MOCK_EOF'
#!/bin/bash
echo 'Some unrelated leading text without ac= in it
<!-- wholework-event: type=preview-ac-unverified phase=review issue=42 ac=7 -->
Trailing human-readable note.'
exit 0
MOCK_EOF
    chmod +x "$MOCK_DIR/gh"

    run "$SCRIPT" 42
    [ "$status" -eq 0 ]
    [ "$output" = "7" ]
}

@test "empty argument: exit 1" {
    run "$SCRIPT" ""
    [ "$status" -eq 1 ]
}

@test "non-numeric argument: exit 1" {
    run "$SCRIPT" "abc"
    [ "$status" -eq 1 ]
}

@test "no argument: exit 1" {
    run "$SCRIPT"
    [ "$status" -eq 1 ]
}
