#!/bin/bash
# get-issue-size.sh
# Script to retrieve the Size of a GitHub Issue
#
# Usage:
#   scripts/get-issue-size.sh <issue-number>
#
# Priority:
#   1. Project field (GraphQL)
#   2. size/* label fallback
#
# Output:
#   Prints Size value (XS / S / M / L / XL) to stdout on one line
#   If not set, prints nothing and exits with code 1

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <issue-number>" >&2
    exit 1
fi

NUMBER="$1"

if ! [[ "$NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: Issue number must be a positive integer: $NUMBER" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Phase 1: Get from Project field
GQL_QUERY='query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){projectItems(first:10){nodes{fieldValues(first:20){nodes{... on ProjectV2ItemFieldSingleSelectValue{field{... on ProjectV2SingleSelectField{name}}value:name}}}}}}}}'

PROJECT_SIZE=""
PROJECT_SIZE=$(
    "$SCRIPT_DIR/gh-graphql.sh" --cache "$GQL_QUERY" -F num="$NUMBER" \
        --jq '.data.repository.issue.projectItems.nodes[].fieldValues.nodes[] | select(.field.name=="Size") | .value' \
        2>/dev/null | head -1 | tr -d '"' || true
)

case "$PROJECT_SIZE" in
    XS|S|M|L|XL)
        echo "$PROJECT_SIZE"
        exit 0
        ;;
esac

# Phase 2: Label fallback
LABEL_SIZE=""
LABEL_SIZE=$(
    gh issue view "$NUMBER" --json labels -q '.labels[].name' 2>/dev/null \
        | grep '^size/' | head -1 | sed 's|^size/||' || true
)

case "$LABEL_SIZE" in
    XS|S|M|L|XL)
        echo "$LABEL_SIZE"
        exit 0
        ;;
    *)
        # Unexpected size/* label value treated as unset
        LABEL_SIZE=""
        ;;
esac

# Not set
exit 1
