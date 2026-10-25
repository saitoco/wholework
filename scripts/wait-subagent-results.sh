#!/bin/bash
# wait-subagent-results.sh - Bounded foreground wait for sub-agent result files
#
# Usage: wait-subagent-results.sh [--interval <sec>] <timeout-sec> <result-file>...
#
# Blocks in the foreground until every <result-file> exists as a non-empty regular file,
# or until <timeout-sec> seconds have passed, whichever comes first. Used by
# skills/review/SKILL.md Step 10 ("Wait limit"): one call per fan-out, so that a sub-agent
# result file written as the sub-agent's last action has a bounded time to appear before the
# orchestrator substitutes for the sub-agent (Issue #1551).
#
# Options:
#   --interval <sec>   Check interval in seconds, an integer >= 1 (default: 5). For tests.
#
# Arguments:
#   <timeout-sec>      Maximum wait in seconds, a non-negative integer. Values above 540
#                      (inside the Bash tool's 600000 ms ceiling) are clamped to 540 with a
#                      warning on stderr. 0 checks once and never sleeps.
#   <result-file>...   One or more result file paths. A path must not contain a newline.
#
# Output:
#   stdout  One line per file, in argument order, printed once when the wait ends:
#             ready <path>     the file exists and is not empty
#             missing <path>   anything else (absent, empty, a directory, an empty path)
#   stderr  Last line: wait-subagent-results: <ready>/<total> ready after <N>s (limit <L>s)
#
# Exit codes:
#   0  every file is ready
#   1  usage error (stdout stays empty)
#   2  the limit was reached with at least one file still missing
#
# Bash 3.2+ compatible.
set -euo pipefail

MAX_TIMEOUT_SEC=540
DEFAULT_INTERVAL_SEC=5
# Digit strings longer than this are clamped before arithmetic so that a huge value cannot
# overflow and abort the script under errexit.
MAX_DIGITS=5

usage() {
  echo "Usage: wait-subagent-results.sh [--interval <sec>] <timeout-sec> <result-file>..." >&2
}

die_usage() {
  echo "wait-subagent-results: $1" >&2
  usage
  exit 1
}

# to_int VALUE
#   Prints VALUE (digits only) as a decimal integer, 10#-interpreted so that a leading 0 is
#   never read as octal. A value with more than MAX_DIGITS significant digits prints as
#   99999 (callers clamp anyway).
to_int() {
  local v="$1"
  while [[ "${#v}" -gt 1 && "${v:0:1}" == "0" ]]; do
    v="${v:1}"
  done
  if [[ "${#v}" -gt "$MAX_DIGITS" ]]; then
    echo 99999
    return 0
  fi
  echo "$((10#$v))"
}

interval="$DEFAULT_INTERVAL_SEC"
while [[ $# -gt 0 && "$1" == --* ]]; do
  case "$1" in
    --interval)
      if [[ $# -lt 2 ]]; then
        die_usage "--interval requires a value"
      fi
      if [[ ! "$2" =~ ^[0-9]+$ ]]; then
        die_usage "--interval must be an integer >= 1 (got '$2')"
      fi
      interval="$(to_int "$2")"
      if [[ "$interval" -lt 1 ]]; then
        die_usage "--interval must be an integer >= 1 (got '$2')"
      fi
      shift 2
      ;;
    *)
      die_usage "unknown option '$1'"
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  die_usage "timeout-sec is required"
fi
timeout_given="$1"
shift
if [[ ! "$timeout_given" =~ ^[0-9]+$ ]]; then
  die_usage "timeout-sec must be a non-negative integer (got '$timeout_given')"
fi
timeout_sec="$(to_int "$timeout_given")"
if [[ "$timeout_sec" -gt "$MAX_TIMEOUT_SEC" ]]; then
  echo "wait-subagent-results: Warning: timeout $timeout_given clamped to $MAX_TIMEOUT_SEC" >&2
  timeout_sec="$MAX_TIMEOUT_SEC"
fi

if [[ $# -lt 1 ]]; then
  die_usage "at least one result file is required"
fi
for path in "$@"; do
  case "$path" in
    *$'\n'*) die_usage "path must not contain a newline" ;;
  esac
done

total=$#
states=()
ready_count=0

# evaluate: refresh states[] and ready_count for the files given on the command line.
evaluate() {
  local path
  states=()
  ready_count=0
  for path in "$@"; do
    if [ -f "$path" ] && [ -s "$path" ]; then
      states[${#states[@]}]="ready"
      ready_count=$((ready_count + 1))
    else
      states[${#states[@]}]="missing"
    fi
  done
}

# The limit is enforced by the clock ($SECONDS), not by counting sleeps, so a failing or
# interrupted sleep cannot extend the wait.
SECONDS=0
while true; do
  evaluate "$@"
  if [[ "$ready_count" -eq "$total" ]]; then
    break
  fi
  elapsed="$SECONDS"
  if [[ "$elapsed" -ge "$timeout_sec" ]]; then
    break
  fi
  remaining=$((timeout_sec - elapsed))
  nap="$interval"
  if [[ "$remaining" -lt "$nap" ]]; then
    nap="$remaining"
  fi
  sleep "$nap" || true
done

i=0
for path in "$@"; do
  printf '%s %s\n' "${states[$i]}" "$path"
  i=$((i + 1))
done
echo "wait-subagent-results: ${ready_count}/${total} ready after ${SECONDS}s (limit ${timeout_sec}s)" >&2

if [[ "$ready_count" -eq "$total" ]]; then
  exit 0
fi
exit 2
