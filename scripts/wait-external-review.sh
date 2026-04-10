#!/bin/bash
# wait-external-review.sh
# Waits for an external review bot to complete a PR review and outputs the review content.
#
# Usage:
#   ./scripts/wait-external-review.sh          # PR for current branch (external review)
#   ./scripts/wait-external-review.sh 88       # Specify PR number (external review)
#   ./scripts/wait-external-review.sh 88 copilot            # Explicit Copilot review
#   ./scripts/wait-external-review.sh 88 claude-code-review # Claude Code Review
#
# When called from a Claude Code PostToolUse hook:
#   Receives tool information as JSON on stdin.
#   Processes only when the tool is a gh pr create command.

set -euo pipefail

# Configuration
TIMEOUT=${EXTERNAL_REVIEW_TIMEOUT:-${COPILOT_REVIEW_TIMEOUT:-300}}  # Default: 5 minutes
INTERVAL=${EXTERNAL_REVIEW_INTERVAL:-${COPILOT_REVIEW_INTERVAL:-10}}  # Default: 10 seconds

# Reviewer configuration: switched by second argument (default: copilot)
REVIEWER_TYPE="${2:-copilot}"

case "$REVIEWER_TYPE" in
    copilot)
        # GitHub API returns with [bot] suffix
        REVIEWER_LOGIN="copilot-pull-request-reviewer[bot]"
        # gh pr view returns without [bot] suffix
        REVIEWER_LOGIN_SHORT="copilot-pull-request-reviewer"
        REVIEWER_DISPLAY_NAME="Copilot"
        ;;
    claude-code-review)
        REVIEWER_LOGIN="claude-code-review[bot]"
        REVIEWER_LOGIN_SHORT="claude-code-review"
        REVIEWER_DISPLAY_NAME="Claude Code"
        ;;
    coderabbit)
        REVIEWER_LOGIN="coderabbitai[bot]"
        REVIEWER_LOGIN_SHORT="coderabbitai"
        REVIEWER_DISPLAY_NAME="CodeRabbit"
        ;;
    *)
        echo "Error: unknown reviewer type: ${REVIEWER_TYPE} (specify copilot, claude-code-review, or coderabbit)" >&2
        exit 1
        ;;
esac

# Get PR number
get_pr_number() {
    local pr_num="$1"

    if [ -n "$pr_num" ]; then
        # Validate that PR number is a positive integer
        if ! [[ "$pr_num" =~ ^[0-9]+$ ]]; then
            echo "Error: PR number must be a positive integer: $pr_num" >&2
            return 1
        fi
        echo "$pr_num"
        return
    fi

    # Get PR number from current branch
    gh pr view --json number -q '.number' 2>/dev/null || echo ""
}

# Check if external review exists
check_reviewer() {
    local pr_num="$1"
    # gh pr view returns without [bot] suffix
    gh pr view "$pr_num" --json latestReviews -q ".latestReviews[] | select(.author.login == \"$REVIEWER_LOGIN_SHORT\")" 2>/dev/null
}

# Output review content
output_review() {
    local pr_num="$1"

    echo "=== $REVIEWER_DISPLAY_NAME Review Complete ==="
    echo ""

    # Get review information (including review ID)
    local review_info
    review_info=$(gh api "repos/{owner}/{repo}/pulls/$pr_num/reviews" \
        --jq ".[] | select(.user.login == \"$REVIEWER_LOGIN\") | {id: .id, body: .body}" 2>/dev/null | head -1)

    # Output review body
    echo "$review_info" | jq -r '.body // ""' 2>/dev/null

    # Get review ID
    local review_id
    review_id=$(echo "$review_info" | jq -r '.id // ""' 2>/dev/null)

    if [ -n "$review_id" ]; then
        # Get review comments
        local comments
        comments=$(gh api "repos/{owner}/{repo}/pulls/$pr_num/reviews/$review_id/comments" 2>/dev/null || echo "[]")

        local comment_count
        comment_count=$(echo "$comments" | jq 'length' 2>/dev/null || echo "0")

        if [ "$comment_count" -gt 0 ]; then
            echo ""
            echo "=== $comment_count Review Comments ==="
            echo ""
            echo "$comments" | jq -r '.[] | "[\(.path):\(.line // .original_position // "N/A")]\n\(.body)\n"' 2>/dev/null
        fi
    fi

    echo ""
    echo "---"
    echo "Please review the $REVIEWER_DISPLAY_NAME feedback above."
    echo "Decide whether each comment requires action, and make any necessary changes."
    echo "If you determine no action is needed, please explain why."
    echo "Note: Do not merge the PR automatically; always confirm with the user first."
}

# Wait for external review to complete
wait_for_review() {
    local pr_num="$1"
    local elapsed=0

    echo "Waiting for $REVIEWER_DISPLAY_NAME review... (PR #$pr_num, timeout: ${TIMEOUT}s)" >&2

    while [ "$elapsed" -lt "$TIMEOUT" ]; do
        local review
        review=$(check_reviewer "$pr_num")

        if [ -n "$review" ]; then
            output_review "$pr_num"
            return 0
        fi

        sleep "$INTERVAL"
        elapsed=$((elapsed + INTERVAL))
        echo "  Waiting... (${elapsed}/${TIMEOUT}s)" >&2
    done

    echo "Timeout: $REVIEWER_DISPLAY_NAME review did not complete within ${TIMEOUT}s" >&2
    return 1
}

# Main
main() {
    local pr_num_arg="${1:-}"

    # Detect hook invocation via CLAUDE_PROJECT_DIR environment variable
    # When called from a hook, JSON is passed on stdin
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -z "$pr_num_arg" ]; then
        local tool_input=""

        # Read data from stdin (timeout 0.1s)
        if read -t 0.1 -r tool_input 2>/dev/null; then
            # Try to parse as JSON
            local command
            command=$(echo "$tool_input" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")

            if [ -n "$command" ]; then
                # Check if it's a gh pr create command
                if ! echo "$command" | grep -q 'gh pr create'; then
                    # Not gh pr create, do nothing
                    exit 0
                fi
            fi
        fi
    fi

    # Get PR number
    local pr_num
    pr_num=$(get_pr_number "$pr_num_arg")

    if [ -z "$pr_num" ]; then
        echo "Error: could not determine PR number. Specify the PR number as an argument." >&2
        exit 1
    fi

    wait_for_review "$pr_num"
}

main "$@"
