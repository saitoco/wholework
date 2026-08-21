#!/usr/bin/env bash
# check-config-schema.sh
# Warns about unknown/typo'd top-level keys in .wholework.yml by cross-referencing
# them against modules/detect-config-markers.md's Marker Definition Table (the SSoT
# for known config keys). Runs in CI (see .github/workflows/test.yml) alongside
# check-forbidden-expressions.sh / check-bare-bracket-assertions.sh.
#
# Scope: top-level keys only. Nested child keys (e.g. capabilities.browser) are
# out of scope — see docs/tech.md § Config Schema Validation.
#
# bash 3.2+ compatible: no associative arrays, no mapfile.
set -euo pipefail

SCRIPT_DIR="${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
MARKERS_FILE="$SCRIPT_DIR/../modules/detect-config-markers.md"
CONFIG_FILE="${WHOLEWORK_CONFIG_PATH:-.wholework.yml}"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$MARKERS_FILE" ]; then
  exit 0
fi

# Extract known top-level keys from the Marker Definition Table: rows starting
# with "| `", pull the backtick-quoted key, drop anything from "." onward to
# normalize nested keys (capabilities.browser -> capabilities) to their
# top-level name, then dedup.
KNOWN_KEYS=$(awk '
  /^### Marker Definition Table/ { found=1; next }
  found && /^\|/ { intable=1; if (/^\| `/) print; next }
  intable && !/^\|/ { exit }
' "$MARKERS_FILE" \
  | sed -E 's/^\| `([^`]+)`.*/\1/' \
  | sed -E 's/\..*//' \
  | sort -u)

# Extract actual top-level keys from .wholework.yml: unindented "key:" lines.
# Whitespace between the key name and the colon (e.g. "autonomy   : L3") is
# tolerated so incidental formatting doesn't defeat extraction. Comment lines
# and indented (nested) child key lines are excluded by the anchored regex.
ACTUAL_KEYS=$(grep -E '^[A-Za-z0-9_-]+[[:space:]]*:' "$CONFIG_FILE" | sed -E 's/^([A-Za-z0-9_-]+)[[:space:]]*:.*/\1/' || true)

VIOLATIONS=0

for KEY in $ACTUAL_KEYS; do
  if ! printf '%s\n' "$KNOWN_KEYS" | grep -Fxq "$KEY"; then
    echo "Unknown key '$KEY' in $CONFIG_FILE (not found in modules/detect-config-markers.md's Marker Definition Table). Check for a typo, or add it to the table if intentional."
    VIOLATIONS=1
  fi
done

# Catch unindented, non-comment lines that look like a "key: value" entry but
# weren't recognized as a plain key name above (e.g. quoted/backticked keys,
# keys with metacharacters). These can't be matched against the known-key
# list, but must still surface a warning instead of silently passing through.
UNRECOGNIZED_LINES=$(grep -E '^[^#[:space:]].*:' "$CONFIG_FILE" | grep -vE '^[A-Za-z0-9_-]+[[:space:]]*:' || true)
if [ -n "$UNRECOGNIZED_LINES" ]; then
  while IFS= read -r LINE; do
    echo "Unrecognized top-level key syntax in $CONFIG_FILE: '$LINE' (expected a plain key name like 'key: value'; cannot be checked against modules/detect-config-markers.md's Marker Definition Table)."
    VIOLATIONS=1
  done <<< "$UNRECOGNIZED_LINES"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  exit 1
fi
