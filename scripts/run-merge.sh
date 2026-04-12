#!/bin/bash
# run-merge.sh - Autonomous /merge execution with Sonnet model
# Usage: run-merge.sh <pr-number>

set -euo pipefail
PR_NUMBER="${1:?Usage: run-merge.sh <pr-number>}"

# Validate PR number is numeric
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: PR number must be numeric: $PR_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== run-merge.sh: Starting /merge for PR #${PR_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "pr" "$PR_NUMBER" "merge"
echo "Model: sonnet"
echo "Effort: low"
echo "Permissions: skip (autonomous mode)"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Pass SKILL.md body directly as prompt (same pattern as run-review.sh)
# /merge has no context: fork, but uses the same approach for consistency
# See: #284 (context: fork permission non-propagation issue)
SKILL_FILE="${SCRIPT_DIR}/../skills/merge/SKILL.md"

if [[ ! -f "$SKILL_FILE" ]]; then
  echo "Error: SKILL.md not found: $SKILL_FILE" >&2
  exit 1
fi

# Strip frontmatter (---...---) and extract body
FRONTMATTER_END=$(awk 'NR>1 && /^---$/{print NR; exit}' "$SKILL_FILE")
if [[ -z "$FRONTMATTER_END" ]]; then
  echo "Error: SKILL.md frontmatter not found" >&2
  exit 1
fi
SKILL_BODY=$(tail -n +"$((FRONTMATTER_END + 1))" "$SKILL_FILE")
PROMPT="${SKILL_BODY}

ARGUMENTS: ${PR_NUMBER}"

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
set +e
ANTHROPIC_MODEL=claude-sonnet-4-6 \
  env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
    --model claude-sonnet-4-6 \
    --effort low \
    --dangerously-skip-permissions
EXIT_CODE=$?
set -e

echo "---"
echo "=== run-merge.sh: Finished /merge for PR #${PR_NUMBER} ==="
print_end_banner "pr" "$PR_NUMBER" "merge"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
