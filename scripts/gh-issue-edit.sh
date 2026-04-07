#!/bin/bash
# gh-issue-edit.sh
# Update issue body
#
# Usage:
#   scripts/gh-issue-edit.sh <issue-number> <body-file>
#   scripts/gh-issue-edit.sh <issue-number> --checkbox <indices> --check|--uncheck
#   scripts/gh-issue-edit.sh --help|-h

set -euo pipefail

usage() {
    cat <<EOF
Usage:
  $0 <issue-number> <body-file>
      Update issue body with contents of file

  $0 <issue-number> --checkbox <indices> --check|--uncheck
      Update checkboxes at specified 1-based indices in issue body
      <indices>: comma-separated 1-based indices (e.g. 1,1,3,5)
      --check:   mark unchecked ( - [ ] ) as checked ( - [x] )
      --uncheck: mark checked ( - [x] ) as unchecked ( - [ ] )

  $0 --help|-h
      Show this help
EOF
}

if [ $# -eq 0 ]; then
    usage >&2
    exit 1
fi

# --help/-h
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
    exit 0
fi

ISSUE_NUMBER="$1"

# Validate issue number is a positive integer
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: issue number must be a positive integer: $ISSUE_NUMBER" >&2
    exit 1
fi

# Detect --checkbox mode
if [ $# -ge 2 ] && [ "$2" = "--checkbox" ]; then
    # Check indices argument
    if [ $# -lt 3 ]; then
        echo "Error: please specify indices" >&2
        exit 1
    fi

    INDICES="$3"

    # Validate indices are numeric (early check)
    IFS=',' read -ra IDX_VALIDATE <<< "$INDICES"
    for idx in "${IDX_VALIDATE[@]}"; do
        if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
            echo "Error: indices must be positive integers: $idx" >&2
            exit 1
        fi
    done

    # Check action argument
    if [ $# -lt 4 ]; then
        echo "Error: please specify --check or --uncheck" >&2
        exit 1
    fi

    ACTION="$4"

    if [ "$ACTION" != "--check" ] && [ "$ACTION" != "--uncheck" ]; then
        echo "Error: please specify --check or --uncheck" >&2
        exit 1
    fi

    # Fetch issue body
    BODY=$(gh issue view "$ISSUE_NUMBER" --json body -q .body)

    # Count checkboxes
    CB_COUNT=$(echo "$BODY" | awk '/^- \[[ xX]\]/ { count++ } END { print count+0 }')

    # Validate index range
    IFS=',' read -ra IDX_LIST <<< "$INDICES"
    for idx in "${IDX_LIST[@]}"; do
        if [ "$idx" -lt 1 ] || [ "$idx" -gt "$CB_COUNT" ]; then
            echo "Error: index out of range: $idx (checkbox count: $CB_COUNT)" >&2
            exit 1
        fi
    done

    # Update checkboxes with awk
    UPDATED_BODY=$(echo "$BODY" | awk -v action="$ACTION" -v indices="$INDICES" '
    BEGIN {
        n = split(indices, idx_arr, ",")
        for (i = 1; i <= n; i++) {
            target_set[idx_arr[i]+0] = 1
        }
        cb_count = 0
    }
    /^- \[[ xX]\]/ {
        cb_count++
        if (cb_count in target_set) {
            if (action == "--check") {
                sub(/^- \[ \]/, "- [x]")
            } else {
                sub(/^- \[[xX]\]/, "- [ ]")
            }
        }
    }
    { print }
    ')

    # Write to temp file and update
    TMPFILE=$(mktemp)
    trap 'rm -f "$TMPFILE"' EXIT
    printf '%s' "$UPDATED_BODY" > "$TMPFILE"

    if ! gh issue edit "$ISSUE_NUMBER" --body-file "$TMPFILE"; then
        rm -f "$TMPFILE"
        echo "Error: failed to update issue #$ISSUE_NUMBER body" >&2
        exit 1
    fi
    rm -f "$TMPFILE"

else
    # body-file mode
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <issue-number> <body-file>" >&2
        exit 1
    fi

    BODY_FILE="$2"

    # Check file exists
    if [ ! -f "$BODY_FILE" ]; then
        echo "Error: file not found: $BODY_FILE" >&2
        exit 1
    fi

    # Read body from file
    BODY=$(cat "$BODY_FILE")

    if [ -z "$BODY" ]; then
        echo "Error: empty body: $BODY_FILE" >&2
        exit 1
    fi

    if ! gh issue edit "$ISSUE_NUMBER" --body "$BODY"; then
        echo "Error: failed to update issue #$ISSUE_NUMBER body" >&2
        exit 1
    fi
fi
