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

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

PERMISSION_MODE=$("$SCRIPT_DIR/get-config-value.sh" permission-mode bypass 2>/dev/null || echo bypass)
if [[ "$PERMISSION_MODE" == "auto" ]]; then
  PERMISSION_FLAG="--permission-mode auto"
  _PERM_LABEL="permission-mode auto (with allow rules template)"
else
  PERMISSION_FLAG="--dangerously-skip-permissions"
  _PERM_LABEL="skip (autonomous mode)"
fi

echo "=== run-merge.sh: Starting /merge for PR #${PR_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
source "$SCRIPT_DIR/watchdog-defaults.sh"
print_start_banner "pr" "$PR_NUMBER" "merge"
echo "Model: sonnet"
echo "Effort: low"
echo "Permissions: ${_PERM_LABEL}"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Wait for CI checks to complete before running claude
"$SCRIPT_DIR/wait-ci-checks.sh" "$PR_NUMBER"

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

ARGUMENTS: ${PR_NUMBER} --non-interactive"

# Specify --model and ANTHROPIC_MODEL both (workaround for -p mode bug)
# See: https://github.com/anthropics/claude-code/issues/22362
load_watchdog_timeout "$SCRIPT_DIR"

set +e
ANTHROPIC_MODEL=sonnet \
  WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
  env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
    --model sonnet \
    --effort low \
    $PERMISSION_FLAG
EXIT_CODE=$?
set -e

if [[ $EXIT_CODE -eq 143 ]]; then
  _MERGE_ISSUE=$("$SCRIPT_DIR/gh-extract-issue-from-pr.sh" "$PR_NUMBER" 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('issue_number',''))" 2>/dev/null || echo "")
  if [[ -n "$_MERGE_ISSUE" ]]; then
    if "$SCRIPT_DIR/watchdog-reconcile.sh" merge "$_MERGE_ISSUE" --pr "$PR_NUMBER"; then
      EXIT_CODE=0
    fi
  else
    echo "watchdog-reconcile: could not extract issue number from PR #${PR_NUMBER}, skipping reconcile" >&2
  fi
fi

# Post-validation: guard against silent no-op (claude exits 0 but merge never happened)
if [[ $EXIT_CODE -eq 0 ]]; then
  PR_STATE=$(gh pr view "$PR_NUMBER" --json state -q .state 2>/dev/null || echo "")
  if [[ -n "$PR_STATE" && "$PR_STATE" != "MERGED" ]]; then
    echo "Warning: PR #${PR_NUMBER} state is '${PR_STATE}', not MERGED. Merge may have failed." >&2
    EXIT_CODE=1
  fi
fi

echo "---"
echo "=== run-merge.sh: Finished /merge for PR #${PR_NUMBER} ==="
print_end_banner "pr" "$PR_NUMBER" "merge"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
