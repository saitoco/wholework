#!/usr/bin/env bash
# collect-verify-path-done-rate.sh
# Compare `phase/done` reach rate across the three verify-backlog dispatch
# paths (batch sweep / observation dispatch / opportunistic-verify), for
# `/audit stats --retention` Section 12 (see
# docs/spec/issue-1352-audit-batch-sweep-done-rate.md).
#
# Usage:
#   scripts/collect-verify-path-done-rate.sh [--limit N]
#
# --limit N: `gh issue list` page size (default 1000, same convention as
#   Section 10's `gh issue list --state all --limit 1000`). A stderr warning
#   is printed if the returned count equals --limit (some Issues may not
#   have been scanned).
#
# Population: `gh issue list --state all --json number,labels,comments
# --limit N` fetches every Issue (with labels and comments) in one call —
# avoiding the `gh issue view` per-Issue N+1 pattern used by
# collect-verify-retention-stats.sh. On `gh` failure, all three paths
# fail-open (processed=0 done=0 rate=N/A, exit 0) rather than only the paths
# that depend on this call, so "gh failed -> unknown" is never conflated
# with "measured 0%".
#
# Path membership (not mutually exclusive -- an Issue can belong to more
# than one path):
#   - batch-sweep: at least one comment body contains
#     "<!-- wholework-event: type=batch-verify-dispatch" (posted by
#     `/audit verify-backlog` Step 2).
#   - observation-dispatch: at least one comment body contains
#     "<!-- wholework-event: type=observation-trigger" (posted by
#     observation-trigger.sh; read-only here).
#   - opportunistic-verify: Issue numbers with at least one
#     `opportunistic_verify_result` event in docs/sessions/*/events.jsonl
#     (same data source as collect-opportunistic-retire-candidates.sh /
#     Section 11). Issue numbers not present in the `gh issue list` result
#     (e.g. deleted) are excluded from aggregation, with the excluded count
#     printed as a stderr warning.
#
# For each path: processed_count (set size), done_count (subset carrying
# `phase/done`), rate = done_count/processed_count as a percentage with one
# decimal place, or "N/A" when processed_count is 0 (no division by zero).
#
# Output: stdout carries exactly 3 tab-separated lines, one per path:
#   <path>\t<processed_count>\t<done_count>\t<rate>
# `path` is one of the fixed slugs: batch-sweep / observation-dispatch /
# opportunistic-verify.
#
# bash 3.2+ compatible (macOS system bash): no mapfile, no associative
# arrays; jq drives the actual data processing (same approach as
# collect-opportunistic-retire-candidates.sh).

set -euo pipefail

LIMIT=1000

while [ $# -gt 0 ]; do
  case "$1" in
    --limit)
      if [ $# -lt 2 ]; then
        echo "Error: --limit requires an argument" >&2
        exit 1
      fi
      LIMIT="$2"
      shift 2
      ;;
    --limit=*)
      LIMIT="${1#--limit=}"
      shift
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if ! echo "$LIMIT" | grep -qE '^[0-9]+$' || [ "$LIMIT" -eq 0 ]; then
  echo "Error: --limit must be a positive integer: $LIMIT" >&2
  exit 1
fi

fail_open() {
  printf 'batch-sweep\t0\t0\tN/A\n'
  printf 'observation-dispatch\t0\t0\tN/A\n'
  printf 'opportunistic-verify\t0\t0\tN/A\n'
}

ISSUES_JSON=$(gh issue list --state all --json number,labels,comments --limit "$LIMIT" 2>/dev/null) || {
  fail_open
  exit 0
}

if [ -z "$ISSUES_JSON" ]; then
  fail_open
  exit 0
fi

ISSUE_COUNT=$(printf '%s' "$ISSUES_JSON" | jq 'length' 2>/dev/null || echo 0)
if [ "$ISSUE_COUNT" -eq "$LIMIT" ]; then
  echo "Warning: issue list hit the --limit ${LIMIT} cap; some Issues were not scanned." >&2
fi

rate_of() {
  local processed="$1"
  local done_count="$2"
  awk -v p="$processed" -v d="$done_count" 'BEGIN {
    if (p == 0) { print "N/A"; exit }
    printf "%.1f%%\n", (d / p) * 100
  }'
}

path_stats() {
  local marker="$1"
  printf '%s' "$ISSUES_JSON" | jq -r --arg marker "$marker" '
    [ .[] | select(.comments | any(.body // "" | contains($marker))) ] as $sel
    | ($sel | length) as $processed
    | ([ $sel[] | select(.labels | any(.name == "phase/done")) ] | length) as $done
    | "\($processed)\t\($done)"
  '
}

BATCH_STATS=$(path_stats "<!-- wholework-event: type=batch-verify-dispatch")
BATCH_PROCESSED=$(printf '%s' "$BATCH_STATS" | cut -f1)
BATCH_DONE=$(printf '%s' "$BATCH_STATS" | cut -f2)

OBS_STATS=$(path_stats "<!-- wholework-event: type=observation-trigger")
OBS_PROCESSED=$(printf '%s' "$OBS_STATS" | cut -f1)
OBS_DONE=$(printf '%s' "$OBS_STATS" | cut -f2)

SESSIONS_DIR="docs/sessions"
OPP_ISSUES_JSON="[]"
if [ -d "$SESSIONS_DIR" ]; then
  EVENT_FILES=()
  while IFS= read -r f; do
    EVENT_FILES+=("$f")
  done < <(find "$SESSIONS_DIR" -mindepth 2 -maxdepth 2 -name events.jsonl 2>/dev/null)

  if [ "${#EVENT_FILES[@]}" -gt 0 ]; then
    OPP_ISSUES_JSON=$(
      for f in "${EVENT_FILES[@]}"; do
        jq -c . "$f" 2>/dev/null || true
      done | jq -cs '
        map(select(.event == "opportunistic_verify_result")) | map(.issue) | unique
      '
    )
    if [ -z "$OPP_ISSUES_JSON" ]; then
      OPP_ISSUES_JSON="[]"
    fi
  fi
fi

OPP_RESULT=$(printf '%s' "$ISSUES_JSON" | jq -r --argjson opp "$OPP_ISSUES_JSON" '
  . as $issues
  | ($opp | map(tostring) | unique) as $opp_set
  | ($issues | map(.number | tostring)) as $known
  | ($opp_set - $known) as $excluded
  | ($issues | map(select((.number | tostring) as $n | $opp_set | index($n) != null))) as $sel
  | ($sel | length) as $processed
  | ([ $sel[] | select(.labels | any(.name == "phase/done")) ] | length) as $done
  | "\($processed)\t\($done)\t\($excluded | length)"
')
OPP_PROCESSED=$(printf '%s' "$OPP_RESULT" | cut -f1)
OPP_DONE=$(printf '%s' "$OPP_RESULT" | cut -f2)
OPP_EXCLUDED=$(printf '%s' "$OPP_RESULT" | cut -f3)

if [ "$OPP_EXCLUDED" -gt 0 ] 2>/dev/null; then
  echo "Warning: ${OPP_EXCLUDED} opportunistic-verify Issue number(s) not found in gh issue list results; excluded from aggregation." >&2
fi

printf 'batch-sweep\t%s\t%s\t%s\n' "$BATCH_PROCESSED" "$BATCH_DONE" "$(rate_of "$BATCH_PROCESSED" "$BATCH_DONE")"
printf 'observation-dispatch\t%s\t%s\t%s\n' "$OBS_PROCESSED" "$OBS_DONE" "$(rate_of "$OBS_PROCESSED" "$OBS_DONE")"
printf 'opportunistic-verify\t%s\t%s\t%s\n' "$OPP_PROCESSED" "$OPP_DONE" "$(rate_of "$OPP_PROCESSED" "$OPP_DONE")"
