#!/usr/bin/env bash
# scan-pending-ac.sh
# Enumerate unchecked post-merge acceptance conditions across closed
# phase/verify Issues, optionally pre-filtered by run-fact tokens
# (see modules/run-fact-matching.md).
#
# Usage:
#   scripts/scan-pending-ac.sh [--facts <path>] [--limit <N>] [--max-candidates <N>]
#
# --facts <path>: path to a collect-run-facts.sh JSON output
#   ({"session_id":...,"issues":[{...,"fact_tokens":[...]},...]}). When given,
#   only candidate AC whose condition text contains (case-insensitive substring)
#   at least one fact token (unioned across all issues in the facts file) are
#   kept. Omit to return all candidates unfiltered (backward-compatible/debug use).
# --limit <N>: `gh issue list` page size (default 400). When the returned count
#   equals --limit, a stderr warning is printed (some Issues may not have been
#   scanned).
# --max-candidates <N>: truncate the candidate list to this size (default 30).
#   Truncation is never silent: a stderr Note reports how many were dropped.
#
# --facts exclusion rules (only active when --facts is given; see
# modules/run-fact-matching.md "Candidate Pre-filter Exclusion Rules" for the
# rationale and regression-risk evaluation):
#   Rule 1: a candidate whose verify_type is "observation" or "opportunistic"
#     is excluded when its Issue number is not present in the facts file's
#     `issues[].number` array — per-issue facts (route/phases/anomalies/...)
#     cannot exist for an Issue the current run never touched, so such a
#     candidate is structurally undecidable (always "ambiguous").
#   Rule 2: a candidate whose condition text contains an L3/session
#     retrospective reference keyword (case-insensitive; see
#     L3_KEYWORDS_LOWER below) is excluded — the facts JSON has no field
#     representing L3 retrospective content, and reconciliation runs before
#     L3 retrospective generation in skills/auto/SKILL.md, so this class of
#     candidate is also structurally undecidable.
#
# Global 1-based checkbox index: counted over every `^- \[[ xX]\]` line in the
# full Issue body (same convention as scripts/gh-issue-edit.sh --checkbox and
# scripts/check-pre-merge-ac.sh), so returned ac_index values are directly
# usable with gh-issue-edit.sh --checkbox. Fenced code block lines are
# excluded from this count — see modules/l0-surfaces.md § AC Enumeration
# Convention (SSoT for this exclusion rule).
#
# Post-merge section range: from the line after a heading matching
# `^### Post-merge` or `^## Post-merge` up to (but excluding) the next line
# matching `^## ` or `^### ` (same range convention as check-pre-merge-ac.sh's
# Pre-merge section, mirrored for Post-merge).
#
# verify_type: parsed from a `verify-type: <t>` HTML-comment attribute on the
# line. The tag is read only from inside an HTML comment (`<!-- verify-type:
# <t> -->`), never from condition prose — a condition that quotes a tag name
# in its own text (Issue #1273) must not be mistaken for the real tag.
# A line with no verify-type tag is classified "manual" (matches
# skills/verify/SKILL.md Step 8b's existing convention: a condition with
# neither a verify command nor a verify-type tag is treated as manual).
# manual / observation / opportunistic / auto are all included as candidates —
# none are excluded (this is how AC2's "manual AC must be in-scope" is satisfied).
#
# Output: JSON array [{"number":N,"ac_index":I,"verify_type":"manual","condition":"..."}]
#   on stdout, or [] when there are no candidates.
#
# Fails open: any `gh` failure prints [] and exits 0 (never blocks /auto).
# Only invalid CLI arguments exit non-zero.
#
# bash 3.2+ compatible (macOS system bash): no mapfile, no ${VAR,,}.

set -euo pipefail

FACTS_PATH=""
LIMIT=400
MAX_CANDIDATES=30

while [ $# -gt 0 ]; do
  case "$1" in
    --facts)
      if [ $# -lt 2 ]; then
        echo "Error: --facts requires an argument" >&2
        exit 1
      fi
      FACTS_PATH="$2"
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
    --max-candidates)
      if [ $# -lt 2 ]; then
        echo "Error: --max-candidates requires an argument" >&2
        exit 1
      fi
      MAX_CANDIDATES="$2"
      shift 2
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if ! echo "$LIMIT" | grep -qE '^[0-9]+$'; then
  echo "Error: --limit must be a positive integer: $LIMIT" >&2
  exit 1
fi
if ! echo "$MAX_CANDIDATES" | grep -qE '^[0-9]+$'; then
  echo "Error: --max-candidates must be a positive integer: $MAX_CANDIDATES" >&2
  exit 1
fi

FACT_TOKENS_LOWER=""
FACTS_ISSUE_NUMBERS=""
if [ -n "$FACTS_PATH" ]; then
  if [ ! -f "$FACTS_PATH" ]; then
    echo "Error: --facts file not found: $FACTS_PATH" >&2
    exit 1
  fi
  FACT_TOKENS_LOWER=$(jq -r '[.issues[].fact_tokens[]?] | unique | .[]' "$FACTS_PATH" 2>/dev/null | tr '[:upper:]' '[:lower:]') || {
    echo "Error: failed to parse --facts file: $FACTS_PATH" >&2
    exit 1
  }
  FACTS_ISSUE_NUMBERS=$(jq -r '[.issues[].number] | unique | .[]' "$FACTS_PATH" 2>/dev/null) || {
    echo "Error: failed to parse --facts file: $FACTS_PATH" >&2
    exit 1
  }
  if [ -z "$FACT_TOKENS_LOWER" ]; then
    echo "Warning: --facts contains no fact tokens; no candidates can match." >&2
    echo "[]"
    exit 0
  fi
fi

# Rule 2 keyword list (case-insensitive substring match against condition text).
L3_KEYWORDS_LOWER=$(printf '%s\n' \
  "l3 retrospective" \
  "l3 レトロスペクティブ" \
  "l3 セッションレトロスペクティブ" \
  "session.md" \
  "セッションレトロスペクティブ" \
  "session retrospective" \
  | tr '[:upper:]' '[:lower:]')

ISSUES_JSON=$(gh issue list --label "phase/verify" --state all --json number,body --limit "$LIMIT" 2>/dev/null) || {
  echo "[]"
  exit 0
}

if [ -z "$ISSUES_JSON" ]; then
  echo "[]"
  exit 0
fi

ISSUE_COUNT=$(printf '%s' "$ISSUES_JSON" | jq 'length' 2>/dev/null || echo 0)
if [ "$ISSUE_COUNT" -eq 0 ]; then
  echo "[]"
  exit 0
fi
if [ "$ISSUE_COUNT" -eq "$LIMIT" ]; then
  echo "Warning: issue list hit the --limit ${LIMIT} cap; some phase/verify Issues were not scanned." >&2
fi

AWK_PROGRAM='
  BEGIN { idx = 0; in_section = 0; in_fence = 0 }
  /^[ \t]*```/ { in_fence = !in_fence; next }
  in_fence { next }
  /^### Post-merge/ || /^## Post-merge/ { in_section = 1; next }
  /^## / || /^### / {
    in_section = 0
    next
  }
  /^- \[[ xX]\]/ {
    idx++
    if (in_section) {
      checked = (substr($0, 4, 1) == " ") ? 0 : 1
      if (!checked) {
        line = $0
        vtype = "manual"
        if (match(line, /<!--[ \t]*verify-type:[ \t]*[a-zA-Z_]+/)) {
          tag = substr(line, RSTART, RLENGTH)
          sub(/^<!--[ \t]*verify-type:[ \t]*/, "", tag)
          vtype = tag
        }
        text = line
        sub(/^- \[ \][ \t]*/, "", text)
        gsub(/<!--([^-]|-[^-]|--[^>])*-->/, "", text)
        gsub(/^[ \t]+/, "", text)
        gsub(/[ \t\r]+$/, "", text)
        print idx "\t" vtype "\t" text
      }
    }
    next
  }
  { next }
'

CANDIDATES="[]"
CANDIDATE_COUNT=0
TRUNCATED_COUNT=0

while IFS= read -r issue_obj; do
  [ -z "$issue_obj" ] && continue
  N=$(printf '%s' "$issue_obj" | jq -r '.number')
  BODY=$(printf '%s' "$issue_obj" | jq -r '.body')

  RECORDS=$(printf '%s\n' "$BODY" | awk "$AWK_PROGRAM")
  [ -z "$RECORDS" ] && continue

  while IFS=$'\t' read -r ac_idx vtype cond_text; do
    [ -z "$ac_idx" ] && continue

    TEXT_LOWER=$(printf '%s' "$cond_text" | tr '[:upper:]' '[:lower:]')

    if [ -n "$FACT_TOKENS_LOWER" ]; then
      MATCHED=false
      while IFS= read -r tok; do
        [ -z "$tok" ] && continue
        case "$TEXT_LOWER" in
          *"$tok"*)
            MATCHED=true
            break
            ;;
        esac
      done <<< "$FACT_TOKENS_LOWER"
      if [ "$MATCHED" = false ]; then
        continue
      fi
    fi

    if [ -n "$FACTS_PATH" ]; then
      # Rule 1: observation/opportunistic candidates whose Issue is absent
      # from this run's facts.issues[].number are structurally undecidable.
      if [ "$vtype" = "observation" ] || [ "$vtype" = "opportunistic" ]; then
        ISSUE_IN_FACTS=false
        while IFS= read -r facts_n; do
          [ -z "$facts_n" ] && continue
          if [ "$facts_n" = "$N" ]; then
            ISSUE_IN_FACTS=true
            break
          fi
        done <<< "$FACTS_ISSUE_NUMBERS"
        if [ "$ISSUE_IN_FACTS" = false ]; then
          continue
        fi
      fi

      # Rule 2: candidates referencing L3/session retrospective content are
      # structurally undecidable (no facts JSON field represents them, and
      # reconciliation runs before L3 retrospective generation).
      L3_MATCHED=false
      while IFS= read -r kw; do
        [ -z "$kw" ] && continue
        case "$TEXT_LOWER" in
          *"$kw"*)
            L3_MATCHED=true
            break
            ;;
        esac
      done <<< "$L3_KEYWORDS_LOWER"
      if [ "$L3_MATCHED" = true ]; then
        continue
      fi
    fi

    if [ "$CANDIDATE_COUNT" -ge "$MAX_CANDIDATES" ]; then
      TRUNCATED_COUNT=$((TRUNCATED_COUNT + 1))
      continue
    fi

    CANDIDATES=$(printf '%s' "$CANDIDATES" | jq -c \
      --argjson n "$N" \
      --argjson idx "$ac_idx" \
      --arg vt "$vtype" \
      --arg cond "$cond_text" \
      '. += [{"number": $n, "ac_index": $idx, "verify_type": $vt, "condition": $cond}]') || {
      echo "Error: failed to append candidate for issue #${N} AC #${ac_idx}" >&2
      exit 1
    }
    CANDIDATE_COUNT=$((CANDIDATE_COUNT + 1))
  done <<< "$RECORDS"
done < <(printf '%s' "$ISSUES_JSON" | jq -c '.[]')

if [ "$TRUNCATED_COUNT" -gt 0 ]; then
  echo "Note: truncated ${TRUNCATED_COUNT} candidate AC(s) to ${MAX_CANDIDATES}; deferred to the next run." >&2
fi

printf '%s\n' "$CANDIDATES"
