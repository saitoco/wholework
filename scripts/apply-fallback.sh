#!/bin/bash
# apply-fallback.sh - Tier 2 bash projection of modules/orchestration-fallbacks.md
# Detects known symptom anchors from wrapper logs and dispatches recovery handlers.
#
# Usage: apply-fallback.sh <phase> <issue> --log <log-file>
# Exit 0 on successful recovery, exit 1 on unknown anchor or handler failure.
# Bash 3.2+ compatible.

set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

PHASE="${1:?Usage: apply-fallback.sh <phase> <issue> --log <log-file>}"
ISSUE="${2:?Usage: apply-fallback.sh <phase> <issue> --log <log-file>}"
shift 2

LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --log requires a file path" >&2
        exit 1
      fi
      LOG_FILE="$2"
      shift 2
      ;;
    *)
      echo "Error: Invalid option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$LOG_FILE" ]]; then
  echo "Error: --log <log-file> is required" >&2
  exit 1
fi

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Error: log file not found: $LOG_FILE" >&2
  exit 1
fi

# Detect symptom anchor by inspecting the log file.
# Returns anchor name on stdout; empty string if no known pattern matches.
detect_symptom_anchor() {
  local log="$1"
  # See modules/orchestration-fallbacks.md#dco-signoff-missing-autofix
  if grep -qE "ERROR: missing sign-off" "$log" 2>/dev/null; then
    echo "dco-signoff-missing-autofix"
    return 0
  fi
  # See modules/orchestration-fallbacks.md#gh-pr-list-head-glob (not yet implemented)
  # See modules/orchestration-fallbacks.md#ff-only-merge-fallback (not yet implemented)
  # See modules/orchestration-fallbacks.md#conflict-marker-residual (not yet implemented)
  echo ""
}

# Handler: dco-signoff-missing-autofix
# Amends the latest commit to add Signed-off-by, then force-with-lease pushes.
# Safety guard: refuses to operate on main or master.
apply_dco_signoff_autofix() {
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

  if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
    echo "Error: dco-signoff-missing-autofix refuses to amend on protected branch: $current_branch" >&2
    return 1
  fi

  echo "[apply-fallback] dco-signoff-missing-autofix: amending commit to add Signed-off-by"
  git commit --amend -s --no-edit
  git push --force-with-lease
  echo "[apply-fallback] dco-signoff-missing-autofix: done"
}

symptom_anchor=$(detect_symptom_anchor "$LOG_FILE")

case "$symptom_anchor" in
  dco-signoff-missing-autofix)
    apply_dco_signoff_autofix
    ;;
  *)
    exit 1
    ;;
esac
