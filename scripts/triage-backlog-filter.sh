#!/bin/bash
# triage-backlog-filter.sh
# Issue listing script for /triage bulk execution
#
# Usage:
#   scripts/triage-backlog-filter.sh [--limit N] [--assignee USER | --no-assignee]
#
# Lists open Issues in the repository that do not have the triaged label.
#
# Filter criteria:
#   No triaged label
#   --assignee USER: only Issues assigned to specified user
#   --no-assignee: only unassigned Issues

set -euo pipefail

# Parse arguments
LIMIT=10
ASSIGNEE=""
NO_ASSIGNEE=false
while [ $# -gt 0 ]; do
    case "$1" in
        --limit)
            if [ $# -lt 2 ]; then
                echo "Error: --limit option requires a numeric value" >&2
                exit 1
            fi
            LIMIT="$2"
            shift 2
            ;;
        --assignee)
            if [ $# -lt 2 ]; then
                echo "Error: --assignee option requires a username" >&2
                exit 1
            fi
            ASSIGNEE="$2"
            shift 2
            ;;
        --no-assignee)
            NO_ASSIGNEE=true
            shift
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# 1. Fetch open Issues (number, title, labels)
if [ "$NO_ASSIGNEE" = "true" ]; then
    ISSUES_JSON=$(gh issue list --state open --json number,title,labels --limit 100 --no-assignee)
elif [ -n "$ASSIGNEE" ]; then
    ISSUES_JSON=$(gh issue list --state open --json number,title,labels --limit 100 --assignee "$ASSIGNEE")
else
    ISSUES_JSON=$(gh issue list --state open --json number,title,labels --limit 100)
fi

# 2. Extract Issues without triaged label, apply --limit, and output
echo "$ISSUES_JSON" | jq -r '
    [.[] | select(
        (.labels | map(.name) | index("triaged") | not)
    ) | .number] | .[]
' | head -n "$LIMIT"
