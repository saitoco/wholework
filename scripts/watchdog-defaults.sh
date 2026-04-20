#!/bin/bash
# sourceable helper — do not execute directly

WATCHDOG_TIMEOUT_DEFAULT=1800

load_watchdog_timeout() {
  local script_dir="$1"
  local val
  val=$("$script_dir/get-config-value.sh" watchdog-timeout-seconds "$WATCHDOG_TIMEOUT_DEFAULT" 2>/dev/null || echo "$WATCHDOG_TIMEOUT_DEFAULT")
  if ! echo "$val" | grep -qE '^[0-9]+$' || [[ "$val" -le 0 ]]; then
    echo "Warning: invalid watchdog-timeout-seconds '${val}', using default ${WATCHDOG_TIMEOUT_DEFAULT}" >&2
    val="$WATCHDOG_TIMEOUT_DEFAULT"
  fi
  WATCHDOG_TIMEOUT="$val"
}
