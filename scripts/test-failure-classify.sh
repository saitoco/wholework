#!/bin/bash
# test-failure-classify.sh - Classify test failure output into recovery categories.
#
# Usage: test-failure-classify.sh --log <test-output-file>
#
# Outputs a single category to stdout:
#   snapshot  - snapshot mismatch (repairable, exit 0)
#   mock      - mock/call expectation mismatch (repairable, exit 0)
#   fixture   - literal value mismatch in assertion (repairable, exit 0)
#   logic     - logic error or unrecognized failure (not repairable, exit 1)
#   infra     - infrastructure/environment failure (not repairable, exit 1)
#
# Exit 0: repairable (snapshot/mock/fixture)
# Exit 1: not repairable (infra/logic)
# Bash 3.2+ compatible.

set -uo pipefail

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
      echo "Error: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$LOG_FILE" ]]; then
  echo "Error: --log <test-output-file> is required" >&2
  exit 1
fi

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Error: log file not found: $LOG_FILE" >&2
  exit 1
fi

# Detection priority: infra first (may co-occur with other patterns), then
# snapshot, mock, fixture in order, falling back to logic.

# 1. infra: environment/tooling failures take highest priority
if grep -qiE "command not found|permission denied|No such file or directory|ModuleNotFoundError" "$LOG_FILE" 2>/dev/null; then
  echo "infra"
  exit 1
fi

# 2. snapshot: snapshot mismatch patterns
if grep -qiE "snapshot doesn't match|expected snapshot to be|--update-snapshot" "$LOG_FILE" 2>/dev/null; then
  echo "snapshot"
  exit 0
fi

# 3. mock: call/argument expectation patterns
if grep -qiE "expected calls|not called with expected arguments|mock returned" "$LOG_FILE" 2>/dev/null; then
  echo "mock"
  exit 0
fi

# 4. fixture: literal value comparison mismatch (heuristic: "expected ... got ..." line)
if grep -qiE "expected .+, got .+" "$LOG_FILE" 2>/dev/null; then
  echo "fixture"
  exit 0
fi

# 5. logic: default for unrecognized failures
echo "logic"
exit 1
