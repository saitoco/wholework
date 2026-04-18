#!/bin/bash
# run-spec.sh - Autonomous /spec execution with Sonnet model
# Usage: run-spec.sh <issue-number> [--opus] [--max]

set -euo pipefail
ISSUE_NUMBER="${1:?Usage: run-spec.sh <issue-number> [--opus] [--max]}"
shift

# Parse options
# Default: --model sonnet, --effort max (Opus path: xhigh by default, max with --max)
MODEL="sonnet"
EFFORT="max"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --opus)
      MODEL="opus"
      EFFORT="xhigh"
      shift
      ;;
    --max)
      EFFORT="max"
      shift
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: run-spec.sh <issue-number> [--opus] [--max]" >&2
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
echo "Effort: ${EFFORT}"
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
WATCHDOG_TIMEOUT=$("$SCRIPT_DIR/get-config-value.sh" watchdog-timeout-seconds 1800 2>/dev/null || echo 1800)
if ! echo "$WATCHDOG_TIMEOUT" | grep -qE '^[0-9]+$' || [[ "$WATCHDOG_TIMEOUT" -le 0 ]]; then
  echo "Warning: invalid watchdog-timeout-seconds '${WATCHDOG_TIMEOUT}', using default 1800" >&2
  WATCHDOG_TIMEOUT=1800
fi

set +e
ANTHROPIC_MODEL="${MODEL}" \
  WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
  env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
    --model "${MODEL}" \
    --effort "${EFFORT}" \
    --dangerously-skip-permissions
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 143 ]]; then
  if "$SCRIPT_DIR/watchdog-reconcile.sh" spec "$ISSUE_NUMBER"; then
    EXIT_CODE=0
  fi
fi

echo "---"
echo "=== run-spec.sh: Finished /spec for issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER" "spec"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
