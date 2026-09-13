#!/usr/bin/env bash
# Verify that a SKILL.md's <!-- skill-body-sha: H --> marker matches the
# content hash actually computed from the file, catching edits (renames,
# word substitutions, same-line-count rewrites) that keep the line count
# marker in sync but silently drift the content marker. See docs/spec/issue-1468-*.md.
#
# Usage: check-skill-body-hash.sh [target-file]
#   target-file: file to check (default: skills/verify/SKILL.md)
# Exit codes: 0 = match (or target file absent, fail-open), 1 = mismatch or marker absent
#
# bash 3.2+ compatible: no associative arrays, no mapfile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_FILE="${1:-$SCRIPT_DIR/../skills/verify/SKILL.md}"

if [ ! -f "$TARGET_FILE" ]; then
  exit 0
fi

MARKER_LINE=$(grep -m1 '<!-- skill-body-sha: ' "$TARGET_FILE" || true)

if [ -z "$MARKER_LINE" ]; then
  echo "Error: '<!-- skill-body-sha: H -->' marker not found in $TARGET_FILE" >&2
  exit 1
fi

# `|| true` on both extractions below prevents a malformed marker or an
# all-marker-lines (no body) file from tripping `pipefail` and aborting the
# script silently before the diagnostic below can print (Issue #1468 review).
EXPECTED_HASH=$(printf '%s\n' "$MARKER_LINE" | grep -oE '[0-9a-f]{8}' | head -1 || true)
ACTUAL_HASH=$(grep -v '<!-- skill-body-' "$TARGET_FILE" | shasum -a 256 | cut -c1-8 || true)

if [ -z "$EXPECTED_HASH" ] || [ -z "$ACTUAL_HASH" ] || [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
  echo "Error: $TARGET_FILE 's skill-body-sha marker is stale or malformed (marker: ${EXPECTED_HASH:-<none>}, computed: ${ACTUAL_HASH:-<none>}). Recompute the hash and update the marker." >&2
  exit 1
fi

exit 0
