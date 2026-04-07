#!/usr/bin/env bats

# Tests for log-permission.sh
# Validates input parsing and log output of the PermissionRequest hook script

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/log-permission.sh"

setup() {
    export CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
    mkdir -p "$CLAUDE_PROJECT_DIR/.tmp"
}

teardown() {
    rm -rf "$CLAUDE_PROJECT_DIR"
}

@test "logs tool_name and tool_input from JSON input" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    LOG_FILE="$CLAUDE_PROJECT_DIR/.tmp/permission-log.txt"
    [ -f "$LOG_FILE" ]
    grep -q "| Bash |" "$LOG_FILE"
    grep -q '{"command":"ls -la"}' "$LOG_FILE"
}

@test "outputs ask decision as JSON" {
    INPUT='{"tool_name":"Read","tool_input":{"file":"/tmp/test.txt"}}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    [ "$OUTPUT" = '{"decision": "ask"}' ]
}

@test "handles missing tool_name gracefully" {
    INPUT='{"tool_input":{"file":"/tmp/test.txt"}}'
    OUTPUT=$(echo "$INPUT" | bash "$SCRIPT")
    LOG_FILE="$CLAUDE_PROJECT_DIR/.tmp/permission-log.txt"
    grep -q "| unknown |" "$LOG_FILE"
    [ "$OUTPUT" = '{"decision": "ask"}' ]
}

@test "truncates long tool_input to 200 chars" {
    # Generate tool_input longer than 200 characters
    LONG_INPUT=$(python3 -c "print('x' * 300)")
    INPUT="{\"tool_name\":\"Bash\",\"tool_input\":\"${LONG_INPUT}\"}"
    echo "$INPUT" | bash "$SCRIPT"
    LOG_FILE="$CLAUDE_PROJECT_DIR/.tmp/permission-log.txt"
    LINE=$(cat "$LOG_FILE")
    # Extract the tool_input portion (after second |)
    TOOL_INPUT_PART=$(echo "$LINE" | awk -F'|' '{print $3}' | xargs)
    [ ${#TOOL_INPUT_PART} -le 200 ]
}

@test "creates .tmp directory if not exists" {
    rm -rf "$CLAUDE_PROJECT_DIR/.tmp"
    INPUT='{"tool_name":"Write","tool_input":{"file":"/tmp/out.txt"}}'
    echo "$INPUT" | bash "$SCRIPT"
    [ -d "$CLAUDE_PROJECT_DIR/.tmp" ]
    [ -f "$CLAUDE_PROJECT_DIR/.tmp/permission-log.txt" ]
}

@test "appends multiple log entries" {
    INPUT1='{"tool_name":"Bash","tool_input":{"command":"echo hello"}}'
    INPUT2='{"tool_name":"Read","tool_input":{"file":"/tmp/a.txt"}}'
    echo "$INPUT1" | bash "$SCRIPT"
    echo "$INPUT2" | bash "$SCRIPT"
    LOG_FILE="$CLAUDE_PROJECT_DIR/.tmp/permission-log.txt"
    LINE_COUNT=$(wc -l < "$LOG_FILE")
    [ "$LINE_COUNT" -eq 2 ]
}

@test "log entry contains timestamp in expected format" {
    INPUT='{"tool_name":"Bash","tool_input":{"command":"date"}}'
    echo "$INPUT" | bash "$SCRIPT"
    LOG_FILE="$CLAUDE_PROJECT_DIR/.tmp/permission-log.txt"
    # Verify timestamp format: YYYY-MM-DD HH:MM:SS
    grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \|' "$LOG_FILE"
}
