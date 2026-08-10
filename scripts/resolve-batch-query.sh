#!/bin/bash
# resolve-batch-query.sh
# Resolve a `/auto --batch --until <query>` query into a sorted list of matching open Issue numbers.
#
# Usage:
#   scripts/resolve-batch-query.sh --query "<query string>" [--exclude "<space-separated numbers>"] [--limit <N>]
#
# Query grammar (exhaustive): whitespace-separated key:value clauses.
#   label:<glob>    required. Matched against each Issue's label names with bash `case` glob
#                   (`*` supported). At least one label on the Issue must match.
#   status:<value>  optional. Exact, case-sensitive match against the Project v2 Status
#                   single-select field. Values containing whitespace are not supported
#                   (the query is whitespace-split, so a space inside a status value produces
#                   an unrecognized bare token and is treated as a parse error).
#
# Exit codes:
#   0  success. stdout: ascending Issue numbers, one per line (empty stdout on 0 matches).
#   1  parse error (missing/empty --query, no label: clause, unknown key, duplicate key).
#      stderr: "resolve-batch-query: <reason>"; no stdout.
#   2  `gh issue list` failed (non-zero exit). stderr: error detail; no stdout.
#
# A per-Issue Status GraphQL resolution failure (error / no project item / Status unset) is
# treated fail-closed: that Issue is excluded (not a hard error) and a warning is printed to
# stderr. The overall exit code stays 0 in that case.

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

QUERY=""
EXCLUDE=""
LIMIT=200

while [ $# -gt 0 ]; do
    case "$1" in
        --query)
            QUERY="${2:-}"
            shift 2
            ;;
        --exclude)
            EXCLUDE="${2:-}"
            shift 2
            ;;
        --limit)
            LIMIT="${2:-}"
            shift 2
            ;;
        *)
            echo "resolve-batch-query: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$QUERY" ]; then
    echo "resolve-batch-query: --query is required and must not be empty" >&2
    exit 1
fi

LABEL_PATTERN=""
STATUS_VALUE=""
HAS_LABEL=false
HAS_STATUS=false

for clause in $QUERY; do
    case "$clause" in
        label:*)
            if [ "$HAS_LABEL" = true ]; then
                echo "resolve-batch-query: duplicate key: label" >&2
                exit 1
            fi
            LABEL_PATTERN="${clause#label:}"
            HAS_LABEL=true
            ;;
        status:*)
            if [ "$HAS_STATUS" = true ]; then
                echo "resolve-batch-query: duplicate key: status" >&2
                exit 1
            fi
            STATUS_VALUE="${clause#status:}"
            HAS_STATUS=true
            ;;
        *)
            echo "resolve-batch-query: unknown key in query clause: $clause" >&2
            exit 1
            ;;
    esac
done

if [ "$HAS_LABEL" != true ] || [ -z "$LABEL_PATTERN" ]; then
    echo "resolve-batch-query: query must include a non-empty label: clause" >&2
    exit 1
fi

# (a) Fetch candidate Issues
ISSUES_JSON=""
if ! ISSUES_JSON=$(gh issue list --state open --json number,labels --limit "$LIMIT" 2>/dev/null); then
    echo "resolve-batch-query: gh issue list failed" >&2
    exit 2
fi

ISSUES_COUNT=$(printf '%s' "$ISSUES_JSON" | jq 'length' 2>/dev/null || echo -1)
if [ "$ISSUES_COUNT" -eq "$LIMIT" ] 2>/dev/null; then
    echo "resolve-batch-query: warning: candidate set truncated at --limit $LIMIT; results may be incomplete" >&2
fi

# (b) Filter by label (bash case glob, not [[ ... ]] — bash 3.2 compatible)
LABEL_FILTERED=""
LABEL_TSV=""
if ! LABEL_TSV=$(printf '%s' "$ISSUES_JSON" | jq -r '.[] | [(.number|tostring), ([.labels[].name] | join(","))] | @tsv'); then
    echo "resolve-batch-query: failed to parse gh issue list output" >&2
    exit 2
fi
while IFS=$'\t' read -r num labels_csv; do
    [ -z "$num" ] && continue
    MATCHED=false
    OLDIFS="$IFS"
    IFS=','
    for lbl in $labels_csv; do
        case "$lbl" in
            $LABEL_PATTERN)
                MATCHED=true
                break
                ;;
        esac
    done
    IFS="$OLDIFS"
    if [ "$MATCHED" = true ]; then
        LABEL_FILTERED="$LABEL_FILTERED $num"
    fi
done <<< "$LABEL_TSV"

# (c) Filter by status (only when a status: clause was given — no GraphQL call otherwise)
STATUS_FILTERED=""
if [ "$HAS_STATUS" = true ]; then
    STATUS_GQL='query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){projectItems(first:10){nodes{fieldValues(first:20){nodes{... on ProjectV2ItemFieldSingleSelectValue{field{... on ProjectV2SingleSelectField{name}}value:name}}}}}}}}'
    for num in $LABEL_FILTERED; do
        ISSUE_STATUS=""
        if ! ISSUE_STATUS=$("$SCRIPT_DIR/gh-graphql.sh" "$STATUS_GQL" -F num="$num" \
            --jq '.data.repository.issue.projectItems.nodes[].fieldValues.nodes[] | select(.field.name=="Status") | .value' \
            2>/dev/null | head -1 | tr -d '"'); then
            echo "resolve-batch-query: warning: failed to resolve Status for #$num; excluding" >&2
            continue
        fi
        if [ -z "$ISSUE_STATUS" ]; then
            echo "resolve-batch-query: warning: Status not set for #$num; excluding" >&2
            continue
        fi
        if [ "$ISSUE_STATUS" != "$STATUS_VALUE" ]; then
            continue
        fi
        STATUS_FILTERED="$STATUS_FILTERED $num"
    done
else
    STATUS_FILTERED="$LABEL_FILTERED"
fi

# (d) Exclude already-processed Issue numbers (`for n in $EXCLUDE`, not `while read`, to
# safely tolerate an empty string)
RESULT=""
for num in $STATUS_FILTERED; do
    EXCLUDED=false
    for ex in $EXCLUDE; do
        if [ "$num" = "$ex" ]; then
            EXCLUDED=true
            break
        fi
    done
    if [ "$EXCLUDED" = false ]; then
        RESULT="$RESULT $num"
    fi
done

# (e) Ascending sort, one per line (skip printf entirely on 0 matches to avoid a spurious blank line)
if [ -n "$RESULT" ]; then
    printf '%s\n' $RESULT | sort -n
fi

exit 0
