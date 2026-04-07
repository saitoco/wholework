#!/bin/bash
# gh-issue-comment.sh
# Post a comment to an issue
#
# Usage:
#   scripts/gh-issue-comment.sh <issue-number> <comment-file>

set -euo pipefail

if [ $# -lt 2 ]; then
    echo "Usage: $0 <issue-number> <comment-file>" >&2
    exit 1
fi

ISSUE_NUMBER="$1"
COMMENT_FILE="$2"

# Validate issue number is a positive integer
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: issue number must be a positive integer: $ISSUE_NUMBER" >&2
    exit 1
fi

# Check file exists
if [ ! -f "$COMMENT_FILE" ]; then
    echo "Error: file not found: $COMMENT_FILE" >&2
    exit 1
fi

# Read comment body from file
COMMENT_BODY=$(cat "$COMMENT_FILE")

if [ -z "$COMMENT_BODY" ]; then
    echo "Error: empty body: $COMMENT_FILE" >&2
    exit 1
fi

# Replace {REPO} placeholder with actual repository info
if [[ "$COMMENT_BODY" == *"{REPO}"* ]]; then
    REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
    COMMENT_BODY="${COMMENT_BODY//\{REPO\}/$REPO}"
fi

if ! gh issue comment "$ISSUE_NUMBER" --body "$COMMENT_BODY"; then
    echo "Error: failed to post comment to issue #$ISSUE_NUMBER" >&2
    exit 1
fi
