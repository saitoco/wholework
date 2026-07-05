#!/bin/bash
# post-fallback-review-summary.sh
# Fallback poster for the Review Response Summary comment.
#
# Called by run-review.sh when claude exits 0 but reconcile-phase-state.sh
# reports matches_expected:false (silent no-op: Step 11 review posted, but
# Step 14 Response Summary never got posted before exit). Only posts a
# fallback comment when evidence of a completed Step 11 review exists
# ("Acceptance Criteria Verification Results" in an existing PR review) —
# this guard prevents a false "recovered" report when review never
# actually progressed.
#
# Usage:
#   scripts/post-fallback-review-summary.sh <pr-number>

set -euo pipefail

PR_NUMBER="${1:?Usage: post-fallback-review-summary.sh <pr-number>}"

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: PR number must be numeric: $PR_NUMBER" >&2
    exit 1
fi

REVIEW_BODIES=$(gh pr view "$PR_NUMBER" --json reviews --jq '.reviews[].body' 2>/dev/null) || true

if ! echo "$REVIEW_BODIES" | grep -q "Acceptance Criteria Verification Results"; then
    echo "post-fallback-review-summary: no prior Review with Acceptance Criteria Verification Results found for PR #${PR_NUMBER}; skipping fallback post" >&2
    exit 1
fi

FALLBACK_BODY="<!-- review-summary -->
## Review Response Summary

This is an auto-generated fallback summary, posted by \`post-fallback-review-summary.sh\` after the review session exited without posting its own Response Summary (silent no-op). A prior review with Acceptance Criteria Verification Results was found for this PR.

Before merging, manually confirm CI status and the content of any fix commits pushed during this review."

if ! gh pr comment "$PR_NUMBER" --body "$FALLBACK_BODY"; then
    echo "Error: failed to post fallback Review Response Summary to PR #${PR_NUMBER}" >&2
    exit 1
fi
