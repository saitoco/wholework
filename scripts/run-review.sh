#!/bin/bash
# run-review.sh - Autonomous /review execution with Sonnet model
# Usage: run-review.sh <pr-number> [--review-only] [--light | --full]

set -euo pipefail
PR_NUMBER="${1:?Usage: run-review.sh <pr-number>}"
shift
EXTRA_ARGS="$*"

# Validate PR number is numeric
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: PR number must be numeric: $PR_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== run-review.sh: Starting /review for PR #${PR_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "pr" "$PR_NUMBER" "review"
echo "Model: sonnet"
echo "Effort: high"
echo "Permissions: skip (autonomous mode)"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Pass SKILL.md body directly as prompt (avoids context: fork issue)
# /review has context: fork, so calling it via claude -p "/review N" prevents
# --dangerously-skip-permissions from propagating to the fork sub-agent (#284)
# By passing SKILL.md body directly, we bypass frontmatter interpretation
SKILL_FILE="${SCRIPT_DIR}/../skills/review/SKILL.md"

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
ARGUMENTS="${PR_NUMBER}"
if [[ -n "$EXTRA_ARGS" ]]; then
  ARGUMENTS="${ARGUMENTS} ${EXTRA_ARGS}"
fi
PROMPT="${SKILL_BODY}

ARGUMENTS: ${ARGUMENTS}"

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
echo "=== run-review.sh: Finished /review for PR #${PR_NUMBER} ==="
print_end_banner "pr" "$PR_NUMBER" "review"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
