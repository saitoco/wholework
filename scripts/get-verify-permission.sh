#!/usr/bin/env bash
# Extract **Permission:** declaration from a verify command handler file.
# Outputs "always_allow" or "always_ask". Default is "always_ask" (conservative).
set -euo pipefail

HANDLER_FILE="${1:-}"

if [[ -z "$HANDLER_FILE" ]] || [[ ! -f "$HANDLER_FILE" ]]; then
  echo "always_ask"
  exit 0
fi

raw=$(grep -m1 '^\*\*Permission:\*\*' "$HANDLER_FILE" 2>/dev/null || true)
value=$(echo "$raw" | sed 's/^\*\*Permission:\*\*[[:space:]]*//')

case "$value" in
  always_allow)
    echo "always_allow"
    ;;
  *)
    echo "always_ask"
    ;;
esac
