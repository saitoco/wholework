#!/bin/bash
# gh-graphql.sh
# GitHub GraphQL API wrapper script
#
# Usage:
#   scripts/gh-graphql.sh [--cache] [--cache-ttl N] <query> [options]
#   scripts/gh-graphql.sh [--cache] [--cache-ttl N] --query <name> [options]
#   scripts/gh-graphql.sh --cache-clear
#
# Options:
#   -F key=value     Pass GraphQL variables
#   --jq <expr>      Filter output with jq
#   --cache          Enable response caching (can be placed before or after query)
#   --cache-ttl N    Cache TTL in seconds (default: 300)
#   --cache-clear    Delete cache directory and exit
#   --query <name>   Use a named query
#                    e.g. --query get-issue-id -F num=123
#                         --query get-projects-with-fields
#                         --query update-field-value -F projectId="..." ...
#
# owner/repo is auto-resolved (-F owner=... -F repo=... overrides auto-resolution)

set -euo pipefail

CACHE_DIR="${GH_GRAPHQL_CACHE_DIR:-.tmp/gh-graphql-cache}"
CACHE_ENABLED=false
CACHE_TTL=300
QUERY_NAME=""

# Named query dictionary (referenced via --query <name>)
get_named_query() {
    local name="$1"
    case "$name" in
        get-projects-with-fields)
            printf '%s' 'query($owner:String!,$repo:String!){repository(owner:$owner,name:$repo){projectsV2(first:5){nodes{id title number fields(first:20){nodes{... on ProjectV2SingleSelectField{id name options{id name}}... on ProjectV2Field{id name dataType}}}}}}}'
            ;;
        get-issue-id)
            printf '%s' 'query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){id}}}'
            ;;
        add-project-item)
            printf '%s' 'mutation($projectId:ID!,$contentId:ID!){addProjectV2ItemById(input:{projectId:$projectId,contentId:$contentId}){item{id}}}'
            ;;
        update-field-value)
            printf '%s' 'mutation($projectId:ID!,$itemId:ID!,$fieldId:ID!,$optionId:String!){updateProjectV2ItemFieldValue(input:{projectId:$projectId,itemId:$itemId,fieldId:$fieldId,value:{singleSelectOptionId:$optionId}}){projectV2Item{id}}}'
            ;;
        get-issue-types)
            printf '%s' 'query($owner:String!,$repo:String!){repository(owner:$owner,name:$repo){issueTypes(first:10){nodes{id name}}}}'
            ;;
        update-issue-type)
            printf '%s' 'mutation($issueId:ID!,$typeId:ID!){updateIssueIssueType(input:{issueId:$issueId,issueTypeId:$typeId}){issue{title}}}'
            ;;
        add-sub-issue)
            printf '%s' 'mutation($parentId:ID!,$childId:ID!){addSubIssue(input:{issueId:$parentId,subIssueId:$childId}){issue{title}subIssue{title number}}}'
            ;;
        add-blocked-by)
            printf '%s' 'mutation($issueId:ID!,$blockingId:ID!){addBlockedBy(input:{issueId:$issueId,blockingIssueId:$blockingId}){issue{number}}}'
            ;;
        get-sub-issues)
            printf '%s' 'query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){subIssues(first:50){nodes{number title state blockedBy(first:20){nodes{number state}}}}}}}'
            ;;
        get-blocked-by)
            printf '%s' 'query($owner:String!,$repo:String!,$num:Int!){repository(owner:$owner,name:$repo){issue(number:$num){blockedBy(first:100){nodes{number title state}}}}}'
            ;;
        *)
            echo "Error: unknown query name: $name" >&2
            return 1
            ;;
    esac
}

# Parse --cache-clear / --cache / --cache-ttl / --query (may appear before query argument)
while [ $# -gt 0 ]; do
    case "$1" in
        --cache-clear)
            rm -rf "$CACHE_DIR"
            exit 0
            ;;
        --cache)
            CACHE_ENABLED=true
            shift
            ;;
        --cache-ttl)
            if [ $# -lt 2 ]; then
                echo "Error: --cache-ttl requires a numeric value" >&2
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --cache-ttl must be a non-negative integer: $2" >&2
                exit 1
            fi
            CACHE_TTL="$2"
            shift 2
            ;;
        --query)
            if [ $# -lt 2 ]; then
                echo "Error: --query requires a name argument" >&2
                exit 1
            fi
            QUERY_NAME="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# Resolve query string: named query or positional argument
if [ -n "$QUERY_NAME" ]; then
    QUERY=$(get_named_query "$QUERY_NAME") || exit 1
elif [ $# -ge 1 ]; then
    QUERY="$1"
    shift
else
    echo "Usage: $0 [--cache] [--cache-ttl N] [--query <name> | <query>] [-F key=value ...] [--jq <expr>]" >&2
    exit 1
fi

# Unescape \! sequences injected by Claude Code Bash tool (#249)
QUERY=$(printf '%s\n' "$QUERY" | sed 's/\\!/!/g')

if [ -z "$QUERY" ]; then
    echo "Error: empty query" >&2
    exit 1
fi

# Parse remaining options
JQ_EXPR=""
F_ARGS=()
F_VALS=()
HAS_OWNER=false
HAS_REPO=false

while [ $# -gt 0 ]; do
    case "$1" in
        --cache)
            # Accept --cache after query too
            CACHE_ENABLED=true
            shift
            ;;
        --cache-ttl)
            # Accept --cache-ttl after query too
            if [ $# -lt 2 ]; then
                echo "Error: --cache-ttl requires a numeric value" >&2
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --cache-ttl must be a non-negative integer: $2" >&2
                exit 1
            fi
            CACHE_TTL="$2"
            shift 2
            ;;
        --jq)
            if [ $# -lt 2 ]; then
                echo "Error: --jq requires an argument" >&2
                exit 1
            fi
            JQ_EXPR="$2"
            shift 2
            ;;
        -F)
            if [ $# -lt 2 ]; then
                echo "Error: -F requires a key=value argument" >&2
                exit 1
            fi
            F_ARGS+=("-F" "$2")
            F_VALS+=("$2")
            case "$2" in
                owner=*) HAS_OWNER=true ;;
                repo=*)  HAS_REPO=true ;;
            esac
            shift 2
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# TTL check: returns 0 if file exists and is within TTL
is_cache_valid() {
    local file="$1"
    [ -f "$file" ] || return 1
    local file_mtime
    if [ "$(uname)" = "Darwin" ]; then
        file_mtime=$(stat -f '%m' "$file")
    else
        file_mtime=$(stat -c '%Y' "$file")
    fi
    local now
    now=$(date +%s)
    local age=$(( now - file_mtime ))
    [ "$age" -lt "$CACHE_TTL" ]
}

# Auto-resolve owner/repo (only when not explicitly specified)
if [ "$HAS_OWNER" = false ] || [ "$HAS_REPO" = false ]; then
    REPO_INFO=""

    # Load repo-info from cache if enabled
    if [ "$CACHE_ENABLED" = true ]; then
        mkdir -p "$CACHE_DIR"
        REPO_CACHE="$CACHE_DIR/repo-info.tsv"
        if is_cache_valid "$REPO_CACHE"; then
            REPO_INFO=$(cat "$REPO_CACHE")
        fi
    fi

    # Cache miss or cache disabled: fetch from API
    if [ -z "$REPO_INFO" ]; then
        REPO_INFO=$(gh repo view --json owner,name --jq '[.owner.login,.name] | @tsv')
        # Save to cache if enabled
        if [ "$CACHE_ENABLED" = true ]; then
            echo "$REPO_INFO" > "$REPO_CACHE"
        fi
    fi

    REPO_OWNER=$(echo "$REPO_INFO" | cut -f1)
    REPO_NAME=$(echo "$REPO_INFO" | cut -f2)

    if [ "$HAS_OWNER" = false ]; then
        F_ARGS+=("-F" "owner=$REPO_OWNER")
        F_VALS+=("owner=$REPO_OWNER")
    fi
    if [ "$HAS_REPO" = false ]; then
        F_ARGS+=("-F" "repo=$REPO_NAME")
        F_VALS+=("repo=$REPO_NAME")
    fi
fi

# Generate cache key and handle response caching
if [ "$CACHE_ENABLED" = true ]; then
    mkdir -p "$CACHE_DIR"

    # Cache key: query + sorted variables (--jq excluded)
    if [ ${#F_VALS[@]} -gt 0 ]; then
        SORTED_VARS=$(printf '%s\n' "${F_VALS[@]}" | sort | tr '\n' '|')
    else
        SORTED_VARS=""
    fi
    if command -v md5 >/dev/null 2>&1; then
        CACHE_KEY=$(printf '%s' "${QUERY}|${SORTED_VARS}" | md5 -q)
    else
        CACHE_KEY=$(printf '%s' "${QUERY}|${SORTED_VARS}" | md5sum | cut -d' ' -f1)
    fi
    CACHE_FILE="$CACHE_DIR/${CACHE_KEY}.json"

    if is_cache_valid "$CACHE_FILE"; then
        # Cache hit: apply --jq filter if specified
        if [ -n "$JQ_EXPR" ]; then
            jq "$JQ_EXPR" < "$CACHE_FILE"
        else
            cat "$CACHE_FILE"
        fi
        exit 0
    fi

    # Cache miss: execute API call without --jq to get raw response
    GH_ARGS=("-f" "query=$QUERY" "${F_ARGS[@]}")
    RAW_RESPONSE=$(gh api graphql "${GH_ARGS[@]}")
    echo "$RAW_RESPONSE" > "$CACHE_FILE"

    # Apply --jq filter if specified
    if [ -n "$JQ_EXPR" ]; then
        echo "$RAW_RESPONSE" | jq "$JQ_EXPR"
    else
        echo "$RAW_RESPONSE"
    fi
else
    # No cache: standard execution
    GH_ARGS=("-f" "query=$QUERY" "${F_ARGS[@]}")

    if [ -n "$JQ_EXPR" ]; then
        GH_ARGS+=("--jq" "$JQ_EXPR")
    fi

    gh api graphql "${GH_ARGS[@]}"
fi
