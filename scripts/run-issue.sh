#!/bin/bash
# run-issue.sh - Autonomous /issue execution with Sonnet model
# Usage: run-issue.sh <issue-number>

set -euo pipefail
ISSUE_NUMBER="${1:?Usage: run-issue.sh <issue-number>}"
shift

# Validate issue number is numeric
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric: $ISSUE_NUMBER" >&2
  exit 1
fi

# Reject unexpected arguments
if [[ $# -gt 0 ]]; then
  echo "Error: Unexpected arguments: $*" >&2
  echo "Usage: run-issue.sh <issue-number>" >&2
  exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

PERMISSION_MODE=$("$SCRIPT_DIR/get-config-value.sh" permission-mode bypass 2>/dev/null || echo bypass)
if [[ "$PERMISSION_MODE" == "auto" ]]; then
  PERMISSION_FLAG="--permission-mode auto"
  _PERM_LABEL="permission-mode auto (with allow rules template)"
else
  PERMISSION_FLAG="--dangerously-skip-permissions"
  _PERM_LABEL="skip (autonomous mode)"
fi

echo "=== run-issue.sh: Starting /issue for issue #${ISSUE_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "issue" "$ISSUE_NUMBER" "issue"
echo "Model: sonnet"
echo "Effort: high"
echo "Permissions: ${_PERM_LABEL}"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Pass SKILL.md body directly as prompt to inject --non-interactive into ARGUMENTS.
# claude -p "/issue N" invokes the skill with no ARGUMENTS override, so the
# --non-interactive flag cannot be passed that way. Appending "ARGUMENTS: N --non-interactive"
# to the body text is the only way to set the flag for non-interactive execution.
SKILL_FILE="${SCRIPT_DIR}/../skills/issue/SKILL.md"

if [[ ! -f "$SKILL_FILE" ]]; then
  echo "Error: SKILL.md not found: $SKILL_FILE" >&2
  exit 1
fi

# Strip frontmatter (---...---) and extract body
# Detect the first --- after line 1 and take everything from the next line onward
FRONTMATTER_END=$(awk 'NR>1 && /^---$/{print NR; exit}' "$SKILL_FILE")
if [[ -z "$FRONTMATTER_END" ]]; then
  echo "Error: SKILL.md frontmatter not found" >&2
  exit 1
fi
SKILL_BODY=$(tail -n +"$((FRONTMATTER_END + 1))" "$SKILL_FILE")

PROMPT="${SKILL_BODY}

ARGUMENTS: ${ISSUE_NUMBER} --non-interactive"

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
WATCHDOG_TIMEOUT=$("$SCRIPT_DIR/get-config-value.sh" watchdog-timeout-seconds 1800 2>/dev/null || echo 1800)
if ! echo "$WATCHDOG_TIMEOUT" | grep -qE '^[0-9]+$' || [[ "$WATCHDOG_TIMEOUT" -le 0 ]]; then
  echo "Warning: invalid watchdog-timeout-seconds '${WATCHDOG_TIMEOUT}', using default 1800" >&2
  WATCHDOG_TIMEOUT=1800
fi

set +e
ANTHROPIC_MODEL=sonnet \
  WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
  env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
    --model sonnet \
    --effort high \
    $PERMISSION_FLAG
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 143 ]]; then
  if "$SCRIPT_DIR/watchdog-reconcile.sh" issue "$ISSUE_NUMBER"; then
    EXIT_CODE=0
  fi
fi

echo "---"
echo "=== run-issue.sh: Finished /issue for issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER" "issue"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
