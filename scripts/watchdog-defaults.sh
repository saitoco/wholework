#!/bin/bash
# sourceable helper — do not execute directly

WATCHDOG_TIMEOUT_DEFAULT=2700
# Base 2700 raised from 1800 following the #556 spike (Fable 5, 2026-06-13):
# analytical/multi-paragraph prompts showed ~120s silent windows even in a
# short-form spike, and hard production tasks (spec design, PR body
# composition, review synthesis) were extrapolated at 600-2000s — see
# docs/reports/watchdog-recovery-strategy.md § Fable 5 long-turn findings.

# Phase-specific watchdog timeouts (in seconds).
# Calibrated against typical silent windows observed under the dominant parent
# orchestrator model. Lower-latency parent models (e.g. Fable 5) can use tighter
# values; high-effort triage under Sonnet 5 / Opus 4.8 requires more headroom.
#
# Recalibration guidance:
#   - If watchdog kills become frequent on a phase, raise that phase's *_DEFAULT
#   - If true-stall detection becomes too slow, consider per-effort tuning (Icebox #596)
#   - Empirical baseline: docs/reports/auto-session-performance-2026-06-13.md (Fable 5),
#     docs/reports/auto-batch-list-mode-2026-06-14.md (Sonnet 4.6)
#   - CODE_DEFAULT / REVIEW_DEFAULT raised ~1.3x (Sonnet 5 tokenizer recalibration,
#     #903, docs/reports/sonnet-5-watchdog-recalibration.md): wall-clock samples
#     recorded p95/max close to the prior 80% margin threshold under the Sonnet 5
#     tokenizer (#878 measured 1.3-1.4x more tokens for equivalent content)
WATCHDOG_TIMEOUT_SPEC_DEFAULT=1800
WATCHDOG_TIMEOUT_CODE_DEFAULT=4680
WATCHDOG_TIMEOUT_REVIEW_DEFAULT=2600
WATCHDOG_TIMEOUT_MERGE_DEFAULT=600
WATCHDOG_TIMEOUT_ISSUE_DEFAULT=1200

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
