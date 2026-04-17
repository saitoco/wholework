#!/bin/bash
# run-spec.sh - Autonomous /spec execution with Sonnet model
# Usage: run-spec.sh <issue-number> [--opus]

set -euo pipefail
ISSUE_NUMBER="${1:?Usage: run-spec.sh <issue-number> [--opus]}"
shift

# Parse options
# Default: --model sonnet (override: --model opus with --opus flag)
MODEL="sonnet"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --opus)
      MODEL="opus"
      shift
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: run-spec.sh <issue-number> [--opus]" >&2
      exit 1
      ;;
  esac
done

# Validate issue number is numeric
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric: $ISSUE_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

echo "=== run-spec.sh: Starting /spec for issue #${ISSUE_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
print_start_banner "issue" "$ISSUE_NUMBER" "spec"
echo "Model: ${MODEL}"
echo "Effort: max"
echo "Permissions: skip (autonomous mode)"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Pass SKILL.md body directly as prompt (avoids context: fork issue)
SKILL_FILE="${SCRIPT_DIR}/../skills/spec/SKILL.md"

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

ARGUMENTS: ${ISSUE_NUMBER} --non-interactive"

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
set +e
ANTHROPIC_MODEL="${MODEL}" \
  env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
    --model "${MODEL}" \
    --effort max \
    --dangerously-skip-permissions
EXIT_CODE=$?
set -e

echo "---"
echo "=== run-spec.sh: Finished /spec for issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER" "spec"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
