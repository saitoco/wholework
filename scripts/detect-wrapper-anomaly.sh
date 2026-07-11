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
elif grep -q '"matches_expected":false' "$LOG_FILE" && grep -q '"phase":"code-pr"' "$LOG_FILE" && ! grep -q '"matches_expected":true' "$LOG_FILE"; then
  # reconcile-first authority: a later matches_expected:true in the same log (e.g. code_retry_fire retry success) suppresses this anomaly
  PATTERN_NAME="code-completed-no-pr"
  ANOMALY_DESC="Watchdog killed the process in phase \`$PHASE\` (exit code $EXIT_CODE) after code-pr completed its commits but before PR creation: \`matches_expected:false\` and \`phase:code-pr\` detected in reconcile-phase-state output. The run-code.sh phase exited without creating a PR. Reference: #415."
  IMPROVEMENT_HINT="Follow the recovery procedure at \`modules/orchestration-fallbacks.md#code-completed-no-pr\`: checkout the worktree branch, rebase onto latest main, push the branch, and create the PR with \`gh pr create\`, then continue with \`/review\`."
elif [[ "$EXIT_CODE" == "143" ]] && grep -q "still waiting (json mode)" "$LOG_FILE"; then
  PATTERN_NAME="json-mode-silent-hang"
  ANOMALY_DESC="json mode silent hang in phase \`$PHASE\` (exit code $EXIT_CODE): \`watchdog: still waiting (json mode)\` detected in wrapper output. The forked session did not produce any output after launching in json mode, and the watchdog terminated it with SIGTERM."
  IMPROVEMENT_HINT="Follow the recovery procedure at \`modules/orchestration-fallbacks.md#json-mode-silent-hang\`: retry the phase once via the corresponding run-*.sh script. Rationale: transient API delay or session init stall."
elif grep -q "watchdog: kill and state not reached" "$LOG_FILE"; then
  PATTERN_NAME="watchdog-kill"
  ANOMALY_DESC="Watchdog killed the process in phase \`$PHASE\` (exit code $EXIT_CODE): \`watchdog: kill and state not reached\` detected. The phase did not complete within the timeout."
  IMPROVEMENT_HINT="Increase \`watchdog-timeout-seconds\` in \`.wholework.yml\` or improve liveness signals (progress output) to prevent false-positive kills. Related: #308."
elif grep -q "VERIFY_FAILED" "$LOG_FILE" && grep -q "uncommitted" "$LOG_FILE"; then
  PATTERN_NAME="dirty-working-tree"
  ANOMALY_DESC="Verify failed due to uncommitted changes in phase \`$PHASE\` (exit code $EXIT_CODE): \`VERIFY_FAILED\` and \`uncommitted\` detected in wrapper output. The verify skill cannot run when uncommitted changes are present in the working tree. Reference: #393."
  IMPROVEMENT_HINT="Run \`git status\` to identify uncommitted files. If the files are unrelated to issue #$ISSUE_NUMBER, notify and retry via \`/verify $ISSUE_NUMBER\`. If the files are related to the issue (unexpected edits), abort and investigate before retrying. See \`modules/orchestration-fallbacks.md#dirty-working-tree\` for the full recovery procedure."
elif grep -q '"matches_expected":false' "$LOG_FILE" && grep -q "Review Summary" "$LOG_FILE"; then
  PATTERN_NAME="reconciler-header-mismatch"
  ANOMALY_DESC="Reconciler detected header mismatch in phase \`$PHASE\` (exit code $EXIT_CODE): \`matches_expected:false\` and \`Review Summary\` pattern detected in wrapper output. The reconciler could not find \`## Review Response Summary\` in the PR comment, indicating a mismatch between the skill output header and the reconciler's expected pattern. Reference: #394."
  IMPROVEMENT_HINT="Check whether \`run-review.sh\` or the review skill changed the header format of the PR comment. The reconciler expects \`## Review Response Summary\` as defined in \`modules/phase-state.md\`. See \`modules/orchestration-fallbacks.md#reconciler-header-mismatch\` for the full recovery procedure."
elif grep -q '"matches_expected":false' "$LOG_FILE" && grep -q '"phase":"review"' "$LOG_FILE" && ! grep -q '"matches_expected":true' "$LOG_FILE"; then
  # reconcile-first authority: a later matches_expected:true in the same log (post-fallback-review-summary.sh recovery) suppresses this anomaly
  PATTERN_NAME="review-completion-false-negative"
  ANOMALY_DESC="Review phase completion false-negative in phase \`$PHASE\` (exit code $EXIT_CODE): \`matches_expected:false\` and \`phase:review\` detected in reconciler output, but no existing fallback header (## Review Response Summary / ## レビュー回答サマリ) was found in wrapper log. Likely caused by LLM omitting the \`<!-- review-summary -->\` marker and using a non-standard heading. Reference: #547."
  IMPROVEMENT_HINT="Follow the recovery procedure at \`modules/orchestration-fallbacks.md#review-completion-false-negative\`: re-run reconcile, check PR comments for summary, add \`<!-- review-summary -->\` marker if present, or re-run /review if absent."
elif grep -qiE "APIConnectionError|Request timed out|overloaded_error|529.*[Oo]verload" "$LOG_FILE"; then
  PATTERN_NAME="mid-run-api-error"
  ANOMALY_DESC="API connection error in phase \`$PHASE\` (exit code $EXIT_CODE): API connection/overload pattern detected in wrapper output. The forked session terminated mid-run before phase completion."
  IMPROVEMENT_HINT="Follow the recovery procedure at \`modules/orchestration-fallbacks.md#mid-run-api-error\`: run reconcile-phase-state.sh to check actual completion, restore the phase label if needed, then retry the phase once with the corresponding run-*.sh script."
elif [[ "$EXIT_CODE" == "0" ]]; then
  _merge_pr_confirmed_merged=false
  if [[ "$PHASE" == "merge" ]]; then
    _merge_pr_state=$(gh pr view "$ISSUE_NUMBER" --json state -q '.state' 2>/dev/null)
    if [[ $? -eq 0 && "$_merge_pr_state" == "MERGED" ]]; then
      _merge_pr_confirmed_merged=true
    fi
  fi
  _review_confirmed_posted=false
  if [[ "$PHASE" == "review" ]]; then
    _review_bodies=$(gh pr view "$ISSUE_NUMBER" --json reviews --jq '.reviews[].body' 2>/dev/null)
    if [[ $? -eq 0 ]] && echo "$_review_bodies" | grep -q "Acceptance Criteria Verification Results"; then
      _review_confirmed_posted=true
    fi
  fi
  if [[ "$_merge_pr_confirmed_merged" == "true" ]]; then
    : # merge phase live check: gh pr view confirms PR MERGED, skip silent-no-op detection entirely (fail-safe: gh failure or non-MERGED state falls through to existing logic below)
  elif [[ "$_review_confirmed_posted" == "true" ]]; then
    : # review phase live check: gh pr view confirms a Review with Acceptance Criteria Verification Results was posted, skip silent-no-op detection entirely (fail-safe: gh failure or no matching Review falls through to existing logic below)
  elif grep -q '"matches_expected":true' "$LOG_FILE"; then
    : # reconcile-first authority: matches_expected:true skips silent-no-op (covers async external commit recognition)
  elif grep -qiE "完了しました|commit and push|successfully committed|pushed to|changes have been committed" "$LOG_FILE"; then
    if ! git log --oneline -20 2>/dev/null | grep -q "#${ISSUE_NUMBER}"; then
      _found_on_origin=false
      if [[ "$PHASE" == "code-patch" || "$PHASE" == "code" ]]; then
        if git fetch origin main 2>/dev/null; then
          if git log origin/main --oneline -20 2>/dev/null | grep -q "#${ISSUE_NUMBER}"; then
            _found_on_origin=true
          fi
        fi
      fi
      if [[ "$_found_on_origin" == "false" ]]; then
        PATTERN_NAME="silent-no-op"
        ANOMALY_DESC="LLM reported success in phase \`$PHASE\` (exit code 0) but no commit for #$ISSUE_NUMBER found in recent git log. Possible silent no-op: output indicated completion but no code was committed. Reference: #365."
        IMPROVEMENT_HINT="Re-run \`run-code.sh $ISSUE_NUMBER\` to retry the code phase. If a second run also fails to produce a commit, escalate to manual implementation. See Issue #365 for a known case of this pattern."
      fi
    fi
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
