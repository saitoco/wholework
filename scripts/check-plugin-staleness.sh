#!/usr/bin/env bash
# check-plugin-staleness.sh - Report how far the plugin directory is behind its upstream.
#
# Used by modules/phase-banner.md (Step 4) to warn, at the start of a Skill, that the
# directory it was loaded from (${CLAUDE_PLUGIN_ROOT}, typically `claude --plugin-dir <checkout>`)
# is a git checkout whose upstream branch has commits HEAD does not contain.
#
# Usage: check-plugin-staleness.sh [plugin-root]
#   plugin-root  Directory to inspect. Defaults to the parent directory of this script,
#                which is ${CLAUDE_PLUGIN_ROOT} when run from ${CLAUDE_PLUGIN_ROOT}/scripts/.
#
# Output contract (stdout), exit code is always 0:
#   - nothing, or
#   - one line when the upstream is ahead of HEAD:
#       behind=<N> upstream=<tracking ref, e.g. origin/main> root=<shell-quoted absolute path>
#
# Fail-open policy: this is an advisory check. Every failure path (not a git checkout,
# detached HEAD, no upstream, git missing or failing, non-numeric count) prints nothing and
# exits 0, because a silent skip is safer than stopping a Skill or raising a false warning.
# For that reason this script deliberately does not use `set -e` or `set -u`: every failure
# must land on a quiet `exit 0`, not on an unhandled error.
#
# Read-only and offline: only `git rev-parse` and `git rev-list` are used. It never runs
# fetch, pull, merge, checkout, or anything else that changes the repository or touches the
# network, so the count is relative to the remote-tracking ref as of the last fetch.

unset CDPATH

root="${1:-}"
if [ -z "$root" ]; then
  root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)" || exit 0
else
  root="$(cd -- "$root" 2>/dev/null && pwd -P)" || exit 0
fi

command -v git >/dev/null 2>&1 || exit 0

# Only a directory that is itself the top level of a work tree counts as a checkout;
# a plain directory nested inside an unrelated repository must not report that repository.
top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || exit 0
top="$(cd -- "$top" 2>/dev/null && pwd -P)" || exit 0
[ "$top" = "$root" ] || exit 0

behind="$(git -C "$root" rev-list --count 'HEAD..@{u}' 2>/dev/null)" || exit 0
case "$behind" in
  ''|*[!0-9]*) exit 0 ;;
esac
[ "$behind" -gt 0 ] || exit 0

upstream="$(git -C "$root" rev-parse --abbrev-ref '@{u}' 2>/dev/null)" || upstream="upstream"
[ -n "$upstream" ] || upstream="upstream"

printf 'behind=%s upstream=%s root=%q\n' "$behind" "$upstream" "$root"
exit 0
