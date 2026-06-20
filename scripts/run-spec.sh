#!/bin/bash
# run-spec.sh - Autonomous /spec execution with Sonnet model
# Usage: run-spec.sh <issue-number> [--opus] [--fable] [--max]

set -euo pipefail
ISSUE_NUMBER="${1:?Usage: run-spec.sh <issue-number> [--opus] [--fable] [--max]}"
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
    --fable)
      MODEL="claude-fable-5"
      EFFORT="high"
      shift
      ;;
    --max)
      EFFORT="max"
      shift
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      echo "Usage: run-spec.sh <issue-number> [--opus] [--fable] [--max]" >&2
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

AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"
export AUTO_EVENTS_LOG

PERMISSION_MODE=$("$SCRIPT_DIR/get-config-value.sh" permission-mode auto 2>/dev/null || echo auto)
if [[ "$PERMISSION_MODE" == "auto" ]]; then
  PERMISSION_FLAG="--permission-mode auto"
  _PERM_LABEL="permission-mode auto (with allow rules template)"
else
  PERMISSION_FLAG="--dangerously-skip-permissions"
  _PERM_LABEL="skip (autonomous mode)"
fi

echo "=== run-spec.sh: Starting /spec for issue #${ISSUE_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
source "$SCRIPT_DIR/watchdog-defaults.sh"
print_start_banner "issue" "$ISSUE_NUMBER" "spec"
echo "Model: ${MODEL}"
echo "Effort: ${EFFORT}"
echo "Permissions: ${_PERM_LABEL}"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"
if [[ "$MODEL" == "claude-fable-5" ]]; then
  echo "WARNING: Fable 5 is currently suspended (government directive to Anthropic, 2026-06-13~). API will likely return an error."
  echo "WARNING: Fable 5 opt-in — cost \$10/\$50 per MTok (2x Opus 4.8, ~3.3x Sonnet)"
  echo "WARNING: Usage credits required after 2026-06-22 (subscription plans)"
  echo "WARNING: 30-day retention required — ZDR organizations not supported"
fi

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

source "$SCRIPT_DIR/guard-prefix.sh"

PROMPT="${GUARD_PREFIX}

${SKILL_BODY}

ARGUMENTS: ${ISSUE_NUMBER} --non-interactive"

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
load_watchdog_timeout "$SCRIPT_DIR" "spec"

SECONDS=0
set +e
ANTHROPIC_MODEL="${MODEL}" \
  WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
  env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
    --model "${MODEL}" \
    --effort "${EFFORT}" \
    $PERMISSION_FLAG
EXIT_CODE=$?
set -e
"$SCRIPT_DIR/handle-permission-mode-failure.sh" "$EXIT_CODE" "$SECONDS" "$PERMISSION_MODE"

if [[ $EXIT_CODE -eq 143 || $EXIT_CODE -eq 0 ]]; then
  _reconcile_out=$("$SCRIPT_DIR/reconcile-phase-state.sh" spec "$ISSUE_NUMBER" --check-completion 2>/dev/null) || true
  if [[ $EXIT_CODE -eq 143 ]]; then
    if echo "$_reconcile_out" | grep -q '"matches_expected":true'; then
      EXIT_CODE=0
    fi
  elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then
    echo "Warning: claude exited 0 but spec phase did not complete (silent no-op). reconcile: $_reconcile_out" >&2
    EXIT_CODE=1
  fi
fi

echo "---"
echo "=== run-spec.sh: Finished /spec for issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER" "spec"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
