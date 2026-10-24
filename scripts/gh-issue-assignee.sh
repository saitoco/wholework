#!/bin/bash
# gh-issue-assignee.sh
# Inspect and update the assignee of an issue on behalf of the executing user
#
# Usage:
#   scripts/gh-issue-assignee.sh status   <issue-number>   # read-only
#   scripts/gh-issue-assignee.sh assign   <issue-number>   # add the executing user, only when unassigned
#   scripts/gh-issue-assignee.sh reassign <issue-number>   # replace the other assignees with the executing user
#
# The executing user is the login returned by `gh api user`.
#
# Output (stdout, exactly one word):
#   status:
#     unassigned  no assignee
#     self        the only assignee is the executing user
#     other       the assignees include someone other than the executing user
#                 (bots and Copilot count as "other")
#     unknown     the assignees could not be read
#   assign / reassign:
#     assigned    a write was made and the executing user is now an assignee
#                 (also when the verification re-read could not confirm it)
#     unchanged   nothing was changed (assign: someone is already assigned;
#                 reassign: the executing user is already the only assignee)
#     disabled    nothing was done because `auto-assign: false` is set in .wholework.yml
#     failed      the update failed (the reason is a warning on stderr)
#
# Exit codes:
#   0 -- always, including every runtime failure (the vocabulary word reports it,
#        so that a calling phase is never stopped by an assignee problem)
#   1 -- usage error only (bad subcommand, issue number is not a positive
#        integer, missing or extra arguments)
#
# stderr carries human-readable messages only, each starting with "Warning:" or
# "Info:". Machine consumers must read the stdout word and ignore stderr.
#
# When the executing user cannot be identified (`gh api user` fails, prints nothing,
# or prints a malformed login; typical for GitHub App tokens and the CI GITHUB_TOKEN):
#   status:   no assignee -> unassigned; one or more assignees -> other
#             (whether they are the executing user cannot be checked, so they are
#             never treated as the executing user)
#   assign:   someone already assigned -> unchanged (the executing user is not needed);
#             nobody assigned -> warning and failed (nothing is written)
#   reassign: warning and failed (nothing is written)
#
# auto-assign (.wholework.yml, default true): when false, assign and reassign print
# "disabled" without calling gh at all. status is never affected. The setting does
# not depend on the autonomy tier. The setting is read from .wholework.yml in the
# current directory (or WHOLEWORK_CONFIG_PATH), like every get-config-value.sh
# caller, so run this script from the repository root: from another directory the
# file is not found and the default (true) applies.
#
# Writes use the REST API instead of `gh issue edit`: `gh issue edit --add-assignee`
# sends a client-computed full assignee set, which can drop an assignee another
# member added in between. assign uses the add endpoint (server-side additive);
# reassign uses the update endpoint (replaces the set). After every write the
# assignees are re-read: when the executing user is missing the update is reported
# as failed, and when someone else is also assigned (another member started at about
# the same time) a warning is printed.
#
# Limitation: an assignee is not a lock. The same user running another session cannot
# be told apart from this session.

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

usage() {
    echo "Usage: $(basename "$0") <status|assign|reassign> <issue-number>"
    echo ""
    echo "Subcommands:"
    echo "  status    Print unassigned | self | other | unknown (read-only)"
    echo "  assign    Add the executing user only when the issue has no assignee"
    echo "  reassign  Replace the other assignees with the executing user"
    echo ""
    echo "assign / reassign print: assigned | unchanged | disabled | failed"
    echo "Set 'auto-assign: false' in .wholework.yml to disable assign and reassign."
    echo ""
    echo "Exit codes:"
    echo "  0 -- always (runtime failures are reported on stdout as unknown / failed)"
    echo "  1 -- usage error"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ $# -ne 2 ]; then
    echo "Error: subcommand and issue number are required" >&2
    usage >&2
    exit 1
fi

SUBCOMMAND="$1"
ISSUE_NUMBER="$2"

case "$SUBCOMMAND" in
    status|assign|reassign) ;;
    *)
        echo "Error: unknown subcommand: $SUBCOMMAND" >&2
        usage >&2
        exit 1
        ;;
esac

if ! [[ "$ISSUE_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: issue number must be a positive integer: $ISSUE_NUMBER" >&2
    exit 1
fi

# Globals filled by the helpers below
ME=""            # executing user login (empty when unknown)
ASSIGNEES=""     # newline-separated assignee logins
N_TOTAL=0
N_SELF=0
N_OTHER=0
OTHER_LOGINS=""  # ", "-joined logins other than the executing user
ALL_LOGINS=""    # ", "-joined logins of every assignee

warn() {
    echo "Warning: $*" >&2
}

lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# auto-assign defaults to true; only an explicit "false" disables writes.
auto_assign_enabled() {
    local value=""
    value=$("$SCRIPT_DIR/get-config-value.sh" auto-assign true 2>/dev/null) || value="true"
    value=$(lower "$value" | tr -d '[:space:]')
    [ "$value" != "false" ]
}

# Resolve the executing user into ME. Returns 1 (ME empty) when it cannot be identified.
resolve_me() {
    local raw="" first=""
    ME=""
    if ! raw=$(gh api user --jq '.login' 2>/dev/null); then
        return 1
    fi
    first=$(printf '%s\n' "$raw" | head -n 1 | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -z "$first" ] || [ "${#first}" -gt 100 ]; then
        return 1
    fi
    if ! [[ "$first" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
        return 1
    fi
    ME="$first"
    return 0
}

# Read the assignee logins of the issue into ASSIGNEES. Returns 1 when they cannot be read.
read_assignees() {
    local raw="" logins=""
    ASSIGNEES=""
    if ! raw=$(gh issue view "$ISSUE_NUMBER" --json assignees 2>/dev/null); then
        return 1
    fi
    raw=$(printf '%s' "$raw" | tr -d '\r')
    if [ -z "${raw//[[:space:]]/}" ]; then
        return 1
    fi
    if ! logins=$(printf '%s' "$raw" | jq -r 'if (.assignees | type) == "array" then .assignees[]?.login // empty else error("no assignees array") end' 2>/dev/null); then
        return 1
    fi
    ASSIGNEES=$(printf '%s\n' "$logins" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d')
    return 0
}

# Split ASSIGNEES into the executing user (case-insensitive) and the others.
# With ME empty every assignee counts as "other".
classify_assignees() {
    local login="" me_lc=""
    N_TOTAL=0
    N_SELF=0
    N_OTHER=0
    OTHER_LOGINS=""
    ALL_LOGINS=""
    me_lc=$(lower "$ME")
    # Read line by line: logins such as "dependabot[bot]" must never be glob-expanded
    while IFS= read -r login; do
        [ -n "$login" ] || continue
        N_TOTAL=$((N_TOTAL + 1))
        if [ -z "$ALL_LOGINS" ]; then
            ALL_LOGINS="$login"
        else
            ALL_LOGINS="$ALL_LOGINS, $login"
        fi
        if [ -n "$me_lc" ] && [ "$(lower "$login")" = "$me_lc" ]; then
            N_SELF=$((N_SELF + 1))
        else
            N_OTHER=$((N_OTHER + 1))
            if [ -z "$OTHER_LOGINS" ]; then
                OTHER_LOGINS="$login"
            else
                OTHER_LOGINS="$OTHER_LOGINS, $login"
            fi
        fi
    done <<EOF
$ASSIGNEES
EOF
}

# Re-read the assignees after a write and print the result word.
verify_after_write() {
    if ! read_assignees; then
        warn "could not re-read the assignees of issue #$ISSUE_NUMBER to verify the update; continuing"
        echo "assigned"
        return 0
    fi
    classify_assignees
    if [ "$N_SELF" -eq 0 ]; then
        warn "@$ME is not an assignee of issue #$ISSUE_NUMBER after the update (the change may have been silently dropped, e.g. no push access); continuing"
        echo "failed"
        return 0
    fi
    if [ "$N_OTHER" -gt 0 ]; then
        warn "issue #$ISSUE_NUMBER is also assigned to: $OTHER_LOGINS. Another member may have started this Issue at about the same time; check with them to avoid duplicate work"
    fi
    echo "assigned"
}

# Add the executing user (additive endpoint). Prints nothing on success.
api_add() {
    gh api "repos/{owner}/{repo}/issues/$ISSUE_NUMBER/assignees" -X POST -f "assignees[]=$ME" >/dev/null 2>&1
}

# Replace the assignee set with the executing user only.
api_replace() {
    gh api "repos/{owner}/{repo}/issues/$ISSUE_NUMBER" -X PATCH -f "assignees[]=$ME" >/dev/null 2>&1
}

cmd_status() {
    if ! read_assignees; then
        warn "could not read the assignees of issue #$ISSUE_NUMBER; status is unknown"
        echo "unknown"
        return 0
    fi
    classify_assignees
    if [ "$N_TOTAL" -eq 0 ]; then
        echo "unassigned"
        return 0
    fi
    resolve_me || true
    classify_assignees
    if [ "$N_OTHER" -eq 0 ]; then
        echo "self"
        return 0
    fi
    if [ -z "$ME" ]; then
        echo "Info: issue #$ISSUE_NUMBER is assigned to: $ALL_LOGINS (the executing user could not be identified, so these cannot be compared with you)" >&2
    else
        echo "Info: issue #$ISSUE_NUMBER is assigned to: $ALL_LOGINS" >&2
    fi
    echo "other"
}

cmd_assign() {
    if ! auto_assign_enabled; then
        echo "disabled"
        return 0
    fi
    if ! read_assignees; then
        warn "could not read the assignees of issue #$ISSUE_NUMBER; skipping the assignee update"
        echo "failed"
        return 0
    fi
    classify_assignees
    if [ "$N_TOTAL" -gt 0 ]; then
        echo "unchanged"
        return 0
    fi
    if ! resolve_me; then
        warn "could not identify the executing user (gh api user failed); skipping the assignee update for issue #$ISSUE_NUMBER"
        echo "failed"
        return 0
    fi
    if ! api_add; then
        warn "failed to update the assignee of issue #$ISSUE_NUMBER (no permission or API error); continuing"
        echo "failed"
        return 0
    fi
    verify_after_write
}

cmd_reassign() {
    if ! auto_assign_enabled; then
        echo "disabled"
        return 0
    fi
    if ! read_assignees; then
        warn "could not read the assignees of issue #$ISSUE_NUMBER; skipping the assignee update"
        echo "failed"
        return 0
    fi
    if ! resolve_me; then
        warn "could not identify the executing user (gh api user failed); skipping the assignee update for issue #$ISSUE_NUMBER"
        echo "failed"
        return 0
    fi
    classify_assignees
    if [ "$N_TOTAL" -gt 0 ] && [ "$N_OTHER" -eq 0 ]; then
        echo "unchanged"
        return 0
    fi
    if [ "$N_TOTAL" -eq 0 ]; then
        # Nobody assigned as far as we saw: add instead of replacing, so that an
        # assignee another member added in between is not removed unseen.
        if ! api_add; then
            warn "failed to update the assignee of issue #$ISSUE_NUMBER (no permission or API error); continuing"
            echo "failed"
            return 0
        fi
    else
        if ! api_replace; then
            warn "failed to update the assignee of issue #$ISSUE_NUMBER (no permission or API error); continuing"
            echo "failed"
            return 0
        fi
    fi
    verify_after_write
}

case "$SUBCOMMAND" in
    status) cmd_status ;;
    assign) cmd_assign ;;
    reassign) cmd_reassign ;;
esac
