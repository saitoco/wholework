#!/bin/bash
# sourceable helper — do not execute directly

WATCHDOG_TIMEOUT_DEFAULT=2700

WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800
WATCHDOG_TIMEOUT_CODE_DEFAULT=1800
WATCHDOG_TIMEOUT_REVIEW_DEFAULT=2000
WATCHDOG_TIMEOUT_MERGE_DEFAULT=600
WATCHDOG_TIMEOUT_ISSUE_DEFAULT=600

load_watchdog_timeout() {
  local script_dir="$1"
  local phase="${2:-}"
  local val phase_default
  phase_default="$WATCHDOG_TIMEOUT_DEFAULT"
  if [ -n "$phase" ]; then
    local phase_upper
    phase_upper=$(echo "$phase" | tr '[:lower:]' '[:upper:]')
    local var_name="WATCHDOG_TIMEOUT_${phase_upper}_DEFAULT"
    eval "phase_default=\"\${${var_name}:-$WATCHDOG_TIMEOUT_DEFAULT}\""
    val=$("$script_dir/get-config-value.sh" "watchdog-timeout-${phase}-seconds" "" 2>/dev/null || echo "")
    if [ -z "$val" ]; then
      val=$("$script_dir/get-config-value.sh" watchdog-timeout-seconds "$phase_default" 2>/dev/null || echo "$phase_default")
    fi
  else
    val=$("$script_dir/get-config-value.sh" watchdog-timeout-seconds "$WATCHDOG_TIMEOUT_DEFAULT" 2>/dev/null || echo "$WATCHDOG_TIMEOUT_DEFAULT")
  fi
  if ! echo "$val" | grep -qE '^[0-9]+$' || [ "$val" -le 0 ]; then
    echo "Warning: invalid watchdog timeout '${val}', using default ${phase_default}" >&2
    val="$phase_default"
  fi
  WATCHDOG_TIMEOUT="$val"
}
