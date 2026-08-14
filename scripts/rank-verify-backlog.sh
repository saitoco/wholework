#!/usr/bin/env bash
# rank-verify-backlog.sh
# Rank phase/verify Issues by unchecked Post-merge acceptance conditions that
# carry a verify command (auto-checkable), so a batch /verify run can be
# targeted at the highest-confidence candidates first (see
# docs/spec/issue-1349-rank-verify-backlog-batch.md).
#
# Usage:
#   scripts/rank-verify-backlog.sh [--top N] [--limit L]
#
# --top N: number of ranked Issue numbers to output (default 10)
# --limit L: `gh issue list` page size (default 500, same convention as
#   scan-pending-ac.sh — when the returned count equals --limit, a stderr
#   warning is printed since some phase/verify Issues may not have been
#   scanned)
#
# Population: `gh issue list --label "phase/verify" --state all --json
# number,body --limit L` (--state all, matching scan-pending-ac.sh's
# convention — a phase/verify Issue may already be CLOSED via a concurrent
# /verify run). gh failure fails open (empty stdout, exit 0).
#
# Post-merge section range: from the line after a heading matching
# `^### Post-merge` or `^## Post-merge` up to (but excluding) the next line
# matching `^## ` or `^### ` (same range convention as scan-pending-ac.sh).
#
# Code fence exclusion: a line matching `^[ \t]*```` toggles an in_fence flag,
# independent of section tracking. While in_fence is true, no line is judged
# as a checkbox line (in or out of the Post-merge section) — this excludes
# sample/example checkbox text embedded in a fenced code block from both
# auto_count and manual_count (regression guard for the false-positive
# pattern hit in #709).
#
# Scoring: within the Post-merge section and outside any fence, each
# unchecked `^- \[ \]` line is classified by whether it contains
# `<!--[ \t]*verify:` (a verify command HTML comment, matched anywhere in the
# line — this also catches the Option B co-tagged form
# `<!-- verify-type: observation --> <!-- verify: rubric "..." -->`, since the
# match targets the second, independent comment marker):
#   - match -> auto_count += 1
#   - no match -> manual_count += 1
#
# Ranking: per-Issue auto_count descending; ties broken by Issue number
# ascending. Truncated to the top --top entries.
#
# Output: stdout carries only the ranked Issue numbers, one per line (same
# stdout contract as observation-trigger.sh — no other output mixed in).
# stderr carries one score line per scanned Issue: "#<N>: auto=<auto_count>
# manual=<manual_count>".
#
# Fails open: any `gh` failure prints nothing to stdout and exits 0. Only
# invalid CLI arguments exit non-zero.
#
# bash 3.2+ compatible (macOS system bash): no mapfile, no ${VAR,,}.

set -euo pipefail

TOP=10
LIMIT=500

while [ $# -gt 0 ]; do
  case "$1" in
    --top)
      if [ $# -lt 2 ]; then
        echo "Error: --top requires an argument" >&2
        exit 1
      fi
      TOP="$2"
      shift 2
      ;;
    --limit)
      if [ $# -lt 2 ]; then
        echo "Error: --limit requires an argument" >&2
        exit 1
      fi
      LIMIT="$2"
      shift 2
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if ! echo "$TOP" | grep -qE '^[0-9]+$' || [ "$TOP" -eq 0 ]; then
  echo "Error: --top must be a positive integer: $TOP" >&2
  exit 1
fi
if ! echo "$LIMIT" | grep -qE '^[0-9]+$' || [ "$LIMIT" -eq 0 ]; then
  echo "Error: --limit must be a positive integer: $LIMIT" >&2
  exit 1
fi

ISSUES_JSON=$(gh issue list --label "phase/verify" --state all --json number,body --limit "$LIMIT" 2>/dev/null) || {
  exit 0
}

if [ -z "$ISSUES_JSON" ]; then
  exit 0
fi

ISSUE_COUNT=$(printf '%s' "$ISSUES_JSON" | jq 'length' 2>/dev/null || echo 0)
if [ "$ISSUE_COUNT" -eq 0 ]; then
  exit 0
fi
if [ "$ISSUE_COUNT" -eq "$LIMIT" ]; then
  echo "Warning: issue list hit the --limit ${LIMIT} cap; some phase/verify Issues were not scanned." >&2
fi

AWK_PROGRAM='
  BEGIN { in_section = 0; in_fence = 0; auto_count = 0; manual_count = 0 }
  /^[ \t]*```/ { in_fence = !in_fence; next }
  in_fence { next }
  /^### Post-merge/ || /^## Post-merge/ { in_section = 1; next }
  /^## / || /^### / { in_section = 0; next }
  in_section && /^- \[ \]/ {
    if ($0 ~ /<!--[ \t]*verify:/) { auto_count++ } else { manual_count++ }
    next
  }
  { next }
  END { print auto_count "\t" manual_count }
'

SCORES=""

while IFS= read -r issue_obj; do
  [ -z "$issue_obj" ] && continue
  N=$(printf '%s' "$issue_obj" | jq -r '.number')
  BODY=$(printf '%s' "$issue_obj" | jq -r '.body')

  COUNTS=$(printf '%s\n' "$BODY" | awk "$AWK_PROGRAM")
  AUTO_C=$(printf '%s' "$COUNTS" | cut -f1)
  MANUAL_C=$(printf '%s' "$COUNTS" | cut -f2)

  echo "#${N}: auto=${AUTO_C} manual=${MANUAL_C}" >&2

  SCORES="${SCORES}${N}"$'\t'"${AUTO_C}"$'\n'
done < <(printf '%s' "$ISSUES_JSON" | jq -c '.[]')

if [ -z "$SCORES" ]; then
  exit 0
fi

printf '%s' "$SCORES" | sort -t $'\t' -k2,2nr -k1,1n | head -n "$TOP" | cut -f1
