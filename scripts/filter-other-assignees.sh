#!/bin/bash
# filter-other-assignees.sh
# Drop the issues that are assigned to someone other than the executing user.
#
# Usage:
#   gh issue list --state open --json number,...,assignees ... | scripts/filter-other-assignees.sh
#   scripts/filter-other-assignees.sh --help
#
# Used by `/auto --batch N` (Count mode) and by scripts/resolve-batch-query.sh
# (`/auto --batch --until <query>`) so that an issue another member is working on is not
# picked up automatically.
#
# stdin:  a JSON array of objects. Every element needs a numeric `number`. `assignees` is an
#         array of objects with a string `login`; null, a missing key and [] all mean
#         "unassigned".
# stdout: a compact JSON array (jq -c) in the same shape as the input (order and every field
#         are kept) without the excluded issues. `[]` when every issue is excluded.
# stderr: human-readable lines starting with "Info:", "Warning:" or "Error:" only. Machine
#         consumers must read stdout only.
#
# Exit codes:
#   0  success (stdout is always a JSON array). --help / -h also exit 0.
#   1  usage error (an argument is given, stdin is a terminal) or invalid input (empty stdin,
#      invalid JSON, not an array, an element that is not an object or has no numeric
#      `number`). stdout is empty. Also used when jq itself fails, so a partial output is
#      never printed.
#
# Decision rule (an issue is excluded when any of these holds, otherwise it is kept):
#   - the assignees include someone other than the executing user (several people, bots and
#     Copilot included); logins are compared case-insensitively
#   - `assignees` is not an array, or an element has no string `login`, or a `login` is empty
#     (it cannot be confirmed to be the executing user)
#   - the executing user cannot be identified and the issue has a non-empty assignees array
# Kept: null / missing / [] assignees (the executing user is not needed), and issues whose
# assignees are all the executing user.
#
# The executing user is the login returned by `gh api user`. It is looked up lazily, once,
# and only when at least one issue has a non-empty assignees array. The accepted login format
# is the same as `resolve_me` in scripts/gh-issue-assignee.sh (first line only, CR and
# surrounding whitespace removed, ^[A-Za-z0-9][A-Za-z0-9_-]*$, at most 100 characters).
#
# Fail-closed when the executing user cannot be identified (`gh api user` fails, prints
# nothing, or prints a malformed login; typical for GitHub App tokens and the CI
# GITHUB_TOKEN): every issue that has an assignee is excluded and a warning is printed to
# stderr. Whether an assignee is the executing user or another member cannot be checked, and
# the cost is asymmetric: excluding too much only means the issue is not picked this time (a
# re-run fixes it), while not excluding means working on top of another member's issue, which
# is hard to take back. This matches `gh-issue-assignee.sh status`, which reports "other" in
# the same situation. Authenticating `gh` with a personal access token resolves it.
#
# The evaluation is a single read at the time of the call; an assignee is not a lock.

set -euo pipefail

usage() {
    echo "Usage: gh issue list --json number,...,assignees ... | $(basename "$0")"
    echo ""
    echo "Reads a JSON array of issues from stdin and prints the same array without the issues"
    echo "that are assigned to someone other than the executing user."
    echo ""
    echo "Kept: unassigned issues (assignees null, missing or []) and issues assigned only to"
    echo "the executing user. When the executing user cannot be identified, every issue that has"
    echo "an assignee is excluded (fail-closed) and a warning is printed to stderr."
    echo ""
    echo "Exit codes:"
    echo "  0 -- success (stdout is a JSON array)"
    echo "  1 -- usage error or invalid input (stdout is empty)"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ $# -ne 0 ]; then
    echo "Error: unexpected argument: $1" >&2
    usage >&2
    exit 1
fi

if [ -t 0 ]; then
    echo "Error: a JSON array of issues must be piped to stdin" >&2
    usage >&2
    exit 1
fi

# Shared jq definitions (used by the need-lookup check, the filter and the summary).
JQ_DEFS='
def atype: (.assignees | type);
def has_assignee: if atype == "null" then false elif atype == "array" then (.assignees | length) > 0 else true end;
def logins: if atype == "array" then [.assignees[] | if type == "object" and ((.login | type) == "string") then .login else "" end] else [] end;
def only_me($me): ($me != "") and atype == "array" and ((logins | length) > 0) and all(logins[]; . != "" and (ascii_downcase == ($me | ascii_downcase)));
def keep($me): (has_assignee | not) or only_me($me);
'

INPUT=""
ME=""

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

# Validate the input: a JSON array whose elements are objects with a numeric number.
validate_input() {
    if [ -z "${INPUT//[[:space:]]/}" ]; then
        echo "Error: empty input (expected a JSON array of issues on stdin)" >&2
        return 1
    fi
    if ! printf '%s' "$INPUT" | jq -e 'type == "array" and all(.[]; type == "object" and ((.number | type) == "number"))' >/dev/null 2>&1; then
        echo "Error: invalid input (expected a JSON array of objects that each have a numeric number)" >&2
        return 1
    fi
    return 0
}

# Print "true" when at least one issue has a non-empty assignees array.
needs_lookup() {
    printf '%s' "$INPUT" | jq -r 'any(.[]; (.assignees | type) == "array" and (.assignees | length) > 0)'
}

# Print the kept issues as a compact JSON array.
filter_issues() {
    printf '%s' "$INPUT" | jq -c --arg me "$ME" "$JQ_DEFS"'map(select(keep($me)))'
}

# Print the one-line summary of the excluded issues (empty when nothing is excluded).
summarize_excluded() {
    printf '%s' "$INPUT" | jq -r --arg me "$ME" "$JQ_DEFS"'
        [.[] | select(keep($me) | not)] as $ex
        | if ($ex | length) == 0 then empty else
            ($ex[:20] | map(
                "#\(.number) (" + (
                    if atype == "array" and ((logins | index("")) == null) and (logins | length) > 0
                    then (logins | map(gsub("[^A-Za-z0-9_.\\[\\]-]"; "?")) | join(", "))
                    else "unreadable assignees" end
                ) + ")"
            ) | join(", ")) as $list
            | ($ex | length) as $n
            | (if $n > 20 then ", ... (+\($n - 20) more)" else "" end) as $more
            | (if $me == ""
               then "Info: excluded \($n) issue(s) that have an assignee (the executing user could not be identified): "
               else "Info: excluded \($n) issue(s) assigned to someone other than the executing user: " end)
              + $list + $more
          end'
}

main() {
    local need="" result="" summary=""
    INPUT=$(cat)
    INPUT=$(printf '%s' "$INPUT" | tr -d '\r')
    validate_input || return 1
    if ! need=$(needs_lookup); then
        echo "Error: failed to evaluate the input" >&2
        return 1
    fi
    if [ "$need" = "true" ]; then
        if ! resolve_me; then
            echo "Warning: could not identify the executing user (gh api user failed); excluding every issue that has an assignee" >&2
        fi
    fi
    if ! result=$(filter_issues); then
        echo "Error: failed to filter the input" >&2
        return 1
    fi
    if ! summary=$(summarize_excluded); then
        echo "Error: failed to summarize the excluded issues" >&2
        return 1
    fi
    if [ -n "$summary" ]; then
        echo "$summary" >&2
    fi
    printf '%s\n' "$result"
}

main
