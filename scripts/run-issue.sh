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

echo "=== run-issue.sh: Starting /issue for issue #${ISSUE_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "issue" "$ISSUE_NUMBER" "issue"
echo "Model: sonnet"
echo "Effort: high"
echo "Permissions: skip (autonomous mode)"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Pass SKILL.md body directly as prompt (avoids context: fork issue)
# /issue has context: fork, so calling it via claude -p "/issue N" prevents
# --dangerously-skip-permissions from propagating to the fork sub-agent (#284)
# By passing SKILL.md body directly, we bypass frontmatter interpretation
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
set +e
ANTHROPIC_MODEL=claude-sonnet-4-6 \
  env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
    --model claude-sonnet-4-6 \
    --effort high \
    --dangerously-skip-permissions
EXIT_CODE=$?
set -e

echo "---"
echo "=== run-issue.sh: Finished /issue for issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER" "issue"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
