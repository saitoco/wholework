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

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

PERMISSION_MODE=$("$SCRIPT_DIR/get-config-value.sh" permission-mode bypass 2>/dev/null || echo bypass)
if [[ "$PERMISSION_MODE" == "auto" ]]; then
  PERMISSION_FLAG="--permission-mode auto"
  _PERM_LABEL="permission-mode auto (with allow rules template)"
else
  PERMISSION_FLAG="--dangerously-skip-permissions"
  _PERM_LABEL="skip (autonomous mode)"
fi

echo "=== run-verify.sh: Starting /verify for Issue #${ISSUE_NUMBER} ==="
source "$SCRIPT_DIR/phase-banner.sh"
source "$SCRIPT_DIR/watchdog-defaults.sh"
print_start_banner "issue" "$ISSUE_NUMBER" "verify"
echo "Model: sonnet"
echo "Effort: medium"
echo "Permissions: ${_PERM_LABEL}"
echo "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "---"

# Detect associated PR for CI wait (patch route has no PR)
VERIFY_PR_NUMBER=$(gh pr list --head "worktree-code+issue-${ISSUE_NUMBER}" --state merged --json number -q '.[0].number' 2>/dev/null || echo "")
if [[ -n "$VERIFY_PR_NUMBER" ]]; then
  # pr route: wait for the associated PR's CI checks
  "$SCRIPT_DIR/wait-ci-checks.sh" "$VERIFY_PR_NUMBER"
else
  # patch route: wait for the latest branch workflow run
  _WAIT_BRANCH="${BASE_BRANCH:-main}"
  _RUN_ID=$(gh run list --branch "$_WAIT_BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || echo "")
  if [[ -n "$_RUN_ID" ]]; then
    TIMEOUT_SEC="${WHOLEWORK_CI_TIMEOUT_SEC:-1200}"
    echo "Waiting for ${_WAIT_BRANCH} branch CI run #${_RUN_ID} (patch route, timeout: ${TIMEOUT_SEC}s)..." >&2
    if command -v timeout >/dev/null 2>&1; then
      timeout "$TIMEOUT_SEC" gh run watch "$_RUN_ID" --interval 60 2>/dev/null || true
    elif command -v gtimeout >/dev/null 2>&1; then
      gtimeout "$TIMEOUT_SEC" gh run watch "$_RUN_ID" --interval 60 2>/dev/null || true
    else
      gh run watch "$_RUN_ID" --interval 60 2>/dev/null || true
    fi
    echo "CI run #${_RUN_ID} complete" >&2
  else
    echo "No CI runs found for ${_WAIT_BRANCH} branch (patch route), skipping CI wait" >&2
  fi
fi

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
load_watchdog_timeout "$SCRIPT_DIR"

VERIFY_TMPOUT=$(mktemp)
set +e
ANTHROPIC_MODEL=sonnet \
  WATCHDOG_TIMEOUT="$WATCHDOG_TIMEOUT" \
  env -u CLAUDECODE "$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" \
    --model sonnet \
    --effort medium \
    $PERMISSION_FLAG 2>&1 | tee "$VERIFY_TMPOUT"
EXIT_CODE=$?
set -e

# Output marker detection: non-zero exit if VERIFY_FAILED is present
if grep -q "VERIFY_FAILED" "$VERIFY_TMPOUT"; then
  echo "Error: verify output contained VERIFY_FAILED marker" >&2
  EXIT_CODE=1
fi
rm -f "$VERIFY_TMPOUT"

if [[ $EXIT_CODE -eq 143 ]]; then
  _reconcile_out=$("$SCRIPT_DIR/reconcile-phase-state.sh" verify "$ISSUE_NUMBER" --check-completion 2>/dev/null) || true
  if echo "$_reconcile_out" | grep -q '"matches_expected":true'; then
    EXIT_CODE=0
  fi
fi

echo "---"
echo "=== run-verify.sh: Finished /verify for Issue #${ISSUE_NUMBER} ==="
print_end_banner "issue" "$ISSUE_NUMBER" "verify"
echo "Exit code: ${EXIT_CODE}"
echo "Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
exit $EXIT_CODE
