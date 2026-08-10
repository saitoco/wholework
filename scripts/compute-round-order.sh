#!/bin/bash
# compute-round-order.sh
# Fetch title/Size/Value for each issue in a ROUND_LIST and compute ROI.
#
# Usage:
#   scripts/compute-round-order.sh "<space-separated issue numbers>"
#
# For each issue number, fetches title/Size/Value in a single gh-graphql.sh
# call (Project field first, size/*|value/* label fallback second, same
# priority as get-issue-size.sh), computes:
#   size_rank: XS=1 S=2 M=3 L=4 XL=5 (unset/unresolvable -> neutral 3)
#   value_num: 1-5 (unset/unresolvable -> neutral 3)
#   roi = value_num / size_rank (2 decimal places)
#
# Output (one line per issue, input order preserved, no reordering):
#   <number><TAB><size><TAB><value><TAB><roi><TAB><title>
#
# Clustering and reordering are out of scope for this script — see
# modules/round-ordering.md for the LLM-driven combination step.
#
# bash 3.2+ compatible (no associative arrays).

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 \"<space-separated issue numbers>\"" >&2
    exit 1
fi

ROUND_LIST="$1"

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

size_rank() {
    case "$1" in
        XS) echo 1 ;;
        S) echo 2 ;;
        M) echo 3 ;;
        L) echo 4 ;;
        XL) echo 5 ;;
        *) echo 3 ;; # neutral fallback (unset/unresolvable)
    esac
}

GQL_QUERY='query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){title projectItems(first:10){nodes{fieldValues(first:20){nodes{... on ProjectV2ItemFieldSingleSelectValue{field{... on ProjectV2SingleSelectField{name}}value:name}}}}}}}}'
# gh-graphql.sh does not pass -r to jq, so a filter must return a JSON object
# here (not a pre-flattened @tsv string) — the caller re-parses it below with
# its own `jq -r` to avoid quoting/escaping issues.
JQ_FILTER='{title: .data.repository.issue.title, size: ([.data.repository.issue.projectItems.nodes[].fieldValues.nodes[] | select(.field.name=="Size") | .value] | first), value: ([.data.repository.issue.projectItems.nodes[].fieldValues.nodes[] | select(.field.name=="Value") | .value] | first)}'

for num in $ROUND_LIST; do
    RESULT_JSON=""
    RESULT_JSON=$(
        "$SCRIPT_DIR/gh-graphql.sh" --cache "$GQL_QUERY" -F num="$num" \
            --jq "$JQ_FILTER" \
            2>/dev/null || true
    )

    TITLE=""
    SIZE=""
    VALUE=""
    if [ -n "$RESULT_JSON" ]; then
        LINE=$(printf '%s' "$RESULT_JSON" | jq -r '[(.title // ""), (.size // ""), (.value // "")] | @tsv' 2>/dev/null || true)
        if [ -n "$LINE" ]; then
            IFS=$'\t' read -r TITLE SIZE VALUE <<< "$LINE"
        fi
    fi

    # Label fallback (only fetched when at least one field is still unresolved)
    NEED_LABELS=false
    case "$SIZE" in
        XS|S|M|L|XL) ;;
        *) NEED_LABELS=true ;;
    esac
    case "$VALUE" in
        1|2|3|4|5) ;;
        *) NEED_LABELS=true ;;
    esac

    if [ "$NEED_LABELS" = true ]; then
        LABELS=$(gh issue view "$num" --json labels -q '.labels[].name' 2>/dev/null || true)
        case "$SIZE" in
            XS|S|M|L|XL) ;;
            *)
                SIZE=$(printf '%s\n' "$LABELS" | grep '^size/' | head -1 | sed 's|^size/||' || true)
                ;;
        esac
        case "$VALUE" in
            1|2|3|4|5) ;;
            *)
                VALUE=$(printf '%s\n' "$LABELS" | grep '^value/' | head -1 | sed 's|^value/||' || true)
                ;;
        esac
    fi

    if [ -z "$TITLE" ]; then
        TITLE=$(gh issue view "$num" --json title -q '.title' 2>/dev/null || true)
    fi

    case "$SIZE" in
        XS|S|M|L|XL) ;;
        *) SIZE="" ;;
    esac
    case "$VALUE" in
        1|2|3|4|5) ;;
        *) VALUE="" ;;
    esac

    SIZE_RANK=$(size_rank "$SIZE")

    case "$VALUE" in
        1|2|3|4|5) VALUE_NUM="$VALUE" ;;
        *) VALUE_NUM=3 ;;
    esac

    ROI=$(awk -v v="$VALUE_NUM" -v s="$SIZE_RANK" 'BEGIN { printf "%.2f", v / s }')

    printf '%s\t%s\t%s\t%s\t%s\n' "$num" "$SIZE" "$VALUE" "$ROI" "$TITLE"
done
