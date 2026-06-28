#!/bin/bash
# append-loop-state-heartbeat.sh - Append a phase-transition heartbeat row to
# `docs/sessions/_daily/loop-state-{DATE}.md` (UTC date).
#
# Best-effort: failures must not block the caller. The script always exits 0
# unless argument parsing itself fails — so callers can invoke it from
# critical hot paths (run-auto-sub.sh phase completion, /auto SKILL.md verify
# completion) without worrying about side effects.
#
# Usage:
#   append-loop-state-heartbeat.sh --issue N --from <phase> --to <phase> [--phase-label <label>]
#
# Where:
#   --issue N           Issue (or PR) number associated with the transition
#   --from <phase>      Source phase name (spec, code, review, merge, ...)
#   --to <phase>        Destination phase name (code, review, merge, verify, ...)
#   --phase-label <s>   Optional Phase column override (defaults to --to value)
#
# File schema (aligned with #703 next-cycle-seed, which writes to the same
# file). New files are created with the unified header so phase-transition and
# next-cycle-seed rows coexist in one append-only log:
#
#   | Time (UTC) | Phase | Event | Detail |
#   |------------|-------|-------|--------|
#   | HH:MM:SS | <to-phase> | phase-transition | #N from→to snapshot:[...] |
#
# Snapshot is `gh issue list --json labels` aggregated by phase/* label,
# omitting `phase/ready` and `phase/done` (transient/terminal).

set -uo pipefail

ISSUE=""
FROM=""
TO=""
PHASE_LABEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)
      ISSUE="${2:-}"
      shift 2
      ;;
    --from)
      FROM="${2:-}"
      shift 2
      ;;
    --to)
      TO="${2:-}"
      shift 2
      ;;
    --phase-label)
      PHASE_LABEL="${2:-}"
      shift 2
      ;;
    *)
      echo "append-loop-state-heartbeat.sh: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Best-effort: validate but never fail loudly to the caller.
if [[ -z "$ISSUE" || -z "$FROM" || -z "$TO" ]]; then
  echo "append-loop-state-heartbeat.sh: WARNING — skip (missing --issue/--from/--to)" >&2
  exit 0
fi

[[ -z "$PHASE_LABEL" ]] && PHASE_LABEL="$TO"

DATE=$(date -u +%Y-%m-%d 2>/dev/null || true)
TS=$(date -u +%H:%M:%S 2>/dev/null || true)

if [[ -z "$DATE" || -z "$TS" ]]; then
  echo "append-loop-state-heartbeat.sh: WARNING — skip (date command failed)" >&2
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
if [[ -z "$SCRIPT_DIR" ]]; then
  echo "append-loop-state-heartbeat.sh: WARNING — skip (cannot resolve script dir)" >&2
  exit 0
fi
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SESSIONS_DAILY_DIR="$REPO_ROOT/docs/sessions/_daily"
FILE="$SESSIONS_DAILY_DIR/loop-state-$DATE.md"

# Aggregate open phase/* label counts via a single gh call. Omits phase/ready
# (transient before code) and phase/done (terminal). Falls back gracefully
# when gh/jq are unavailable or rate-limited.
SNAPSHOT=""
if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  SNAPSHOT=$(gh issue list --state open --json labels --limit 1000 2>/dev/null \
    | jq -r '
        [.[].labels[].name | select(startswith("phase/"))]
        | (
            "issue:" + (([.[] | select(. == "phase/issue")] | length | tostring))
            + " spec:" + (([.[] | select(. == "phase/spec")] | length | tostring))
            + " code:" + (([.[] | select(. == "phase/code")] | length | tostring))
            + " review:" + (([.[] | select(. == "phase/review")] | length | tostring))
            + " verify:" + (([.[] | select(. == "phase/verify")] | length | tostring))
          )
      ' 2>/dev/null) || SNAPSHOT=""
fi
[[ -z "$SNAPSHOT" ]] && SNAPSHOT="snapshot-unavailable"

# Create file with unified header if it does not yet exist.
if [[ ! -f "$FILE" ]]; then
  mkdir -p "$SESSIONS_DAILY_DIR" 2>/dev/null || true
  {
    printf '%s\n' '---'
    printf '%s\n' 'type: report'
    printf '%s\n' "description: Loop state log for $DATE (phase-transition heartbeats and next-cycle seeds)"
    printf '%s\n' "date: $DATE"
    printf '%s\n' '---'
    printf '\n'
    printf '%s\n' "# Loop State — $DATE"
    printf '\n'
    printf '%s\n' '| Time (UTC) | Phase | Event | Detail |'
    printf '%s\n' '|------------|-------|-------|--------|'
  } >> "$FILE" 2>/dev/null || {
    echo "append-loop-state-heartbeat.sh: WARNING — skip (cannot create $FILE)" >&2
    exit 0
  }
fi

# Append row (best-effort). Detail packs issue, transition, and aggregated snapshot.
DETAIL="#${ISSUE} ${FROM}→${TO} snapshot:[${SNAPSHOT}]"

# Dedup: skip if last row already contains this transition (best-effort).
if [[ -f "$FILE" ]]; then
  LAST_ROW=$(tail -1 "$FILE" 2>/dev/null || true)
  if [[ -n "$LAST_ROW" && "$LAST_ROW" == *"$DETAIL"* ]]; then
    exit 0
  fi
fi

printf '| %s | %s | %s | %s |\n' "$TS" "$PHASE_LABEL" "phase-transition" "$DETAIL" >> "$FILE" 2>/dev/null || true

exit 0
