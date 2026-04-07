#!/bin/bash
# opportunistic-search.sh
# Issue search helper script for opportunistic verification
#
# Usage:
#   scripts/opportunistic-search.sh <skill-name> [--dry-run]
#
# Examples:
#   scripts/opportunistic-search.sh /issue
#   scripts/opportunistic-search.sh /spec --dry-run
#
# Output: JSON array [{"number": N, "condition": "condition text"}]
#         Empty array [] when no matches found

set -euo pipefail

# Parse arguments
SKILL_NAME=""
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [ -n "$SKILL_NAME" ]; then
                echo "Error: Only one skill name may be specified" >&2
                exit 1
            fi
            SKILL_NAME="$1"
            shift
            ;;
    esac
done

if [ -z "$SKILL_NAME" ]; then
    echo "Usage: $0 <skill-name> [--dry-run]" >&2
    echo "Example: $0 /issue" >&2
    exit 1
fi

# dry-run mode: skip actual API calls and exit successfully
if [ "$DRY_RUN" = true ]; then
    echo "[]"
    exit 0
fi

# 1. Fetch closed Issues with phase/verify label
ISSUES_JSON=$(gh issue list --label "phase/verify" --state closed --json number --limit 50)
ISSUE_NUMBERS=$(echo "$ISSUES_JSON" | jq -r '.[].number')

if [ -z "$ISSUE_NUMBERS" ]; then
    echo "[]"
    exit 0
fi

# 2. Fetch each Issue body and filter
RESULTS="[]"

for N in $ISSUE_NUMBERS; do
    BODY=$(gh issue view "$N" --json body -q .body)

    # Filter criteria:
    # - has verify-type: opportunistic tag
    # - condition text contains skill name
    # - checkbox is unchecked (- [ ])
    MATCHED=$(echo "$BODY" | grep -E '^- \[ \]' | grep "verify-type: opportunistic" | grep -F "$SKILL_NAME" || true)

    if [ -z "$MATCHED" ]; then
        continue
    fi

    # Convert each matched line to a JSON entry
    while IFS= read -r line; do
        # Extract text with HTML comments and checkbox markup removed
        CONDITION=$(echo "$line" \
            | sed 's/^- \[ \] //' \
            | sed 's/ *<!--.*-->//g')
        RESULTS=$(echo "$RESULTS" | jq --argjson n "$N" --arg c "$CONDITION" '. += [{"number": $n, "condition": $c}]')
    done <<< "$MATCHED"
done

echo "$RESULTS"
