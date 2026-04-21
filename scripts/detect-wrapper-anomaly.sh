#!/bin/bash
# detect-wrapper-anomaly.sh - Detect known failure patterns in shell wrapper output
# and generate Auto Retrospective markdown fragments.
#
# Usage: detect-wrapper-anomaly.sh --log <path> --exit-code <N> --issue <N> --phase <name>
#
# Outputs markdown fragment to stdout when a known pattern is matched.
# Outputs nothing (empty) when no pattern matches.

set -uo pipefail

LOG_FILE=""
EXIT_CODE=""
ISSUE_NUMBER=""
PHASE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      LOG_FILE="${2:-}"
      shift 2
      ;;
    --exit-code)
      EXIT_CODE="${2:-}"
      shift 2
      ;;
    --issue)
      ISSUE_NUMBER="${2:-}"
      shift 2
      ;;
    --phase)
      PHASE="${2:-}"
      shift 2
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$LOG_FILE" || -z "$EXIT_CODE" || -z "$ISSUE_NUMBER" || -z "$PHASE" ]]; then
  echo "Usage: detect-wrapper-anomaly.sh --log <path> --exit-code <N> --issue <N> --phase <name>" >&2
  exit 1
fi

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Error: log file not found: $LOG_FILE" >&2
  exit 1
fi

PATTERN_NAME=""
ANOMALY_DESC=""
IMPROVEMENT_HINT=""

if grep -q "Could not retrieve PR number" "$LOG_FILE"; then
  PATTERN_NAME="pr-extraction-failure"
  ANOMALY_DESC="PR extraction failed in phase \`$PHASE\` (exit code $EXIT_CODE): \`Could not retrieve PR number\` detected in wrapper output. See #311 for root cause (gh pr list glob non-support)."
  IMPROVEMENT_HINT="Use \`gh pr list --head\` with exact branch name match instead of glob patterns. Reference: #311."
elif grep -q "Patch lock acquisition timeout" "$LOG_FILE"; then
  PATTERN_NAME="patch-lock-timeout"
  ANOMALY_DESC="Patch lock acquisition timed out in phase \`$PHASE\` (exit code $EXIT_CODE): \`Patch lock acquisition timeout\` detected. Another process may have held the lock or the previous run did not release it."
  IMPROVEMENT_HINT="Adjust \`patch-lock-timeout\` in \`.wholework.yml\` or investigate stale lock files under \`.claude/\`. Consider lock design review if timeouts recur."
elif grep -q "ERROR: missing sign-off" "$LOG_FILE"; then
  PATTERN_NAME="dco-missing"
  ANOMALY_DESC="DCO sign-off missing in phase \`$PHASE\` (exit code $EXIT_CODE): \`ERROR: missing sign-off\` detected. Commit was created without \`git commit -s\`."
  IMPROVEMENT_HINT="Ensure \`git commit -s\` is used in all SKILL.md commit steps. Check the corresponding skill's commit instructions for missing \`-s\` flag."
elif grep -q "watchdog: kill and state not reached" "$LOG_FILE"; then
  PATTERN_NAME="watchdog-kill"
  ANOMALY_DESC="Watchdog killed the process in phase \`$PHASE\` (exit code $EXIT_CODE): \`watchdog: kill and state not reached\` detected. The phase did not complete within the timeout."
  IMPROVEMENT_HINT="Increase \`watchdog-timeout-seconds\` in \`.wholework.yml\` or improve liveness signals (progress output) to prevent false-positive kills. Related: #308."
fi

if [[ -z "$PATTERN_NAME" ]]; then
  exit 0
fi

cat <<EOF
### Orchestration Anomalies
- **[$PATTERN_NAME]** $ANOMALY_DESC

### Improvement Proposals
- $IMPROVEMENT_HINT
EOF
