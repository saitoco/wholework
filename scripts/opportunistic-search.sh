#!/bin/bash
# opportunistic-search.sh
# Issue search helper script for opportunistic verification
#
# Usage:
#   scripts/opportunistic-search.sh <skill-name> [--dry-run]
#   scripts/opportunistic-search.sh --event <event-name> [--dry-run]
#
# Examples:
#   scripts/opportunistic-search.sh /issue
#   scripts/opportunistic-search.sh /spec --dry-run
#   scripts/opportunistic-search.sh --event pr-review-full
#   scripts/opportunistic-search.sh --event auto-run --dry-run
#
# Output: JSON array [{"number": N, "condition": "condition text"}]
#         Empty array [] when no matches found

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

# Parse arguments
SKILL_NAME=""
EVENT_NAME=""
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --event)
            if [ $# -lt 2 ]; then
                echo "Error: --event requires an argument" >&2
                exit 1
            fi
            EVENT_NAME="$2"
            shift 2
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

# Validate: skill name required when --event is not specified
if [ -z "$EVENT_NAME" ] && [ -z "$SKILL_NAME" ]; then
    echo "Usage: $0 <skill-name> [--dry-run]" >&2
    echo "       $0 --event <event-name> [--dry-run]" >&2
    echo "Example: $0 /issue" >&2
    echo "         $0 --event pr-review-full" >&2
    exit 1
fi

# Validate known event names; warn and fall back to opportunistic treatment on unknown
KNOWN_EVENTS="pr-review-full pr-review-light auto-run watchdog-kill fix-cycle"
if [ -n "$EVENT_NAME" ]; then
    IS_KNOWN=false
    for e in $KNOWN_EVENTS; do
        if [ "$EVENT_NAME" = "$e" ]; then
            IS_KNOWN=true
            break
        fi
    done
    if [ "$IS_KNOWN" = false ]; then
        echo "Warning: unknown event '${EVENT_NAME}', falling back to opportunistic treatment" >&2
        # Fall back: treat as opportunistic (clear event, require skill name)
        EVENT_NAME=""
        if [ -z "$SKILL_NAME" ]; then
            echo "Error: unknown event fallback requires a skill name" >&2
            exit 1
        fi
    fi
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

    if [ -n "$EVENT_NAME" ]; then
        # Event mode: match verify-type: observation with the specified event name
        MATCHED=$(echo "$BODY" | grep -E '^- \[ \]' | grep "verify-type: observation" | grep "event=${EVENT_NAME}" || true)
    else
        # Opportunistic mode: match verify-type: opportunistic with skill name
        MATCHED=$(echo "$BODY" | grep -E '^- \[ \]' | grep "verify-type: opportunistic" | grep -F "$SKILL_NAME" || true)
    fi

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
