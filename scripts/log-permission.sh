#!/bin/bash
# PermissionRequest hook: Log all permission prompts
# Output destination: $CLAUDE_PROJECT_DIR/.tmp/permission-log.txt

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input | tostring' | cut -c1-200)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

LOG_DIR="${CLAUDE_PROJECT_DIR}/.tmp"
mkdir -p "$LOG_DIR"
echo "${TIMESTAMP} | ${TOOL} | ${TOOL_INPUT}" >> "${LOG_DIR}/permission-log.txt"

# PermissionRequest hook must return a decision
# "ask" = show normal confirmation prompt
echo '{"decision": "ask"}'
