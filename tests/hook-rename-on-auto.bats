#!/usr/bin/env bats

# Tests for hook-rename-on-auto.sh
# Validates session title generation for /auto prompt patterns

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/hook-rename-on-auto.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Default mock gh: return a fixed title for issue 123
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
case "$*" in
  "issue view 123 --json title -q .title")
    echo "auto: Add auto-rename of session title"
    exit 0
    ;;
  "issue view 456 --json title -q .title")
    echo "Short title"
    exit 0
    ;;
  "issue view 999 --json title -q .title")
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
MOCK
    chmod +x "$MOCK_DIR/gh"
}

teardown() {
    rm -rf "$MOCK_DIR"
}

@test "numbered /auto 123 strips component prefix and sets sessionTitle" {
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    EVENT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.hookEventName')
    [ "$TITLE" = "auto #123: Add auto-rename of session title" ]
    [ "$EVENT" = "UserPromptSubmit" ]
}

@test "numbered /auto 123 --patch (flag after number) sets same sessionTitle" {
    INPUT='{"prompt":"/auto 123 --patch"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "auto #123: Add auto-rename of session title" ]
}

@test "--resume 456 produces resume format" {
    INPUT='{"prompt":"/auto --resume 456"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "auto #456 (resume): Short title" ]
}

@test "--batch single number produces batch count format" {
    INPUT='{"prompt":"/auto --batch 5"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "auto batch (5 issues)" ]
}

@test "--batch multiple numbers produces comma-joined format" {
    INPUT='{"prompt":"/auto --batch 123 124 125"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "auto batch #123,124,125" ]
}

@test "title without component prefix is preserved as-is" {
    INPUT='{"prompt":"/auto 456"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "auto #456: Short title" ]
}

@test "title exactly 50 chars is not truncated" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
# Title of 45 chars: "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrst"
# With "auto #123: " prefix (11 chars) = 56 chars total -> will be truncated
# Use 38-char title so "auto #123: " + 38 = 49 chars (no truncation)
echo "abcdefghijklmnopqrstuvwxyzabcdefghijkl"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    # "auto #123: " (11) + 38 = 49 chars, no truncation
    [ "$TITLE" = "auto #123: abcdefghijklmnopqrstuvwxyzabcdefghijkl" ]
}

@test "title resulting in over 50 chars is truncated to 49 chars plus ellipsis" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwx"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    # Output must end with ellipsis and be at most 52 bytes (49 ASCII + 3-byte UTF-8 ellipsis)
    [[ "$TITLE" == *"…" ]]
    # The non-ellipsis part must be 49 chars
    WITHOUT_ELLIPSIS="${TITLE%…}"
    [ ${#WITHOUT_ELLIPSIS} -eq 49 ]
}

@test "non-/auto prompt produces empty output" {
    INPUT='{"prompt":"/code 123"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    [ -z "$OUTPUT" ]
}

@test "--help flag produces empty output" {
    INPUT='{"prompt":"/auto --help"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    [ -z "$OUTPUT" ]
}

@test "/auto without number produces empty output" {
    INPUT='{"prompt":"/auto"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    [ -z "$OUTPUT" ]
}

@test "gh failure produces empty output (session name preserved)" {
    INPUT='{"prompt":"/auto 999"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    [ -z "$OUTPUT" ]
}

@test "missing prompt field in JSON produces empty output" {
    INPUT='{}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    [ -z "$OUTPUT" ]
}
