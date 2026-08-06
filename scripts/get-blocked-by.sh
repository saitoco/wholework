#!/bin/bash
# get-blocked-by.sh
# Single read window for GitHub native blocked-by relationships (GraphQL SSoT).
#
# Usage:
#   scripts/get-blocked-by.sh <issue-number>
#   scripts/get-blocked-by.sh --all [--limit N]
#
# Output (single issue mode):
#   <blocker-number><TAB><state>   -- one line per blocker (CLOSED and OPEN both listed)
#
# Output (--all mode):
#   <issue-number><TAB><blocker-number><TAB><blocker-state>   -- one line per relation
#   (open issues with no blockers produce no line)
#
# Exit codes:
#   0 -- success (single issue: no OPEN blockers; --all: always 0 on success)
#   1 -- error (bad arguments, API error, etc.)
#   2 -- single issue mode only: one or more OPEN blockers found

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
GH_GRAPHQL="$SCRIPT_DIR/gh-graphql.sh"

DEFAULT_LIMIT=100

usage() {
    echo "Usage: $(basename "$0") <issue-number>"
    echo "       $(basename "$0") --all [--limit N]"
    echo ""
    echo "Read GitHub native blocked-by relationships via GraphQL."
    echo ""
    echo "Single issue mode output: <blocker-number><TAB><state> per line"
    echo "--all mode output: <issue-number><TAB><blocker-number><TAB><blocker-state> per line"
    echo ""
    echo "Exit codes:"
    echo "  0 -- success (single issue: no OPEN blockers; --all: always 0 on success)"
    echo "  1 -- error"
    echo "  2 -- single issue mode only: OPEN blocker(s) found"
}

NUMBER=""
ALL_MODE=false
LIMIT="$DEFAULT_LIMIT"

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --all)
            ALL_MODE=true
            shift
            ;;
        --limit)
            if [ $# -lt 2 ] || ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -le 0 ]; then
                echo "Error: --limit must be a positive integer: ${2:-}" >&2
                exit 1
            fi
            LIMIT="$2"
            shift 2
            ;;
        -*)
            echo "Error: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if ! [[ "$1" =~ ^[0-9]+$ ]]; then
                echo "Error: issue-number must be a positive integer: $1" >&2
                exit 1
            fi
            NUMBER="$1"
            shift
            ;;
    esac
done

if [ "$ALL_MODE" = false ] && [ -z "$NUMBER" ]; then
    echo "Error: issue number or --all is required" >&2
    usage >&2
    exit 1
fi

if [ "$ALL_MODE" = true ]; then
    if [ "$LIMIT" -lt 100 ]; then
        PAGE_SIZE="$LIMIT"
    else
        PAGE_SIZE=100
    fi

    CURSOR=""
    TOTAL_ISSUES_SEEN=0

    while :; do
        if [ -z "$CURSOR" ]; then
            PAGE_JSON=$("$GH_GRAPHQL" --query get-open-issues-blocked-by -F first="$PAGE_SIZE") || {
                echo "Error: failed to fetch open-issue blocked-by graph" >&2
                exit 1
            }
        else
            PAGE_JSON=$("$GH_GRAPHQL" --query get-open-issues-blocked-by -F first="$PAGE_SIZE" -F cursor="$CURSOR") || {
                echo "Error: failed to fetch open-issue blocked-by graph" >&2
                exit 1
            }
        fi

        LINES=$(printf '%s' "$PAGE_JSON" | jq -r '.data.repository.issues.nodes[] | . as $i | ($i.blockedBy.nodes[]? | "\($i.number)\t\(.number)\t\(.state)")') || {
            echo "Error: failed to fetch open-issue blocked-by graph" >&2
            exit 1
        }
        if [ -n "$LINES" ]; then
            printf '%s\n' "$LINES"
        fi

        PAGE_COUNT=$(printf '%s' "$PAGE_JSON" | jq -r '.data.repository.issues.nodes | length')
        TOTAL_ISSUES_SEEN=$((TOTAL_ISSUES_SEEN + PAGE_COUNT))

        HAS_NEXT=$(printf '%s' "$PAGE_JSON" | jq -r '.data.repository.issues.pageInfo.hasNextPage')
        if [ "$HAS_NEXT" != "true" ]; then
            break
        fi
        if [ "$TOTAL_ISSUES_SEEN" -ge "$LIMIT" ]; then
            break
        fi
        CURSOR=$(printf '%s' "$PAGE_JSON" | jq -r '.data.repository.issues.pageInfo.endCursor')
    done

    exit 0
fi

# Single issue mode
RAW=$("$GH_GRAPHQL" --query get-blocked-by -F num="$NUMBER" --jq '.data.repository.issue.blockedBy.nodes[]? | "\(.number)\t\(.state)"') || {
    echo "Error: failed to fetch blocked-by for issue #$NUMBER" >&2
    exit 1
}

if [ -z "$RAW" ]; then
    exit 0
fi

printf '%s\n' "$RAW"

if printf '%s\n' "$RAW" | cut -f2 | grep -q '^OPEN$'; then
    exit 2
fi

exit 0
