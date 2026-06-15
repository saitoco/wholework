#!/bin/bash
# get-auto-session-report.sh - Generate a data-layer retrospective report for a /auto session.
# Reads .tmp/auto-events.jsonl filtered by session_id and renders a markdown report.
#
# Usage:
#   get-auto-session-report.sh <session-id> [--output <path>] [--no-github] [--narrative-draft <path>]
#   get-auto-session-report.sh [--since <spec>]   # list mode: show distinct session_ids
#
# Options:
#   <session-id>              Report for the specified session
#   --output <path>           Output path (default: docs/reports/auto-session-<id>-<date>.md)
#   --no-github               Skip gh issue/pr calls (for hermetic bats tests)
#   --narrative-draft <path>  Pre-generated narrative draft file; replaces TBD placeholders with
#                             draft content prefixed by [LLM draft — human review required] marker
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
OUTPUT_PATH=""
NO_GITHUB=false
ISSUE_BODY_DIR="${WHOLEWORK_ISSUE_BODY_DIR:-}"
LIST_MODE=false
SINCE_SPEC="24h"
NARRATIVE_DRAFT_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_PATH="${2:?--output requires a path}"
      shift 2
      ;;
    --no-github)
      NO_GITHUB=true
      shift
      ;;
    --narrative-draft)
      NARRATIVE_DRAFT_PATH="${2:?--narrative-draft requires a path}"
      shift 2
      ;;
    --since)
      LIST_MODE=true
      if [[ $# -gt 1 && "${2:-}" != -* ]]; then
        SINCE_SPEC="$2"
        shift 2
      else
        SINCE_SPEC="24h"
        shift
      fi
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      echo "Usage: get-auto-session-report.sh <session-id> [--output <path>] [--no-github]" >&2
      exit 1
      ;;
    *)
      SESSION_ID="$1"
      shift
      ;;
  esac
done

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

# Report mode: generate report for the specified session
echo "Generating report for session: $SESSION_ID"

TODAY=$(date +%Y-%m-%d)

if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="docs/reports/auto-session-${SESSION_ID}-${TODAY}.md"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"

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

# Verify phase residuals: issues that have phase_start for verify but no phase_complete for verify
VERIFY_RESIDUALS=$(echo "$EVENTS_JSON" | jq -r '
  . as $all |
  [.[] | select(.event == "sub_complete" and (.exit_code == "0" or .exit_code == 0)) | .issue] as $completed |
  ([$all[] | select(.event == "phase_start" and .phase == "verify") | .issue] -
   [$all[] | select(.event == "phase_complete" and .phase == "verify") | .issue]) |
  unique |
  map(select(. as $i | $completed | contains([$i]) | not)) |
  .[]
' 2>/dev/null || true)

# Per-issue durations table — Bash loop computes Phase breakdown, PR, Notes per issue
ISSUE_NUMS_FOR_TABLE=$(echo "$EVENTS_JSON" | jq -r '[.[] | select(.issue != null and .issue > 0) | .issue] | unique | .[]' 2>/dev/null || true)
PER_ISSUE_TABLE=""
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
  # Phase breakdown: per-phase duration (latest phase_complete - earliest phase_start) joined by →
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
  # PR lookup via gh (skipped when --no-github)
  _pr_col="—"
  if [[ "$NO_GITHUB" == "false" ]]; then
    _pr_num=$(gh pr list --search "closes #${_num}" --state all --json number --jq '.[0].number // empty' 2>/dev/null || true)
    [[ -n "$_pr_num" ]] && _pr_col="#${_pr_num}"
  fi
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
  _tier3=$(echo "$_issue_events" | jq -r '[.[] | select(.event == "recovery" and .tier == "3")] | length' 2>/dev/null || echo 0)
  [[ "$_tier3" -gt 0 ]] && _notes_parts+=("Tier 3 recover")
  _concurrent_for_issue=$(echo "$_issue_events" | jq -r '[.[] | select(.event == "concurrent_commit_detected")] | length' 2>/dev/null || echo 0)
  [[ "$_concurrent_for_issue" -gt 0 ]] && _notes_parts+=("${_concurrent_for_issue} concurrent commits")
  if [[ ${#_notes_parts[@]} -eq 0 ]]; then
    _notes_col="—"
  else
    _notes_col=$(IFS='; '; echo "${_notes_parts[*]}")
  fi
  PER_ISSUE_TABLE+="| #${_num} | ${_size}/${_route} | ${_first_ts} – ${_last_ts} | ${_phase_breakdown} | ${_pr_col} | ${_notes_col} |
"
done
[[ -z "$PER_ISSUE_TABLE" ]] && PER_ISSUE_TABLE="| (no events) | — | — | — | — | — |"

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
      _issue_hint=$(echo "$_commit_msg" | grep -ioE '(closes|fixes|resolves)?[[:space:]]*#[0-9]+' | grep -oE '#[0-9]+' | head -1)
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

# Improvement candidates from anomaly events
IMPROVEMENT_CANDIDATES=$(echo "$EVENTS_JSON" | jq -r '
  [.[] | select(.event == "recovery" and .tier == "3")] |
  if length == 0 then "(none — no Tier 3 recoveries)"
  else
    "- Tier 3 recovery occurred in " + (.[] | "phase=" + (.phase // "?")) + " — investigate root cause"
  end
' 2>/dev/null || echo "(none)")

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
    fi
  done
else
  FULLY_CLOSED="N/A (--no-github)"
  VERIFY_REMAINING="N/A (--no-github)"
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

# Render the markdown report
cat > "$OUTPUT_PATH" << REPORT_EOF
# /auto Session Report — ${SESSION_ID}

**Session start**: ${SESSION_START}
**Session end**: ${SESSION_END}
**Wall-clock**: ${WALL_CLOCK}
**Route mix**: ${ROUTE_MIX}

## Summary

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

## Per-Issue Durations

| Issue | Size/Route | Duration | Phase breakdown | PR | Notes |
|---|---|---|---|---|---|
${PER_ISSUE_TABLE}

## Recovery Events

${RECOVERY_EVENTS}

## Verify Phase Residuals

$(
  if [[ -z "$VERIFY_RESIDUALS" ]]; then
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

## Concurrent Sessions Detected

${CONCURRENT_SECTION}

## Improvement Candidates Surfaced

${IMPROVEMENT_CANDIDATES}

---

## Narrative Section (manual / --full LLM-assist)

### What worked
TBD — fill in after reviewing the session

### Limits and gaps
TBD — fill in after reviewing the session

### Improvement candidates surfaced
TBD — fill in after reviewing the session

### Conclusion
TBD — fill in after reviewing the session
REPORT_EOF

# Apply narrative draft if --narrative-draft was specified
if [[ -n "$NARRATIVE_DRAFT_PATH" && -f "$NARRATIVE_DRAFT_PATH" ]]; then
  python3 - "$OUTPUT_PATH" "$NARRATIVE_DRAFT_PATH" << 'PYTHON_EOF'
import sys, re

report_path = sys.argv[1]
draft_path = sys.argv[2]

with open(report_path, 'r') as f:
    report = f.read()

with open(draft_path, 'r') as f:
    draft = f.read()

# Extract per-section content from draft file
# Sections are delimited by "### <name>" headings
section_pattern = re.compile(r'^### (.+)$', re.MULTILINE)
parts = section_pattern.split(draft)
# parts[0] is pre-section text; then alternating name, content
sections = {}
for i in range(1, len(parts), 2):
    name = parts[i].strip()
    content = parts[i + 1].strip() if i + 1 < len(parts) else ''
    sections[name] = content

MARKER = '[LLM draft — human review required]'

def replace_tbd(report_text, section_name, draft_content):
    """Replace 'TBD — fill in after reviewing the session' under section_name with draft."""
    pattern = re.compile(
        r'(### ' + re.escape(section_name) + r'\n)TBD — fill in after reviewing the session',
        re.MULTILINE
    )
    replacement = r'\1> ' + MARKER + '\n\n' + draft_content
    return pattern.sub(replacement, report_text)

for section_name, content in sections.items():
    if content:
        report = replace_tbd(report, section_name, content)

with open(report_path, 'w') as f:
    f.write(report)

print("Narrative draft inserted into report.")
PYTHON_EOF
  declare -f emit_event > /dev/null 2>&1 && \
    AUTO_SESSION_ID="$SESSION_ID" emit_event "auto-session-report-published" "report_path=${OUTPUT_PATH}"
fi

echo "Report written to: $OUTPUT_PATH"
