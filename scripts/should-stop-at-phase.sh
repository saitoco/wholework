#!/bin/bash
# should-stop-at-phase.sh - phase-order-based stop-at gate predicate.
#
# Usage: should-stop-at-phase.sh <completed-phase> [stop-at-value]
#   <completed-phase>: phase just completed (spec/code/review/merge/verify)
#   [stop-at-value]: optional; when omitted, resolved from .wholework.yml via
#                     get-config-value.sh auto-stop-at (fallback: verify)
#
# Exit codes: 0 = stop (do not proceed past <completed-phase>)
#             1 = continue (proceed to the next phase)
#             2 = usage error (unknown/empty <completed-phase>)
#
# No stdout output (callers use this as an `if` condition, not a value producer).
# Fail-open: an unknown/empty stop-at value or a get-config-value.sh failure both
# fall back to "verify" (= full pipeline, i.e. continue), matching the fail-open
# behavior of the direct AUTO_STOP_AT comparisons this helper replaces.

set -uo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

_phase_order() {
  case "$1" in
    spec) echo 1 ;;
    code) echo 2 ;;
    review) echo 3 ;;
    merge) echo 4 ;;
    verify) echo 5 ;;
    *) echo "" ;;
  esac
}

completed_phase="${1:-}"
completed_order="$(_phase_order "$completed_phase")"
if [[ -z "$completed_order" ]]; then
  echo "should-stop-at-phase.sh: unknown completed phase: '${completed_phase}'" >&2
  exit 2
fi

stop_at="${2:-}"
if [[ -z "$stop_at" ]]; then
  stop_at="$("$SCRIPT_DIR/get-config-value.sh" auto-stop-at verify 2>/dev/null || echo verify)"
fi

stop_order="$(_phase_order "$stop_at")"
if [[ -z "$stop_order" ]]; then
  stop_order="$(_phase_order verify)"
fi

if [[ "$stop_order" -le "$completed_order" ]]; then
  exit 0
else
  exit 1
fi
