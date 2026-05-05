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

# Pattern matching (first match wins; only one pattern is reported per run)
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
elif grep -q '"matches_expected":false' "$LOG_FILE" && grep -q '"phase":"code-pr"' "$LOG_FILE"; then
  PATTERN_NAME="code-completed-no-pr"
  ANOMALY_DESC="Watchdog killed the process in phase \`$PHASE\` (exit code $EXIT_CODE) after code-pr completed its commits but before PR creation: \`matches_expected:false\` and \`phase:code-pr\` detected in reconcile-phase-state output. The run-code.sh phase exited without creating a PR. Reference: #415."
  IMPROVEMENT_HINT="Follow the recovery procedure at \`modules/orchestration-fallbacks.md#code-completed-no-pr\`: checkout the worktree branch, rebase onto latest main, push the branch, and create the PR with \`gh pr create\`, then continue with \`/review\`."
elif grep -q "watchdog: kill and state not reached" "$LOG_FILE"; then
  PATTERN_NAME="watchdog-kill"
  ANOMALY_DESC="Watchdog killed the process in phase \`$PHASE\` (exit code $EXIT_CODE): \`watchdog: kill and state not reached\` detected. The phase did not complete within the timeout."
  IMPROVEMENT_HINT="Increase \`watchdog-timeout-seconds\` in \`.wholework.yml\` or improve liveness signals (progress output) to prevent false-positive kills. Related: #308."
elif grep -q "VERIFY_FAILED" "$LOG_FILE" && grep -q "uncommitted" "$LOG_FILE"; then
  PATTERN_NAME="dirty-working-tree"
  ANOMALY_DESC="Verify failed due to uncommitted changes in phase \`$PHASE\` (exit code $EXIT_CODE): \`VERIFY_FAILED\` and \`uncommitted\` detected in wrapper output. The verify skill cannot run when uncommitted changes are present in the working tree. Reference: #393."
  IMPROVEMENT_HINT="Run \`git status\` to identify uncommitted files. If the files are unrelated to issue #$ISSUE_NUMBER, notify and retry via \`run-verify.sh $ISSUE_NUMBER\`. If the files are related to the issue (unexpected edits), abort and investigate before retrying. See \`modules/orchestration-fallbacks.md#dirty-working-tree\` for the full recovery procedure."
elif grep -q '"matches_expected":false' "$LOG_FILE" && grep -q "Review Summary" "$LOG_FILE"; then
  PATTERN_NAME="reconciler-header-mismatch"
  ANOMALY_DESC="Reconciler detected header mismatch in phase \`$PHASE\` (exit code $EXIT_CODE): \`matches_expected:false\` and \`Review Summary\` pattern detected in wrapper output. The reconciler could not find \`## Review Response Summary\` in the PR comment, indicating a mismatch between the skill output header and the reconciler's expected pattern. Reference: #394."
  IMPROVEMENT_HINT="Check whether \`run-review.sh\` or the review skill changed the header format of the PR comment. The reconciler expects \`## Review Response Summary\` as defined in \`modules/phase-state.md\`. See \`modules/orchestration-fallbacks.md#reconciler-header-mismatch\` for the full recovery procedure."
elif [[ "$EXIT_CODE" == "0" ]]; then
  if grep -qiE "完了しました|commit and push|successfully committed|pushed to|changes have been committed" "$LOG_FILE" && \
     ! git log --oneline -5 2>/dev/null | grep -q "#${ISSUE_NUMBER}"; then
    PATTERN_NAME="silent-no-op"
    ANOMALY_DESC="LLM reported success in phase \`$PHASE\` (exit code 0) but no commit for #$ISSUE_NUMBER found in recent git log. Possible silent no-op: output indicated completion but no code was committed. Reference: #365."
    IMPROVEMENT_HINT="Re-run \`run-code.sh $ISSUE_NUMBER\` to retry the code phase. If a second run also fails to produce a commit, escalate to manual implementation. See Issue #365 for a known case of this pattern."
  fi
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
