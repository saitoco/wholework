#!/bin/bash
# run-code.sh - Autonomous /code execution with Sonnet model
# Usage: run-code.sh <issue-number> [--patch|--pr] [--base <branch>]

set -euo pipefail
ISSUE_NUMBER="${1:?Usage: run-code.sh <issue-number> [--patch|--pr] [--base <branch>]}"
shift

# Parse options
ROUTE_FLAG=""
BASE_FLAG=""
BASE_BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --patch|--pr)
      if [[ -n "$ROUTE_FLAG" ]]; then
        echo "Error: --patch and --pr cannot be specified together" >&2
        exit 1
      fi
      ROUTE_FLAG="$1"
      shift
      ;;
    --base)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --base requires a branch name" >&2
        exit 1
      fi
      BASE_BRANCH="$2"
      BASE_FLAG="--base $2"
      shift 2
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: run-code.sh <issue-number> [--patch|--pr] [--base <branch>]" >&2
      exit 1
      ;;
  esac
done

# Validate issue number is numeric
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric: $ISSUE_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== run-code.sh: Starting /code for issue #${ISSUE_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "issue" "$ISSUE_NUMBER"
echo "Model: sonnet"
echo "Effort: high"
echo "Permissions: skip (autonomous mode)"
if [[ "$ROUTE_FLAG" == "--patch" ]]; then
  echo "Route: patch (${BASE_BRANCH:-main} direct commit)"
elif [[ "$ROUTE_FLAG" == "--pr" ]]; then
  echo "Route: pr (branch + PR)"
fi
if [[ -n "$BASE_BRANCH" ]]; then
  echo "Base branch: ${BASE_BRANCH}"
fi
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Pass SKILL.md body directly as prompt (avoids context: fork issue)
# /code has context: fork, so calling it via claude -p "/code N" prevents
# --dangerously-skip-permissions from propagating to the fork sub-agent (#284)
# By passing SKILL.md body directly, we bypass frontmatter interpretation
SKILL_FILE="${SCRIPT_DIR}/../skills/code/SKILL.md"

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

# Include route flag and base flag in ARGUMENTS
EXTRA_FLAGS=""
if [[ -n "$ROUTE_FLAG" ]]; then
  EXTRA_FLAGS="${EXTRA_FLAGS} ${ROUTE_FLAG}"
fi
if [[ -n "$BASE_FLAG" ]]; then
  EXTRA_FLAGS="${EXTRA_FLAGS} ${BASE_FLAG}"
fi

if [[ -n "$EXTRA_FLAGS" ]]; then
  PROMPT="${SKILL_BODY}

ARGUMENTS: ${ISSUE_NUMBER}${EXTRA_FLAGS} --non-interactive"
else
  PROMPT="${SKILL_BODY}

ARGUMENTS: ${ISSUE_NUMBER} --non-interactive"
fi

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
set +e
ANTHROPIC_MODEL=claude-sonnet-4-6 \
  env -u CLAUDECODE claude -p "$PROMPT" \
    --model claude-sonnet-4-6 \
    --effort high \
    --dangerously-skip-permissions
EXIT_CODE=$?
set -e

echo "---"
echo "=== run-code.sh: Finished /code for issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
