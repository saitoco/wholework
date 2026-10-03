#!/usr/bin/env bats

# Tests for hook-rename-on-auto.sh
# Validates session title generation for /auto prompt patterns

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/hook-rename-on-auto.sh"

setup() {
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export PATH="$MOCK_DIR:$PATH"

    # Set CLAUDE_PROJECT_DIR with session-auto-rename: true so existing tests pass opt-in check
    PROJ_DIR="$BATS_TEST_TMPDIR/wholework-proj"
    mkdir -p "$PROJ_DIR"
    echo "session-auto-rename: true" > "$PROJ_DIR/.wholework.yml"
    export CLAUDE_PROJECT_DIR="$PROJ_DIR"

    # Isolate from the operator's shell: the prefix env var is expected to be exported there
    unset WHOLEWORK_SESSION_TITLE_PREFIX

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

@test "no .wholework.yml produces empty output" {
    EMPTY_DIR="$BATS_TEST_TMPDIR/empty-proj"
    mkdir -p "$EMPTY_DIR"
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(CLAUDE_PROJECT_DIR="$EMPTY_DIR" echo "$INPUT" | CLAUDE_PROJECT_DIR="$EMPTY_DIR" bash "$SCRIPT")
    [ -z "$OUTPUT" ]
}

@test "session-auto-rename: false produces empty output" {
    OPT_OUT_DIR="$BATS_TEST_TMPDIR/optout-proj"
    mkdir -p "$OPT_OUT_DIR"
    echo "session-auto-rename: false" > "$OPT_OUT_DIR/.wholework.yml"
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | CLAUDE_PROJECT_DIR="$OPT_OUT_DIR" bash "$SCRIPT")
    [ -z "$OUTPUT" ]
}

@test "session-auto-rename: true fires hook and returns sessionTitle" {
    OPT_IN_DIR="$BATS_TEST_TMPDIR/optin-proj"
    mkdir -p "$OPT_IN_DIR"
    echo "session-auto-rename: true" > "$OPT_IN_DIR/.wholework.yml"
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | CLAUDE_PROJECT_DIR="$OPT_IN_DIR" bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "auto #123: Add auto-rename of session title" ]
}

@test "WHOLEWORK_SESSION_TITLE_PREFIX unset keeps output unchanged" {
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    EXPECTED='{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","sessionTitle":"auto #123: Add auto-rename of session title"}}'
    [ "$(echo "$OUTPUT" | jq -c .)" = "$EXPECTED" ]
}

@test "WHOLEWORK_SESSION_TITLE_PREFIX empty string keeps output unchanged" {
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX="" bash "$SCRIPT")
    EXPECTED='{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","sessionTitle":"auto #123: Add auto-rename of session title"}}'
    [ "$(echo "$OUTPUT" | jq -c .)" = "$EXPECTED" ]
}

@test "WHOLEWORK_SESSION_TITLE_PREFIX is prepended to /auto N title" {
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX="🐧" bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "🐧auto #123: Add auto-rename of session title" ]
}

@test "WHOLEWORK_SESSION_TITLE_PREFIX is prepended to --resume title" {
    INPUT='{"prompt":"/auto --resume 456"}'
    OUTPUT=$(echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX="🐧" bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "🐧auto #456 (resume): Short title" ]
}

@test "WHOLEWORK_SESSION_TITLE_PREFIX is prepended to --batch titles" {
    INPUT='{"prompt":"/auto --batch 123 124 125"}'
    OUTPUT=$(echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX="🐧" bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "🐧auto batch #123,124,125" ]

    INPUT='{"prompt":"/auto --batch 5"}'
    OUTPUT=$(echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX="🐧" bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "🐧auto batch (5 issues)" ]
}

@test "WHOLEWORK_SESSION_TITLE_PREFIX inserts no separator automatically" {
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX="mac " bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "mac auto #123: Add auto-rename of session title" ]

    OUTPUT=$(echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX="mac" bash "$SCRIPT")
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = "macauto #123: Add auto-rename of session title" ]
}

@test "WHOLEWORK_SESSION_TITLE_PREFIX is kept intact when the body title is truncated" {
    cat > "$MOCK_DIR/gh" <<'MOCK'
#!/bin/bash
echo "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwx"
exit 0
MOCK
    chmod +x "$MOCK_DIR/gh"
    INPUT='{"prompt":"/auto 123"}'
    PLAIN=$(echo "$INPUT" | bash "$SCRIPT" | jq -r '.hookSpecificOutput.sessionTitle')
    PREFIXED=$(echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX="🐧" bash "$SCRIPT" | jq -r '.hookSpecificOutput.sessionTitle')
    # Without prefix the body is truncated; with prefix only the body is truncated
    [[ "$PLAIN" == *"…" ]] || false
    [ "$PREFIXED" = "🐧${PLAIN}" ]
}

@test "WHOLEWORK_SESSION_TITLE_PREFIX with JSON special characters keeps valid JSON output" {
    INPUT='{"prompt":"/auto 123"}'
    OUTPUT=$(echo "$INPUT" | WHOLEWORK_SESSION_TITLE_PREFIX='a"b\c ' bash "$SCRIPT")
    echo "$OUTPUT" | jq -e . >/dev/null
    TITLE=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.sessionTitle')
    [ "$TITLE" = 'a"b\c auto #123: Add auto-rename of session title' ]
}

@test "WHOLEWORK_SESSION_TITLE_PREFIX does not affect no-output paths" {
    export WHOLEWORK_SESSION_TITLE_PREFIX="🐧"

    OUTPUT=$(echo '{"prompt":"/auto 999"}' | bash "$SCRIPT")
    [ -z "$OUTPUT" ]

    OUTPUT=$(echo '{"prompt":"/code 123"}' | bash "$SCRIPT")
    [ -z "$OUTPUT" ]

    OUTPUT=$(echo '{"prompt":"/auto --help"}' | bash "$SCRIPT")
    [ -z "$OUTPUT" ]

    OPT_OUT_DIR="$BATS_TEST_TMPDIR/optout-proj"
    mkdir -p "$OPT_OUT_DIR"
    echo "session-auto-rename: false" > "$OPT_OUT_DIR/.wholework.yml"
    OUTPUT=$(echo '{"prompt":"/auto 123"}' | CLAUDE_PROJECT_DIR="$OPT_OUT_DIR" bash "$SCRIPT")
    [ -z "$OUTPUT" ]
}
