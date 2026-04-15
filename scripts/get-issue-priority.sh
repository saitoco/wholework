#!/bin/bash
# get-issue-priority.sh
# Script to retrieve the Priority of a GitHub Issue
#
# Usage:
#   scripts/get-issue-priority.sh <issue-number>
#
# Priority:
#   1. Project field (GraphQL)
#   2. priority/* label fallback
#
# Output:
#   Prints Priority value (urgent / high / medium / low) to stdout on one line
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

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

# Phase 1: Get from Project field
GQL_QUERY='query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){projectItems(first:10){nodes{fieldValues(first:20){nodes{... on ProjectV2ItemFieldSingleSelectValue{field{... on ProjectV2SingleSelectField{name}}value:name}}}}}}}}'

PROJECT_PRIORITY=""
PROJECT_PRIORITY=$(
    "$SCRIPT_DIR/gh-graphql.sh" --cache "$GQL_QUERY" -F num="$NUMBER" \
        --jq '.data.repository.issue.projectItems.nodes[].fieldValues.nodes[] | select(.field.name=="Priority") | .value' \
        2>/dev/null | head -1 | tr -d '"' || true
)

case "$PROJECT_PRIORITY" in
    urgent|high|medium|low)
        echo "$PROJECT_PRIORITY"
        exit 0
        ;;
esac

# Phase 2: Label fallback
LABEL_PRIORITY=""
LABEL_PRIORITY=$(
    gh issue view "$NUMBER" --json labels -q '.labels[].name' 2>/dev/null \
        | grep '^priority/' | head -1 | sed 's|^priority/||' || true
)

case "$LABEL_PRIORITY" in
    urgent|high|medium|low)
        echo "$LABEL_PRIORITY"
        exit 0
        ;;
    *)
        # Unexpected priority/* label value treated as unset
        LABEL_PRIORITY=""
        ;;
esac

# Not set
exit 1
