#!/bin/bash
# run-verify.sh - Autonomous /verify execution with Sonnet model
# Usage: run-verify.sh <issue-number> [--base <branch>]

set -euo pipefail
ISSUE_NUMBER="${1:?Usage: run-verify.sh <issue-number> [--base <branch>]}"

# Validate issue number is numeric
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric: $ISSUE_NUMBER" >&2
  exit 1
fi

# --- Option parsing ---
BASE_BRANCH=""
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --base requires a branch name" >&2
        exit 1
      fi
      BASE_BRANCH="$2"
      shift 2
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: run-verify.sh <issue-number> [--base <branch>]" >&2
      exit 1
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== run-verify.sh: Starting /verify for Issue #${ISSUE_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "issue" "$ISSUE_NUMBER" "verify"
echo "Model: sonnet"
echo "Effort: medium"
echo "Permissions: skip (autonomous mode)"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Pass SKILL.md body directly as prompt (avoids context: fork issue)
# /verify has context: fork, so calling it via claude -p "/verify N" prevents
# --dangerously-skip-permissions from propagating to the fork sub-agent (#284)
# By passing SKILL.md body directly, we bypass frontmatter interpretation
SKILL_FILE="${SCRIPT_DIR}/../skills/verify/SKILL.md"

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

# Build ARGUMENTS: include --base if specified
if [[ -n "$BASE_BRANCH" ]]; then
  PROMPT="${SKILL_BODY}

ARGUMENTS: ${ISSUE_NUMBER} --base ${BASE_BRANCH} --non-interactive"
else
  PROMPT="${SKILL_BODY}

ARGUMENTS: ${ISSUE_NUMBER} --non-interactive"
fi

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
VERIFY_TMPOUT=$(mktemp)
set +e
ANTHROPIC_MODEL=claude-sonnet-4-6 \
  env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
    --model claude-sonnet-4-6 \
    --effort medium \
    --dangerously-skip-permissions 2>&1 | tee "$VERIFY_TMPOUT"
EXIT_CODE=$?
set -e

# Output marker detection: non-zero exit if VERIFY_FAILED is present
if grep -q "VERIFY_FAILED" "$VERIFY_TMPOUT"; then
  echo "Error: verify output contained VERIFY_FAILED marker" >&2
  EXIT_CODE=1
fi
rm -f "$VERIFY_TMPOUT"

echo "---"
echo "=== run-verify.sh: Finished /verify for Issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER" "verify"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
