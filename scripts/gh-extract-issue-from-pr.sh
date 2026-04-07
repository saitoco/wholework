#!/bin/bash
# gh-extract-issue-from-pr.sh
# Extract issue number and base branch from a PR
#
# Usage: gh-extract-issue-from-pr.sh <pr-number>
#
# Output (JSON):
#   {"issue_number": "123", "base_ref": "main"}
#   issue_number is empty string if not found

set -euo pipefail

if [ "${1:-}" = "--help" ]; then
    echo "Usage: $0 <pr-number>"
    echo ""
    echo "Extract issue number and base branch from a PR as JSON"
    echo ""
    echo "Example output:"
    echo '  {"issue_number": "123", "base_ref": "main"}'
    echo ""
    echo "Options:"
    echo "  --help  Show this help"
    exit 0
fi

if [ $# -lt 1 ]; then
    echo "Error: PR number is required" >&2
    echo "Usage: $0 <pr-number>" >&2
    exit 1
fi

PR_NUMBER="$1"

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: PR number must be a positive integer: $PR_NUMBER" >&2
    exit 1
fi

# Fetch PR data
PR_DATA=$(gh pr view "$PR_NUMBER" --json body,title,baseRefName 2>/dev/null) || {
    echo "Error: failed to fetch PR #$PR_NUMBER" >&2
    exit 1
}

PR_BODY=$(echo "$PR_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('body','') or '')")
PR_TITLE=$(echo "$PR_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title','') or '')")
BASE_REF=$(echo "$PR_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('baseRefName','main') or 'main')")

# Extract issue number from PR body (preferred)
# Patterns: closes/fixes/resolves/related to #XX (case-insensitive)
ISSUE_NUMBER=$(echo "$PR_BODY" | python3 -c "
import sys, re
body = sys.stdin.read()
pattern = r'(?:closes|fixes|resolves|related\s+to)\s+#(\d+)'
m = re.search(pattern, body, re.IGNORECASE)
if m:
    print(m.group(1))
" 2>/dev/null || true)

# Fall back to title if body match fails
if [ -z "$ISSUE_NUMBER" ]; then
    ISSUE_NUMBER=$(echo "$PR_TITLE" | python3 -c "
import sys, re
title = sys.stdin.read()
# 'Issue #XX:' or '#XX:' pattern
pattern = r'(?:Issue\s+)?#(\d+):'
m = re.search(pattern, title, re.IGNORECASE)
if m:
    print(m.group(1))
" 2>/dev/null || true)
fi

# Output as JSON
python3 -c "
import json
print(json.dumps({'issue_number': '$ISSUE_NUMBER', 'base_ref': '$BASE_REF'}))
"
