#!/usr/bin/env bash
# apply-run-fact-match.sh
# Deterministic autonomy-tier gate for a single run-fact AC match verdict
# (see modules/run-fact-matching.md). This is the only script in the
# collect-run-facts.sh / scan-pending-ac.sh / apply-run-fact-match.sh pipeline
# that writes to GitHub (checkbox + audit-trail comment).
#
# Usage:
#   scripts/apply-run-fact-match.sh --issue <N> --ac <index> \
#     --verdict satisfied|not_satisfied|ambiguous [--evidence <text>] [--dry-run]
#
# Verdict x autonomy-tier gate (exhaustive):
#   satisfied     -> L1: advisory   | L2: auto-check | L3: auto-check
#   ambiguous     -> advisory regardless of tier
#   not_satisfied -> none regardless of tier
#
# Tier resolution: AUTONOMY_TIER env var > `get-config-value.sh autonomy L1`.
# Any value other than L1/L2/L3 falls back to L1 (safest), matching
# modules/detect-config-markers.md's existing autonomy-tier fallback rule.
#
# Fail-safe: an empty, missing, or unrecognized --verdict is treated as
# `ambiguous` (never reaches auto-check) and prints a stderr warning. This is
# deliberate: an unparseable verdict must never accidentally reach auto-check.
#
# Output (stdout):
#   Line 1 is always `action=<auto-check|advisory|none>`.
#   When action=advisory, line 2 is `Recommend: /verify <N> — post-merge AC #<index>
#   may be satisfied by this run (<evidence>)` (modules/autonomy-tier.md path A's
#   `Recommend:` prefix convention — never posted as an Issue comment).
#
# When action=auto-check and --dry-run is not given, in this order:
#   1. `gh-issue-edit.sh <N> --checkbox <index> --check`
#   2. `gh-issue-comment.sh` posts an audit-trail comment whose first line is the
#      marker `<!-- wholework-event: type=run-fact-ac-match phase=run-fact-match
#      issue=<N> ac=<index> verdict=satisfied -->`, followed by human-readable evidence.
#   Either step failing prints a stderr warning and still exits 0 (fail-open —
#   this must never abort /auto).
#
# --dry-run performs no L0 writes; only the action= (and advisory) lines are printed.
#
# Exit codes: 1 on invalid arguments (missing/non-numeric --issue or --ac,
#   unknown option). 0 otherwise, including all fail-open branches above.
#
# bash 3.2+ compatible (macOS system bash): no mapfile, no ${VAR,,}.

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

ISSUE_NUMBER=""
AC_INDEX=""
VERDICT=""
EVIDENCE=""
DRY_RUN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --issue)
      if [ $# -lt 2 ]; then
        echo "Error: --issue requires an argument" >&2
        exit 1
      fi
      ISSUE_NUMBER="$2"
      shift 2
      ;;
    --ac)
      if [ $# -lt 2 ]; then
        echo "Error: --ac requires an argument" >&2
        exit 1
      fi
      AC_INDEX="$2"
      shift 2
      ;;
    --verdict)
      if [ $# -lt 2 ]; then
        echo "Error: --verdict requires an argument" >&2
        exit 1
      fi
      VERDICT="$2"
      shift 2
      ;;
    --evidence)
      if [ $# -lt 2 ]; then
        echo "Error: --evidence requires an argument" >&2
        exit 1
      fi
      EVIDENCE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [ -z "$ISSUE_NUMBER" ] || ! echo "$ISSUE_NUMBER" | grep -qE '^[0-9]+$'; then
  echo "Error: --issue is required and must be a positive integer" >&2
  exit 1
fi
if [ -z "$AC_INDEX" ] || ! echo "$AC_INDEX" | grep -qE '^[0-9]+$'; then
  echo "Error: --ac is required and must be a positive integer" >&2
  exit 1
fi

case "$VERDICT" in
  satisfied | not_satisfied | ambiguous) ;;
  *)
    echo "Warning: unknown verdict '${VERDICT}', treating as ambiguous (fail-safe)." >&2
    VERDICT="ambiguous"
    ;;
esac

TIER="${AUTONOMY_TIER:-}"
if [ -z "$TIER" ]; then
  TIER=$("$SCRIPT_DIR/get-config-value.sh" autonomy L1)
fi
case "$TIER" in
  L1 | L2 | L3) ;;
  *)
    TIER="L1"
    ;;
esac

ACTION="none"
case "$VERDICT" in
  satisfied)
    case "$TIER" in
      L1) ACTION="advisory" ;;
      L2 | L3) ACTION="auto-check" ;;
    esac
    ;;
  ambiguous)
    ACTION="advisory"
    ;;
  not_satisfied)
    ACTION="none"
    ;;
esac

echo "action=${ACTION}"

EVIDENCE_TEXT="${EVIDENCE:-no evidence provided}"

if [ "$ACTION" = "advisory" ]; then
  echo "Recommend: /verify ${ISSUE_NUMBER} — post-merge AC #${AC_INDEX} may be satisfied by this run (${EVIDENCE_TEXT})"
fi

if [ "$ACTION" = "auto-check" ] && [ "$DRY_RUN" = false ]; then
  if ! "$SCRIPT_DIR/gh-issue-edit.sh" "$ISSUE_NUMBER" --checkbox "$AC_INDEX" --check >/dev/null 2>&1; then
    echo "Warning: failed to check AC #${AC_INDEX} on issue #${ISSUE_NUMBER}" >&2
  fi

  COMMENT_FILE=$(mktemp)
  trap 'rm -f "$COMMENT_FILE"' EXIT
  {
    printf '%s\n' "<!-- wholework-event: type=run-fact-ac-match phase=run-fact-match issue=${ISSUE_NUMBER} ac=${AC_INDEX} verdict=satisfied -->"
    printf '%s\n' "Post-merge AC #${AC_INDEX} on issue #${ISSUE_NUMBER} was detected as satisfied by this run's facts."
    printf '%s\n' "${EVIDENCE_TEXT}"
  } > "$COMMENT_FILE"

  if ! "$SCRIPT_DIR/gh-issue-comment.sh" "$ISSUE_NUMBER" "$COMMENT_FILE" >/dev/null 2>&1; then
    echo "Warning: failed to post audit-trail comment on issue #${ISSUE_NUMBER}" >&2
  fi
  rm -f "$COMMENT_FILE"
fi

exit 0
