#!/bin/bash
# install.sh — Generate .claude/settings.json from template with ${HOME} substitution.
#
# Wholework's permission patterns require absolute paths (Claude Code does not
# expand ${HOME} or ~/ inside permissions.allow), so each user must materialize
# the template with their actual $HOME. Run this script once after `git clone`
# and again whenever .claude/settings.json.template changes.
#
# Usage: ./install.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/.claude/settings.json.template"
OUTPUT="${SCRIPT_DIR}/.claude/settings.json"

if [ ! -f "$TEMPLATE" ]; then
  echo "Error: template not found at $TEMPLATE" >&2
  exit 1
fi

if [ -z "${HOME:-}" ]; then
  echo "Error: \$HOME is not set" >&2
  exit 1
fi

# Substitute ${HOME} with the actual home path.
# Use a sed delimiter (|) that is unlikely to appear in filesystem paths.
# Note: if $HOME itself contains `|` or `\`, the sed command would break —
# but POSIX systems always use `/` in paths, so this is not a practical concern.
#
# Atomic write pattern: write to a temp file first, then rename.
# This prevents a corrupted/empty settings.json if sed fails mid-stream.
TMP_OUTPUT="${OUTPUT}.tmp"
trap 'rm -f "$TMP_OUTPUT"' EXIT
sed "s|\${HOME}|${HOME}|g" "$TEMPLATE" > "$TMP_OUTPUT"
mv "$TMP_OUTPUT" "$OUTPUT"

echo "Generated $OUTPUT from $TEMPLATE"
echo "HOME substituted as: $HOME"
