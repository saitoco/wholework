#!/bin/bash
# get-issue-type.sh
# Script to retrieve the Type of a GitHub Issue
#
# Usage:
#   scripts/get-issue-type.sh <issue-number>
#
# Priority:
#   1. Issue Types GraphQL API
#   2. type/* label fallback
#
# Output:
#   Prints Type value (Bug / Feature / Task) to stdout on one line
#   If not set, prints empty string and exits with code 0

set -euo pipefail

if [ "${1:-}" = "--help" ]; then
    echo "Usage: $0 <issue-number>"
    echo ""
    echo "Retrieve the Type (Bug/Feature/Task) of a GitHub Issue."
    echo "Priority: Issue Types GraphQL API -> type/* label fallback"
    echo "If not set, prints empty string and exits with code 0."
    exit 0
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <issue-number>" >&2
    exit 1
fi

NUMBER="$1"

if ! [[ "$NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: Issue number must be a positive integer: $NUMBER" >&2
    exit 1
fi

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

# Phase 1: Get from Issue Types GraphQL API
GQL_QUERY='query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){issueType{name}}}}'

GRAPHQL_TYPE=""
GRAPHQL_TYPE=$(
    "$SCRIPT_DIR/gh-graphql.sh" --cache "$GQL_QUERY" -F num="$NUMBER" \
        --jq '.data.repository.issue.issueType.name // empty' \
        2>/dev/null | head -1 | tr -d '"' || true
)

case "$GRAPHQL_TYPE" in
    Bug|Feature|Task)
        echo "$GRAPHQL_TYPE"
        exit 0
        ;;
esac

# Phase 2: type/* label fallback
LABEL_TYPE=""
LABEL_TYPE=$(
    gh issue view "$NUMBER" --json labels -q '[.labels[].name | select(startswith("type/"))] | first // empty' \
        2>/dev/null || true
)

case "$LABEL_TYPE" in
    type/bug)
        echo "Bug"
        exit 0
        ;;
    type/feature)
        echo "Feature"
        exit 0
        ;;
    type/task)
        echo "Task"
        exit 0
        ;;
esac

# Not set
echo ""
exit 0
