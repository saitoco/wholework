#!/bin/bash
# install.sh — Sync .claude/settings.json, marketplace, and plugin (run after clone or pull).
#
# Wholework's permission patterns require absolute paths (Claude Code does not
# expand ${HOME} or ~/ inside permissions.allow), so each user must materialize
# the template with their actual $HOME. Run this script once after `git clone`
# and again whenever .claude/settings.json.template changes.
#
# Usage: ./install.sh [--no-plugin] [--marketplace NAME]
#
#   --no-plugin          Skip marketplace and plugin update steps (settings.json only)
#   --marketplace NAME   Override marketplace name (default: saitoco-wholework)

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/.claude/settings.json.template"
OUTPUT="${SCRIPT_DIR}/.claude/settings.json"

# Argument parser
MARKETPLACE="saitoco-wholework"
NO_PLUGIN=false

while [ $# -gt 0 ]; do
  case "$1" in
    --no-plugin)
      NO_PLUGIN=true
      shift
      ;;
    --marketplace)
      if [ $# -lt 2 ]; then
        echo "Error: --marketplace requires a NAME argument" >&2
        exit 1
      fi
      MARKETPLACE="$2"
      shift 2
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      echo "Usage: ./install.sh [--no-plugin] [--marketplace NAME]" >&2
      exit 1
      ;;
  esac
done

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

# Plugin update (skipped when --no-plugin is specified)
if [ "$NO_PLUGIN" = false ]; then
  if command -v claude > /dev/null 2>&1; then
    echo "Updating marketplace: $MARKETPLACE"
    claude plugin marketplace update "$MARKETPLACE" || echo "Warning: marketplace update failed (continuing)"
    echo "Updating plugin: wholework@${MARKETPLACE}"
    claude plugin update "wholework@${MARKETPLACE}" || echo "Warning: plugin update failed (continuing)"
  else
    echo "Warning: 'claude' CLI not found — skipping marketplace and plugin update"
  fi
fi

echo ""
echo "Done. Restart Claude Code to apply the updated plugin."
