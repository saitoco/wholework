#!/bin/bash
# compute-escalation-level.sh
# Compute escalation level for phase/verify or Icebox dwell time.
#
# Usage:
#   scripts/compute-escalation-level.sh <type> <days>
#
# Arguments:
#   type   "verify" or "icebox"
#   days   Non-negative integer (dwell days)
#
# Output (stdout):
#   Escalation level:
#     verify: 0 (0-29d), 1 (30-59d), 2 (60-89d), 3 (90+d)
#     icebox: 0 (0-89d), 1 (90-179d), 2 (180+d)
#
# Exit codes:
#   0  Success
#   1  Invalid arguments

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

TYPE="${1:-}"
DAYS="${2:-}"

if [ -z "$TYPE" ] || [ -z "$DAYS" ]; then
    echo "Usage: $0 <type> <days>" >&2
    exit 1
fi

case "$TYPE" in
    verify|icebox) ;;
    *)
        echo "Error: invalid type '$TYPE' (must be 'verify' or 'icebox')" >&2
        exit 1
        ;;
esac

if ! echo "$DAYS" | grep -qE '^[0-9]+$'; then
    echo "Error: days must be a non-negative integer, got '$DAYS'" >&2
    exit 1
fi

if [ "$TYPE" = "verify" ]; then
    if [ "$DAYS" -ge 90 ]; then
        echo 3
    elif [ "$DAYS" -ge 60 ]; then
        echo 2
    elif [ "$DAYS" -ge 30 ]; then
        echo 1
    else
        echo 0
    fi
elif [ "$TYPE" = "icebox" ]; then
    if [ "$DAYS" -ge 180 ]; then
        echo 2
    elif [ "$DAYS" -ge 90 ]; then
        echo 1
    else
        echo 0
    fi
fi
