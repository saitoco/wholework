#!/bin/bash
# get-auto-session-report.sh - Generate a Metrics section for a /auto session, for embedding into session.md.
# Reads .tmp/auto-events.jsonl filtered by session_id and renders a markdown section to stdout.
#
# Usage:
#   get-auto-session-report.sh <session-id> --metrics-only [--no-github]
#   get-auto-session-report.sh [--since <spec>]   # list mode: show distinct session_ids
#
# Options:
#   <session-id>              Emit the Metrics section for the specified session
#   --metrics-only            Emit the `## Metrics` markdown section to stdout (report mode selector)
#   --no-github               Skip gh issue/pr calls (for hermetic bats tests)
#   --since <spec>            List mode: filter sessions by time (e.g. 24h, 2026-06-14)
#
# Environment:
#   AUTO_EVENTS_LOG  Path to event log (default: .tmp/auto-events.jsonl)
#
# bash 3.2+ compatible

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
[[ -f "$SCRIPT_DIR/emit-event.sh" ]] && source "$SCRIPT_DIR/emit-event.sh" || true
[[ -f "$SCRIPT_DIR/watchdog-defaults.sh" ]] && source "$SCRIPT_DIR/watchdog-defaults.sh" || true
SILENT_MARGIN=600
SILENT_THRESHOLD_SPEC=$(( ${WATCHDOG_TIMEOUT_SPEC_DEFAULT:-1800} - SILENT_MARGIN ))
SILENT_THRESHOLD_CODE=$(( ${WATCHDOG_TIMEOUT_CODE_DEFAULT:-1800} - SILENT_MARGIN ))
SILENT_THRESHOLD_REVIEW=$(( ${WATCHDOG_TIMEOUT_REVIEW_DEFAULT:-2000} - SILENT_MARGIN ))
SILENT_THRESHOLD_ISSUE=$(( ${WATCHDOG_TIMEOUT_ISSUE_DEFAULT:-1200} - SILENT_MARGIN ))
AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"

SESSION_ID=""
METRICS_ONLY=false
NO_GITHUB=false
ISSUE_BODY_DIR="${WHOLEWORK_ISSUE_BODY_DIR:-}"
LIST_MODE=false
SINCE_SPEC="24h"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --metrics-only)
      METRICS_ONLY=true
      shift
      ;;
    --no-github)
      NO_GITHUB=true
      shift
      ;;
    --since)
      if [[ $# -gt 1 && "${2:-}" != -* ]]; then
        SINCE_SPEC="$2"
        shift 2
      else
        SINCE_SPEC="24h"
        shift
      fi
      LIST_MODE=true
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      echo "Usage: get-auto-session-report.sh <session-id> --metrics-only [--no-github]" >&2
      exit 1
      ;;
    *)
      SESSION_ID="$1"
      shift
      ;;
  esac
done

# Read recoveries-auto-fire.threshold from .wholework.yml (awk for nested YAML; get-config-value.sh lacks nested key support)
_config_path="${WHOLEWORK_CONFIG_PATH:-.wholework.yml}"
RECOVERIES_THRESHOLD=3
if [[ -f "$_config_path" ]]; then
  _raw=$(awk '
    /^recoveries-auto-fire:/ { in_section=1; next }
    /^[^ ]/ { in_section=0 }
    /^recoveries-auto-fire\.threshold:/ { gsub(/.*threshold:[[:space:]]*/, ""); print; exit }
    in_section && /threshold:/ { gsub(/.*threshold:[[:space:]]*/, ""); print; exit }
  ' "$_config_path" 2>/dev/null || true)
  if [[ "$_raw" =~ ^[0-9]+$ ]] && [[ "$_raw" -gt 0 ]]; then
    RECOVERIES_THRESHOLD="$_raw"
  fi
fi
RECOVERIES_APPROACH=$(( RECOVERIES_THRESHOLD - 1 ))

# List mode: show distinct session_ids from event log
if [[ "$LIST_MODE" == "true" ]] || [[ -z "$SESSION_ID" ]]; then
  if [[ ! -f "$AUTO_EVENTS_LOG" ]]; then
    echo "No event log found at: $AUTO_EVENTS_LOG"
    echo "Run /auto to generate events."
    exit 0
  fi
  echo "Sessions found in $AUTO_EVENTS_LOG (--since $SINCE_SPEC):"
  # Compute cutoff timestamp for --since filter
  CUTOFF_TS=""
  case "$SINCE_SPEC" in
    *h)
      HOURS="${SINCE_SPEC%h}"
      if CUTOFF_EPOCH=$(date -j -v-"${HOURS}H" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || \
         CUTOFF_EPOCH=$(date -u -d "$HOURS hours ago" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null); then
        CUTOFF_TS="$CUTOFF_EPOCH"
      fi
      ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      CUTOFF_TS="${SINCE_SPEC}T00:00:00Z"
      ;;
    *)
      CUTOFF_TS=""
      ;;
  esac
  # Extract distinct session_ids with their first timestamp, filtered by cutoff
  if [[ -n "$CUTOFF_TS" ]]; then
    jq -r --arg cutoff "$CUTOFF_TS" \
      'select(.session_id != null and .session_id != "" and .ts >= $cutoff) | [.session_id, .ts] | @tsv' \
      "$AUTO_EVENTS_LOG" 2>/dev/null | \
      sort | awk -F'\t' '!seen[$1]++ { print $1 " (first event: " $2 ")" }' || \
      echo "(no session_id fields found — run /auto after this update to populate)"
  else
    jq -r 'select(.session_id != null and .session_id != "") | [.session_id, .ts] | @tsv' \
      "$AUTO_EVENTS_LOG" 2>/dev/null | \
      sort | awk -F'\t' '!seen[$1]++ { print $1 " (first event: " $2 ")" }' || \
      echo "(no session_id fields found — run /auto after this update to populate)"
  fi
  exit 0
fi

# Report mode: emit the Metrics section for the specified session
# Extract events for this session (graceful degrade if file missing or empty)
if [[ ! -f "$AUTO_EVENTS_LOG" ]]; then
  EVENTS_JSON="[]"
else
  EVENTS_JSON=$(jq -s --arg sid "$SESSION_ID" \
    '[.[] | select(.session_id == $sid)]' \
    "$AUTO_EVENTS_LOG" 2>/dev/null || echo "[]")
fi

EVENT_COUNT=$(echo "$EVENTS_JSON" | jq 'length' 2>/dev/null || echo 0)

# Compute session metrics using jq
SESSION_START=$(echo "$EVENTS_JSON" | jq -r 'if length == 0 then "N/A" else sort_by(.ts) | first | .ts end' 2>/dev/null || echo "N/A")
SESSION_END=$(echo "$EVENTS_JSON" | jq -r 'if length == 0 then "N/A" else sort_by(.ts) | last | .ts end' 2>/dev/null || echo "N/A")

# Wall-clock in hh:mm:ss (from first to last event ts)
WALL_CLOCK="N/A"
if [[ "$SESSION_START" != "N/A" && "$SESSION_END" != "N/A" ]]; then
  # Convert ISO8601 to epoch using date (bash 3.2+ portable)
  if START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$SESSION_START" "+%s" 2>/dev/null) || \
     START_EPOCH=$(date -d "$SESSION_START" "+%s" 2>/dev/null); then
    if END_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$SESSION_END" "+%s" 2>/dev/null) || \
       END_EPOCH=$(date -d "$SESSION_END" "+%s" 2>/dev/null); then
      WALL_SEC=$(( END_EPOCH - START_EPOCH ))
      WALL_HH=$(( WALL_SEC / 3600 ))
      WALL_MM=$(( (WALL_SEC % 3600) / 60 ))
      WALL_SS=$(( WALL_SEC % 60 ))
      WALL_CLOCK=$(printf "%02d:%02d:%02d" "$WALL_HH" "$WALL_MM" "$WALL_SS")
    fi
  fi
fi

# Route mix: count patch (XS/S) vs pr (M/L) from sub_start events
ROUTE_MIX=$(echo "$EVENTS_JSON" | jq -r '
  [.[] | select(.event == "sub_start")] |
  {
    patch: ([.[] | select(.size == "XS" or .size == "S")] | length),
    pr:    ([.[] | select(.size == "M" or .size == "L")] | length),
    xl:    ([.[] | select(.size == "XL")] | length)
  } |
  "patch: \(.patch), pr: \(.pr), xl: \(.xl)"
' 2>/dev/null || echo "N/A")

# Issues processed (distinct issue numbers)
ISSUES_PROCESSED=$(echo "$EVENTS_JSON" | jq '
  [.[] | select(.issue != null and .issue > 0) | .issue] | unique | length
' 2>/dev/null || echo 0)

# Recovery events by tier
RECOVERY_COUNTS=$(echo "$EVENTS_JSON" | jq -r '
  [.[] | select(.event == "recovery")] |
  {
    t1: ([.[] | select(.tier == "1")] | length),
    t2: ([.[] | select(.tier == "2")] | length),
    t3: ([.[] | select(.tier == "3")] | length)
  } |
  "\(.t1) / \(.t2) / \(.t3)"
' 2>/dev/null || echo "0 / 0 / 0")

# Watchdog kills (R1 metric; degrade to 0 if not present)
WATCHDOG_KILLS=$(echo "$EVENTS_JSON" | jq '[.[] | select(.event == "watchdog_kill")] | length' 2>/dev/null || echo 0)

# Max silent window (R1 metric; N/A if not present)
MAX_SILENT=$(echo "$EVENTS_JSON" | jq -r '
  [.[] | select(.event == "max_silent_window") | .max_sec | tonumber] |
  if length == 0 then "N/A" else max | tostring + "s" end
' 2>/dev/null || echo "N/A")

# Phase silent window breakdown (merge excluded: WATCHDOG_TIMEOUT_MERGE_DEFAULT - SILENT_MARGIN = 0)
PHASE_SILENT_BREAKDOWN=$(echo "$EVENTS_JSON" | jq -r \
  --argjson t_spec "$SILENT_THRESHOLD_SPEC" \
  --argjson t_code "$SILENT_THRESHOLD_CODE" \
  --argjson t_review "$SILENT_THRESHOLD_REVIEW" \
  --argjson t_issue "$SILENT_THRESHOLD_ISSUE" \
  '
  [.[] |
    select(.event == "max_silent_window" and .phase != null and .phase != "merge") |
    (if .phase == "spec" then $t_spec
     elif .phase == "code" then $t_code
     elif .phase == "review" then $t_review
     elif .phase == "issue" then $t_issue
     else -1 end) as $at_risk_limit |
    select($at_risk_limit > 0 and ((.max_sec | tonumber) > $at_risk_limit)) |
    .phase
  ] |
  if length == 0 then "0"
  else
    (length) as $total |
    (group_by(.) | map(.[0] + ":" + (length | tostring))) as $parts |
    "\($total) (" + ($parts | join(", ")) + ")"
  end
' 2>/dev/null || echo "0")

# Token usage totals (R1 metric; N/A if not present)
TOKEN_INPUT=$(echo "$EVENTS_JSON" | jq '
  [.[] | select(.event == "token_usage") | .input_tokens | tonumber] |
  if length == 0 then null else add end // null
' 2>/dev/null || echo "null")
TOKEN_OUTPUT=$(echo "$EVENTS_JSON" | jq '
  [.[] | select(.event == "token_usage") | .output_tokens | tonumber] |
  if length == 0 then null else add end // null
' 2>/dev/null || echo "null")
if [[ "$TOKEN_INPUT" == "null" ]]; then
  TOKEN_USAGE="N/A"
else
  TOKEN_USAGE="input ${TOKEN_INPUT} / output ${TOKEN_OUTPUT:-0}"
fi

# Concurrent commits detected
CONCURRENT_COMMITS=$(echo "$EVENTS_JSON" | jq '[.[] | select(.event == "concurrent_commit_detected")] | length' 2>/dev/null || echo 0)

# Parent session manual interventions
MANUAL_INTERVENTIONS=$(echo "$EVENTS_JSON" | jq '[.[] | select(.event == "manual_intervention")] | length' 2>/dev/null || echo 0)

# verify FAIL reopen fix cycles
VERIFY_REOPEN_CYCLES=$(echo "$EVENTS_JSON" | jq '[.[] | select(.event == "verify_reopen_cycle")] | length' 2>/dev/null || echo 0)

# Backfilled phase_complete events
BACKFILLED_COUNT=$(echo "$EVENTS_JSON" | jq '[.[] | select(.event == "phase_complete" and .backfilled == true)] | length' 2>/dev/null || echo 0)

# Verify phase residuals: issues currently carrying the phase/verify label (live lookup).
# Populated below in the GitHub state lookups block, since /verify is a wrapper-less Skill
# invocation and never emits phase_start/phase_complete(phase=="verify") events (see #900).
VERIFY_RESIDUALS=""
VERIFY_RESIDUALS_NO_GITHUB_NOTE=""

# Phase Activity Summary — phase_start/phase_complete counts per phase
PHASE_ACTIVITY_TABLE=$(echo "$EVENTS_JSON" | jq -r '
  [.[] | select(.event == "phase_start" or .event == "phase_complete") | .phase] |
  group_by(.) | map({
    phase: .[0],
    starts: ([.[] | select(. != null)] | length)
  }) | .[] |
  "| \(.phase) | \(.starts) |"
' 2>/dev/null || true)
if [[ -z "$PHASE_ACTIVITY_TABLE" ]]; then
  PHASE_ACTIVITY_TABLE="| (no phase events) | 0 |"
fi

# Sub-Issue Completion Timeline — per-issue with Route, Phase breakdown, PR, Recovery, Notes
ISSUE_NUMS_FOR_TABLE=$(echo "$EVENTS_JSON" | jq -r '[.[] | select(.issue != null and .issue > 0) | .issue] | unique | .[]' 2>/dev/null || true)
COMPLETION_TIMELINE_TABLE=""
for _num in $ISSUE_NUMS_FOR_TABLE; do
  _issue_events=$(echo "$EVENTS_JSON" | jq --argjson n "$_num" '[.[] | select(.issue == $n)]' 2>/dev/null || echo "[]")
  _first_ts=$(echo "$_issue_events" | jq -r '[.[] | select(.event == "phase_start") | .ts] | sort | first // "?"' 2>/dev/null || echo "?")
  _last_ts=$(echo "$_issue_events" | jq -r '
    [.[] | select(.event == "phase_complete" or .event == "sub_complete")] |
    sort_by(.ts) | last // null |
    if . == null then "?"
    elif .backfilled == true then .ts + " (backfilled)"
    else .ts
    end
  ' 2>/dev/null || echo "?")
  _size=$(echo "$_issue_events" | jq -r '[.[] | select(.event == "sub_start") | .size] | first // "?"' 2>/dev/null || echo "?")
  case "$_size" in
    XS|S) _route="patch" ;;
    M|L)  _route="pr" ;;
    *)    _route="?" ;;
  esac
  # Phase breakdown: per-phase duration joined by →
  _phase_breakdown=$(echo "$_issue_events" | jq -r '
    [.[] | select(.event == "phase_start" or .event == "phase_complete")] |
    group_by(.phase) |
    map(
      (.[0].phase) as $p |
      ([.[] | select(.event == "phase_start") | .ts] | sort | first) as $ps |
      ([.[] | select(.event == "phase_complete") | .ts] | sort | last) as $pc |
      if $ps == null or $pc == null then empty
      else
        ($pc | fromdateiso8601) as $end |
        ($ps | fromdateiso8601) as $start |
        (($end - $start) / 60 | floor) as $mins |
        $p + " " + ($mins | tostring) + "m"
      end
    ) | if length == 0 then "—" else join(" → ") end
  ' 2>/dev/null || echo "—")
  [[ -z "$_phase_breakdown" ]] && _phase_breakdown="—"
  # PR lookup
  _pr_col="—"
  if [[ "$NO_GITHUB" == "false" ]]; then
    _pr_num=$(gh pr list --search "closes #${_num}" --state all --json number --jq '.[0].number // empty' 2>/dev/null || true)
    [[ -n "$_pr_num" ]] && _pr_col="#${_pr_num}"
  fi
  # Recovery events for this issue
  _t1_n=$(echo "$_issue_events" | jq '[.[] | select(.event == "recovery" and .tier == "1")] | length' 2>/dev/null || echo 0)
  _t2_n=$(echo "$_issue_events" | jq '[.[] | select(.event == "recovery" and .tier == "2")] | length' 2>/dev/null || echo 0)
  _t3_n=$(echo "$_issue_events" | jq '[.[] | select(.event == "recovery" and .tier == "3")] | length' 2>/dev/null || echo 0)
  _recovery_col="T1:${_t1_n}/T2:${_t2_n}/T3:${_t3_n}"
  # Notes: heuristic from events
  _notes_parts=()
  _size_refresh=$(echo "$_issue_events" | jq -r '[.[] | select(.event == "size_refresh")] | first | if . == null then "" else "Size " + .from + "→" + .to end' 2>/dev/null || true)
  [[ -n "$_size_refresh" ]] && _notes_parts+=("$_size_refresh")
  _max_silent=$(echo "$_issue_events" | jq -r '[.[] | select(.event == "max_silent_window") | .max_sec | tonumber] | if length == 0 then 0 else max end' 2>/dev/null || echo 0)
  _at_risk_silent=$(echo "$_issue_events" | jq -r \
    --argjson t_spec "$SILENT_THRESHOLD_SPEC" \
    --argjson t_code "$SILENT_THRESHOLD_CODE" \
    --argjson t_review "$SILENT_THRESHOLD_REVIEW" \
    --argjson t_issue "$SILENT_THRESHOLD_ISSUE" \
    '
    [.[] |
      select(.event == "max_silent_window" and .phase != null and .phase != "merge") |
      (if .phase == "spec" then $t_spec
       elif .phase == "code" then $t_code
       elif .phase == "review" then $t_review
       elif .phase == "issue" then $t_issue
       else -1 end) as $at_risk_limit |
      select($at_risk_limit > 0 and ((.max_sec | tonumber) > $at_risk_limit)) |
      {phase: .phase, max_sec: (.max_sec | tonumber)}
    ] |
    if length == 0 then ""
    else
      (max_by(.max_sec)) as $worst |
      "Silent \($worst.max_sec)s phase=\($worst.phase) (within 600s of watchdog limit)"
    end
  ' 2>/dev/null || echo "")
  if [[ -n "$_at_risk_silent" ]]; then
    _notes_parts+=("$_at_risk_silent")
  elif [[ "$_max_silent" -gt 600 ]]; then
    _notes_parts+=("Silent ${_max_silent}s")
  fi
  _concurrent_for_issue=$(echo "$_issue_events" | jq -r '[.[] | select(.event == "concurrent_commit_detected")] | length' 2>/dev/null || echo 0)
  [[ "$_concurrent_for_issue" -gt 0 ]] && _notes_parts+=("${_concurrent_for_issue} concurrent commits")
  if [[ ${#_notes_parts[@]} -eq 0 ]]; then
    _notes_col="—"
  else
    _notes_col=$(IFS='; '; echo "${_notes_parts[*]}")
  fi
  COMPLETION_TIMELINE_TABLE+="| #${_num} | ${_size}/${_route} | ${_first_ts} – ${_last_ts} | ${_phase_breakdown} | ${_pr_col} | ${_recovery_col} | ${_notes_col} |
"
done
[[ -z "$COMPLETION_TIMELINE_TABLE" ]] && COMPLETION_TIMELINE_TABLE="| (no events) | — | — | — | — | — | — |"

# Token Usage Aggregate — per-issue if schema has issue granularity, else session total
TOKEN_USAGE_TABLE=$(echo "$EVENTS_JSON" | jq -r '
  [.[] | select(.event == "token_usage" and .issue != null and (.issue | type) == "number")] |
  if length > 0 then
    group_by(.issue) |
    map({
      issue: .[0].issue,
      input: ([.[].input_tokens | tonumber] | add // 0),
      output: ([.[].output_tokens | tonumber] | add // 0)
    }) | .[] |
    "| #\(.issue) | \(.input) | \(.output) | \(.input + .output) |"
  else empty end
' 2>/dev/null || true)
if [[ -n "$TOKEN_USAGE_TABLE" ]]; then
  TOKEN_USAGE_HEADER="| Issue | Input tokens | Output tokens | Total |
|---|---|---|---|"
else
  # Fallback: session-level aggregate
  TOKEN_USAGE_HEADER="| Scope | Input tokens | Output tokens | Total |
|---|---|---|---|"
  _sess_input=$(echo "$EVENTS_JSON" | jq '[.[] | select(.event == "token_usage") | .input_tokens | tonumber] | add // 0' 2>/dev/null || echo 0)
  _sess_output=$(echo "$EVENTS_JSON" | jq '[.[] | select(.event == "token_usage") | .output_tokens | tonumber] | add // 0' 2>/dev/null || echo 0)
  if [[ "$_sess_input" == "0" && "$_sess_output" == "0" ]]; then
    TOKEN_USAGE_TABLE="| (session total) | N/A | N/A | N/A |"
  else
    _sess_total=$(( _sess_input + _sess_output ))
    TOKEN_USAGE_TABLE="| (session total) | ${_sess_input} | ${_sess_output} | ${_sess_total} |"
  fi
fi

# Recovery events section
RECOVERY_EVENTS=$(echo "$EVENTS_JSON" | jq -r '
  [.[] | select(.event == "recovery")] |
  if length == 0 then "(no recovery events)"
  else
    .[] |
    "- [" + .ts + "] Issue #" + (.issue | tostring) + " phase=" + (.phase // "?") +
    " tier=" + (.tier // "?") + " result=" + (.result // "?")
  end
' 2>/dev/null || echo "(no recovery events)")

# Concurrent sessions section — resolve sha → issue via local git log when possible
CONCURRENT_SECTION=""
if [[ "$CONCURRENT_COMMITS" -gt 0 ]]; then
  _concurrent_lines=$(echo "$EVENTS_JSON" | jq -r '
    [.[] | select(.event == "concurrent_commit_detected")] | .[] |
    .ts + "\t" + (.phase // "?") + "\t" + (.commit_sha // "?") + "\t" + (.author // "?")
  ' 2>/dev/null || true)
  while IFS=$'\t' read -r _ts _phase _sha _author; do
    [[ -z "$_ts" ]] && continue
    _sha8="${_sha:0:8}"
    _issue_hint=""
    _commit_msg=$(git log -1 --format='%s%n%b' "$_sha" 2>/dev/null || true)
    if [[ -n "$_commit_msg" ]]; then
      _issue_hint=$(echo "$_commit_msg" | grep -ioE '(closes|fixes|resolves)?[[:space:]]*#[0-9]+' | grep -oE '#[0-9]+' | head -1 || true)
    fi
    if [[ -n "$_issue_hint" ]]; then
      CONCURRENT_SECTION+="- [${_ts}] phase=${_phase} sha=${_sha8} → ${_issue_hint} (author=${_author})"$'\n'
    else
      CONCURRENT_SECTION+="- [${_ts}] phase=${_phase} sha=${_sha8} author=${_author}"$'\n'
    fi
  done <<< "$_concurrent_lines"
  [[ -z "$CONCURRENT_SECTION" ]] && CONCURRENT_SECTION="(error parsing concurrent commits)"
else
  CONCURRENT_SECTION="(none detected)"
fi

# Improvement candidates from anomaly events (Tier 2 approaching threshold + Tier 3)
TIER3_CANDIDATES=$(echo "$EVENTS_JSON" | jq -r '
  [.[] | select(.event == "recovery" and .tier == "3")] |
  if length == 0 then ""
  else .[] |
    "- Tier 3 recovery occurred in phase=" + (.phase // "?") + " — investigate root cause"
  end
' 2>/dev/null || true)

TIER2_CANDIDATES=$(echo "$EVENTS_JSON" | jq -r --argjson approach "$RECOVERIES_APPROACH" --argjson threshold "$RECOVERIES_THRESHOLD" '
  [.[] | select(.event == "recovery" and .tier == "2" and .phase != null)] |
  group_by(.phase) |
  map({phase: .[0].phase, count: length}) |
  .[] | select(.count >= $approach) |
  if .count >= $threshold
  then "- Tier 2 recovery in phase=" + .phase + " (count=" + (.count | tostring) + ", threshold reached) — review recoveries-auto-fire.threshold"
  else "- Tier 2 recovery in phase=" + .phase + " (count=" + (.count | tostring) + ", approaching threshold) — review recoveries-auto-fire.threshold"
  end
' 2>/dev/null || true)

if [[ -z "$TIER2_CANDIDATES" && -z "$TIER3_CANDIDATES" ]]; then
  IMPROVEMENT_CANDIDATES="(none — no Tier 3 recoveries or Tier 2 approaching recoveries-auto-fire threshold)"
else
  IMPROVEMENT_CANDIDATES=""
  [[ -n "$TIER2_CANDIDATES" ]] && IMPROVEMENT_CANDIDATES+="${TIER2_CANDIDATES}"$'\n'
  [[ -n "$TIER3_CANDIDATES" ]] && IMPROVEMENT_CANDIDATES+="${TIER3_CANDIDATES}"$'\n'
  IMPROVEMENT_CANDIDATES="${IMPROVEMENT_CANDIDATES%$'\n'}"
fi

# GitHub state lookups (best-effort, skipped with --no-github)
FULLY_CLOSED=0
VERIFY_REMAINING=0
if [[ "$NO_GITHUB" == "false" ]]; then
  # Extract distinct issue numbers
  ISSUE_NUMS=$(echo "$EVENTS_JSON" | jq -r '[.[] | select(.issue != null and .issue > 0) | .issue] | unique | .[]' 2>/dev/null || true)
  for _num in $ISSUE_NUMS; do
    _labels=$(gh issue view "$_num" --json labels -q '.labels[].name' 2>/dev/null || true)
    if echo "$_labels" | grep -q "phase/done"; then
      FULLY_CLOSED=$(( FULLY_CLOSED + 1 ))
    elif echo "$_labels" | grep -q "phase/verify"; then
      VERIFY_REMAINING=$(( VERIFY_REMAINING + 1 ))
      if [[ -z "$VERIFY_RESIDUALS" ]]; then
        VERIFY_RESIDUALS="$_num"
      else
        VERIFY_RESIDUALS="${VERIFY_RESIDUALS}
${_num}"
      fi
    fi
  done
else
  FULLY_CLOSED="N/A (--no-github)"
  VERIFY_REMAINING="N/A (--no-github)"
  VERIFY_RESIDUALS_NO_GITHUB_NOTE="(--no-github mode: cannot detect phase/verify residuals via live label lookup. Re-run without --no-github to populate this section.)"
fi

# Compute throughput (issues/hr from wall-clock, reusing epoch values computed above)
THROUGHPUT="N/A"
if [[ "$WALL_CLOCK" != "N/A" && "$ISSUES_PROCESSED" -gt 0 ]]; then
  if [[ -n "${START_EPOCH:-}" && -n "${END_EPOCH:-}" && "$END_EPOCH" -gt "$START_EPOCH" ]]; then
    WALL_SEC_FOR_THROUGHPUT=$(( END_EPOCH - START_EPOCH ))
    if [[ "$WALL_SEC_FOR_THROUGHPUT" -gt 0 ]]; then
      THROUGHPUT=$(echo "$ISSUES_PROCESSED $WALL_SEC_FOR_THROUGHPUT" | awk '{printf "%.1f", $1/($2/3600)}')
      THROUGHPUT="${THROUGHPUT} issues/hr"
    fi
  fi
fi

# Verify-type breakdown for phase/verify residuals
VERIFY_RESIDUALS_TABLE=""
VERIFY_RESIDUALS_AGGREGATE=""
VERIFY_RESIDUALS_TOTAL=0
_total_obs=0
_total_opp=0
_total_manual=0
_all_obs_events=""
if [[ -n "$VERIFY_RESIDUALS" ]]; then
  for _r in $VERIFY_RESIDUALS; do
    VERIFY_RESIDUALS_TOTAL=$(( VERIFY_RESIDUALS_TOTAL + 1 ))
    _body=""
    _title=""
    if [[ -n "$ISSUE_BODY_DIR" && -f "${ISSUE_BODY_DIR}/${_r}.md" ]]; then
      _body=$(cat "${ISSUE_BODY_DIR}/${_r}.md")
      _title="#${_r}"
    elif [[ "$NO_GITHUB" == "false" ]]; then
      _gh_json=$(gh issue view "$_r" --json body,title 2>/dev/null || echo '{}')
      _body=$(echo "$_gh_json" | jq -r '.body // ""')
      _title=$(echo "$_gh_json" | jq -r '.title // ""')
    fi
    _obs_count=0
    _opp_count=0
    _manual_count=0
    _obs_events=""
    _in_post_merge=false
    while IFS= read -r _line; do
      if echo "$_line" | grep -q "^### Post-merge"; then
        _in_post_merge=true
        continue
      fi
      if [[ "$_in_post_merge" == "true" ]] && echo "$_line" | grep -q "^### "; then
        _in_post_merge=false
        continue
      fi
      if [[ "$_in_post_merge" == "true" ]] && echo "$_line" | grep -qE "^- \[ \]"; then
        if echo "$_line" | grep -qE "verify-type: observation event="; then
          _evt=$(echo "$_line" | grep -oE "verify-type: observation event=[^ >]+" | sed 's/verify-type: observation event=//')
          _obs_count=$(( _obs_count + 1 ))
          if [[ -z "$_obs_events" ]]; then
            _obs_events="$_evt"
          else
            _obs_events="${_obs_events},${_evt}"
          fi
        elif echo "$_line" | grep -qE "verify-type: opportunistic"; then
          _opp_count=$(( _opp_count + 1 ))
        else
          _manual_count=$(( _manual_count + 1 ))
        fi
      fi
    done <<< "$_body"
    if [[ $_obs_count -eq 0 ]]; then
      _obs_str="0"
    else
      _obs_str="${_obs_count} (event=${_obs_events})"
    fi
    _row="| #${_r} | ${_title:-#${_r}} | ${_obs_str} | ${_opp_count} | ${_manual_count} |"
    if [[ -z "$VERIFY_RESIDUALS_TABLE" ]]; then
      VERIFY_RESIDUALS_TABLE="$_row"
    else
      VERIFY_RESIDUALS_TABLE="${VERIFY_RESIDUALS_TABLE}
${_row}"
    fi
    _total_obs=$(( _total_obs + _obs_count ))
    _total_opp=$(( _total_opp + _opp_count ))
    _total_manual=$(( _total_manual + _manual_count ))
    if [[ -n "$_obs_events" ]]; then
      if [[ -z "$_all_obs_events" ]]; then
        _all_obs_events="$_obs_events"
      else
        _all_obs_events="${_all_obs_events},${_obs_events}"
      fi
    fi
  done
  if [[ -z "$VERIFY_RESIDUALS_TABLE" ]]; then
    VERIFY_RESIDUALS_TABLE="| (none) | — | — | — | — |"
  fi
  if [[ $_total_obs -gt 0 && -n "$_all_obs_events" ]]; then
    _obs_detail=" (event breakdown: ${_all_obs_events})"
  else
    _obs_detail=""
  fi
  VERIFY_RESIDUALS_AGGREGATE="- observation waiting: ${_total_obs}${_obs_detail}
- opportunistic remaining: ${_total_opp}
- manual waiting: ${_total_manual}"
fi

# Render the Metrics markdown section to stdout
cat << REPORT_EOF
## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - The verify phase does not emit phase_start/phase_complete events (/verify is a wrapper-less Skill invocation), so it is not counted in the Phase Activity Summary / Sub-Issue Completion Timeline phase breakdown.
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: ${SESSION_START}
**Session end**: ${SESSION_END}
**Wall-clock**: ${WALL_CLOCK}
**Route mix**: ${ROUTE_MIX}

### Summary

| Metric | Value |
|---|---|
| Issues processed | ${ISSUES_PROCESSED} |
| Fully closed (phase/done) | ${FULLY_CLOSED} |
| phase/verify remaining | ${VERIFY_REMAINING} |
| Throughput | ${THROUGHPUT} |
| Tier 1/2/3 recoveries | ${RECOVERY_COUNTS} |
| Watchdog kills | ${WATCHDOG_KILLS} |
| Max silent window (any phase) | ${MAX_SILENT} |
| Phase silent windows > threshold | ${PHASE_SILENT_BREAKDOWN} |
| Total token usage | ${TOKEN_USAGE} |
| Concurrent commits detected | ${CONCURRENT_COMMITS} |
| Parent session manual interventions | ${MANUAL_INTERVENTIONS} |
| verify FAIL → reopen fix cycles | ${VERIFY_REOPEN_CYCLES} |
| Backfilled phase_complete events | ${BACKFILLED_COUNT} |
| Merge conflicts | 0 |

### Phase Activity Summary

| Phase | Event count |
|---|---|
${PHASE_ACTIVITY_TABLE}

### Sub-Issue Completion Timeline

| Issue | Size/Route | Duration | Phase breakdown | PR | Recovery | Notes |
|---|---|---|---|---|---|---|
${COMPLETION_TIMELINE_TABLE}

### Token Usage Aggregate

${TOKEN_USAGE_HEADER}
${TOKEN_USAGE_TABLE}

### Recovery Events

${RECOVERY_EVENTS}

### Verify Phase Residuals

$(
  if [[ -n "$VERIFY_RESIDUALS_NO_GITHUB_NOTE" ]]; then
    echo "$VERIFY_RESIDUALS_NO_GITHUB_NOTE"
  elif [[ -z "$VERIFY_RESIDUALS" ]]; then
    echo "(none)"
  else
    # verify-type breakdown: observation / opportunistic / manual
    echo "Total: ${VERIFY_RESIDUALS_TOTAL} phase/verify remaining"
    echo ""
    echo "| Issue | Title | observation event=* | opportunistic | manual |"
    echo "|---|---|---|---|---|"
    printf '%s\n' "${VERIFY_RESIDUALS_TABLE}"
    echo ""
    printf '%s\n' "${VERIFY_RESIDUALS_AGGREGATE}"
  fi
)

### Concurrent Sessions Detected

${CONCURRENT_SECTION}

### Improvement Candidates Surfaced

${IMPROVEMENT_CANDIDATES}
REPORT_EOF
