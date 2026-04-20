#!/bin/bash
# wait-ci-checks.sh - Wait for CI checks to complete on a PR
# Usage: ./scripts/wait-ci-checks.sh <pr-number>
#
# Environment variables:
#   WHOLEWORK_CI_TIMEOUT_SEC: Maximum wait time in seconds (default: 1200)
set -euo pipefail
PR_NUMBER="${1:?Usage: wait-ci-checks.sh <pr-number>}"
TIMEOUT_SEC="${WHOLEWORK_CI_TIMEOUT_SEC:-1200}"
echo "Waiting for CI checks on PR #${PR_NUMBER} (timeout: ${TIMEOUT_SEC}s)..." >&2
if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_SEC" gh pr checks "$PR_NUMBER" --watch --interval 60 || true
elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$TIMEOUT_SEC" gh pr checks "$PR_NUMBER" --watch --interval 60 || true
else
    gh pr checks "$PR_NUMBER" --watch --interval 60 || true
fi
echo "CI check wait complete for PR #${PR_NUMBER}" >&2
