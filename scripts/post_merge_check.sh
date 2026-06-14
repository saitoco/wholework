#!/bin/bash
# post_merge_check.sh
# Bundle and run post-merge manual verification for multiple Issues.
#
# Usage:
#   scripts/post_merge_check.sh <ISSUE_NUM>...
#
# For each issue: extracts verify-type: manual ACs from its Spec or Issue body,
# prompts [P]ass/[F]ail/[S]kip for each, then:
#   - All non-SKIP are PASS: transitions issue to phase/done and posts completion comment
#   - Any FAIL: reopens issue and posts FAIL detail comment
#   - All SKIP: no label change

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <ISSUE_NUM>..." >&2
    echo "  Example: $0 501 502 503" >&2
    exit 1
fi

# Validate all arguments are numeric before processing
for ARG in "$@"; do
    case "$ARG" in
        ''|*[!0-9]*)
            echo "Error: '$ARG' is not a valid issue number" >&2
            echo "Usage: $0 <ISSUE_NUM>..." >&2
            exit 1
            ;;
    esac
done

# extract_manual_acs <file>
# Print lines from <file> that contain verify-type: manual, stripped of checkbox and HTML comment markup.
extract_manual_acs() {
    local src_file="$1"
    grep "verify-type: manual" "$src_file" \
        | sed 's/^[[:space:]]*-[[:space:]]*//' \
        | sed 's/^\[[[:space:]xX]*\][[:space:]]*//' \
        | sed 's/[[:space:]]*<!--.*$//' \
        | grep -v '^[[:space:]]*$' || true
}

for NUMBER in "$@"; do
    echo ""
    echo "=== Issue #${NUMBER} ==="

    # Locate Spec file (prefer Spec over Issue body)
    SPEC_FILE=""
    if [ -d "docs/spec" ]; then
        SPEC_FILE=$(find docs/spec -name "issue-${NUMBER}-*.md" 2>/dev/null | head -1 || true)
    fi

    # Extract manual ACs from Spec or Issue body
    TMP_SRC_CREATED=false
    if [ -n "$SPEC_FILE" ] && [ -f "$SPEC_FILE" ]; then
        echo "Source: Spec (${SPEC_FILE})"
        TMP_SRC="$SPEC_FILE"
    else
        echo "Source: Issue body (no Spec found)"
        TMP_SRC=$(mktemp /tmp/post-merge-issue-body-XXXXXX.md)
        TMP_SRC_CREATED=true
        gh issue view "$NUMBER" --json body -q .body > "$TMP_SRC" 2>/dev/null || true
    fi

    MANUAL_ACS=$(extract_manual_acs "$TMP_SRC" || true)

    if $TMP_SRC_CREATED; then
        rm -f "$TMP_SRC"
    fi

    if [ -z "$MANUAL_ACS" ]; then
        echo "No manual ACs found for Issue #${NUMBER}. Skipping."
        continue
    fi

    # Write ACs to temp file and iterate via fd 3 to keep stdin free for user input
    TMP_ACS=$(mktemp /tmp/post-merge-acs-XXXXXX.txt)
    echo "$MANUAL_ACS" > "$TMP_ACS"

    PASS_COUNT=0
    FAIL_COUNT=0
    SKIP_COUNT=0
    FAILED_ACS=""
    AC_INDEX=0

    exec 3< "$TMP_ACS"
    while IFS= read -r -u 3 ac_line; do
        [ -z "$ac_line" ] && continue
        AC_INDEX=$((AC_INDEX + 1))
        echo ""
        echo "[Issue #${NUMBER}] AC ${AC_INDEX}: ${ac_line}"
        printf "[P]ass/[F]ail/[S]kip (default: S): "

        INPUT=""
        if read -r INPUT; then
            INPUT="${INPUT:0:1}"
        fi
        echo ""

        case "$INPUT" in
            P|p)
                echo "  => PASS"
                PASS_COUNT=$((PASS_COUNT + 1))
                ;;
            F|f)
                echo "  => FAIL"
                FAIL_COUNT=$((FAIL_COUNT + 1))
                if [ -z "$FAILED_ACS" ]; then
                    FAILED_ACS="$ac_line"
                else
                    FAILED_ACS="${FAILED_ACS}
${ac_line}"
                fi
                ;;
            *)
                echo "  => SKIP"
                SKIP_COUNT=$((SKIP_COUNT + 1))
                ;;
        esac
    done
    exec 3<&-
    rm -f "$TMP_ACS"

    echo ""
    echo "Results for Issue #${NUMBER}: PASS=${PASS_COUNT} FAIL=${FAIL_COUNT} SKIP=${SKIP_COUNT}"

    if [ "$FAIL_COUNT" -gt 0 ]; then
        # Any FAIL: reopen issue and post failure comment
        echo "FAIL detected — reopening Issue #${NUMBER}..."
        gh issue reopen "$NUMBER"

        TMP_COMMENT=$(mktemp /tmp/post-merge-comment-XXXXXX.md)
        cat > "$TMP_COMMENT" <<COMMENT
## Post-Merge Manual Verification: FAIL

The following AC(s) failed during manual verification via \`scripts/post_merge_check.sh\`:

$(printf '%s\n' "$FAILED_ACS" | sed 's/^/- /')

Please address the failed items and re-run verification.
COMMENT
        "$SCRIPT_DIR/gh-issue-comment.sh" "$NUMBER" "$TMP_COMMENT"
        rm -f "$TMP_COMMENT"

    elif [ "$PASS_COUNT" -gt 0 ]; then
        # All non-SKIP results are PASS: transition to phase/done
        echo "Transitioning Issue #${NUMBER} to phase/done..."
        "$SCRIPT_DIR/gh-label-transition.sh" "$NUMBER" done

        TMP_COMMENT=$(mktemp /tmp/post-merge-comment-XXXXXX.md)
        cat > "$TMP_COMMENT" <<COMMENT
## Post-Merge Manual Verification: Complete

All manual ACs for Issue #${NUMBER} passed (run via \`scripts/post_merge_check.sh\`).

- PASS: ${PASS_COUNT}
- SKIP: ${SKIP_COUNT}

Issue transitioned to \`phase/done\`.
COMMENT
        "$SCRIPT_DIR/gh-issue-comment.sh" "$NUMBER" "$TMP_COMMENT"
        rm -f "$TMP_COMMENT"

    else
        # All SKIP: no label change
        echo "All ACs were skipped for Issue #${NUMBER}. No label change."
    fi
done

echo ""
echo "post_merge_check.sh: Done."
