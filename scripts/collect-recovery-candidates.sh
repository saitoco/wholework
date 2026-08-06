#!/usr/bin/env bash
# Parse orchestration-recoveries.md and output frequency-filtered candidate list.
# Output format: <group-key>\t<count> (tab-separated, one per line).
# Only entries whose group-key clears --threshold K after entry-unit exclusion are included.
#
# group-key (Issue #1123): normally the H2 header's symptom-short (e.g.
# "manual-recovery-review-rerun"). When an entry's "### Diagnosis" body has a
# "- cause: <slug>" line (written by run-auto-sub.sh --write-manual-recovery --cause),
# the group key becomes "<symptom-short>/<cause-slug>" instead, so that same-symptom
# events with a different root cause are counted (and duplicate-checked) separately
# rather than merged. Entries without a cause line keep the plain symptom-short key
# (backward compatible with the existing 4 recoveries-log entries).
#
# Exclusion (Issue #1152): judged per entry, not per group-key, so a resolved symptom
# and a genuine post-fix recurrence of the same group-key can be told apart.
#   1. Resolve the group-key's corresponding Issue:
#      - Prefer the "起票済み #N" marker on any entry in the group (latest occurrence wins).
#      - Otherwise, look up --issues-json for a title exactly equal to "recoveries: <group-key>".
#   2. If the resolved Issue's state (from --issues-json) is OPEN: exclude every entry in
#      the group (the symptom is still being worked, so nothing new can be inferred yet).
#   3. If CLOSED with a closedAt timestamp: exclude entries at or before closedAt; count
#      entries strictly after closedAt (a real recurrence after the fix).
#   4. Degrade path -- no resolvable Issue, or --issues-json lacks state/closedAt for the
#      resolved Issue, or --issues-json was not passed at all: fall back to the group's own
#      latest "起票済み #N" entry timestamp as the cutoff (same before/after rule as step 3).
#      If the group has no "起票済み" entry either, there is no basis to exclude anything --
#      every entry in the group is counted.
# This keeps the default output format unchanged; pass --with-tracking to append a 3rd
# column (tracked:#N / untracked) for consumers that need to distinguish the two.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$SCRIPT_DIR}"

THRESHOLD=3
ISSUES_JSON=""
RECOVERY_FILE=""
WITH_TRACKING=0

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold)
      THRESHOLD="$2"
      shift 2
      ;;
    --threshold=*)
      THRESHOLD="${1#--threshold=}"
      shift
      ;;
    --issues-json)
      ISSUES_JSON="$2"
      shift 2
      ;;
    --issues-json=*)
      ISSUES_JSON="${1#--issues-json=}"
      shift
      ;;
    --with-tracking)
      WITH_TRACKING=1
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$RECOVERY_FILE" ]; then
        RECOVERY_FILE="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$RECOVERY_FILE" ]; then
  echo "Usage: $0 <recovery-file> [--threshold K] [--issues-json PATH] [--with-tracking]" >&2
  exit 1
fi

if [ ! -f "$RECOVERY_FILE" ]; then
  echo "File not found: $RECOVERY_FILE" >&2
  exit 1
fi

# Load issues for group-key resolution: number, title, state, closedAt (any of the latter
# two may be empty -- callers on an older contract may pass title-only records).
ISS_NUM=()
ISS_TITLE=()
ISS_STATE=()
ISS_CLOSEDAT=()
if [ -n "$ISSUES_JSON" ] && [ -f "$ISSUES_JSON" ]; then
  # Use \x1f (unit separator) rather than \t as the record delimiter -- an Issue title
  # could in principle contain a literal tab, which would shift these fields and corrupt
  # state/closedAt resolution for that Issue (Issue #1198 review finding).
  while IFS=$'\x1f' read -r iss_num iss_title iss_state iss_closedat; do
    [ -z "$iss_num" ] && continue
    ISS_NUM+=("$iss_num")
    ISS_TITLE+=("$iss_title")
    ISS_STATE+=("$iss_state")
    ISS_CLOSEDAT+=("$iss_closedat")
  done < <(python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
for item in data:
    number = item.get('number', '')
    title = item.get('title', '')
    state = item.get('state', '') or ''
    closed_at = item.get('closedAt') or ''
    print(f'{number}\x1f{title}\x1f{state}\x1f{closed_at}')
" "$ISSUES_JSON" 2>/dev/null || true)
fi

_lookup_issue_by_number() {
  LOOKUP_FOUND=0
  LOOKUP_STATE=""
  LOOKUP_CLOSEDAT=""
  local target="$1" i
  for ((i = 0; i < ${#ISS_NUM[@]}; i++)); do
    if [ "${ISS_NUM[$i]}" = "$target" ]; then
      LOOKUP_FOUND=1
      LOOKUP_STATE="${ISS_STATE[$i]}"
      LOOKUP_CLOSEDAT="${ISS_CLOSEDAT[$i]}"
      return 0
    fi
  done
}

_lookup_issue_by_title() {
  LOOKUP_FOUND=0
  LOOKUP_NUMBER=""
  LOOKUP_STATE=""
  LOOKUP_CLOSEDAT=""
  local target="$1" i
  for ((i = 0; i < ${#ISS_TITLE[@]}; i++)); do
    if [ "${ISS_TITLE[$i]}" = "$target" ]; then
      LOOKUP_FOUND=1
      LOOKUP_NUMBER="${ISS_NUM[$i]}"
      LOOKUP_STATE="${ISS_STATE[$i]}"
      LOOKUP_CLOSEDAT="${ISS_CLOSEDAT[$i]}"
      return 0
    fi
  done
}

# Parse the recovery file into parallel per-entry arrays (bash 3.2+ compatible: indexed
# arrays only, no associative arrays):
# - ENTRY_TS: entry timestamp, normalized to "YYYY-MM-DDTHH:MM" (same width as closedAt
#   truncated to 16 chars, so lexicographic string comparison matches chronological order)
# - ENTRY_KEY: group-key (symptom-short, or symptom-short/cause-slug)
# - ENTRY_FILED: "起票済み #N" issue number for this entry, or "" if absent

ENTRY_TS=()
ENTRY_KEY=()
ENTRY_FILED=()

CURRENT_SYMPTOM=""
CURRENT_CAUSE=""
CURRENT_FILED=""
CURRENT_TS=""
HAS_PENDING_ENTRY=0

_flush_entry() {
  [ "$HAS_PENDING_ENTRY" -eq 1 ] || return 0
  local key="$CURRENT_SYMPTOM"
  if [ -n "$CURRENT_CAUSE" ]; then
    key="${CURRENT_SYMPTOM}/${CURRENT_CAUSE}"
  fi
  ENTRY_TS+=("$CURRENT_TS")
  ENTRY_KEY+=("$key")
  ENTRY_FILED+=("$CURRENT_FILED")
}

while IFS= read -r line; do
  # Detect entry header: "## YYYY-MM-DD HH:MM UTC: <symptom-short>"
  if echo "$line" | grep -qE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2} UTC: .+'; then
    _flush_entry
    # Extract symptom-short (everything after "UTC: ")
    CURRENT_SYMPTOM="${line#*UTC: }"
    CURRENT_SYMPTOM="$(echo "$CURRENT_SYMPTOM" | sed 's/ ([^)]*) *$//')"
    CURRENT_TS="$(echo "$line" | sed -E 's/^## ([0-9]{4}-[0-9]{2}-[0-9]{2}) ([0-9]{2}:[0-9]{2}) UTC:.*/\1T\2/')"
    CURRENT_CAUSE=""
    CURRENT_FILED=""
    HAS_PENDING_ENTRY=1
    continue
  fi
  if [ "$HAS_PENDING_ENTRY" -eq 1 ]; then
    # Detect "Improvement Candidate" line with 起票済み
    if echo "$line" | grep -qE '^\- 起票済み #[0-9]+'; then
      CURRENT_FILED="$(echo "$line" | sed -E 's/^- 起票済み #([0-9]+).*/\1/')"
    fi
    # Detect "### Diagnosis" body's "- cause: <slug>" line (Issue #1123)
    if echo "$line" | grep -qE '^- cause: .+'; then
      CURRENT_CAUSE="${line#- cause: }"
    fi
  fi
done < "$RECOVERY_FILE"
_flush_entry

# Collect unique group-keys, first-seen order.
# Note: iterate by index (${#ARR[@]}), not "for x in "${ARR[@]}"" -- under `set -u`,
# bash 3.2 (macOS system bash) raises "unbound variable" when expanding an empty array
# with "${ARR[@]}", while ${#ARR[@]} on an empty array safely evaluates to 0.
UNIQUE_KEYS=()
for ((ei = 0; ei < ${#ENTRY_KEY[@]}; ei++)); do
  key="${ENTRY_KEY[$ei]}"
  is_known=0
  for ((ui = 0; ui < ${#UNIQUE_KEYS[@]}; ui++)); do
    if [ "${UNIQUE_KEYS[$ui]}" = "$key" ]; then
      is_known=1
      break
    fi
  done
  if [ "$is_known" -eq 0 ]; then
    UNIQUE_KEYS+=("$key")
  fi
done

for ((ki = 0; ki < ${#UNIQUE_KEYS[@]}; ki++)); do
  key="${UNIQUE_KEYS[$ki]}"
  resolved_number=""
  latest_filed_ts=""
  # Entries are appended in file order (chronological), so the last filed marker seen
  # while scanning is both the authoritative resolution and the latest filed timestamp.
  for ((i = 0; i < ${#ENTRY_KEY[@]}; i++)); do
    if [ "${ENTRY_KEY[$i]}" = "$key" ] && [ -n "${ENTRY_FILED[$i]}" ]; then
      resolved_number="${ENTRY_FILED[$i]}"
      latest_filed_ts="${ENTRY_TS[$i]}"
    fi
  done

  resolved_state=""
  resolved_closedat=""
  if [ -n "$resolved_number" ]; then
    _lookup_issue_by_number "$resolved_number"
    if [ "$LOOKUP_FOUND" -eq 1 ]; then
      resolved_state="$LOOKUP_STATE"
      resolved_closedat="$LOOKUP_CLOSEDAT"
    fi
  else
    _lookup_issue_by_title "recoveries: $key"
    if [ "$LOOKUP_FOUND" -eq 1 ]; then
      resolved_number="$LOOKUP_NUMBER"
      resolved_state="$LOOKUP_STATE"
      resolved_closedat="$LOOKUP_CLOSEDAT"
    fi
  fi

  mode="count_all"
  cutoff=""
  if [ "$resolved_state" = "OPEN" ]; then
    mode="exclude_all"
  elif [ "$resolved_state" = "CLOSED" ] && [ -n "$resolved_closedat" ]; then
    mode="cutoff"
    cutoff="${resolved_closedat:0:16}"
  fi

  # Degrade path: no usable state/closedAt from --issues-json -- fall back to this
  # group's own latest 起票済み entry timestamp, if any.
  if [ "$mode" = "count_all" ] && [ -n "$latest_filed_ts" ]; then
    mode="cutoff"
    cutoff="$latest_filed_ts"
  fi

  count=0
  case "$mode" in
    exclude_all)
      count=0
      ;;
    cutoff)
      for ((i = 0; i < ${#ENTRY_KEY[@]}; i++)); do
        if [ "${ENTRY_KEY[$i]}" = "$key" ] && [[ "${ENTRY_TS[$i]}" > "$cutoff" ]]; then
          count=$((count + 1))
        fi
      done
      ;;
    count_all)
      for ((i = 0; i < ${#ENTRY_KEY[@]}; i++)); do
        [ "${ENTRY_KEY[$i]}" = "$key" ] && count=$((count + 1))
      done
      ;;
  esac

  if [ "$count" -ge "$THRESHOLD" ]; then
    if [ "$WITH_TRACKING" -eq 1 ]; then
      if [ -n "$resolved_number" ]; then
        printf '%s\t%d\ttracked:#%s\n' "$key" "$count" "$resolved_number"
      else
        printf '%s\t%d\tuntracked\n' "$key" "$count"
      fi
    else
      printf '%s\t%d\n' "$key" "$count"
    fi
  fi
done
