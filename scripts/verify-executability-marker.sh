#!/usr/bin/env bash
# verify-executability-marker.sh
# Generate and resolve `type=verify-executability` wholework-event markers that
# record /verify Step 8b's Claude-executability judgment for manual post-merge AC.
# See modules/l0-surfaces.md § Machine-Readable Event Marker (type=verify-executability)
# for the marker format and reason vocabulary (SSoT — do not duplicate here).
#
# Usage:
#   verify-executability-marker.sh format <issue> <ac_index> <executable> [reason] [capability=<key>|detail=<text>]
#   verify-executability-marker.sh resolve <issue>
#
# Exit codes: 0 on success. `format` returns 1 on invalid/missing arguments.
# `resolve` returns 0 with empty output when no marker exists; it returns 2
# (distinct from "no marker") when `gh` itself fails, so callers can tell
# "unevaluated" apart from "could not be determined this run".
set -uo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"

usage() {
  cat <<'EOF'
Usage:
  verify-executability-marker.sh format <issue> <ac_index> <executable> [reason] [capability=<key>|detail=<text>]
  verify-executability-marker.sh resolve <issue>
EOF
}

is_positive_int() {
  echo "$1" | grep -qE '^[1-9][0-9]*$'
}

cmd_format() {
  local issue="${1:-}"
  local ac_index="${2:-}"
  local executable="${3:-}"

  if [ -z "$issue" ] || [ -z "$ac_index" ] || [ -z "$executable" ]; then
    echo "Error: format requires <issue> <ac_index> <executable>" >&2
    return 1
  fi
  shift 3 || true

  if ! is_positive_int "$issue"; then
    echo "Error: <issue> must be a positive integer, got: $issue" >&2
    return 1
  fi
  if ! is_positive_int "$ac_index"; then
    echo "Error: <ac_index> must be a positive integer, got: $ac_index" >&2
    return 1
  fi
  if [ "$executable" != "true" ] && [ "$executable" != "false" ]; then
    echo "Error: <executable> must be 'true' or 'false', got: $executable" >&2
    return 1
  fi

  if [ "$executable" = "true" ]; then
    if [ "$#" -gt 0 ]; then
      echo "Error: executable=true does not accept reason/capability/detail arguments" >&2
      return 1
    fi
    echo "<!-- wholework-event: type=verify-executability phase=verify issue=${issue} ac=${ac_index} executable=true -->"
    return 0
  fi

  # executable=false: reason is required.
  if [ "$#" -eq 0 ]; then
    echo "Error: executable=false requires a reason argument" >&2
    return 1
  fi
  local reason="$1"
  shift

  case "$reason" in
    browser-required|external-service-required|production-action-required|subjective-judgment|capability-unavailable|other) ;;
    *)
      echo "Error: unknown reason '$reason'. Must be one of: browser-required, external-service-required, production-action-required, subjective-judgment, capability-unavailable, other" >&2
      return 1
      ;;
  esac

  local capability="" detail=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      capability=*) capability="${1#capability=}" ;;
      detail=*) detail="${1#detail=}" ;;
      *)
        echo "Error: unrecognized argument: $1" >&2
        return 1
        ;;
    esac
    shift
  done

  if [ "$reason" = "capability-unavailable" ] && [ -z "$capability" ]; then
    echo "Error: reason=capability-unavailable requires capability=<key>" >&2
    return 1
  fi
  if [ "$reason" = "other" ] && [ -z "$detail" ]; then
    echo "Error: reason=other requires detail=<text>" >&2
    return 1
  fi
  if [ -n "$capability" ]; then
    case "$capability" in
      *'"'*|*'-->'*|*' '*)
        echo 'Error: capability must not contain a space, double quote, or "-->"' >&2
        return 1
        ;;
    esac
  fi
  if [ -n "$detail" ]; then
    case "$detail" in
      *'"'*|*'-->'*)
        echo 'Error: detail must not contain a double quote or "-->"' >&2
        return 1
        ;;
    esac
  fi

  local line="<!-- wholework-event: type=verify-executability phase=verify issue=${issue} ac=${ac_index} executable=false reason=${reason}"
  if [ -n "$capability" ]; then
    line="${line} capability=${capability}"
  fi
  if [ -n "$detail" ]; then
    line="${line} detail=\"${detail}\""
  fi
  line="${line} -->"
  echo "$line"
  return 0
}

extract_attr() {
  # extract_attr <line> <key> -> value of key=<value> (space-delimited), or empty
  local line="$1" key="$2"
  echo "$line" | grep -oE "${key}=[^ ]*" | head -1 | sed "s/^${key}=//"
}

cmd_resolve() {
  local issue="${1:-}"

  if [ -z "$issue" ]; then
    echo "Error: resolve requires <issue>" >&2
    return 1
  fi
  if ! is_positive_int "$issue"; then
    echo "Error: <issue> must be a positive integer, got: $issue" >&2
    return 1
  fi

  local body
  if ! body="$(gh issue view "$issue" --json comments \
    --jq '[.comments[] | select(.body | contains("<!-- wholework-event: type=verify-executability"))] | sort_by(.createdAt) | .[-1].body // empty' \
    2>/dev/null)"; then
    echo "Error: gh issue view failed for issue $issue (network/auth/rate-limit) — result is unknown, not \"no marker\"" >&2
    return 2
  fi

  if [ -z "$body" ]; then
    return 0
  fi

  echo "$body" | grep -F '<!-- wholework-event: type=verify-executability' | while IFS= read -r line; do
    local ac executable reason capability
    ac="$(extract_attr "$line" "ac")"
    executable="$(extract_attr "$line" "executable")"
    reason="$(extract_attr "$line" "reason")"
    capability="$(extract_attr "$line" "capability")"
    printf '%s\t%s\t%s\t%s\n' "$ac" "$executable" "$reason" "$capability"
  done

  return 0
}

main() {
  local subcmd="${1:-}"

  case "$subcmd" in
    format)
      shift
      cmd_format "$@"
      ;;
    resolve)
      shift
      cmd_resolve "$@"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
