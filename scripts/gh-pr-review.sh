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
#
# Diff-range fallback:
#   Each line comment's path/line is checked against the PR diff's hunk ranges
#   (via `gh pr diff`). Comments whose line falls outside the diff range (side: RIGHT
#   only) are excluded from the API `comments[]` payload and merged into the review
#   body as a "### General Comments" Markdown list instead, since the GitHub Pull
#   Request Review API rejects lines that are not part of the diff.

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

    # Fetch PR diff to build the hunk range map used for diff-range fallback classification
    DIFF_FILE=$(mktemp)
    trap 'rm -f "$DIFF_FILE"' EXIT
    if ! gh pr diff "$PR_NUMBER" > "$DIFF_FILE" 2>/dev/null; then
        echo "Error: failed to fetch PR diff for #$PR_NUMBER" >&2
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

    # Build payload: exclude severity field, filter invalid entries, classify by
    # PR diff hunk range (in-range stays as a line comment; out-of-range is merged
    # into the review body as General Comments), then POST
    REVIEW_PAYLOAD=$(python3 - "$REVIEW_BODY_FILE" "$LINE_COMMENTS_FILE" "$EVENT" "$DIFF_FILE" <<'PYEOF'
import sys, json, re

review_body_file = sys.argv[1]
line_comments_file = sys.argv[2]
event = sys.argv[3]
diff_file = sys.argv[4]

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

# Parse the PR diff into a path -> [(new_start, new_end), ...] hunk range map
with open(diff_file) as f:
    diff_text = f.read()

range_map = {}
current_path = None
hunk_re = re.compile(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@')
for line in diff_text.splitlines():
    if line.startswith('+++ '):
        target = line[4:].strip()
        if target == '/dev/null':
            current_path = None
        elif target.startswith('b/'):
            current_path = target[2:]
        else:
            current_path = target
        continue
    m = hunk_re.match(line)
    if m and current_path is not None:
        new_start = int(m.group(1))
        new_count = int(m.group(2)) if m.group(2) is not None else 1
        if new_count > 0:
            range_map.setdefault(current_path, []).append((new_start, new_start + new_count - 1))

def in_diff_range(path, line_no):
    return any(start <= line_no <= end for start, end in range_map.get(path, []))

in_range_comments = []
out_of_range_comments = []
for c in clean_comments:
    if c.get('side') == 'RIGHT' and not in_diff_range(c['path'], c['line']):
        out_of_range_comments.append(c)
    else:
        in_range_comments.append(c)

if out_of_range_comments:
    bullets = '\n'.join(
        f"- **{c['path']}:{c['line']}**: {c['body']}" for c in out_of_range_comments
    )
    heading_re = re.compile(r'^### General Comments.*$', re.MULTILINE)
    m = heading_re.search(body)
    if m:
        body = body[:m.end()] + '\n' + bullets + body[m.end():]
    else:
        body = body.rstrip('\n') + '\n\n### General Comments (auto-added: line outside PR diff range)\n' + bullets + '\n'

# Omit comments field if no valid comments remain
payload = {'body': body, 'event': event}
if in_range_comments:
    payload['comments'] = in_range_comments
print(json.dumps(payload))
PYEOF
    )
    echo "$REVIEW_PAYLOAD" | gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --method POST --input - || {
        echo "Error: failed to post review for PR #$PR_NUMBER" >&2
        exit 1
    }
else
    # No line comments: post review body only
    REVIEW_PAYLOAD=$(python3 - "$REVIEW_BODY_FILE" "$EVENT" <<'PYEOF'
import sys, json
with open(sys.argv[1]) as f:
    body = f.read()
event = sys.argv[2]
payload = {'body': body, 'event': event}
print(json.dumps(payload))
PYEOF
    )
    echo "$REVIEW_PAYLOAD" | gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --method POST --input - || {
        echo "Error: failed to post review for PR #$PR_NUMBER" >&2
        exit 1
    }
fi
