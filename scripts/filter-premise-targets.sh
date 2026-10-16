#!/usr/bin/env bash
# filter-premise-targets.sh
# Drop Issues whose implementation has already landed from the set of Issues that
# `/audit premise` evaluates. A premise marker describes the codebase state before the
# Issue's implementation, so implementing the Issue is expected to break it; an EXPIRED
# report for such an Issue is by design and carries no signal. See
# scripts/check-premise-expiry.sh (header, "Lifecycle" section) for the SSoT of the marker
# lifecycle.
#
# Usage:
#   gh issue list --state open --json number,title,body,labels --limit 100 | scripts/filter-premise-targets.sh
#
# Input (stdin): the JSON array printed by `gh issue list --json`. Each element is an object;
# `labels` is an array of objects that carry a `name`.
#
# Output:
#   stdout: the same array without the excluded Issues (compact `jq -c` form; remaining
#           elements are passed through unmodified).
#   stderr: one `EXCLUDED: #<N> (<label>[,<label>])` line per excluded Issue.
#
# Exclusion condition (exact match): an Issue is excluded when one of its `labels[].name`
# is exactly `phase/verify` or `phase/done`. Similar names (`retro/verify`,
# `phase/verify-extra`, `Phase/Verify`, `not-phase/verify`) do not match. An Issue whose
# `labels` field is missing, null, or malformed is kept (evaluated as before).
#
# Fail-open (always exits 0 except for a usage error): the filter is the gate that decides
# which Issues get evaluated, so a failure must not shrink the set silently -- that would
# reproduce the silent false negative this mechanism exists to prevent. A failure only adds
# noise.
#
#   | Input                                          | stdout          | stderr                  | exit |
#   |------------------------------------------------|-----------------|-------------------------|------|
#   | JSON array                                     | filtered array  | EXCLUDED: lines         | 0    |
#   | empty or whitespace only                       | (nothing)       | Warning: empty input    | 0    |
#   | not valid JSON / not an array / jq unavailable | input unchanged | Warning: passing through| 0    |
#   | any argument                                   | (nothing)       | Usage: ...              | 1    |
#
# Empty input prints nothing (rather than `[]`): an upstream `gh` failure that left stdin
# empty must not read as "no Issues carry a marker".
#
# There is no timeout or kill condition: the script has no network or external I/O, only
# stdin and `jq`.
#
# bash 3.2+ compatible: no mapfile, no ${VAR,,}. External commands: cat, jq.

set -uo pipefail

if [ $# -ne 0 ]; then
  echo "Usage: filter-premise-targets.sh (reads a JSON array on stdin)" >&2
  exit 1
fi

INPUT="$(cat)"

if [ -z "${INPUT//[[:space:]]/}" ]; then
  echo "Warning: filter-premise-targets.sh: empty input — nothing to filter" >&2
  exit 0
fi

PASSTHROUGH_WARNING="Warning: filter-premise-targets.sh: input is not a JSON array (or jq is unavailable) — passing it through unfiltered"

if ! printf '%s' "$INPUT" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "$PASSTHROUGH_WARNING" >&2
  printf '%s\n' "$INPUT"
  exit 0
fi

JQ_DEFS='def names: [ (.labels? // [])[]? | .name? // empty ]; def hits: [ names[] | select(. == "phase/verify" or . == "phase/done") ]; '

FILTERED="$(printf '%s' "$INPUT" | jq -c "$JQ_DEFS"'[ .[] | select((hits | length) == 0) ]' 2>/dev/null)" || FILTERED=""

if [ -z "$FILTERED" ]; then
  echo "$PASSTHROUGH_WARNING" >&2
  printf '%s\n' "$INPUT"
  exit 0
fi

EXCLUDED="$(printf '%s' "$INPUT" | jq -r "$JQ_DEFS"'.[] | select((hits | length) > 0) | "EXCLUDED: #\(.number) (\(hits | join(",")))"' 2>/dev/null)" || EXCLUDED=""

if [ -n "$EXCLUDED" ]; then
  printf '%s\n' "$EXCLUDED" >&2
fi

printf '%s\n' "$FILTERED"
exit 0
