#!/usr/bin/env bash
# gh-pr-merge-status.sh - PR merge readiness check
#
# Usage: gh-pr-merge-status.sh <pr-number>
#
# Output (single JSON line):
#   {"mergeable": true/false, "reason": "...", "ci_status": "...", "review_status": "..."}
#
# reason values:
#   clean          - mergeable (CI passing, review approved)
#   has_hooks      - mergeable (after required hooks run)
#   conflicts      - has merge conflicts
#   review_pending - review not yet approved
#   ci_failing     - CI checks failing
#   behind_base    - branch is behind base branch
#   unknown        - unable to determine
#
# exit codes:
#   0  - success (merge status determined)
#   1  - error (gh fetch failed or invalid arguments)
#   2  - polling timeout (mergeable=UNKNOWN persisted after all retries)

set -euo pipefail

USAGE="Usage: $(basename "$0") <pr-number>"

if [[ "${1:-}" == "--help" ]]; then
  echo "$USAGE"
  echo ""
  echo "Check PR merge readiness and output result as JSON."
  echo ""
  echo "  <pr-number>  PR number (positive integer)"
  exit 0
fi

if [[ $# -eq 0 ]]; then
  echo "Error: PR number is required." >&2
  echo "$USAGE" >&2
  exit 1
fi

PR="$1"

if ! [[ "$PR" =~ ^[0-9]+$ ]]; then
  echo "Error: PR number must be a positive integer: $PR" >&2
  exit 1
fi

# Fetch PR mergeable and mergeStateStatus
JSON=$(gh pr view "$PR" --json mergeable,mergeStateStatus) || { echo "Error: failed to fetch PR #$PR" >&2; exit 1; }

MERGEABLE=$(echo "$JSON" | jq -r '.mergeable')
STATE=$(echo "$JSON" | jq -r '.mergeStateStatus')

# Polling backoff for UNKNOWN (GitHub metadata sync delay)
# UNKNOWN+UNKNOWN indicates GitHub hasn't synced CI/review state yet, not a genuine failure.
# Retry with exponential delays before aborting to avoid CI bypass risk.
if [[ "$MERGEABLE" == "UNKNOWN" && "$STATE" == "UNKNOWN" ]]; then
  RETRY_DELAYS=(30 60)
  retry_count=0
  while [[ "$MERGEABLE" == "UNKNOWN" && "$STATE" == "UNKNOWN" ]]; do
    if [[ $retry_count -ge ${#RETRY_DELAYS[@]} ]]; then
      echo "Error: PR #$PR mergeable=UNKNOWN persists after ${#RETRY_DELAYS[@]} retries — aborting to avoid CI bypass risk" >&2
      exit 2
    fi
    delay="${RETRY_DELAYS[$retry_count]}"
    echo "Info: mergeable=UNKNOWN (attempt $((retry_count + 1))) — waiting ${delay}s before retry..." >&2
    sleep "$delay"
    JSON=$(gh pr view "$PR" --json mergeable,mergeStateStatus) || { echo "Error: failed to fetch PR #$PR" >&2; exit 1; }
    MERGEABLE=$(echo "$JSON" | jq -r '.mergeable')
    STATE=$(echo "$JSON" | jq -r '.mergeStateStatus')
    retry_count=$((retry_count + 1))
  done
fi

# Determine merge readiness
if [[ "$MERGEABLE" == "MERGEABLE" && "$STATE" == "CLEAN" ]]; then
  echo '{"mergeable": true, "reason": "clean", "ci_status": "success", "review_status": "approved"}'
elif [[ "$MERGEABLE" == "MERGEABLE" && "$STATE" == "HAS_HOOKS" ]]; then
  echo '{"mergeable": true, "reason": "has_hooks", "ci_status": "success", "review_status": "approved"}'
elif [[ "$MERGEABLE" == "CONFLICTING" ]]; then
  echo '{"mergeable": false, "reason": "conflicts", "ci_status": "unknown", "review_status": "unknown"}'
elif [[ "$STATE" == "BLOCKED" ]]; then
  echo '{"mergeable": false, "reason": "review_pending", "ci_status": "unknown", "review_status": "pending"}'
elif [[ "$STATE" == "UNSTABLE" ]]; then
  echo '{"mergeable": false, "reason": "ci_failing", "ci_status": "failing", "review_status": "unknown"}'
elif [[ "$STATE" == "BEHIND" ]]; then
  echo '{"mergeable": false, "reason": "behind_base", "ci_status": "unknown", "review_status": "unknown"}'
else
  echo '{"mergeable": false, "reason": "unknown", "ci_status": "unknown", "review_status": "unknown"}'
fi
