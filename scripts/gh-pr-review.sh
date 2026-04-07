#!/bin/bash
# gh-pr-review.sh
# Post a GitHub Pull Request Review (Pending Review + Line Comments)
#
# Usage:
#   scripts/gh-pr-review.sh <pr-number> <review-body-file> [<line-comments-json-file>]
#
# Arguments:
#   pr-number              : PR number (positive integer)
#   review-body-file       : review body file (acceptance criteria table, CI status, etc.)
#   line-comments-json-file: line comments JSON array file (optional)
#                            if omitted, only the review body is posted without line comments
#
# Line comments JSON format (each element):
#   {
#     "path": "scripts/example.sh",
#     "line": 42,
#     "body": "[category] **MUST**: description...",
#     "side": "RIGHT",
#     "severity": "MUST"
#   }
#   Note: severity field is used to determine the event type and is excluded from the API request

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <pr-number> <review-body-file> [<line-comments-json-file>]" >&2
    exit 1
fi

PR_NUMBER="$1"
REVIEW_BODY_FILE="$2"
LINE_COMMENTS_FILE="${3:-}"

# Validate PR number is a positive integer
if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: PR number must be a positive integer: $PR_NUMBER" >&2
    exit 1
fi

# Check review body file exists
if [ ! -f "$REVIEW_BODY_FILE" ]; then
    echo "Error: file not found: $REVIEW_BODY_FILE" >&2
    exit 1
fi

REVIEW_BODY=$(cat "$REVIEW_BODY_FILE")

if [ -z "$REVIEW_BODY" ]; then
    echo "Error: empty review body: $REVIEW_BODY_FILE" >&2
    exit 1
fi

# Get owner/repo
if ! REPO=$(gh repo view --json owner,name -q '.owner.login + "/" + .name'); then
    echo "Error: failed to get repository info. Check gh auth status." >&2
    exit 1
fi

# Determine event and comments
EVENT="COMMENT"

if [ -n "$LINE_COMMENTS_FILE" ]; then
    # Check line comments file exists
    if [ ! -f "$LINE_COMMENTS_FILE" ]; then
        echo "Error: file not found: $LINE_COMMENTS_FILE" >&2
        exit 1
    fi

    # Validate JSON
    if ! python3 -c "import sys,json; json.load(sys.stdin)" < "$LINE_COMMENTS_FILE" 2>/dev/null; then
        echo "Error: invalid line comments JSON: $LINE_COMMENTS_FILE" >&2
        exit 1
    fi

    # Check for MUST severity to determine event type
    HAS_MUST=$(python3 - "$LINE_COMMENTS_FILE" <<'PYEOF'
import sys, json
with open(sys.argv[1]) as f:
    comments = json.load(f)
has_must = any(c.get('severity', '').upper() == 'MUST' for c in comments)
print('true' if has_must else 'false')
PYEOF
)

    if [ "$HAS_MUST" = "true" ]; then
        EVENT="REQUEST_CHANGES"
    fi

    # Build payload: exclude severity field, filter invalid entries, then POST
    python3 - "$REVIEW_BODY_FILE" "$LINE_COMMENTS_FILE" "$EVENT" <<'PYEOF' | \
        gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --method POST --input -
import sys, json
review_body_file = sys.argv[1]
line_comments_file = sys.argv[2]
event = sys.argv[3]

with open(review_body_file) as f:
    body = f.read()
with open(line_comments_file) as f:
    comments = json.load(f)

# Keep only entries with required fields; exclude severity from API payload
required_keys = ('path', 'line', 'body')
clean_comments = []
for c in comments:
    if not isinstance(c, dict):
        continue
    if any((k not in c) or (c[k] is None) for k in required_keys):
        continue
    clean_comments.append({k: v for k, v in c.items() if k != 'severity'})

# Omit comments field if no valid comments remain
payload = {'body': body, 'event': event}
if clean_comments:
    payload['comments'] = clean_comments
print(json.dumps(payload))
PYEOF
else
    # No line comments: post review body only
    python3 - "$REVIEW_BODY_FILE" "$EVENT" <<'PYEOF' | \
        gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --method POST --input -
import sys, json
with open(sys.argv[1]) as f:
    body = f.read()
event = sys.argv[2]
payload = {'body': body, 'event': event}
print(json.dumps(payload))
PYEOF
fi
