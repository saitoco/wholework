#!/bin/bash
# get-sub-issue-progress.sh - Fetch all sub-issues (OPEN + CLOSED) under a parent Issue
#
# Usage: get-sub-issue-progress.sh <parent-issue-number>
#
# Output (JSON):
# {
#   "parent": { "number": 1000, "title": "..." },
#   "sub_issues": [
#     {
#       "number": 1001,
#       "title": "...",
#       "state": "OPEN",
#       "createdAt": "2026-06-01T00:00:00Z",
#       "closedAt": null,
#       "updatedAt": "2026-06-10T12:00:00Z",
#       "labels": [{ "name": "phase/code" }],
#       "blockedBy": [{ "number": 1005, "state": "OPEN" }]
#     }
#   ]
# }

set -euo pipefail

PARENT_NUMBER="${1:?Usage: get-sub-issue-progress.sh <parent-issue-number>}"

if ! echo "$PARENT_NUMBER" | grep -qE '^[0-9]+$'; then
  echo "Error: Issue number must be numeric: $PARENT_NUMBER" >&2
  exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

RAW_JSON=$("$SCRIPT_DIR/gh-graphql.sh" --query get-sub-issues-all -F "num=$PARENT_NUMBER")

jq '{
  parent: {
    number: '"$PARENT_NUMBER"',
    title: (.data.repository.issue.title // "")
  },
  sub_issues: (
    .data.repository.issue.subIssues.nodes // [] |
    map({
      number: .number,
      title: .title,
      state: .state,
      createdAt: .createdAt,
      closedAt: .closedAt,
      updatedAt: .updatedAt,
      labels: (.labels.nodes // []),
      blockedBy: (.blockedBy.nodes // [])
    })
  )
}' <<< "$RAW_JSON"
