#!/usr/bin/env bash
# collect-run-facts.sh
# Collect structured facts about an /auto run from .tmp/auto-events.jsonl for
# reconciliation against pending post-merge acceptance conditions
# (see modules/run-fact-matching.md).
#
# Usage:
#   scripts/collect-run-facts.sh [--session <session-id>] [--issue <N>] [--no-github]
#
# Session resolution order: --session <id> > AUTO_SESSION_ID env var >
#   .tmp/auto-session-current pointer file. Exits 1 if none resolve.
#
# --issue <N> narrows output to a single Issue (used by the single-issue /auto
#   route). Omit for the batch route to collect facts for every Issue in the
#   session.
#
# Output: single-line JSON {"session_id":"<id>","mode":"<batch|single|unknown>","issues":[{...}, ...]}
#   on stdout. When ${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl} does not exist, or the session has
#   no events, prints {"session_id":"<id>","mode":"unknown","issues":[]} and exits 0 (fail-open).
#
# mode (top-level): batch | single | unknown. Resolution ladder, evaluated against ALL session
#   events *before* --issue narrowing (so mode does not depend on whether --issue was passed):
#   (a) .tmp/auto-session-<session-id>.json's "mode" key, when "batch" or "single"
#   (b) event fallback: >=2 distinct non-zero issue numbers with a sub_start event => "batch",
#       else "single" (only reached when the session has at least one event)
#   (c) "unknown" when the session has no events (events log absent, or session id not found)
#
# Per-issue fields:
#   number         - issue number (int)
#   size           - Size label (XS/S/M/L/XL), or "" if unresolved
#                    (or when --no-github is set and no size event exists)
#   route          - pr | patch | operate | unknown (derived from code-pr / code-patch phase
#                    presence; code-patch is further probed for an operate-route marker comment
#                    — see below. Skipped when --no-github is set, so route stays "patch" then)
#   pr             - PR number seen in this issue's events, or null
#   pr_state       - `gh pr view <pr> --json state` result, or "" when unavailable
#   phases         - [{"name":...,"status":"complete"|"started","backfilled":bool}]
#   anomalies      - counts for the exhaustive event set: recovery, watchdog_kill,
#                    manual_intervention, concurrent_commit_detected, code_retry_fire
#   recovery_tiers - sorted unique array of recovery event tiers (1/2/3) seen for this issue,
#                    or [] if none. anomalies.recovery keeps its existing count-only semantics.
#   fact_tokens    - token array for scan-pending-ac.sh's pre-filtering. Deliberately
#                    excludes the generic "/auto" token: measured against 414 pending
#                    post-merge AC (docs/spec/issue-1157-run-fact-ac-match.md § population),
#                    "/auto" alone matched 84 of them and made the pre-filter a no-op. Also
#                    excludes the generic "single" mode token for the same reason (Issue #1171).
#                    Also excludes bare phase-name tokens (e.g. "issue", "spec", "code-pr",
#                    "code-patch", "review", "merge", "verify"): AC condition text almost always
#                    mentions these phase names in prose, so a bare phase-name token matched
#                    nearly every candidate and made the pre-filter a near no-op (Issue #1238).
#                    Only the wrapper_for()-mapped script name (e.g. "run-issue.sh") is kept per
#                    phase; "verify" has no wrapper script (see modules/run-fact-matching.md) and
#                    so contributes no token at all after this change.
#
# operate route detection: when an issue's route resolves to "patch" (and --no-github is not
#   set), probe the Issue's comments for a `type=execution-log` or `type=execution-plan`
#   wholework-event marker (the same signature `reconcile-phase-state.sh`'s _operate_signal_ts()
#   uses). If the marker's createdAt is newer than this issue's first event timestamp in this
#   run (freshness gate — guards against a stale marker from a prior operate cycle mislabeling a
#   later patch run), route is reported as "operate" instead of "patch".
#
# --no-github suppresses all `gh` calls (get-issue-size.sh fallback, `gh pr view`, the operate
# marker probe), for hermetic bats execution. Under --no-github, operate route can never be
# detected and route stays "patch" for diff-less runs.
#
# bash 3.2+ compatible (macOS system bash): no mapfile, no ${VAR,,}.

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

SESSION_ARG=""
ISSUE_FILTER=""
NO_GITHUB=false

while [ $# -gt 0 ]; do
  case "$1" in
    --session)
      if [ $# -lt 2 ]; then
        echo "Error: --session requires an argument" >&2
        exit 1
      fi
      SESSION_ARG="$2"
      shift 2
      ;;
    --issue)
      if [ $# -lt 2 ]; then
        echo "Error: --issue requires an argument" >&2
        exit 1
      fi
      ISSUE_FILTER="$2"
      shift 2
      ;;
    --no-github)
      NO_GITHUB=true
      shift
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [ -n "$ISSUE_FILTER" ] && ! echo "$ISSUE_FILTER" | grep -qE '^[0-9]+$'; then
  echo "Error: --issue must be a positive integer: $ISSUE_FILTER" >&2
  exit 1
fi

# Session resolution: --session > AUTO_SESSION_ID env > .tmp/auto-session-current pointer
SESSION_ID="$SESSION_ARG"
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="${AUTO_SESSION_ID:-}"
fi
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$(cat .tmp/auto-session-current 2>/dev/null || true)"
fi
if [ -z "$SESSION_ID" ]; then
  echo "Error: could not resolve session id (--session / AUTO_SESSION_ID / .tmp/auto-session-current all empty)" >&2
  exit 1
fi

EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"

if [ ! -f "$EVENTS_LOG" ]; then
  printf '{"session_id":"%s","mode":"unknown","issues":[]}\n' "$SESSION_ID"
  exit 0
fi

SESSION_EVENTS=$(jq -c --arg sid "$SESSION_ID" 'select(.session_id == $sid)' "$EVENTS_LOG" 2>/dev/null) || {
  echo "Error: failed to parse ${EVENTS_LOG} as JSONL" >&2
  exit 1
}

if [ -z "$SESSION_EVENTS" ]; then
  printf '{"session_id":"%s","mode":"unknown","issues":[]}\n' "$SESSION_ID"
  exit 0
fi

ISSUE_NUMBERS=$(printf '%s\n' "$SESSION_EVENTS" | jq -r '.issue' 2>/dev/null | sort -n -u) || {
  echo "Error: failed to enumerate issue numbers from session events" >&2
  exit 1
}

if [ -n "$ISSUE_FILTER" ]; then
  ISSUE_NUMBERS=$(printf '%s\n' "$ISSUE_NUMBERS" | awk -v n="$ISSUE_FILTER" '$0 == n')
fi

# Session-level mode resolution ladder. Evaluated against $SESSION_EVENTS (all session events,
# before the --issue narrowing above) so mode does not depend on whether --issue was passed.
MODE=""
SESSION_META_FILE=".tmp/auto-session-${SESSION_ID}.json"
if [ -f "$SESSION_META_FILE" ]; then
  META_MODE=$(jq -r '.mode // ""' "$SESSION_META_FILE" 2>/dev/null || true)
  case "$META_MODE" in
    batch|single) MODE="$META_MODE" ;;
  esac
fi
if [ -z "$MODE" ]; then
  BATCH_ISSUE_COUNT=$(printf '%s\n' "$SESSION_EVENTS" | jq -s '[.[] | select(.event == "sub_start" and .issue != 0) | .issue] | unique | length')
  if [ "$BATCH_ISSUE_COUNT" -ge 2 ]; then
    MODE="batch"
  else
    MODE="single"
  fi
fi

JQ_PASS1='
def wrapper_for(p):
  {"issue":"run-issue.sh","spec":"run-spec.sh","code-pr":"run-code.sh","code-patch":"run-code.sh","review":"run-review.sh","merge":"run-merge.sh"}[p];
def phase_entry($events; $p):
  ($events | map(select(.phase == $p))) as $pevs
  | ($pevs | map(select(.event == "phase_complete")) | length > 0) as $complete
  | ($pevs | map(select(.event == "phase_complete" and .backfilled == true)) | length > 0) as $backfilled
  | {name: $p, status: (if $complete then "complete" else "started" end), backfilled: $backfilled};
. as $events
| ($events | map(select(.phase != null) | .phase) | unique) as $phase_names
| {
    pr: (($events | map(select(has("pr")) | .pr) | last) // null),
    size_candidate: (
      ($events | map(select(.event == "size_refresh") | .to) | last)
      // ($events | map(select(.event == "sub_start" and .size != "") | .size) | last)
      // null
    ),
    route: (
      if ($events | map(select(.phase == "code-pr")) | length) > 0 then "pr"
      elif ($events | map(select(.phase == "code-patch")) | length) > 0 then "patch"
      else "unknown" end
    ),
    first_ts: ($events | map(.ts) | min),
    recovery_tiers: ([$events[] | select(.event == "recovery") | .tier // empty | tonumber?] | unique),
    phases: ($phase_names | map(phase_entry($events; .))),
    anomalies: (
      ["recovery","watchdog_kill","manual_intervention","concurrent_commit_detected","code_retry_fire"]
      | map(. as $name | {($name): ($events | map(select(.event == $name)) | length)})
      | add
    )
  }
'

JQ_PASS2='
def wrapper_for(p):
  {"issue":"run-issue.sh","spec":"run-spec.sh","code-pr":"run-code.sh","code-patch":"run-code.sh","review":"run-review.sh","merge":"run-merge.sh"}[p];
{
  number: $n,
  size: $size,
  route: $route,
  pr: $partial.pr,
  pr_state: $pr_state,
  phases: $partial.phases,
  anomalies: $partial.anomalies,
  recovery_tiers: $partial.recovery_tiers
}
| . + {
    fact_tokens: (
      (if .route != "unknown" then [(.route + " route")] else [] end)
      + (if .size != "" then [("Size " + .size)] else [] end)
      + ((.phases | map(.name)) as $names
         | ($names | map(wrapper_for(.)) | map(select(. != null))))
      + (if .pr != null then [("#" + (.pr | tostring))] else [] end)
      + (.anomalies | to_entries | map(select(.value >= 1) | .key))
      + (.recovery_tiers | map("tier " + (. | tostring)))
      + (if $mode == "batch" then ["batch"] else [] end)
    )
  }
'

ISSUES_JSON="[]"

for N in $ISSUE_NUMBERS; do
  [ -z "$N" ] && continue
  [ "$N" = "0" ] && continue # issue=0 is the sentinel for non-issue-scoped events

  ISSUE_EVENTS=$(printf '%s\n' "$SESSION_EVENTS" | jq -c --argjson n "$N" 'select(.issue == $n)') || {
    echo "Error: failed to filter events for issue #${N}" >&2
    exit 1
  }

  FACTS_PARTIAL=$(printf '%s\n' "$ISSUE_EVENTS" | jq -s "$JQ_PASS1") || {
    echo "Error: failed to compute run facts for issue #${N}" >&2
    exit 1
  }

  SIZE=$(printf '%s' "$FACTS_PARTIAL" | jq -r '.size_candidate // ""')
  if [ -z "$SIZE" ] && [ "$NO_GITHUB" = false ]; then
    SIZE=$("$SCRIPT_DIR/get-issue-size.sh" "$N" 2>/dev/null || true)
  fi

  PR_NUMBER=$(printf '%s' "$FACTS_PARTIAL" | jq -r '.pr // ""')
  PR_STATE=""
  if [ -n "$PR_NUMBER" ] && [ "$NO_GITHUB" = false ]; then
    PR_STATE=$(gh pr view "$PR_NUMBER" --json state -q .state 2>/dev/null || true)
  fi

  # Operate route probe: only meaningful when route is "patch" (operate route always emits
  # code-patch phase events — see reconcile-phase-state.sh's identical assumption).
  ROUTE=$(printf '%s' "$FACTS_PARTIAL" | jq -r '.route')
  FIRST_TS=$(printf '%s' "$FACTS_PARTIAL" | jq -r '.first_ts')
  if [ "$ROUTE" = "patch" ] && [ "$NO_GITHUB" = false ]; then
    OPERATE_TS=$(gh issue view "$N" --json comments \
      --jq "[.comments[] | select(.body | contains(\"<!-- wholework-event: type=execution-log phase=code issue=${N}\") or contains(\"<!-- wholework-event: type=execution-plan phase=code issue=${N}\")) | .createdAt] | sort | last // empty" \
      2>/dev/null) || OPERATE_TS=""
    case "$OPERATE_TS" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) ;;
      *) OPERATE_TS="" ;;
    esac
    if [ -n "$OPERATE_TS" ] && [ "$OPERATE_TS" \> "$FIRST_TS" ]; then
      ROUTE="operate"
    fi
  fi

  ISSUE_FACT=$(jq -n \
    --argjson n "$N" \
    --arg size "$SIZE" \
    --arg route "$ROUTE" \
    --arg pr_state "$PR_STATE" \
    --arg mode "$MODE" \
    --argjson partial "$FACTS_PARTIAL" \
    "$JQ_PASS2") || {
    echo "Error: failed to assemble fact object for issue #${N}" >&2
    exit 1
  }

  ISSUES_JSON=$(printf '%s' "$ISSUES_JSON" | jq --argjson fact "$ISSUE_FACT" '. += [$fact]') || {
    echo "Error: failed to append fact object for issue #${N}" >&2
    exit 1
  }
done

jq -n --arg sid "$SESSION_ID" --arg mode "$MODE" --argjson issues "$ISSUES_JSON" '{session_id: $sid, mode: $mode, issues: $issues}' -c
