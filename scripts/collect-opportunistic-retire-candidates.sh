#!/usr/bin/env bash
# Aggregate opportunistic_verify_result events from committed docs/sessions/*/events.jsonl
# and report acceptance conditions whose most recent judgments are all SKIP as retire
# candidates, for /audit stats --retention Section 11 (Issue #1236).
#
# Output format: <issue>\t<ac_index>\t<skill>\t<trailing_skip_count>\t<total_observations>
# (tab-separated, one per line, sorted by trailing_skip_count descending). Empty output
# (and exit 0) when SESSIONS_DIR does not exist, no events.jsonl files are found, or no
# group clears --threshold.
#
# Grouping key: (issue, ac_index). Within a group, events are sorted by ts ascending and
# the trailing SKIP streak is counted from the end (a group whose most recent judgment is
# PASS or FAIL has trailing_skip_count=0, even if earlier judgments were SKIP -- a non-SKIP
# result resets the streak). `skill` in the output is the group's most recent event's value.

set -euo pipefail

SESSIONS_DIR="docs/sessions"
THRESHOLD=1

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
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      SESSIONS_DIR="$1"
      shift
      ;;
  esac
done

if [ ! -d "$SESSIONS_DIR" ]; then
  exit 0
fi

EVENT_FILES=()
while IFS= read -r f; do
  EVENT_FILES+=("$f")
done < <(find "$SESSIONS_DIR" -mindepth 2 -maxdepth 2 -name events.jsonl 2>/dev/null)

if [ "${#EVENT_FILES[@]}" -eq 0 ]; then
  exit 0
fi

cat "${EVENT_FILES[@]}" | jq -rs --argjson threshold "$THRESHOLD" '
  map(select(.event == "opportunistic_verify_result"))
  | group_by([.issue, .ac_index])
  | map(
      (sort_by(.ts)) as $sorted
      | {
          issue: $sorted[0].issue,
          ac_index: $sorted[0].ac_index,
          skill: $sorted[-1].skill,
          total: ($sorted | length),
          trailing: (
            $sorted
            | reverse
            | reduce .[] as $r ({stop:false, count:0};
                if .stop then .
                elif $r.result == "SKIP" then .count += 1
                else .stop = true end
              )
            | .count
          )
        }
    )
  | map(select(.trailing >= $threshold))
  | sort_by(-.trailing)
  | .[]
  | [.issue, .ac_index, .skill, .trailing, .total]
  | @tsv
'
