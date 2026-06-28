#!/bin/bash
# auto-events-rollup.sh - Daily rollup of .tmp/auto-events.jsonl into a curated report.
# Usage: auto-events-rollup.sh [--date YYYY-MM-DD] [--input <file>] [--output-dir <dir>] [--cleanup]

set -euo pipefail

# Defaults
TARGET_DATE=$(date -u +%Y-%m-%d)
INPUT_FILE=".tmp/auto-events.jsonl"
OUTPUT_DIR="docs/sessions/_daily"
CLEANUP=false

# Option parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)
      [[ -z "${2:-}" ]] && { echo "Error: --date requires YYYY-MM-DD" >&2; exit 1; }
      TARGET_DATE="$2"; shift 2;;
    --input)
      [[ -z "${2:-}" ]] && { echo "Error: --input requires a file path" >&2; exit 1; }
      INPUT_FILE="$2"; shift 2;;
    --output-dir)
      [[ -z "${2:-}" ]] && { echo "Error: --output-dir requires a directory path" >&2; exit 1; }
      OUTPUT_DIR="$2"; shift 2;;
    --cleanup)
      CLEANUP=true; shift;;
    *)
      echo "Error: Unknown option: $1" >&2
      echo "Usage: $0 [--date YYYY-MM-DD] [--input <file>] [--output-dir <dir>] [--cleanup]" >&2
      exit 1;;
  esac
done

GENERATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
OUTPUT_FILE="${OUTPUT_DIR}/auto-events-rollup-${TARGET_DATE}.md"

mkdir -p "$OUTPUT_DIR"

write_header() {
  printf '%s\n' \
    "---" \
    "type: report" \
    "description: Daily rollup of /auto session events from .tmp/auto-events.jsonl" \
    "generated_by: scripts/auto-events-rollup.sh" \
    "generated_at: ${GENERATED_AT}" \
    "---" \
    "" \
    "# /auto Event Rollup — ${TARGET_DATE}"
}

write_sessions_section() {
  local rows="$1"
  printf '%s\n' \
    "" \
    "## Sessions" \
    "" \
    "| Issue | Size | Start (UTC) | End (UTC) | Duration | Phases | Recoveries | Outcome |" \
    "|-------|------|-------------|-----------|----------|--------|------------|---------|"
  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows"
  fi
}

write_phase_dist_section() {
  local rows="$1"
  printf '%s\n' \
    "" \
    "## Phase Distribution" \
    "" \
    "| Phase | Count | Median Duration | p95 |" \
    "|-------|-------|-----------------|-----|"
  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows"
  fi
}

write_recovery_section() {
  local rows="$1"
  printf '%s\n' \
    "" \
    "## Recovery Tier Invocations" \
    "" \
    "| Tier | Count | Issues |" \
    "|------|-------|--------|"
  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows"
  fi
}

write_anomalies_section() {
  local items="$1"
  printf '%s\n' "" "## Anomalies" "" "$items"
}

write_empty_report() {
  write_header
  write_sessions_section ""
  write_phase_dist_section ""
  write_recovery_section ""
  write_anomalies_section "- (none)"
}

# Handle missing or empty input
if [[ ! -f "$INPUT_FILE" ]] || [[ ! -s "$INPUT_FILE" ]]; then
  write_empty_report > "$OUTPUT_FILE"
  echo "Rollup complete: ${OUTPUT_FILE} (no input data)"
  exit 0
fi

# Filter lines matching target date
FILTERED=$(grep "\"ts\":\"${TARGET_DATE}" "$INPUT_FILE" 2>/dev/null || true)

if [[ -z "$FILTERED" ]]; then
  write_empty_report > "$OUTPUT_FILE"
  echo "Rollup complete: ${OUTPUT_FILE} (no events for ${TARGET_DATE})"
  exit 0
fi

# Build Sessions table rows
SESSIONS_ROWS=$(printf '%s\n' "$FILTERED" | jq -rs '
  . as $ev |
  [$ev[] | {issue, session_id: (.session_id // "")}] | unique | sort_by(.issue) |
  map(
    .issue as $iss |
    .session_id as $sid |
    ($ev | map(select(.issue == $iss and (.session_id // "") == $sid))) as $own |
    ($own | map(select(.event == "sub_start")) | first) as $sub_start |
    ($own | map(select(.event == "phase_start")) | first) as $first_phase_start |
    ($sub_start // $first_phase_start) as $start |
    if $start == null then empty else
      ($sub_start.size // "-") as $sz |
      $start.ts as $start_ts |
      ($start_ts | split("T")[1] | rtrimstr("Z")) as $start_time |
      ($own | map(select(.event == "sub_complete")) | last) as $sub_complete |
      ($own | map(select(.event == "phase_complete")) | last) as $last_phase_complete |
      ($sub_complete // $last_phase_complete) as $end |
      (if $end then $end.ts | split("T")[1] | rtrimstr("Z") else "-" end) as $end_time |
      (if $end then
        (($end.ts | split("T")[1] | rtrimstr("Z") | split(":") |
            (.[0]|tonumber)*3600 + (.[1]|tonumber)*60 + (.[2]|tonumber)) -
         ($start_ts | split("T")[1] | rtrimstr("Z") | split(":") |
            (.[0]|tonumber)*3600 + (.[1]|tonumber)*60 + (.[2]|tonumber))) as $sec |
        if $sec < 0 then "\(($sec + 86400) / 60 | floor)m"
        else if $sec >= 60 then "\($sec / 60 | floor)m"
        else "\($sec)s"
        end end
      else "-" end) as $dur |
      ($own | map(select(.event == "phase_complete")) | map(.phase) | join("→")) as $phases |
      ($own | map(select(.event == "recovery")) | length) as $rec_count |
      (if $rec_count == 0 then "—" else ($rec_count | tostring) end) as $recs |
      (if $sub_complete then
        if (($sub_complete.exit_code // "0") == "0") then "success" else "failure" end
      elif $last_phase_complete then "success"
      else "incomplete" end) as $outcome |
      "| #\($iss) | \($sz) | \($start_time) | \($end_time) | \($dur) | \($phases) | \($recs) | \($outcome) |"
    end
  ) | join("\n")
' 2>/dev/null || true)

# Build Phase Distribution table rows
PHASE_DIST_ROWS=$(printf '%s\n' "$FILTERED" | jq -rs '
  . as $ev |
  [$ev[] | select(.event == "phase_complete")] |
  map(
    .issue as $iss |
    .phase as $ph |
    .ts as $end_ts |
    ($ev | map(select(.event == "phase_start" and .issue == $iss and .phase == $ph and .ts <= $end_ts)) | last) as $start |
    if $start != null then
      (($end_ts | split("T")[1] | rtrimstr("Z") | split(":") |
          (.[0]|tonumber)*3600 + (.[1]|tonumber)*60 + (.[2]|tonumber)) -
       ($start.ts | split("T")[1] | rtrimstr("Z") | split(":") |
          (.[0]|tonumber)*3600 + (.[1]|tonumber)*60 + (.[2]|tonumber))) as $sec |
      {phase: $ph, sec: (if $sec < 0 then $sec + 86400 else $sec end)}
    else empty end
  ) as $durs |
  if ($durs | length) == 0 then ""
  else
    ($durs | map(.phase) | unique | sort) as $phases |
    ($phases | map(. as $p |
      ($durs | map(select(.phase == $p) | .sec) | sort) as $secs |
      ($secs | length) as $n |
      if $n == 0 then "| \($p) | 0 | - | - |"
      else
        ($secs[$n / 2 | floor]) as $med_sec |
        ($secs[$n * 95 / 100 | floor]) as $p95_sec |
        (if $med_sec >= 60 then "\($med_sec / 60 | floor)m" else "\($med_sec)s" end) as $med |
        (if $p95_sec >= 60 then "\($p95_sec / 60 | floor)m" else "\($p95_sec)s" end) as $p95 |
        "| \($p) | \($n) | \($med) | \($p95) |"
      end
    )) | join("\n")
  end
' 2>/dev/null || true)

# Build Recovery Tier table rows
RECOVERY_ROWS=$(printf '%s\n' "$FILTERED" | jq -rs '
  [.[] | select(.event == "recovery")] |
  if length == 0 then ""
  else
    group_by(.tier) |
    map(
      .[0].tier as $t |
      (length | tostring) as $cnt |
      (map("#\(.issue)") | unique | join(", ")) as $issues |
      "| \($t) | \($cnt) | \($issues) |"
    ) | join("\n")
  end
' 2>/dev/null || true)

# Build Anomalies list
ANOMALIES=$(printf '%s\n' "$FILTERED" | jq -rs '
  [.[] | select(.event == "anomaly")] |
  if length == 0 then "- (none)"
  else
    map("- `[#\(.issue)]` \(.description // .detail // "anomaly detected") in phase \(.phase // "unknown")") |
    join("\n")
  end
' 2>/dev/null || echo "- (none)")

# Write the report
{
  write_header
  write_sessions_section "$SESSIONS_ROWS"
  write_phase_dist_section "$PHASE_DIST_ROWS"
  write_recovery_section "$RECOVERY_ROWS"
  write_anomalies_section "$ANOMALIES"
} > "$OUTPUT_FILE"

# Cleanup: remove target date entries from input
if [[ "$CLEANUP" == "true" ]]; then
  TEMP_FILE="${INPUT_FILE}.tmp.$$"
  grep -v "\"ts\":\"${TARGET_DATE}" "$INPUT_FILE" > "$TEMP_FILE" 2>/dev/null
  cleanup_exit=$?
  if [[ $cleanup_exit -gt 1 ]]; then
    rm -f "$TEMP_FILE"
    echo "Warning: cleanup grep failed (exit ${cleanup_exit}), original file preserved" >&2
  else
    mv "$TEMP_FILE" "$INPUT_FILE"
  fi
fi

echo "Rollup complete: ${OUTPUT_FILE}"

# Best-effort auto-commit: commit the rollup file immediately so verify workers see a clean state.
# The || fallback is required because set -euo pipefail is active; failure must not abort the script.
git add "$OUTPUT_FILE" 2>/dev/null && \
  git commit -s -m "chore: auto-events-rollup auto-commit $TARGET_DATE [skip ci]" 2>/dev/null && \
  git push origin HEAD 2>/dev/null || \
  echo "Warning: auto-commit failed (non-fatal)" >&2
