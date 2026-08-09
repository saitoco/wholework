#!/bin/bash
# check-known-events-firing.sh
#
# Verifies that every event name in scripts/opportunistic-search.sh's KNOWN_EVENTS
# list has at least one real invocation site under scripts/, skills/, or modules/.
# A plain substring grep for "--event <name>" also matches shell comment lines and
# echo/printf usage-string literals that mention the name as a documentation example
# rather than an actual call site, so this script excludes both before deciding
# whether an event has a firing site.
#
# Usage:
#   scripts/check-known-events-firing.sh
#
# Exit codes:
#   0 - every KNOWN_EVENTS entry has at least one real invocation site
#   1 - one or more KNOWN_EVENTS entries have no real invocation site (names printed to stdout)
#   2 - KNOWN_EVENTS could not be read from the source file

set -u

SOURCE_FILE="scripts/opportunistic-search.sh"
SEARCH_DIRS="scripts/ skills/ modules/"

if [ ! -f "$SOURCE_FILE" ]; then
  echo "Error: $SOURCE_FILE not found" >&2
  exit 2
fi

KNOWN_EVENTS_LINE=$(grep -m1 '^KNOWN_EVENTS=' "$SOURCE_FILE")
if [ -z "$KNOWN_EVENTS_LINE" ]; then
  echo "Error: KNOWN_EVENTS assignment not found in $SOURCE_FILE" >&2
  exit 2
fi

KNOWN_EVENTS=$(printf '%s\n' "$KNOWN_EVENTS_LINE" | sed -E 's/^KNOWN_EVENTS="([^"]*)".*/\1/')
if [ -z "$KNOWN_EVENTS" ]; then
  echo "Error: could not parse KNOWN_EVENTS value from $SOURCE_FILE" >&2
  exit 2
fi

MISSING=""

for event_name in $KNOWN_EVENTS; do
  found=false
  MATCHES=$(grep -rn -- "--event $event_name" $SEARCH_DIRS 2>/dev/null || true)
  if [ -n "$MATCHES" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      # Strip the "path:lineno:" prefix (relative paths and line numbers are colon-free).
      content="${line#*:}"
      content="${content#*:}"
      # Left-trim whitespace.
      trimmed="${content#"${content%%[![:space:]]*}"}"
      case "$trimmed" in
        "#"*) continue ;;
      esac
      if printf '%s\n' "$content" | grep -qE '\b(echo|printf)\b'; then
        continue
      fi
      found=true
      break
    done <<< "$MATCHES"
  fi
  if [ "$found" = false ]; then
    MISSING="$MISSING $event_name"
  fi
done

MISSING="${MISSING# }"

if [ -n "$MISSING" ]; then
  echo "Missing firing site for event(s): $MISSING"
  exit 1
fi

exit 0
